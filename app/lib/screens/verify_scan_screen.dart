import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/verify_cache_store.dart';
import '../core/verify_repository.dart';
import '../core/verify_strings.dart';
import '../theme/shoppa_theme.dart';
import 'verify_result_screen.dart';

class VerifyScanScreen extends StatefulWidget {
  const VerifyScanScreen({
    super.key,
    required this.verifyRepository,
    this.cacheStore,
  });

  final VerifyRepository verifyRepository;
  final VerifyCacheStore? cacheStore;

  @override
  State<VerifyScanScreen> createState() => _VerifyScanScreenState();
}

class _VerifyScanScreenState extends State<VerifyScanScreen> {
  final _controller = TextEditingController();
  final _cache = SharedPreferencesVerifyCacheStore();
  bool _busy = false;
  String? _error;
  List<VerifyResult> _recent = [];

  VerifyCacheStore get _store => widget.cacheStore ?? _cache;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final recent = await _store.recent(limit: 12);
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  Future<void> _lookup(String raw) async {
    final gtin = raw.replaceAll(RegExp(r'\D'), '');
    if (gtin.length < 8) {
      setState(() => _error = 'Enter a valid barcode (8–14 digits)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
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
      await _loadRecent();
    } on NetworkUnavailableException {
      final cached = await _store.get(gtin);
      if (!mounted) return;
      if (cached != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyResultScreen(
              result: cached,
              verifyRepository: widget.verifyRepository,
              cacheStore: _store,
            ),
          ),
        );
      } else {
        setState(() => _error = 'Offline and no cached result for this barcode');
      }
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        setState(() => _error = e.message);
      } else {
        final cached = await _store.get(gtin);
        if (!mounted) return;
        if (cached != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VerifyResultScreen(
                result: cached,
                verifyRepository: widget.verifyRepository,
                cacheStore: _store,
              ),
            ),
          );
        } else {
          setState(() => _error = e.message);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(VerifyStrings.title),
        actions: [
          IconButton(
            tooltip: VerifyStrings.allergenProfile,
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => context.push('/verify/allergens'),
          ),
          IconButton(
            tooltip: VerifyStrings.history,
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/verify/history'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ShoppaColors.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ShoppaColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      color: ShoppaColors.amber,
                      size: 28,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        VerifyStrings.scanHint,
                        style: TextStyle(
                          color: ShoppaColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Camera scan is limited on web — enter the barcode digits.',
                    style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: ShoppaColors.ink),
                  decoration: InputDecoration(
                    labelText: VerifyStrings.manualLabel,
                    hintText: VerifyStrings.demoGtinHint,
                    labelStyle: const TextStyle(color: ShoppaColors.mist),
                    filled: true,
                    fillColor: ShoppaColors.panel2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: _busy ? null : _lookup,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _lookup(_controller.text),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(VerifyStrings.manualAction),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: ShoppaColors.rose, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            VerifyStrings.disclaimerShort,
            style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Recent on this device',
              style: TextStyle(
                color: ShoppaColors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            for (final r in _recent)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _LevelDot(level: r.verification.level),
                title: Text(
                  r.product?.name.isNotEmpty == true
                      ? r.product!.name
                      : r.gtin,
                  style: const TextStyle(color: ShoppaColors.ink),
                ),
                subtitle: Text(
                  r.gtin,
                  style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VerifyResultScreen(
                        result: r,
                        verifyRepository: widget.verifyRepository,
                        cacheStore: _store,
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _LevelDot extends StatelessWidget {
  const _LevelDot({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      'red' => ShoppaColors.rose,
      'yellow' => ShoppaColors.amber,
      'green' => const Color(0xFF3DDC97),
      _ => ShoppaColors.mist,
    };
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
