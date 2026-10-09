import 'package:flutter/material.dart';

import '../config.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
              onPressed: () => _confirmSignOut(context),
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.people), text: 'Vendors & Billing'),
            Tab(icon: Icon(Icons.video_library), text: 'All Ads'),
            Tab(icon: Icon(Icons.settings), text: 'Pricing'),
          ]),
        ),
        body: const TabBarView(children: [
          _VendorsTab(),
          _AllAdsTab(),
          _PricingTab(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- vendors
class _VendorsTab extends StatefulWidget {
  const _VendorsTab();
  @override
  State<_VendorsTab> createState() => _VendorsTabState();
}

class _VendorsTabState extends State<_VendorsTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _initialLoading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isFirstLoad = _rows.isEmpty && _initialLoading;
    setState(() {
      if (isFirstLoad) {
        _initialLoading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final r = await supabase.from('vendor_billing').select();
      setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      setState(() => _error = 'Could not load vendors. Pull down to retry.');
    } finally {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _pay(Map<String, dynamic> v) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Record payment - ${v['company_name'] ?? v['email']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount received (₹)'),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save')),
          ],
        ),
      );
      if (ok != true) return;
      final value = double.tryParse(amount.text.trim());
      if (value == null || value <= 0) {
        if (mounted) toast(context, 'Enter a valid amount');
        return;
      }
      try {
        await supabase.from('payments').insert({
          'vendor_id': v['vendor_id'],
          'amount': value,
          'note': note.text.trim(),
        });
        if (mounted) toast(context, 'Payment recorded');
        _load();
      } catch (e) {
        if (mounted) toast(context, 'Could not save the payment. Please try again.');
      }
    } finally {
      amount.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final totalDue = _rows.fold<double>(
        0, (s, r) => s + toD(r['total_billed']) - toD(r['total_paid']));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.primaryContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: Icon(Icons.account_balance_wallet_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
              title: const Text('Total outstanding from all vendors'),
              trailing: Text(money(totalDue),
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: totalDue > 0 ? Colors.red.shade700 : Colors.green.shade700)),
            ),
          ),
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          if (_rows.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No vendors have registered yet.'))),
          for (final v in _rows)
            Card(
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              (v['company_name'] as String?)?.isNotEmpty == true
                                  ? v['company_name']
                                  : '(no company name)',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold)),
                          Text(
                              '${v['full_name'] ?? ''}  •  ${v['email'] ?? ''}',
                              style: TextStyle(color: Colors.grey.shade700)),
                          const SizedBox(height: 6),
                          Text(
                              'Plays: ${(v['total_plays'] as num?)?.toInt() ?? 0}   '
                              'Billed: ${money(toD(v['total_billed']))}   '
                              'Paid: ${money(toD(v['total_paid']))}',
                              style: const TextStyle(fontSize: 13)),
                        ]),
                  ),
                  Column(children: [
                    const Text('AMOUNT DUE',
                        style: TextStyle(fontSize: 11, letterSpacing: 0.4)),
                    Builder(builder: (context) {
                      final due = toD(v['total_billed']) - toD(v['total_paid']);
                      return Text(money(due),
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: due > 0
                                  ? Colors.red.shade700
                                  : Colors.green.shade700));
                    }),
                    TextButton(
                        onPressed: () => _pay(v),
                        child: const Text('Record payment')),
                  ]),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- all ads
class _AllAdsTab extends StatefulWidget {
  const _AllAdsTab();
  @override
  State<_AllAdsTab> createState() => _AllAdsTabState();
}

class _AllAdsTabState extends State<_AllAdsTab> {
  List<Map<String, dynamic>> _ads = [];
  bool _initialLoading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isFirstLoad = _ads.isEmpty && _initialLoading;
    setState(() {
      if (isFirstLoad) {
        _initialLoading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final r = await supabase
          .from('ads')
          .select('*, profiles(full_name, company_name, email)')
          .order('created_at', ascending: false);
      setState(() => _ads = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      setState(() => _error = 'Could not load advertisements. Pull down to retry.');
    } finally {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete advertisement?'),
        content: Text(
            '"${ad['title']}" will be removed and stop playing on the display.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('ads').delete().eq('id', ad['id']);
      await supabase.storage.from('ads').remove([ad['file_path'] as String]);
      if (mounted) toast(context, 'Advertisement deleted');
      _load();
    } catch (e) {
      if (mounted) toast(context, 'Delete failed. Please try again.');
    }
  }

  Widget _thumbnail(Map<String, dynamic> ad) {
    final isVideo = ad['file_type'] == 'video';
    String? url;
    try {
      final path = ad['file_path'] as String?;
      if (path != null) url = supabase.storage.from('ads').getPublicUrl(path);
    } catch (_) {
      url = null;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: isVideo || url == null
            ? Container(
                color: Colors.grey.shade200,
                child: Icon(isVideo ? Icons.movie_outlined : Icons.image_outlined,
                    color: Colors.grey.shade600),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: Icon(Icons.image_outlined, color: Colors.grey.shade600),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _ads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          if (_ads.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No advertisements uploaded yet.'))),
          for (final ad in _ads)
            Card(
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                leading: _thumbnail(ad),
                title: Text(ad['title'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Vendor: ${ad['profiles']?['company_name'] ?? ad['profiles']?['email'] ?? '-'}\n'
                    'Age: ${ageLabels[ad['age_group']]}  |  Gender: ${genderLabels[ad['gender']]}'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _delete(ad),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- pricing
class _PricingTab extends StatefulWidget {
  const _PricingTab();
  @override
  State<_PricingTab> createState() => _PricingTabState();
}

class _PricingTabState extends State<_PricingTab> {
  final _rate = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await supabase.from('settings').select().eq('id', 1).single();
      _rate.text = toD(r['rate_per_play']).toStringAsFixed(2);
    } catch (_) {
      // No settings row yet — leave the field blank for the admin to set one.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final v = double.tryParse(_rate.text.trim());
    if (v == null || v < 0) {
      toast(context, 'Enter a valid number');
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.from('settings').update({'rate_per_play': v}).eq('id', 1);
      if (mounted) toast(context, 'Rate saved. Applies to future plays only.');
    } catch (e) {
      if (mounted) toast(context, 'Could not save the rate. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.sell_outlined,
                    size: 32, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                const Text(
                    'Price charged to a vendor each time one of their ads starts playing',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextField(
                  controller: _rate,
                  enabled: !_saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Rate per play (₹)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}