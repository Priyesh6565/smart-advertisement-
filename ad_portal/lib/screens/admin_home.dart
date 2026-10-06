import 'package:flutter/material.dart';

import '../config.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
                onPressed: () => supabase.auth.signOut(),
                icon: const Icon(Icons.logout)),
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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await supabase.from('vendor_billing').select();
      setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay(Map<String, dynamic> v) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Record payment - ${v['company_name'] ?? v['email']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amount,
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
      if (mounted) toast(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final totalDue = _rows.fold<double>(
        0, (s, r) => s + toD(r['total_billed']) - toD(r['total_paid']));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              title: const Text('Total outstanding from all vendors'),
              trailing: Text(money(totalDue),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_rows.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No vendors have registered yet.'))),
          for (final v in _rows)
            Card(
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
                              '${v['full_name'] ?? ''}  •  ${v['email'] ?? ''}'),
                          const SizedBox(height: 6),
                          Text(
                              'Plays: ${(v['total_plays'] as num).toInt()}   '
                              'Billed: ${money(v['total_billed'])}   '
                              'Paid: ${money(v['total_paid'])}',
                              style: const TextStyle(fontSize: 13)),
                        ]),
                  ),
                  Column(children: [
                    const Text('MUST PAY', style: TextStyle(fontSize: 11)),
                    Text(money(toD(v['total_billed']) - toD(v['total_paid'])),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red)),
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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await supabase
          .from('ads')
          .select('*, profiles(full_name, company_name, email)')
          .order('created_at', ascending: false);
      setState(() => _ads = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> ad) async {
    try {
      await supabase.from('ads').delete().eq('id', ad['id']);
      await supabase.storage.from('ads').remove([ad['file_path'] as String]);
      _load();
    } catch (e) {
      if (mounted) toast(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_ads.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No advertisements uploaded yet.'))),
          for (final ad in _ads)
            Card(
              child: ListTile(
                leading: Icon(
                    ad['file_type'] == 'video' ? Icons.movie : Icons.image),
                title: Text(ad['title'] ?? ''),
                subtitle: Text(
                    'Vendor: ${ad['profiles']?['company_name'] ?? ad['profiles']?['email'] ?? '-'}\n'
                    'Age: ${ageLabels[ad['age_group']]}  |  Gender: ${genderLabels[ad['gender']]}'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supabase.from('settings').select().eq('id', 1).single();
      _rate.text = toD(r['rate_per_play']).toStringAsFixed(2);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final v = double.tryParse(_rate.text.trim());
    if (v == null || v < 0) {
      toast(context, 'Enter a valid number');
      return;
    }
    try {
      await supabase.from('settings').update({'rate_per_play': v}).eq('id', 1);
      if (mounted) toast(context, 'Rate saved. Applies to future plays only.');
    } catch (e) {
      if (mounted) toast(context, 'Failed: $e');
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Price charged to a vendor each time one of their ads starts playing',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: _rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Rate per play (₹)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ]),
        ),
      ),
    );
  }
}
