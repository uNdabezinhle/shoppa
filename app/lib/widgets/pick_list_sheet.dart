import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';

/// Pick one of the user's lists (excluding [excludeListId]).
Future<ShoppaList?> showPickListSheet(
  BuildContext context, {
  required ListsRepository listsRepository,
  required String excludeListId,
  String title = 'Choose a list',
}) {
  return showModalBottomSheet<ShoppaList>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _PickListSheet(
      listsRepository: listsRepository,
      excludeListId: excludeListId,
      title: title,
    ),
  );
}

class _PickListSheet extends StatefulWidget {
  const _PickListSheet({
    required this.listsRepository,
    required this.excludeListId,
    required this.title,
  });

  final ListsRepository listsRepository;
  final String excludeListId;
  final String title;

  @override
  State<_PickListSheet> createState() => _PickListSheetState();
}

class _PickListSheetState extends State<_PickListSheet> {
  late Future<List<ShoppaList>> _lists;

  @override
  void initState() {
    super.initState();
    _lists = widget.listsRepository.fetchLists();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ShoppaColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: ShoppaColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ShoppaList>>(
              future: _lists,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        snapshot.error is ApiException
                            ? (snapshot.error as ApiException).message
                            : 'Could not load lists.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: ShoppaColors.rose),
                      ),
                    ),
                  );
                }
                final lists = (snapshot.data ?? [])
                    .where((l) => l.id != widget.excludeListId && l.canEdit)
                    .toList();
                if (lists.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No other editable lists. Create one first.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: lists.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final list = lists[index];
                    return ListTile(
                      tileColor: ShoppaColors.panel2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: ShoppaColors.line),
                      ),
                      title: Text(
                        list.title,
                        style: const TextStyle(
                          color: ShoppaColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${list.itemCount} items · ${list.category}',
                        style: const TextStyle(
                          color: ShoppaColors.mist,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, list),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
