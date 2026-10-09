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
      final uid = supabase.auth.currentUser!.id;

      final ads = await supabase
          .from('ads')
          .select()
          .eq('vendor_id', uid)
          .order('created_at', ascending: false);

      final adsList = List<Map<String, dynamic>>.from(ads);

      final adIds =
          adsList.map((a) => a['id'] as String).toList();

      // Only fetch play counts for this vendor's own ads, not every vendor's.
      final plays = adIds.isEmpty
          ? []
          : await supabase
              .from('ad_play_counts')
              .select()
              .inFilter('ad_id', adIds);

      final bill = await supabase
          .from('vendor_billing')
          .select()
          .eq('vendor_id', uid)
          .maybeSingle();

      setState(() {
        _ads = adsList;

        _plays = {
          for (final r in plays)
            r['ad_id'] as String: (r['plays'] as num).toInt()
        };

        _bill = bill;
      });
    } catch (e) {
      setState(
        () => _error =
            'Could not load your dashboard. Pull down to retry.',
      );
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
    final scheme = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Delete advertisement?',
          style: TextStyle(
            color: Color(0xFF101828),
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${ad['title']}" will stop playing on the display.',
          style: const TextStyle(
            color: Color(0xFF475467),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF344054),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await supabase.from('ads').delete().eq('id', ad['id']);

      await supabase.storage
          .from('ads')
          .remove([ad['file_path'] as String]);

      if (mounted) toast(context, 'Advertisement deleted');

      _load();
    } catch (e) {
      if (mounted) {
        toast(
          context,
          'Delete failed. Please try again.',
        );
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Log out?',
          style: TextStyle(
            color: Color(0xFF101828),
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out of your vendor account?',
          style: TextStyle(
            color: Color(0xFF475467),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF344054),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF101828),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (ok == true) await supabase.auth.signOut();
  }

  Future<void> _add() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddAdScreen(),
      ),
    );

    if (added == true) _load();
  }

  Widget _billingCard() {
    final billed = toD(_bill?['total_billed']);
    final paid = toD(_bill?['total_paid']);
    final due = (billed - paid).clamp(0, double.infinity);
    final plays =
        (_bill?['total_plays'] as num?)?.toInt() ?? 0;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF101828),
            Color(0xFF172554),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF101828).withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.analytics_rounded,
                    color: Color(0xFF101828),
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Campaign Overview',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Your advertising performance',
                        style: TextStyle(
                          color: Color(0xFFD0D5DD),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFFFCD34D),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            Row(
              children: [
                Expanded(
                  child: _stat(
                    Icons.play_circle_outline_rounded,
                    'Total plays',
                    '$plays',
                  ),
                ),
                Expanded(
                  child: _stat(
                    Icons.receipt_long_outlined,
                    'Billed',
                    money(billed),
                  ),
                ),
                Expanded(
                  child: _stat(
                    Icons.check_circle_outline_rounded,
                    'Paid',
                    money(paid),
                  ),
                ),
                Expanded(
                  child: _stat(
                    Icons.account_balance_wallet_outlined,
                    'Amount due',
                    money(due),
                    bold: true,
                    valueColor: due > 0
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFF86EFAC),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(
    IconData icon,
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 20,
            color: const Color(0xFFFCD34D),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFD0D5DD),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight:
                  bold ? FontWeight.w800 : FontWeight.w700,
              color: valueColor ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _adThumbnail(Map<String, dynamic> ad) {
    final isVideo = ad['file_type'] == 'video';

    final scheme = Theme.of(context).colorScheme;

    String? url;

    try {
      final path = ad['file_path'] as String?;

      if (path != null) {
        url = supabase.storage.from('ads').getPublicUrl(path);
      }
    } catch (_) {
      url = null;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 74,
        height: 74,
        child: isVideo || url == null
            ? Container(
                color: const Color(0xFFEFF2F6),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      isVideo
                          ? Icons.movie_outlined
                          : Icons.image_outlined,
                      color: const Color(0xFF344054),
                      size: 30,
                    ),
                    if (isVideo)
                      Positioned(
                        bottom: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101828),
                            borderRadius:
                                BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final name =
        (widget.profile['company_name'] as String?)?.isNotEmpty ==
                true
            ? widget.profile['company_name']
            : widget.profile['email'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      // ================================================================
      // APP BAR
      // ================================================================
      appBar: AppBar(
        backgroundColor: const Color(0xFF101828),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 70,

        titleSpacing: 18,

        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.campaign_rounded,
                color: Color(0xFF101828),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Smart Ad Portal',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Vendor: $name',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFD0D5DD),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _load,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFCD34D),
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                  ),
          ),

          IconButton(
            tooltip: 'Log out',
            onPressed: _confirmSignOut,
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.white,
            ),
          ),

          const SizedBox(width: 6),
        ],
      ),

      // ================================================================
      // ADD ADVERTISEMENT BUTTON
      // ================================================================
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: const Color(0xFFF59E0B),
        foregroundColor: const Color(0xFF101828),
        elevation: 6,
        icon: const Icon(
          Icons.add_rounded,
          size: 23,
        ),
        label: const Text(
          'Add advertisement',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      // ================================================================
      // BODY
      // ================================================================
      body: _initialLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF101828),
              ),
            )
          : _error != null && _ads.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFE4E7EC),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE4E2),
                              borderRadius:
                                  BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.cloud_off_rounded,
                              size: 32,
                              color: Color(0xFFB42318),
                            ),
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            'Unable to load dashboard',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF101828),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              height: 1.5,
                            ),
                          ),

                          const SizedBox(height: 20),

                          FilledButton(
                            onPressed: _load,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF101828),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(11),
                              ),
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF101828),
                  backgroundColor: Colors.white,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      18,
                      20,
                      18,
                      110,
                    ),
                    children: [
                      // ======================================================
                      // WELCOME HEADER
                      // ======================================================
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Dashboard',
                                  style: TextStyle(
                                    color: Color(0xFF101828),
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Manage and monitor your advertisements.',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF3),
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFA6F4C5),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: Color(0xFF039855),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Active',
                                  style: TextStyle(
                                    color: Color(0xFF027A48),
                                    fontSize: 12,
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ======================================================
                      // BILLING / PERFORMANCE CARD
                      // ======================================================
                      _billingCard(),

                      const SizedBox(height: 28),

                      // ======================================================
                      // ADVERTISEMENT HEADER
                      // ======================================================
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.center,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'My advertisements',
                                  style: TextStyle(
                                    color: Color(0xFF101828),
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Your active advertising campaigns',
                                  style: TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF4FF),
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_ads.length} ads',
                              style: const TextStyle(
                                color: Color(0xFF3538CD),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // ======================================================
                      // EMPTY STATE
                      // ======================================================
                      if (_ads.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 25,
                            vertical: 40,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE4E7EC),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7E6),
                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.campaign_outlined,
                                  size: 36,
                                  color: Color(0xFFD97706),
                                ),
                              ),
                              const SizedBox(height: 17),
                              const Text(
                                'No advertisements yet',
                                style: TextStyle(
                                  color: Color(0xFF101828),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 7),
                              const Text(
                                'Create your first advertisement and start reaching your audience.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _add,
                                icon: const Icon(
                                  Icons.add_rounded,
                                ),
                                label: const Text(
                                  'Create advertisement',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF101828),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape:
                                      RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(11),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ======================================================
                      // ADVERTISEMENT CARDS
                      // ======================================================
                      for (final ad in _ads)
                        Container(
                          margin: const EdgeInsets.only(
                            bottom: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFE4E7EC),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.035),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                // ==================================================
                                // THUMBNAIL
                                // ==================================================
                                _adThumbnail(ad),

                                const SizedBox(width: 14),

                                // ==================================================
                                // AD INFORMATION
                                // ==================================================
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              ad['title'] ?? '',
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow
                                                      .ellipsis,
                                              style:
                                                  const TextStyle(
                                                color: Color(
                                                  0xFF101828,
                                                ),
                                                fontSize: 15,
                                                fontWeight:
                                                    FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding:
                                                const EdgeInsets
                                                    .symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration:
                                                BoxDecoration(
                                              color: const Color(
                                                0xFFECFDF3,
                                              ),
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(20),
                                            ),
                                            child:
                                                const Text(
                                              'ACTIVE',
                                              style: TextStyle(
                                                color: Color(
                                                  0xFF027A48,
                                                ),
                                                fontSize: 9,
                                                fontWeight:
                                                    FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 9),

                                      Wrap(
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: [
                                          Container(
                                            padding:
                                                const EdgeInsets
                                                    .symmetric(
                                              horizontal: 9,
                                              vertical: 6,
                                            ),
                                            decoration:
                                                BoxDecoration(
                                              color: const Color(
                                                0xFFF2F4F7,
                                              ),
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .people_outline_rounded,
                                                  size: 14,
                                                  color: Color(
                                                    0xFF475467,
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: 5),
                                                Text(
                                                  'Age: ${ageLabels[ad['age_group']]}',
                                                  style:
                                                      const TextStyle(
                                                    color: Color(
                                                      0xFF344054,
                                                    ),
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight
                                                            .w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          Container(
                                            padding:
                                                const EdgeInsets
                                                    .symmetric(
                                              horizontal: 9,
                                              vertical: 6,
                                            ),
                                            decoration:
                                                BoxDecoration(
                                              color: const Color(
                                                0xFFF2F4F7,
                                              ),
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .wc_rounded,
                                                  size: 14,
                                                  color: Color(
                                                    0xFF475467,
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: 5),
                                                Text(
                                                  'Gender: ${genderLabels[ad['gender']]}',
                                                  style:
                                                      const TextStyle(
                                                    color: Color(
                                                      0xFF344054,
                                                    ),
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight
                                                            .w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          Container(
                                            padding:
                                                const EdgeInsets
                                                    .symmetric(
                                              horizontal: 9,
                                              vertical: 6,
                                            ),
                                            decoration:
                                                BoxDecoration(
                                              color: const Color(
                                                0xFFFFF7E6,
                                              ),
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .play_arrow_rounded,
                                                  size: 14,
                                                  color: Color(
                                                    0xFFB54708,
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: 5),
                                                Text(
                                                  'Plays: ${_plays[ad['id']] ?? 0}',
                                                  style:
                                                      const TextStyle(
                                                    color: Color(
                                                      0xFF93370D,
                                                    ),
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight
                                                            .w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // ==================================================
                                // DELETE
                                // ==================================================
                                const SizedBox(width: 5),

                                IconButton(
                                  tooltip:
                                      'Delete advertisement',
                                  onPressed: () => _delete(ad),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFFFEF3F2),
                                  ),
                                  icon: const Icon(
                                    Icons
                                        .delete_outline_rounded,
                                    color: Color(0xFFB42318),
                                    size: 21,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}