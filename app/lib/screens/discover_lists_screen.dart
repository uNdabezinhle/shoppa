import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/list_category_style.dart';
import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';
import '../widgets/list_form_dialog.dart';

/// FR-8.2 — discover and clone published public lists.
class DiscoverListsScreen extends StatefulWidget {
  const DiscoverListsScreen({super.key, required this.listsRepository});

  final ListsRepository listsRepository;

  @override
  State<DiscoverListsScreen> createState() => _DiscoverListsScreenState();
}

class _DiscoverListsScreenState extends State<DiscoverListsScreen> {
  late Future<List<ShoppaList>> _lists;
  final _searchController = TextEditingController();
  String _query = '';
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _lists = widget.listsRepository.fetchPublicLists();
    });
  }

  Future<void> _clone(ShoppaList list) async {
    try {
      final clone = await widget.listsRepository.duplicateList(list.id);
      if (!mounted) return;
      context.push(
        '/lists/${clone.id}?title=${Uri.encodeComponent(clone.title)}',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ShoppaColors.rose),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not clone list: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _preview(ShoppaList summary) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ShoppaColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PublicListPreviewSheet(
        summary: summary,
        listsRepository: widget.listsRepository,
        onClone: () {
          Navigator.pop(ctx);
          _clone(summary);
        },
      ),
    );
  }

  List<ShoppaList> _filter(List<ShoppaList> lists) {
    final q = _query.trim().toLowerCase();
    return lists.where((list) {
      if (_categoryFilter != null && list.category != _categoryFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return list.title.toLowerCase().contains(q) ||
          list.category.toLowerCase().contains(q) ||
          list.eventName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover lists')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.error is ApiException
                            ? (snapshot.error as ApiException).message
                            : 'Could not load public lists.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: ShoppaColors.rose),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final all = snapshot.data ?? [];
            final lists = _filter(all);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search public lists…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _categoryFilter == null,
                        onSelected: (_) =>
                            setState(() => _categoryFilter = null),
                      ),
                      const SizedBox(width: 8),
                      ...listCategories.map((c) {
                        final style = listCategoryStyle(c['id']);
                        final selected = _categoryFilter == c['id'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            avatar: Icon(
                              style.icon,
                              size: 16,
                              color: selected
                                  ? ShoppaColors.obsidian
                                  : style.color,
                            ),
                            label: Text(style.label),
                            selected: selected,
                            selectedColor: style.color.withOpacity(0.35),
                            checkmarkColor: ShoppaColors.ink,
                            onSelected: (sel) {
                              setState(() {
                                _categoryFilter = sel ? c['id'] : null;
                              });
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No published lists yet — Professional users can publish lists publicly.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    ),
                  )
                else if (lists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No lists match your search.',
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    ),
                  )
                else
                  ...lists.map((list) {
                    final cat = listCategoryStyle(list.category);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: ShoppaColors.panel,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _preview(list),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: ShoppaColors.line),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: 4,
                                    decoration: BoxDecoration(
                                      color: cat.color,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(13),
                                        bottomLeft: Radius.circular(13),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListTile(
                                      title: Text(
                                        list.title,
                                        style: const TextStyle(
                                          color: ShoppaColors.ink,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          cat.label,
                                          '${list.itemCount} items',
                                          if (list.eventName.isNotEmpty)
                                            list.eventName,
                                          'Tap to preview',
                                        ].join(' · '),
                                        style: const TextStyle(
                                          color: ShoppaColors.mist,
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: TextButton(
                                        onPressed: () => _clone(list),
                                        child: const Text('Clone'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PublicListPreviewSheet extends StatefulWidget {
  const _PublicListPreviewSheet({
    required this.summary,
    required this.listsRepository,
    required this.onClone,
  });

  final ShoppaList summary;
  final ListsRepository listsRepository;
  final VoidCallback onClone;

  @override
  State<_PublicListPreviewSheet> createState() =>
      _PublicListPreviewSheetState();
}

class _PublicListPreviewSheetState extends State<_PublicListPreviewSheet> {
  late Future<ShoppaList> _detail;

  @override
  void initState() {
    super.initState();
    _detail = widget.listsRepository.fetchListDetail(widget.summary.id);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      child: SizedBox(
        height: maxHeight,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.summary.title,
                          style: const TextStyle(
                            color: ShoppaColors.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            listCategoryLabel(widget.summary.category),
                            if (widget.summary.eventName.isNotEmpty)
                              widget.summary.eventName,
                            'Public list · preview',
                          ].join(' · '),
                          style: const TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: 12,
                          ),
                        ),
                      ],
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
              child: FutureBuilder<ShoppaList>(
                future: _detail,
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
                              : 'Could not load list items.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: ShoppaColors.rose),
                        ),
                      ),
                    );
                  }
                  final items = snapshot.data?.items ?? const [];
                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        'This list has no items yet.',
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final qty = item.quantity == item.quantity.roundToDouble()
                          ? item.quantity.toInt().toString()
                          : item.quantity.toString();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            color: ShoppaColors.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: Text(
                          '$qty ${item.unit}',
                          style: const TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: item.note.isEmpty
                            ? null
                            : Text(
                                item.note,
                                style: const TextStyle(
                                  color: ShoppaColors.mist,
                                  fontSize: 12,
                                ),
                              ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: widget.onClone,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Clone to my lists'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
