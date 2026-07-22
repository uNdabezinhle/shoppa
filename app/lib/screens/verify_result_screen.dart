import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/verify_cache_store.dart';
import '../core/verify_repository.dart';
import '../core/verify_strings.dart';
import '../theme/shoppa_theme.dart';

class VerifyResultScreen extends StatefulWidget {
  const VerifyResultScreen({
    super.key,
    required this.result,
    required this.verifyRepository,
    this.cacheStore,
  });

  final VerifyResult result;
  final VerifyRepository verifyRepository;
  final VerifyCacheStore? cacheStore;

  @override
  State<VerifyResultScreen> createState() => _VerifyResultScreenState();
}

class _VerifyResultScreenState extends State<VerifyResultScreen> {
  late VerifyResult _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
  }

  Color get _levelColor {
    switch (_result.verification.level) {
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

  String get _levelTitle {
    switch (_result.verification.level) {
      case 'red':
        return VerifyStrings.levelRed;
      case 'yellow':
        return VerifyStrings.levelYellow;
      case 'green':
        return VerifyStrings.levelGreen;
      default:
        return VerifyStrings.levelUnknown;
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final next = await widget.verifyRepository.refresh(_result.gtin);
      await widget.cacheStore?.put(next);
      if (!mounted) return;
      setState(() => _result = next);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ShoppaColors.rose),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text(VerifyStrings.reportIssue),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              hintText: 'What looks wrong?',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
    if (note == null || note.isEmpty) return;
    try {
      await widget.verifyRepository.submitCorrection(
        gtin: _result.gtin,
        field: _result.status == 'not_found' ? 'missing_product' : 'other',
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks — report submitted'),
          backgroundColor: ShoppaColors.panel2,
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
    final product = _result.product;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_result.offline)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ShoppaColors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                VerifyStrings.offlineBanner,
                style: TextStyle(color: ShoppaColors.ink, fontSize: 13),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _levelColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _levelColor.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _levelTitle,
                  style: TextStyle(
                    color: _levelColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final reason in _result.verification.reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· $reason',
                      style: const TextStyle(color: ShoppaColors.ink),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_result.status == 'not_found' || product == null)
            const Text(
              VerifyStrings.notFound,
              style: TextStyle(color: ShoppaColors.mist),
            )
          else ...[
            Text(
              product.name.isEmpty ? 'Unknown product' : product.name,
              style: const TextStyle(
                color: ShoppaColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (product.brand.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                product.brand,
                style: const TextStyle(color: ShoppaColors.mist, fontSize: 15),
              ),
            ],
            if (product.quantity != null && product.quantity!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                product.quantity!,
                style: const TextStyle(color: ShoppaColors.mist, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_result.openFoodFacts)
                  _chip(VerifyStrings.sourcesOff, Icons.public),
                if (_result.shoppaCatalogue)
                  _chip(VerifyStrings.sourcesShoppa, Icons.storefront),
                if (product.nutriscoreGrade != null &&
                    product.nutriscoreGrade!.isNotEmpty)
                  _chip(
                    'Nutri-Score ${product.nutriscoreGrade!.toUpperCase()}',
                    Icons.eco_outlined,
                  ),
                if (_result.cached) _chip('Cached', Icons.cached),
              ],
            ),
            if (product.allergens.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                VerifyStrings.allergens,
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.allergens.join(', '),
                style: const TextStyle(color: ShoppaColors.mist),
              ),
            ],
            if (product.traces.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                VerifyStrings.traces,
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.traces.join(', '),
                style: const TextStyle(color: ShoppaColors.mist),
              ),
            ],
            if (product.ingredientsText.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                VerifyStrings.ingredients,
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.ingredientsText,
                style: const TextStyle(color: ShoppaColors.mist, height: 1.4),
              ),
            ],
            if (product.nutriments.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                VerifyStrings.nutrition,
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              for (final e in product.nutriments.entries.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: const TextStyle(color: ShoppaColors.mist, fontSize: 13),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 12),
          Text(
            'GTIN ${_result.gtin}',
            style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text(
            _result.disclaimer,
            style: const TextStyle(color: ShoppaColors.mist, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _report,
            icon: const Icon(Icons.flag_outlined),
            label: const Text(VerifyStrings.reportIssue),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16, color: ShoppaColors.amber),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: ShoppaColors.panel2,
      side: BorderSide.none,
    );
  }
}
