import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';

/// SRS FR-7.1 (targeted promotions) / FR-7.3 (opt out per store or
/// category), API Specification §6.6: GET /promotions, POST
/// /promotions/opt-out. Standalone screen (rather than a per-list sheet)
/// since promotions are matched across all of the user's lists, not one.
class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key, required this.listsRepository});

  final ListsRepository listsRepository;

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  late Future<List<ShoppaPromotion>> _promotions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _promotions = widget.listsRepository.fetchPromotions();
  }

  void _reload() {
    setState(() {
      _promotions = widget.listsRepository.fetchPromotions();
      _error = null;
    });
  }

  Future<void> _optOutOfStore(String storeId) async {
    try {
      await widget.listsRepository.optOutOfPromotions(storeId: storeId);
      _reload();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _optOutOfCategory(String category) async {
    try {
      await widget.listsRepository.optOutOfPromotions(category: category);
      _reload();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promotions')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<ShoppaPromotion>>(
          future: _promotions,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load promotions: ${snapshot.error}',
                  style: const TextStyle(color: ShoppaColors.rose),
                ),
              );
            }
            final promotions = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
                  const SizedBox(height: 12),
                ],
                if (promotions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No promotions match your lists right now.',
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    ),
                  )
                else
                  ...promotions.map(
                    (promo) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PromotionCard(
                        promotion: promo,
                        onOptOutStore: () => _optOutOfStore(promo.storeId),
                        onOptOutCategory: promo.category.isEmpty
                            ? null
                            : () => _optOutOfCategory(promo.category),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    required this.promotion,
    required this.onOptOutStore,
    required this.onOptOutCategory,
  });

  final ShoppaPromotion promotion;
  final VoidCallback onOptOutStore;
  final VoidCallback? onOptOutCategory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ShoppaColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShoppaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            promotion.title,
            style: const TextStyle(
              color: ShoppaColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${promotion.productName} · ${promotion.storeName}',
            style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
          ),
          if (promotion.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              promotion.description,
              style: const TextStyle(color: ShoppaColors.ink, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: onOptOutStore,
                child: Text("Mute ${promotion.storeName}"),
              ),
              if (onOptOutCategory != null)
                TextButton(
                  onPressed: onOptOutCategory,
                  child: Text("Mute ${promotion.category}"),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
