import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';
import '../widgets/collaborator_avatar_stack.dart';
import '../widgets/list_form_dialog.dart';

class MyListsTabScreen extends StatefulWidget {
  const MyListsTabScreen({super.key, required this.listsRepository});

  final ListsRepository listsRepository;

  @override
  State<MyListsTabScreen> createState() => _MyListsTabScreenState();
}

class _MyListsTabScreenState extends State<MyListsTabScreen> {
  late Future<List<ShoppaList>> _lists;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _lists = widget.listsRepository.fetchLists());

  Future<void> _createList() async {
    final values = await showListFormDialog(context);
    if (values == null) return;
    await widget.listsRepository.createList(
      title: values['title'] as String,
      category: values['category'] as String,
      isRecurring: values['is_recurring'] as bool,
    );
    _reload();
  }

  Future<void> _editList(ShoppaList list) async {
    final values = await showListFormDialog(
      context,
      title: 'Edit list',
      initialTitle: list.title,
      initialCategory: list.category,
      initialRecurring: list.isRecurring,
    );
    if (values == null) return;
    await widget.listsRepository.updateList(
      list.id,
      title: values['title'] as String,
      category: values['category'] as String,
      isRecurring: values['is_recurring'] as bool,
    );
    _reload();
  }

  Future<bool> _confirmDeleteList(ShoppaList list) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete list?'),
        content: Text('Remove "${list.title}" permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteList(ShoppaList list) async {
    if (!await _confirmDeleteList(list)) return;
    await widget.listsRepository.deleteList(list.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Lists'),
        actions: [
          IconButton(
            tooltip: 'Discover public lists',
            icon: const Icon(Icons.public_outlined),
            onPressed: () => context.push('/discover-lists'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createList,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<ShoppaList>>(
          future: _lists,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const ListView(
                children: [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))],
              );
            }
            final lists = snapshot.data!;
            if (lists.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text('No lists yet', style: TextStyle(color: ShoppaColors.mist)),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final list = lists[index];
                return Dismissible(
                  key: ValueKey(list.id),
                  direction: list.isOwner
                      ? DismissDirection.endToStart
                      : DismissDirection.none,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: ShoppaColors.rose,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    if (!list.isOwner) return false;
                    return _confirmDeleteList(list);
                  },
                  onDismissed: (_) async {
                    await widget.listsRepository.deleteList(list.id);
                    _reload();
                  },
                  child: ListTile(
                    tileColor: ShoppaColors.panel,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: ShoppaColors.line),
                    ),
                    title: Text(list.title, style: const TextStyle(color: ShoppaColors.ink)),
                    subtitle: Text(
                      '${list.itemCount} items · ${list.category}',
                      style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                    ),
                    onTap: () => context.push(
                      '/lists/${list.id}?title=${Uri.encodeComponent(list.title)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (list.collaborators.length > 1)
                          CollaboratorAvatarStack(
                            collaborators: list.collaborators,
                          ),
                        if (list.isOwner)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editList(list),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}