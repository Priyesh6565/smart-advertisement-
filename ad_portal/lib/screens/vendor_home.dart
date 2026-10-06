import 'package:flutter/material.dart';

import '../config.dart';
import 'add_ad_screen.dart';

class VendorHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const VendorHome({super.key, required this.profile});

  @override
  State<VendorHome> createState() => _VendorHomeState();
}

class _VendorHomeState extends State<VendorHome> {
  List<Map<String, dynamic>> _ads = [];
  Map<String, int> _plays = {};
  Map<String, dynamic>? _bill;
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
      final uid = supabase.auth.currentUser!.id;
      final ads = await supabase
          .from('ads')
          .select()
          .eq('vendor_id', uid)
          .order('created_at', ascending: false);
      final plays = await supabase.from('ad_play_counts').select();
      final bill = await supabase
          .from('vendor_billing')
          .select()
          .eq('vendor_id', uid)
          .maybeSingle();
      setState(() {
        _ads = List<Map<String, dynamic>>.from(ads);
        _plays = {
          for (final r in plays)
            r['ad_id'] as String: (r['plays'] as num).toInt()
        };
        _bill = bill;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete advertisement?'),
        content: Text('"${ad['title']}" will stop playing on the display.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
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
      if (mounted) toast(context, 'Delete failed: $e');
    }
  }

  Future<void> _add() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddAdScreen()),
    );
    if (added == true) _load();
  }

  Widget _billingCard() {
    final billed = toD(_bill?['total_billed']);
    final paid = toD(_bill?['total_paid']);
    final due = billed - paid;
    final plays = (_bill?['total_plays'] as num?)?.toInt() ?? 0;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('Total plays', '$plays'),
            _stat('Billed', money(billed)),
            _stat('Paid', money(paid)),
            _stat('Amount due', money(due), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {bool bold = false}) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 20 : 16,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final name = (widget.profile['company_name'] as String?)?.isNotEmpty == true
        ? widget.profile['company_name']
        : widget.profile['email'];
    return Scaffold(
      appBar: AppBar(
        title: Text('Vendor: $name'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: () => supabase.auth.signOut(),
              icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add advertisement'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _billingCard(),
                      const SizedBox(height: 8),
                      Text('My advertisements (${_ads.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                      if (_ads.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child:
                                  Text('No ads yet. Tap "Add advertisement".')),
                        ),
                      for (final ad in _ads)
                        Card(
                          child: ListTile(
                            leading: Icon(
                                ad['file_type'] == 'video'
                                    ? Icons.movie
                                    : Icons.image,
                                size: 32),
                            title: Text(ad['title'] ?? ''),
                            subtitle: Text(
                                'Age: ${ageLabels[ad['age_group']]}  |  Gender: ${genderLabels[ad['gender']]}\n'
                                'Plays: ${_plays[ad['id']] ?? 0}'),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _delete(ad),
                            ),
                          ),
                        ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }
}
