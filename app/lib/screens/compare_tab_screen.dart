import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/lists_repository.dart';
import '../core/shopping_session_store.dart';
import '../theme/shoppa_theme.dart';
import '../widgets/confidence_chip.dart';

class CompareTabScreen extends StatefulWidget {
  const CompareTabScreen({super.key, required this.listsRepository});

  final ListsRepository listsRepository;

  @override
  State<CompareTabScreen> createState() => _CompareTabScreenState();
}

class _CompareTabScreenState extends State<CompareTabScreen> {
  List<ShoppaList> _lists = [];
  String? _selectedListId;
  late Future<ShoppaComparison?> _comparison;
  bool _loadingLists = true;
  final ShoppingSessionStore _sessionStore =
      SharedPreferencesShoppingSessionStore();

  Future<void> _setShoppingAt(ShoppaStoreComparison store) async {
    final listId = _selectedListId;
    if (listId == null) return;
    await _sessionStore.setShoppingAt(
      listId,
      ShoppingAtStore(storeId: store.storeId, storeName: store.name),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Shopping at ${store.name} — used for check-off prices on this list',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _comparison = Future.value(null);
    _loadLists();
  }

  Future<void> _loadLists() async {
    setState(() => _loadingLists = true);
    final lists = await widget.listsRepository.fetchLists();
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _selectedListId = lists.isNotEmpty ? lists.first.id : null;
      _loadingLists = false;
    });
    if (_selectedListId != null) _loadComparison();
  }

  void _loadComparison() {
    final listId = _selectedListId;
    if (listId == null) return;
    setState(() {
      _comparison = widget.listsRepository.fetchComparison(listId);
    });
  }

  String _formatZar(int cents) => 'R${(cents / 100).toStringAsFixed(2)}';

  ShoppaList? get _selectedList {
    if (_selectedListId == null) return null;
    for (final list in _lists) {
      if (list.id == _selectedListId) return list;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: _loadingLists
          ? const Center(child: CircularProgressIndicator())
          : _lists.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Create a list and add catalogue items to compare stores.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ShoppaColors.mist),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLists,
                  child: FutureBuilder<ShoppaComparison?>(
                    future: _comparison,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return ListView(
                          children: const [
                            SizedBox(
                              height: 200,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ],
                        );
                      }
                      final comparison = snapshot.data;
                      final selected = _selectedList;
                      final worstTotal = comparison != null &&
                              comparison.stores.isNotEmpty
                          ? comparison.stores.last.total
                          : null;

                      return ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          DropdownButtonFormField<String>(
                            value: _selectedListId,
                            decoration: const InputDecoration(labelText: 'List'),
                            items: _lists
                                .map(
                                  (list) => DropdownMenuItem(
                                    value: list.id,
                                    child: Text(list.title),
                                  ),
                                )
                                .toList(),
                            onChanged: (id) {
                              if (id == null) return;
                              setState(() => _selectedListId = id);
                              _loadComparison();
                            },
                          ),
                          if (selected != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${selected.itemCount} items',
                              style: const TextStyle(
                                color: ShoppaColors.mist,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (comparison == null || comparison.isEmpty) ...[
                            const SizedBox(height: 40),
                            const Text(
                              'Add catalogue-linked items to this list to compare store totals.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: ShoppaColors.mist),
                            ),
                          ] else ...[
                            if (comparison.bestSaves != null &&
                                comparison.bestSaves! > 0 &&
                                comparison.bestStoreId != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      ShoppaColors.green.withOpacity(0.2),
                                      ShoppaColors.panel2,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: ShoppaColors.green.withOpacity(0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Best deal',
                                      style: TextStyle(
                                        color: ShoppaColors.green,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      comparison.stores
                                          .firstWhere(
                                            (s) =>
                                                s.storeId ==
                                                comparison.bestStoreId,
                                            orElse: () => comparison.stores.first,
                                          )
                                          .name,
                                      style: const TextStyle(
                                        color: ShoppaColors.ink,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Save ${_formatZar(comparison.bestSaves!)} vs most expensive store',
                                      style: const TextStyle(
                                        color: ShoppaColors.green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (_selectedListId != null) ...[
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () {
                                  final title = Uri.encodeComponent(
                                    selected?.title ?? 'List',
                                  );
                                  context.push(
                                    '/delivery?listId=$_selectedListId&title=$title',
                                  );
                                },
                                icon: const Icon(Icons.local_shipping_outlined),
                                label: const Text('Compare delivery options'),
                              ),
                            ],
                            const SizedBox(height: 8),
                            const Text(
                              'Tap a store to set it as where you\'re shopping.',
                              style: TextStyle(
                                color: ShoppaColors.mist,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...comparison.stores.map((store) {
                              final isBest =
                                  store.storeId == comparison.bestStoreId;
                              final extra = worstTotal != null && !isBest
                                  ? store.total - comparison.stores.first.total
                                  : 0;
                              return Card(
                                color: ShoppaColors.panel,
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  onTap: () => _setShoppingAt(store),
                                  title: Text(
                                    store.name,
                                    style: TextStyle(
                                      color: ShoppaColors.ink,
                                      fontWeight:
                                          isBest ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        ConfidenceChip(
                                          confidence: store.confidence,
                                          compact: true,
                                        ),
                                        if (extra > 0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '+${_formatZar(extra)} vs best',
                                            style: const TextStyle(
                                              color: ShoppaColors.mist,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  trailing: Text(
                                    _formatZar(store.total),
                                    style: TextStyle(
                                      color: isBest
                                          ? ShoppaColors.green
                                          : ShoppaColors.ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}