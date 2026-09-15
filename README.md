# Laptop-Only Digital Signage — Confidence-Based Gating + Model Recommendation

## What changed this round

### The bug: pose angle doesn't predict correctness
Your screenshot showed a face at ~49° yaw with **98% gender confidence**
marked "Uncertain" — blocked purely by the angle cutoff. I checked this
against an earlier case: a *different* face, also ~50° yaw, was wrong
despite 92% confidence. Since the same angle range contains both a correct
98%-confidence read and a wrong 92%-confidence read, **pose angle cannot
reliably separate good detections from bad ones** — it's just not a good
signal, and was over-blocking legitimate faces.

### The fix: gate on confidence, not angle
- Primary filter is now the model's own gender confidence (`GENDER_CONF_THRESHOLD = 0.60`)
- Pose is kept only as a generous backstop (70°/55°) for truly degenerate
  near-profile crops, not as a "is this probably right" filter
- **Trade-off, stated honestly:** this means the specific known-hard wrong
  case (92% confidence, still wrong) will now pass through too — there's no
  threshold that can distinguish it from a correct 98%-confidence read,
  because the model itself doesn't know it's wrong. To compensate, the
  temporal smoothing window was widened from 1.5s to 2.5s, so one
  occasional bad frame gets outvoted by surrounding correct frames instead
  of flipping the ad. Verified: a steady run of "male" reads with one bad
  "female" frame mixed in still correctly resolves to "male".

## Your question: switch models, or keep improving this one?

**Diagnosis: the bottleneck was our filtering logic, not the underlying
InsightFace model.** In every case I've tested across this whole project,
buffalo_l's raw gender/age predictions have been getting the right answer
with high confidence — the errors came from either (a) a genuinely hard
individual frame (screen glare, motion blur) or (b) our own filter blocking
a correct read. That's a calibration problem, which is what this round
fixed, not necessarily a "wrong model" problem.

**That said, for your stated goal — best possible accuracy specifically on
Indian faces — here's the honest comparison of your three options:**

| Option | Effort | Expected gain |
|---|---|---|
| **Keep InsightFace buffalo_l, well-calibrated** (current state) | Done | Already performing well in testing; main remaining errors are genuinely hard individual frames, not systematic bias |
| **Switch to a FairFace-based model** | Medium (swap in pretrained weights, rewire the age/gender head) | FairFace's training data is explicitly race-balanced including an Indian category, vs. buffalo_l's more general large-scale (not Indian-specific) training data. Likely a real but not dramatic accuracy gain specifically on Indian faces |
| **Train/fine-tune on an Indian-specific dataset** | High (need a labeled dataset, training pipeline, GPU time, evaluation) | Highest possible ceiling, but a genuinely substantial undertaking — not something to do inside a quick iteration cycle |

**My recommendation:** the current calibration fix should meaningfully
reduce the "not working" feeling you've been hitting. Test this version
first. If accuracy is still unsatisfying specifically on Indian faces after
this, the FairFace swap (previously researched: `dchen236/FairFace` or the
ONNX version) is the next reasonable step — it's a model swap, not a
training project, so it's a contained amount of work. Full custom training
is worth pursuing only if FairFace still isn't enough, since it's the most
expensive option by far.

## Setup / Run (unchanged)
```
pip install insightface onnxruntime opencv-python
python signage_app.py
```
First run downloads the InsightFace model pack (~280MB) once, then it's
cached offline. Press `q` to quit, `f` to toggle fullscreen. Drop `.mp4`
files into `ads/male/`, `ads/female/`, `ads/generic/`.

## Tuning knobs (top of `signage_app.py`)
| Constant | What it controls | Current |
|---|---|---|
| `DET_SCORE_THRESHOLD` | Minimum face-detector confidence to trust a face at all | 0.5 |
| `GENDER_CONF_THRESHOLD` | Minimum gender-prediction confidence to count a face (primary gate now) | 0.60 |
| `MAX_YAW_DEGREES` / `MAX_PITCH_DEGREES` | Generous pose backstop, not the main filter anymore | 70° / 55° |
| `EDGE_MARGIN_PX` | How close to the frame border counts as "cut off" | 8px |
| `SMOOTHING_WINDOW_SECONDS` | How long a category must be dominant before the ad switches | 2.5s |
