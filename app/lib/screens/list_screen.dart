import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/list_realtime_client.dart';
import '../core/lists_repository.dart';
import '../core/session_summary.dart';
import '../theme/shoppa_theme.dart';
import '../widgets/item_form_dialog.dart';

/// Item check-off view (SRS FR-2.2, FR-4.1) with a price-capture prompt
/// on check-off (FR-4.3) and a session summary on completion (FR-4.4),
/// sharing (FR-3.1), the per-list activity feed (FR-3.3), and offline
/// usability (FR-4.2): the list stays fully viewable and editable
/// without connectivity, backed by ListsRepository's cache + mutation
/// queue, and flushes that queue as soon as a load succeeds online.
class ListScreen extends StatefulWidget {
  const ListScreen({
    super.key,
    required this.listsRepository,
    required this.realtimeClient,
    required this.listId,
    required this.title,
  });

  final ListsRepository listsRepository;
  final ListRealtimeClient realtimeClient;
  final String listId;
  final String title;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  late Future<ShoppaList> _list;
  StreamSubscription<ListRealtimeEvent>? _realtimeSubscription;
  int _pendingCount = 0;
  // SRS FR-5.3/FR-5.4: the store the shopper says they're currently in,
  // picked from the comparison sheet. Session-only (not persisted) --
  // once set, it's forwarded on every check-off so the server can record
  // a price observation (FR-5.4) without asking per item.
  String? _shoppingAtStoreId;
  String? _shoppingAtStoreName;

  @override
  void initState() {
    super.initState();
    _list = _loadAndSync();
    _list.then((_) => _refreshPendingCount(), onError: (_) {});
    // SRS FR-3.2: any item/collaborator change from another collaborator
    // triggers an immediate refetch, rather than waiting for a manual
    // pull-to-refresh -- this is deliberately a full refetch (not
    // incremental patching) so the screen can never drift from what the
    // REST detail endpoint says is true.
    _realtimeSubscription = widget.realtimeClient
        .connect(widget.listId)
        .listen((_) => _reload());
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  /// Fetches the list, then -- only if that fetch actually reached the
  /// server (not the offline cache fallback) -- flushes anything queued
  /// while we were last offline (SRS FR-4.2) and re-fetches once more so
  /// the screen reflects the synced/merged state.
  Future<ShoppaList> _loadAndSync() async {
    final list = await widget.listsRepository.fetchListDetail(widget.listId);
    if (!list.fromCache) {
      final synced = await widget.listsRepository.syncPending(widget.listId);
      if (synced > 0) {
        return widget.listsRepository.fetchListDetail(widget.listId);
      }
    }
    return list;
  }

  Future<void> _refreshPendingCount() async {
    final count = await widget.listsRepository.pendingCount(widget.listId);
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _list = _loadAndSync();
    });
    _list.then((_) => _refreshPendingCount(), onError: (_) {});
  }

  Future<void> _toggle(ShoppaListItem item, bool canEdit) async {
    if (!canEdit) {
      _showViewOnlySnack();
      return;
    }
    final checking = !item.checked;
    int? paidPrice;
    if (checking) {
      // SRS FR-4.3: confirm or enter the actual price when checking off.
      // There's no price-intelligence comparison price to "confirm"
      // against yet (that lands with Phase 3), so this is scoped to
      // "enter the price paid, or skip" for now.
      if (!mounted) return;
      paidPrice = await _promptForPrice(item.name);
      if (!mounted) return;
    }
    await widget.listsRepository.setItemChecked(
      widget.listId,
      item.id,
      checked: checking,
      paidPrice: paidPrice,
      storeId: checking ? _shoppingAtStoreId : null,
      clientUpdatedAt: DateTime.now().toUtc(),
    );
    _reload();
  }

  /// Returns the entered price in minor units (cents), or null if the
  /// user skipped/cancelled/entered something unparsable.
  Future<int?> _promptForPrice(String itemName) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Price paid for $itemName'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'e.g. 45.99', prefixText: 'R '),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return null;
    final parsed = double.tryParse(result.trim());
    if (parsed == null) return null;
    return (parsed * 100).round();
  }

  void _showViewOnlySnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You have view-only access to this list.')),
    );
  }

  Future<void> _addItem() async {
    final values = await showItemFormDialog(context);
    if (values == null) return;
    try {
      await widget.listsRepository.addItem(
        widget.listId,
        name: values['name'] as String,
        quantity: values['quantity'] as num,
        unit: values['unit'] as String,
        note: values['note'] as String,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editItem(ShoppaListItem item) async {
    final values = await showItemFormDialog(
      context,
      title: 'Edit item',
      initialName: item.name,
      initialQuantity: item.quantity,
      initialUnit: item.unit,
      initialNote: item.note,
    );
    if (values == null) return;
    try {
      await widget.listsRepository.updateItem(
        widget.listId,
        item.id,
        name: values['name'] as String,
        quantity: values['quantity'] as num,
        unit: values['unit'] as String,
        note: values['note'] as String,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<bool> _confirmDeleteItem(ShoppaListItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove item?'),
        content: Text('Remove "${item.name}" from this list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onReorder(List<ShoppaListItem> items, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<ShoppaListItem>.from(items);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    await widget.listsRepository.reorderItems(
      widget.listId,
      reordered.map((e) => e.id).toList(),
    );
    _reload();
  }

  Widget _buildItemTile({
    required ShoppaListItem item,
    required ShoppaList list,
    required int index,
    bool reorderable = false,
    VoidCallback? onDismissed,
  }) {
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: item.checked
            ? ShoppaColors.panel2.withOpacity(0.5)
            : ShoppaColors.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _toggle(item, list.canEdit),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ShoppaColors.line),
            ),
            child: Row(
              children: [
                if (reorderable) ...[
                  ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle, color: ShoppaColors.faint),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  item.checked
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: item.checked ? ShoppaColors.green : ShoppaColors.faint,
                ),
                const SizedBox(width: 12),
                Expanded(child: _itemDetails(item)),
                if (list.canEdit)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: ShoppaColors.mist,
                    onPressed: () => _editItem(item),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!list.canEdit || onDismissed == null) {
      return KeyedSubtree(key: ValueKey(item.id), child: tile);
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: ShoppaColors.rose,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDeleteItem(item),
      onDismissed: (_) => onDismissed(),
      child: tile,
    );
  }

  Widget _itemDetails(ShoppaListItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                item.name,
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w600,
                  decoration:
                      item.checked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (item.hasPromotion) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ShoppaColors.amber.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PROMO',
                  style: TextStyle(
                    color: ShoppaColors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        Text(
          'Qty ${item.quantity} ${item.unit}'
          '${item.note.isNotEmpty ? ' · ${item.note}' : ''}',
          style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _openShareSheet(ShoppaList list) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ShareSheet(
        listsRepository: widget.listsRepository,
        listId: widget.listId,
        canManage: list.isOwner,
      ),
    );
  }

  Future<void> _openActivitySheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ActivitySheet(
        listsRepository: widget.listsRepository,
        listId: widget.listId,
      ),
    );
  }

  /// SRS FR-5.3: shows per-store totals for this list. Tapping a store
  /// sets it as "shopping at" for the rest of this session (SRS FR-5.4),
  /// so subsequent check-offs implicitly submit a price observation for
  /// that store without asking per item.
  Future<void> _openComparisonSheet() async {
    final selected = await showModalBottomSheet<ShoppaStoreComparison>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ComparisonSheet(
        listsRepository: widget.listsRepository,
        listId: widget.listId,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _shoppingAtStoreId = selected.storeId;
      _shoppingAtStoreName = selected.name;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Shopping at ${selected.name}')),
    );
  }

  void _clearShoppingAtStore() {
    setState(() {
      _shoppingAtStoreId = null;
      _shoppingAtStoreName = null;
    });
  }

  /// SRS FR-4.4: a session summary of spend (and, once price_intelligence
  /// exists, savings) on completion. Computed purely from the
  /// already-loaded list -- no extra request, so it works offline too.
  Future<void> _openSessionSummary(ShoppaList list) async {
    final summary = SessionSummary.fromItems(list.items ?? []);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${summary.checkedItems} of ${summary.totalItems} items checked off',
            ),
            const SizedBox(height: 8),
            Text(
              'Total spent: ${summary.formattedTotalSpent}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (summary.hasIncompletePricing) ...[
              const SizedBox(height: 8),
              Text(
                '${summary.checkedWithoutPrice} checked without a recorded price',
                style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Savings vs. other stores arrive with price comparison (Phase 3).',
              style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          FutureBuilder<ShoppaList>(
            future: _list,
            builder: (context, snapshot) {
              final list = snapshot.data;
              return IconButton(
                tooltip: 'Finish shopping',
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed:
                    list == null ? null : () => _openSessionSummary(list),
              );
            },
          ),
          IconButton(
            tooltip: 'Activity',
            icon: const Icon(Icons.history),
            onPressed: _openActivitySheet,
          ),
          IconButton(
            tooltip: 'Compare prices',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: _openComparisonSheet,
          ),
          FutureBuilder<ShoppaList>(
            future: _list,
            builder: (context, snapshot) {
              final list = snapshot.data;
              return IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.people_outline),
                onPressed:
                    list == null ? null : () => _openShareSheet(list),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<ShoppaList>(
        future: _list,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load list: ${snapshot.error}',
                style: const TextStyle(color: ShoppaColors.rose),
              ),
            );
          }
          final list = snapshot.data!;
          final items = list.items ?? [];
          return Column(
            children: [
              if (list.fromCache)
                _InfoBanner(
                  text: 'Offline — showing the last synced version of this list.',
                  color: ShoppaColors.amber,
                )
              else if (_pendingCount > 0)
                _InfoBanner(
                  text: _pendingCount == 1
                      ? '1 change waiting to sync.'
                      : '$_pendingCount changes waiting to sync.',
                  color: ShoppaColors.amber,
                ),
              if (!list.isOwner)
                _InfoBanner(
                  text: list.canEdit
                      ? 'Shared with you — you can edit this list.'
                      : 'Shared with you — view only.',
                  color: ShoppaColors.mist,
                ),
              if (_shoppingAtStoreName != null)
                Container(
                  width: double.infinity,
                  color: ShoppaColors.panel2.withOpacity(0.6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Shopping at $_shoppingAtStoreName',
                          style: const TextStyle(
                            color: ShoppaColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _clearShoppingAtStore,
                        child: const Icon(Icons.close,
                            size: 16, color: ShoppaColors.mist),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'No items yet',
                          style: TextStyle(color: ShoppaColors.mist),
                        ),
                      )
                    : list.canEdit
                        ? ReorderableListView.builder(
                            padding: const EdgeInsets.all(16),
                            buildDefaultDragHandles: false,
                            itemCount: items.length,
                            onReorder: (oldIndex, newIndex) =>
                                _onReorder(items, oldIndex, newIndex),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _buildItemTile(
                                item: item,
                                list: list,
                                index: index,
                                reorderable: true,
                                onDismissed: () => widget.listsRepository
                                    .deleteItem(widget.listId, item.id)
                                    .then((_) => _reload()),
                              );
                            },
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _buildItemTile(
                                item: item,
                                list: list,
                                index: index,
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<ShoppaList>(
        future: _list,
        builder: (context, snapshot) {
          final list = snapshot.data;
          if (list == null || !list.canEdit) return const SizedBox.shrink();
          return FloatingActionButton(
            onPressed: _addItem,
            backgroundColor: ShoppaColors.amber,
            child: const Icon(Icons.add, color: Colors.white),
          );
        },
      ),
    );
  }
}

/// Collaborator management sheet (SRS FR-3.1). Anyone on the list can see
/// who else is on it; only the owner sees the invite form and remove
/// buttons — the backend enforces this too, this just avoids showing
/// controls that would 403.
class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.listsRepository,
    required this.listId,
    required this.canManage,
  });

  final ListsRepository listsRepository;
  final String listId;
  final bool canManage;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late Future<List<ShoppaCollaborator>> _collaborators;
  final _emailController = TextEditingController();
  String _permission = 'view';
  String? _error;

  @override
  void initState() {
    super.initState();
    _collaborators = widget.listsRepository.fetchCollaborators(widget.listId);
  }

  void _reload() {
    setState(() {
      _collaborators = widget.listsRepository.fetchCollaborators(widget.listId);
    });
  }

  Future<void> _invite() async {
    setState(() => _error = null);
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    try {
      await widget.listsRepository.shareList(
        widget.listId,
        email: email,
        permission: _permission,
      );
      _emailController.clear();
      _reload();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _remove(String userId) async {
    await widget.listsRepository.removeCollaborator(widget.listId, userId);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Collaborators',
            style: TextStyle(
              color: ShoppaColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<ShoppaCollaborator>>(
            future: _collaborators,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final collaborators = snapshot.data ?? [];
              if (collaborators.isEmpty) {
                return const Text(
                  'Not shared with anyone yet.',
                  style: TextStyle(color: ShoppaColors.mist),
                );
              }
              return Column(
                children: collaborators
                    .map(
                      (c) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.userEmail),
                        subtitle: Text(c.permission),
                        trailing: widget.canManage
                            ? IconButton(
                                icon: const Icon(Icons.close,
                                    color: ShoppaColors.rose),
                                onPressed: () => _remove(c.userId),
                              )
                            : null,
                      ),
                    )
                    .toList(),
              );
            },
          ),
          if (widget.canManage) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      hintText: 'friend@example.com',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _permission,
                  items: const [
                    DropdownMenuItem(value: 'view', child: Text('View')),
                    DropdownMenuItem(value: 'edit', child: Text('Edit')),
                  ],
                  onChanged: (value) =>
                      setState(() => _permission = value ?? 'view'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _invite,
                child: const Text('Share'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Read-only activity feed (SRS FR-3.3).
class _ActivitySheet extends StatelessWidget {
  const _ActivitySheet({required this.listsRepository, required this.listId});

  final ListsRepository listsRepository;
  final String listId;

  static const _labels = {
    'item_added': 'added an item',
    'item_updated': 'updated an item',
    'item_checked': 'checked off an item',
    'item_removed': 'removed an item',
    'collaborator_joined': 'shared this list',
    'collaborator_removed': 'removed a collaborator',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activity',
            style: TextStyle(
              color: ShoppaColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: FutureBuilder<List<ShoppaActivityEntry>>(
              future: listsRepository.fetchActivity(listId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final entries = snapshot.data ?? [];
                if (entries.isEmpty) {
                  return const Text(
                    'No activity yet.',
                    style: TextStyle(color: ShoppaColors.mist),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final label = _labels[entry.action] ?? entry.action;
                    return Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: entry.actorEmail ?? 'Someone',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' $label'),
                          if (entry.detail.isNotEmpty)
                            TextSpan(
                              text: ' — ${entry.detail}',
                              style: const TextStyle(color: ShoppaColors.mist),
                            ),
                        ],
                      ),
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

/// SRS FR-5.3: per-store totals for this list, cheapest first. Tapping a
/// store returns it to the caller (see ListScreen._openComparisonSheet),
/// which uses that to tag subsequent check-offs (FR-5.4).
class _ComparisonSheet extends StatelessWidget {
  const _ComparisonSheet({required this.listsRepository, required this.listId});

  final ListsRepository listsRepository;
  final String listId;

  String _formatMoney(int minorUnits, String currencyCode) {
    final symbol = currencyCode == 'ZAR' ? 'R' : '$currencyCode ';
    return '$symbol${(minorUnits / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Compare prices',
            style: TextStyle(
              color: ShoppaColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a store to set it as where you\'re shopping.',
            style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: FutureBuilder<ShoppaComparison>(
              future: listsRepository.fetchComparison(listId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    'Could not load comparison: ${snapshot.error}',
                    style: const TextStyle(color: ShoppaColors.rose),
                  );
                }
                final comparison = snapshot.data!;
                if (comparison.isEmpty) {
                  return const Text(
                    'Not enough priced items on this list yet to compare '
                    'stores.',
                    style: TextStyle(color: ShoppaColors.mist),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: comparison.stores.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final store = comparison.stores[index];
                    final isBest = store.storeId == comparison.bestStoreId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Navigator.of(context).pop(store),
                      title: Text(
                        store.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Confidence: ${store.confidence}'
                        '${isBest && comparison.bestSaves != null && comparison.bestSaves! > 0 ? ' · saves ${_formatMoney(comparison.bestSaves!, comparison.currencyCode)}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        _formatMoney(store.total, comparison.currencyCode),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isBest ? ShoppaColors.green : ShoppaColors.ink,
                        ),
                      ),
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

/// Small dismissable-free status strip used for both the offline/pending
/// (FR-4.2) and shared-list-role banners.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ShoppaColors.panel2.withOpacity(0.6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
