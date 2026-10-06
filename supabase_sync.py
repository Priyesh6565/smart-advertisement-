"""
Supabase <-> Laptop sync
Needs only `pip install requests`.
.env next to this script:
    SUPABASE_URL=https://xxxx.supabase.co
    SUPABASE_SERVICE_KEY=eyJ...
"""

import os
import re
import shutil
import threading
from urllib.parse import quote

import requests

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def _load_env():
    env = dict(os.environ)
    path = os.path.join(BASE_DIR, ".env")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    return env


class SupabaseAdSync:
    def __init__(self, ads_dir, interval=15):
        env = _load_env()
        self.ads_dir = ads_dir
        self.interval = interval
        self.url = (env.get("SUPABASE_URL") or "").rstrip("/")
        self.key = env.get("SUPABASE_SERVICE_KEY") or ""
        self.enabled = bool(self.url and self.key)

        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = None
        self._dirty = False
        self._pending_delete = []
        self._plays = []

        if not self.enabled:
            print("[Sync] SUPABASE_URL / SUPABASE_SERVICE_KEY missing in .env -> running OFFLINE (local ads only).")

    # ------------------------------------------------------------ helpers
    def _headers(self, extra=None):
        h = {"apikey": self.key}
        if self.key.startswith("eyJ"):
            h["Authorization"] = f"Bearer {self.key}"
        if extra:
            h.update(extra)
        return h

    def _target_folders(self, ad):
        age, gender = ad["age_group"], ad["gender"]
        genders = ["male", "female"] if gender == "all" else [gender]
        if age == "all":
            if gender == "all":
                return [os.path.join(self.ads_dir, "generic")]
            return [os.path.join(self.ads_dir, g) for g in genders]
        return [os.path.join(self.ads_dir, g, age) for g in genders]

    def _download(self, file_path, dest):
        url = f"{self.url}/storage/v1/object/ads/{quote(file_path, safe='/')}"
        tmp = dest + ".part"
        with requests.get(url, headers=self._headers(), stream=True, timeout=60) as r:
            r.raise_for_status()
            with open(tmp, "wb") as f:
                for chunk in r.iter_content(256 * 1024):
                    f.write(chunk)
        os.replace(tmp, dest)

    # ------------------------------------------------------------ sync
    def sync_once(self):
        if not self.enabled:
            return
        r = requests.get(
            f"{self.url}/rest/v1/ads",
            headers=self._headers(),
            params={"select": "id,age_group,gender,file_path", "is_active": "eq.true"},
            timeout=15,
        )
        r.raise_for_status()
        ads = r.json()

        expected, changed = set(), False
        for ad in ads:
            ext = os.path.splitext(ad["file_path"])[1].lower()
            first_copy = None
            for folder in self._target_folders(ad):
                os.makedirs(folder, exist_ok=True)
                dest = os.path.join(folder, f"{ad['id']}{ext}")
                expected.add(os.path.normcase(dest))
                if not os.path.exists(dest):
                    if first_copy and os.path.exists(first_copy):
                        shutil.copyfile(first_copy, dest)
                    else:
                        print(f"[Sync] Downloading ad {ad['id']} ...")
                        self._download(ad["file_path"], dest)
                    changed = True
                if first_copy is None:
                    first_copy = dest

        stale = []
        for root, _, files in os.walk(self.ads_dir):
            for fn in files:
                stem, _ext = os.path.splitext(fn)
                full = os.path.join(root, fn)
                if UUID_RE.match(stem) and os.path.normcase(full) not in expected:
                    stale.append(full)

        with self._lock:
            self._pending_delete = stale
            if changed or stale:
                self._dirty = True

    def apply_changes(self, ad_player):
        """Call from the MAIN thread."""
        with self._lock:
            if not self._dirty:
                return
            self._dirty = False
            to_delete = list(self._pending_delete)
            self._pending_delete = []
        ad_player.release_media()
        for p in to_delete:
            try:
                os.remove(p)
                print(f"[Sync] Removed deleted ad file: {os.path.basename(p)}")
            except OSError:
                pass
        ad_player.reload()

    # ------------------------------------------------------------ play logging
    def log_play(self, media_path):
        if not self.enabled or not media_path:
            return
        stem = os.path.splitext(os.path.basename(media_path))[0]
        if UUID_RE.match(stem):
            with self._lock:
                self._plays.append(stem)

    def _flush_plays(self):
        with self._lock:
            batch, self._plays = self._plays, []
        if not batch:
            return
        try:
            r = requests.post(
                f"{self.url}/rest/v1/ad_plays",
                headers=self._headers({"Content-Type": "application/json", "Prefer": "return=minimal"}),
                json=[{"ad_id": a} for a in batch],
                timeout=15,
            )
            r.raise_for_status()
        except Exception as e:
            print(f"[Sync] Could not upload play log (will retry): {e}")
            with self._lock:
                self._plays = batch + self._plays

    # ------------------------------------------------------------ thread
    def _loop(self):
        while not self._stop.is_set():
            try:
                self.sync_once()
            except Exception as e:
                print(f"[Sync] Sync error (keeping local ads): {e}")
            self._flush_plays()
            self._stop.wait(self.interval)

    def start(self):
        if not self.enabled or self._thread is not None:
            return
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()
        print(f"[Sync] Background sync started (every {self.interval}s).")

    def stop(self):
        self._stop.set()
        if self.enabled:
            self._flush_plays()