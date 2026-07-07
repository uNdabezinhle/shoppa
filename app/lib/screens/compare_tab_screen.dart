import 'package:flutter/material.dart';

import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';

class CompareTabScreen extends StatefulWidget {
  const CompareTabScreen({super.key, required this.listsRepository});

  final ListsRepository listsRepository;

  @override
  State<CompareTabScreen> createState() => _CompareTabScreenState();
}

class _CompareTabScreenState extends State<CompareTabScreen> {
  late Future<_CompareViewData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_CompareViewData> _load() async {
    final lists = await widget.listsRepository.fetchLists();
    if (lists.isEmpty) return _CompareViewData.empty();
    final comparison =
        await widget.listsRepository.fetchComparison(lists.first.id);
    return _CompareViewData(listTitle: lists.first.title, comparison: comparison);
  }

  String _formatZar(int cents) => 'R${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: FutureBuilder<_CompareViewData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.comparison == null || data.comparison!.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add items with catalogue prices to see store comparisons.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ShoppaColors.mist),
                ),
              ),
            );
          }
          final comparison = data.comparison!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (data.listTitle != null)
                Text(
                  data.listTitle!,
                  style: const TextStyle(
                    color: ShoppaColors.mist,
                    fontSize: 13,
                  ),
                ),
              if (comparison.bestSaves != null && comparison.bestSaves! > 0)
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ShoppaColors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ShoppaColors.green.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Best deal saves ${_formatZar(comparison.bestSaves!)}',
                    style: const TextStyle(
                      color: ShoppaColors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ...comparison.stores.map((store) {
                final isBest = store.storeId == comparison.bestStoreId;
                return Card(
                  color: ShoppaColors.panel,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(store.name,
                        style: TextStyle(
                          color: ShoppaColors.ink,
                          fontWeight: isBest ? FontWeight.w700 : FontWeight.w500,
                        )),
                    subtitle: Text(
                      'Confidence: ${store.confidence}',
                      style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                    ),
                    trailing: Text(
                      _formatZar(store.total),
                      style: TextStyle(
                        color: isBest ? ShoppaColors.green : ShoppaColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _CompareViewData {
  _CompareViewData({this.listTitle, this.comparison});
  _CompareViewData.empty() : listTitle = null, comparison = null;

  final String? listTitle;
  final ShoppaComparison? comparison;
}