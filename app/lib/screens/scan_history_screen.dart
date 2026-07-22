import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/verify_cache_store.dart';
import '../core/verify_repository.dart';
import '../core/verify_strings.dart';
import '../theme/shoppa_theme.dart';
import 'verify_result_screen.dart';

class ScanHistoryScreen extends StatefulWidget {
  const ScanHistoryScreen({
    super.key,
    required this.verifyRepository,
    this.cacheStore,
  });

  final VerifyRepository verifyRepository;
  final VerifyCacheStore? cacheStore;

  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  final _local = SharedPreferencesVerifyCacheStore();
  bool _loading = true;
  String? _error;
  List<ScanHistoryEntry> _server = [];
  List<VerifyResult> _device = [];

  VerifyCacheStore get _store => widget.cacheStore ?? _local;

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
    final device = await _store.recent(limit: 50);
    List<ScanHistoryEntry> server = [];
    try {
      server = await widget.verifyRepository.fetchScanHistory();
    } on NetworkUnavailableException {
      // device-only history is fine offline
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (!mounted) return;
    setState(() {
      _device = device;
      _server = server;
      _loading = false;
    });
  }

  Future<void> _openGtin(String gtin) async {
    final cached = await _store.get(gtin);
    if (cached != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyResultScreen(
            result: cached,
            verifyRepository: widget.verifyRepository,
            cacheStore: _store,
          ),
        ),
      );
      return;
    }
    try {
      final result = await widget.verifyRepository.verify(gtin);
      await _store.put(result);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyResultScreen(
            result: result,
            verifyRepository: widget.verifyRepository,
            cacheStore: _store,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ShoppaColors.rose),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(VerifyStrings.history)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: ShoppaColors.rose),
                      ),
                    ),
                  if (_device.isNotEmpty) ...[
                    const Text(
                      'On this device',
                      style: TextStyle(
                        color: ShoppaColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final r in _device)
                      ListTile(
                        leading: Icon(
                          Icons.circle,
                          size: 12,
                          color: _color(r.verification.level),
                        ),
                        title: Text(
                          r.product?.name.isNotEmpty == true
                              ? r.product!.name
                              : r.gtin,
                          style: const TextStyle(color: ShoppaColors.ink),
                        ),
                        subtitle: Text(
                          r.gtin,
                          style: const TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => _openGtin(r.gtin),
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (_server.isNotEmpty) ...[
                    const Text(
                      'Account history',
                      style: TextStyle(
                        color: ShoppaColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final e in _server)
                      ListTile(
                        leading: Icon(
                          Icons.circle,
                          size: 12,
                          color: _color(e.level),
                        ),
                        title: Text(
                          e.productName.isNotEmpty ? e.productName : e.gtin,
                          style: const TextStyle(color: ShoppaColors.ink),
                        ),
                        subtitle: Text(
                          e.gtin,
                          style: const TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => _openGtin(e.gtin),
                      ),
                  ],
                  if (_device.isEmpty && _server.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'No scans yet',
                          style: TextStyle(color: ShoppaColors.mist),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Color _color(String level) {
    switch (level) {
      case 'red':
        return ShoppaColors.rose;
      case 'yellow':
        return ShoppaColors.amber;
      case 'green':
        return const Color(0xFF3DDC97);
      default:
        return ShoppaColors.mist;
    }
  }
}
