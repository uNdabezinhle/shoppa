import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';

/// Pick another list, then select items to copy into the current list.
/// Returns the chosen items (caller performs addItem).
Future<List<ShoppaListItem>?> showImportFromListSheet(
  BuildContext context, {
  required ListsRepository listsRepository,
  required String currentListId,
}) {
  return showModalBottomSheet<List<ShoppaListItem>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ImportFromListSheet(
      listsRepository: listsRepository,
      currentListId: currentListId,
    ),
  );
}

class _ImportFromListSheet extends StatefulWidget {
  const _ImportFromListSheet({
    required this.listsRepository,
    required this.currentListId,
  });

  final ListsRepository listsRepository;
  final String currentListId;

  @override
  State<_ImportFromListSheet> createState() => _ImportFromListSheetState();
}

class _ImportFromListSheetState extends State<_ImportFromListSheet> {
  late Future<List<ShoppaList>> _lists;
  ShoppaList? _selected;
  List<ShoppaListItem> _items = [];
  final Set<String> _selectedIds = {};
  bool _loadingDetail = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lists = widget.listsRepository.fetchLists();
  }

  Future<void> _pickList(ShoppaList list) async {
    setState(() {
      _selected = list;
      _loadingDetail = true;
      _error = null;
      _items = [];
      _selectedIds.clear();
    });
    try {
      final detail = await widget.listsRepository.fetchListDetail(list.id);
      final items = detail.items ?? [];
      if (!mounted) return;
      setState(() {
        _items = items;
        _selectedIds.addAll(items.map((i) => i.id));
        _loadingDetail = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingDetail = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load list.';
        _loadingDetail = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.75;
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _selected == null ? 'Import from list' : 'Choose items',
              style: const TextStyle(
                color: ShoppaColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _selected == null
                  ? 'Copy items from another of your lists.'
                  : _selected!.title,
              style: const TextStyle(color: ShoppaColors.mist, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: ShoppaColors.rose),
                ),
              ),
            Expanded(
              child: _selected == null
                  ? FutureBuilder<List<ShoppaList>>(
                      future: _lists,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final lists = (snapshot.data ?? [])
                            .where((l) => l.id != widget.currentListId)
                            .toList();
                        if (lists.isEmpty) {
                          return const Center(
                            child: Text(
                              'No other lists to import from.',
                              style: TextStyle(color: ShoppaColors.mist),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: lists.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final list = lists[index];
                            return ListTile(
                              tileColor: ShoppaColors.panel2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              title: Text(list.title),
                              subtitle: Text(
                                '${list.itemCount} items · ${list.category}',
                                style: const TextStyle(
                                  color: ShoppaColors.mist,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _pickList(list),
                            );
                          },
                        );
                      },
                    )
                  : _loadingDetail
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                          ? const Center(
                              child: Text(
                                'That list has no items.',
                                style: TextStyle(color: ShoppaColors.mist),
                              ),
                            )
                          : Column(
                              children: [
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => setState(
                                        () => _selectedIds
                                            .addAll(_items.map((i) => i.id)),
                                      ),
                                      child: const Text('Select all'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _selectedIds.clear()),
                                      child: const Text('Clear'),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _selected = null;
                                        _items = [];
                                        _selectedIds.clear();
                                      }),
                                      child: const Text('Back'),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _items.length,
                                    itemBuilder: (context, index) {
                                      final item = _items[index];
                                      final checked =
                                          _selectedIds.contains(item.id);
                                      return CheckboxListTile(
                                        value: checked,
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selectedIds.add(item.id);
                                            } else {
                                              _selectedIds.remove(item.id);
                                            }
                                          });
                                        },
                                        title: Text(item.name),
                                        subtitle: Text(
                                          'Qty ${item.quantity} ${item.unit}'
                                          '${item.note.isNotEmpty ? ' · ${item.note}' : ''}',
                                          style: const TextStyle(
                                            color: ShoppaColors.mist,
                                            fontSize: 12,
                                          ),
                                        ),
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
            ),
            if (_selected != null && _items.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () {
                        final chosen = _items
                            .where((i) => _selectedIds.contains(i.id))
                            .toList();
                        Navigator.pop(context, chosen);
                      },
                child: Text(
                  'Import ${_selectedIds.length} item'
                  '${_selectedIds.length == 1 ? '' : 's'}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
