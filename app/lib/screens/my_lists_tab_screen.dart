import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/last_paid_prices_store.dart';
import '../core/list_category_style.dart';
import '../core/list_shop_helpers.dart';
import '../core/lists_repository.dart';
import '../core/multi_list_trip.dart';
import '../core/offline_store.dart';
import '../core/last_trip_lists_store.dart';
import '../core/pinned_lists_store.dart';
import '../core/receipt_history_store.dart';
import '../theme/shoppa_theme.dart';
import '../widgets/collaborator_avatar_stack.dart';
import '../widgets/list_form_dialog.dart';
import '../widgets/pick_trip_lists_sheet.dart';
import '../widgets/receipt_history_sheet.dart';

class MyListsTabScreen extends StatefulWidget {
  const MyListsTabScreen({
    super.key,
    required this.listsRepository,
    this.accountType = 'personal',
  });

  final ListsRepository listsRepository;
  final String accountType;

  @override
  State<MyListsTabScreen> createState() => _MyListsTabScreenState();
}

class _MyListsTabScreenState extends State<MyListsTabScreen> {
  late Future<List<ShoppaList>> _lists;
  final _searchController = TextEditingController();
  final PinnedListsStore _pinnedStore = SharedPreferencesPinnedListsStore();
  final LastTripListsStore _lastTripLists = SharedPreferencesLastTripListsStore();
  final ReceiptHistoryStore _receiptHistory =
      SharedPreferencesReceiptHistoryStore();
  final LastPaidPricesStore _lastPaidPrices =
      SharedPreferencesLastPaidPricesStore();
  final OfflineStore _offlineStore = SharedPreferencesOfflineStore();
  String _query = '';
  String? _categoryFilter;
  ListSortMode _sortMode = ListSortMode.recent;
  Set<String> _pinnedIds = {};
  /// When true, only lists with items still left to check.
  bool _incompleteOnly = false;
  Map<String, LoggedReceipt> _latestReceiptByScope = {};
  Map<String, int> _lastPaidSnapshot = const {};
  Map<String, List<ShoppaListItem>> _cachedItemsByListId = {};
  LoggedReceipt? _lastReceipt;
  ReceiptSpendInsights? _receiptInsights;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadPinned();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    final future = _fetchListsWithSpendContext();
    setState(() {
      _lists = future;
    });
  }

  Future<List<ShoppaList>> _fetchListsWithSpendContext() async {
    final lists = await widget.listsRepository.fetchLists();
    await _hydrateSpendContext(lists);
    return lists;
  }

  Future<void> _hydrateSpendContext(List<ShoppaList> lists) async {
    List<LoggedReceipt> recent = const [];
    Map<String, int> snap = const {};
    try {
      recent = await _receiptHistory.recent(limit: 40);
    } catch (_) {}
    try {
      snap = await _lastPaidPrices.snapshot();
    } catch (_) {}

    final itemsById = <String, List<ShoppaListItem>>{};
    final incomplete = lists.where(listIsIncompleteTrip).take(20);
    for (final list in incomplete) {
      if (list.items != null) {
        itemsById[list.id] = list.items!;
        continue;
      }
      try {
        final json = await _offlineStore.getCachedListJson(list.id);
        final rawItems = json?['items'];
        if (rawItems is! List) continue;
        itemsById[list.id] = rawItems
            .map(
              (e) => ShoppaListItem.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(growable: false);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _latestReceiptByScope = indexLatestReceiptsByScope(recent);
      _lastReceipt = recent.isEmpty ? null : recent.first;
      _receiptInsights =
          recent.isEmpty ? null : ReceiptSpendInsights.from(recent);
      _lastPaidSnapshot = snap;
      _cachedItemsByListId = itemsById;
    });
  }

  List<ShoppaListItem>? _itemsForTeaser(ShoppaList list) {
    return list.items ?? _cachedItemsByListId[list.id];
  }

  RemainingSpendEstimate? _aggregateLeftEst(List<ShoppaList> lists) {
    var remaining = 0;
    var priced = 0;
    var cents = 0;
    for (final list in lists.where(listIsIncompleteTrip)) {
      final items = _itemsForTeaser(list);
      if (items == null) continue;
      final est = estimateRemainingSpend(
        items,
        rememberedByName: _lastPaidSnapshot,
      );
      remaining += est.remainingCount;
      priced += est.pricedCount;
      cents += est.estimatedCents;
    }
    if (priced <= 0 || cents <= 0) return null;
    return RemainingSpendEstimate(
      remainingCount: remaining,
      pricedCount: priced,
      estimatedCents: cents,
    );
  }

  Future<void> _openReceiptHistory() async {
    await showReceiptHistorySheet(
      context,
      store: _receiptHistory,
      title: 'Receipt history',
    );
    if (!mounted) return;
    List<ShoppaList> lists = const [];
    try {
      lists = await widget.listsRepository.fetchLists();
    } catch (_) {}
    if (!mounted) return;
    await _hydrateSpendContext(lists);
  }

  Future<void> _loadPinned() async {
    final ids = await _pinnedStore.getPinnedIds();
    if (!mounted) return;
    setState(() => _pinnedIds = ids);
  }

  Future<void> _togglePin(ShoppaList list) async {
    await _pinnedStore.toggle(list.id);
    await _loadPinned();
    if (!mounted) return;
    final nowPinned = _pinnedIds.contains(list.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nowPinned ? 'Pinned “${list.title}”' : 'Unpinned “${list.title}”',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  List<ShoppaList> _filter(List<ShoppaList> lists) {
    final q = _query.trim().toLowerCase();
    final filtered = lists.where((list) {
      if (_incompleteOnly && !listIsIncompleteTrip(list)) {
        return false;
      }
      if (_categoryFilter != null && list.category != _categoryFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return list.title.toLowerCase().contains(q) ||
          list.category.toLowerCase().contains(q) ||
          list.eventName.toLowerCase().contains(q);
    }).toList();
    return sortShoppaLists(
      filtered,
      mode: _sortMode,
      pinnedIds: _pinnedIds,
    );
  }

  String get _sortLabel {
    switch (_sortMode) {
      case ListSortMode.recent:
        return 'Recent';
      case ListSortMode.title:
        return 'A–Z';
      case ListSortMode.itemCount:
        return 'Most items';
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    final message = e is ApiException
        ? e.message
        : e is NetworkUnavailableException
            ? e.message
            : 'Something went wrong. Try again.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: ShoppaColors.rose),
    );
  }

  bool get _isProfessional => widget.accountType == 'professional';

  Future<void> _createList() async {
    final values = await showListFormDialog(
      context,
      showEventFields: _isProfessional,
    );
    if (values == null) return;
    try {
      await widget.listsRepository.createList(
        title: values['title'] as String,
        category: values['category'] as String,
        isRecurring: values['is_recurring'] as bool,
        eventName: values['event_name'] as String?,
        eventDate: values['event_date'] as String?,
      );
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _editList(ShoppaList list) async {
    final values = await showListFormDialog(
      context,
      title: 'Edit list',
      initialTitle: list.title,
      initialCategory: list.category,
      initialRecurring: list.isRecurring,
      initialEventName: list.eventName,
      initialEventDate: list.eventDate,
      showEventFields: _isProfessional,
    );
    if (values == null) return;
    try {
      await widget.listsRepository.updateList(
        list.id,
        title: values['title'] as String,
        category: values['category'] as String,
        isRecurring: values['is_recurring'] as bool,
        eventName: values['event_name'] as String?,
        eventDate: values['event_date'] as String?,
      );
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<bool> _confirmDeleteList(ShoppaList list) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete list?'),
        content: Text('Remove "${list.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _duplicateList(ShoppaList list) async {
    try {
      final clone = await widget.listsRepository.duplicateList(list.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Duplicated “${clone.title}”'),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
    } catch (e) {
      _showError(e);
    }
  }

  void _openList(ShoppaList list, {bool shop = false}) {
    context.push(
      listDetailPath(list.id, title: list.title, shop: shop),
    );
  }

  Future<void> _startTodaysTrip(List<ShoppaList> all) async {
    final incomplete = all.where(listEligibleForTrip).toList();
    if (incomplete.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No lists with items left to shop'),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
      return;
    }
    if (incomplete.length == 1) {
      final only = incomplete.first;
      await _lastTripLists.setListIds([only.id]);
      if (!mounted) return;
      _openList(only, shop: true);
      return;
    }
    final remembered = await _lastTripLists.getListIds();
    if (!mounted) return;
    final selected = await showPickTripListsSheet(
      context,
      lists: incomplete,
      initialSelectedIds: remembered,
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _lastTripLists.setListIds(selected);
    if (!mounted) return;
    if (selected.length == 1) {
      final list = incomplete.firstWhere((l) => l.id == selected.first);
      _openList(list, shop: true);
      return;
    }
    context.push(multiListTripPath(selected));
  }

  Future<void> _onListMenu(ShoppaList list, String action) async {
    if (action == 'shop') {
      _openList(list, shop: true);
    } else if (action == 'pin') {
      await _togglePin(list);
    } else if (action == 'edit') {
      await _editList(list);
    } else if (action == 'duplicate') {
      await _duplicateList(list);
    } else if (action == 'delete') {
      if (!await _confirmDeleteList(list)) return;
      try {
        await widget.listsRepository.deleteList(list.id);
        await _pinnedStore.setPinned(list.id, false);
        await _loadPinned();
        _reload();
      } catch (e) {
        _showError(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Lists'),
        actions: [
          FutureBuilder<List<ShoppaList>>(
            future: _lists,
            builder: (context, snapshot) {
              final all = snapshot.data ?? const <ShoppaList>[];
              final incomplete =
                  all.where(listEligibleForTrip).length;
              if (incomplete == 0) return const SizedBox.shrink();
              return IconButton(
                tooltip: incomplete == 1
                    ? 'Start shopping'
                    : 'Today’s trip ($incomplete lists)',
                icon: Badge(
                  isLabelVisible: incomplete > 1,
                  label: Text('$incomplete'),
                  backgroundColor: ShoppaColors.amber,
                  textColor: ShoppaColors.obsidian,
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
                onPressed: () => _startTodaysTrip(all),
              );
            },
          ),
          PopupMenuButton<ListSortMode>(
            tooltip: 'Sort lists',
            initialValue: _sortMode,
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: ListSortMode.recent,
                child: Text('Sort by recent'),
              ),
              PopupMenuItem(
                value: ListSortMode.title,
                child: Text('Sort A–Z'),
              ),
              PopupMenuItem(
                value: ListSortMode.itemCount,
                child: Text('Sort by item count'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(Icons.sort, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    _sortLabel,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
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
            if (snapshot.connectionState != ConnectionState.done) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              );
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Text(
                    snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : snapshot.error is NetworkUnavailableException
                            ? (snapshot.error as NetworkUnavailableException)
                                .message
                            : 'Could not load lists.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ShoppaColors.rose),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }
            final all = snapshot.data ?? [];
            final lists = _filter(all);
            final fromCache =
                all.isNotEmpty && all.every((l) => l.fromCache);
            if (all.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
                children: [
                  const Icon(
                    Icons.playlist_add_check_outlined,
                    size: 48,
                    color: ShoppaColors.faint,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No lists yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ShoppaColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create a shopping list, or clone a public one from Discover.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ShoppaColors.mist, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _createList,
                    icon: const Icon(Icons.add),
                    label: const Text('Create list'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/discover-lists'),
                    icon: const Icon(Icons.public_outlined),
                    label: const Text('Discover public lists'),
                  ),
                ],
              );
            }
            final categories = all.map((l) => l.category).toSet().toList()
              ..sort();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search lists…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('In progress'),
                        selected: _incompleteOnly,
                        onSelected: (selected) =>
                            setState(() => _incompleteOnly = selected),
                      ),
                      if (categories.length > 1) ...[
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('All categories'),
                          selected: _categoryFilter == null,
                          onSelected: (_) =>
                              setState(() => _categoryFilter = null),
                        ),
                        const SizedBox(width: 8),
                        ...categories.map((c) {
                          final style = listCategoryStyle(c);
                          final selected = _categoryFilter == c;
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
                              onSelected: (sel) => setState(
                                () => _categoryFilter = sel ? c : null,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                if (fromCache) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ShoppaColors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: ShoppaColors.amber.withOpacity(0.35),
                      ),
                    ),
                    child: const Text(
                      'Offline — showing lists from your last successful sync.',
                      style: TextStyle(
                        color: ShoppaColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                Builder(
                  builder: (context) {
                    final incomplete =
                        all.where(listIsIncompleteTrip).toList();
                    final remainingItems = incomplete.fold<int>(
                      0,
                      (n, l) => n + remainingItemCount(l),
                    );
                    final leftEst = _aggregateLeftEst(all);
                    final showTeaser = _lastReceipt != null ||
                        leftEst != null ||
                        remainingItems > 0;
                    if (!showTeaser) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _MyListsSpendTeaser(
                        remainingItems: remainingItems,
                        incompleteListCount: incomplete.length,
                        leftEst: leftEst,
                        lastReceipt: _lastReceipt,
                        insights: _receiptInsights,
                        onTapReceipts: _openReceiptHistory,
                        onStartTrip: incomplete.isEmpty
                            ? null
                            : () => _startTodaysTrip(all),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (lists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(
                      child: Text(
                        'No lists match your filters',
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    ),
                  )
                else
                  ...lists.map((list) {
                    final cat = listCategoryStyle(list.category);
                    final pinned = _pinnedIds.contains(list.id);
                    final moneyBits = listMoneyTeaserBits(
                      lastReceipt: _latestReceiptByScope[list.id],
                      items: _itemsForTeaser(list),
                      rememberedByName: _lastPaidSnapshot,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Dismissible(
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
                          try {
                            await widget.listsRepository.deleteList(list.id);
                            await _pinnedStore.setPinned(list.id, false);
                            await _loadPinned();
                          } catch (e) {
                            _showError(e);
                          }
                          _reload();
                        },
                        child: Material(
                          color: ShoppaColors.panel,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openList(list),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: pinned
                                      ? ShoppaColors.amber.withOpacity(0.55)
                                      : ShoppaColors.line,
                                ),
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      width: 4,
                                      decoration: BoxDecoration(
                                        color: cat.color,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(11),
                                          bottomLeft: Radius.circular(11),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.only(
                                          left: 4,
                                          right: 8,
                                        ),
                                        leading: IconButton(
                                          tooltip: pinned
                                              ? 'Unpin'
                                              : 'Pin to top',
                                          icon: Icon(
                                            pinned
                                                ? Icons.push_pin
                                                : Icons.push_pin_outlined,
                                            color: pinned
                                                ? ShoppaColors.amber
                                                : ShoppaColors.mist,
                                            size: 22,
                                          ),
                                          onPressed: () => _togglePin(list),
                                        ),
                                        title: Text(
                                          list.title,
                                          style: const TextStyle(
                                            color: ShoppaColors.ink,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Wrap(
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: cat.color
                                                        .withOpacity(0.16),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      6,
                                                    ),
                                                    border: Border.all(
                                                      color: cat.color
                                                          .withOpacity(0.4),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        cat.icon,
                                                        size: 12,
                                                        color: cat.color,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        cat.label,
                                                        style: TextStyle(
                                                          color: cat.color,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  [
                                                    list.itemCount == 0
                                                        ? 'Empty'
                                                        : '${list.checkedCount}/${list.itemCount} checked',
                                                    if (list.isRecurring)
                                                      'recurring',
                                                    if (list.eventName
                                                        .isNotEmpty)
                                                      list.eventName,
                                                    if (pinned) 'pinned',
                                                    if (list.updatedAtDate !=
                                                        null)
                                                      formatRelativeTime(
                                                        list.updatedAtDate,
                                                      ),
                                                  ].join(' · '),
                                                  style: const TextStyle(
                                                    color: ShoppaColors.mist,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (moneyBits.isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      top: 3,
                                                    ),
                                                    child: Text(
                                                      moneyBits.join(' · '),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color:
                                                            ShoppaColors.green,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (list.itemCount > 0) ...[
                                              const SizedBox(height: 6),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                child: LinearProgressIndicator(
                                                  value: list.checkedCount /
                                                      list.itemCount,
                                                  minHeight: 4,
                                                  backgroundColor:
                                                      ShoppaColors.line,
                                                  color: list.checkedCount >=
                                                          list.itemCount
                                                      ? ShoppaColors.green
                                                      : cat.color,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (list.itemCount > 0)
                                              IconButton(
                                                tooltip: listIsIncompleteTrip(
                                                  list,
                                                )
                                                    ? 'Start shopping'
                                                    : 'Shop again',
                                                icon: Icon(
                                                  listIsIncompleteTrip(list)
                                                      ? Icons
                                                          .shopping_cart_outlined
                                                      : Icons.replay_outlined,
                                                  color: listIsIncompleteTrip(
                                                    list,
                                                  )
                                                      ? ShoppaColors.amber
                                                      : ShoppaColors.mist,
                                                  size: 22,
                                                ),
                                                onPressed: () =>
                                                    _openList(list, shop: true),
                                              ),
                                            if (list.collaborators.isNotEmpty)
                                              CollaboratorAvatarStack(
                                                collaborators:
                                                    list.collaborators,
                                              ),
                                            PopupMenuButton<String>(
                                              tooltip: 'List actions',
                                              onSelected: (v) =>
                                                  _onListMenu(list, v),
                                              itemBuilder: (ctx) {
                                                return [
                                                  if (list.itemCount > 0)
                                                    PopupMenuItem(
                                                      value: 'shop',
                                                      child: Text(
                                                        listIsIncompleteTrip(
                                                          list,
                                                        )
                                                            ? 'Start shopping'
                                                            : 'Shop again',
                                                      ),
                                                    ),
                                                  PopupMenuItem(
                                                    value: 'pin',
                                                    child: Text(
                                                      pinned
                                                          ? 'Unpin'
                                                          : 'Pin to top',
                                                    ),
                                                  ),
                                                  if (list.isOwner)
                                                    const PopupMenuItem(
                                                      value: 'edit',
                                                      child: Text('Edit'),
                                                    ),
                                                  const PopupMenuItem(
                                                    value: 'duplicate',
                                                    child: Text('Duplicate'),
                                                  ),
                                                  if (list.isOwner)
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('Delete'),
                                                    ),
                                                ];
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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

class _MyListsSpendTeaser extends StatelessWidget {
  const _MyListsSpendTeaser({
    required this.remainingItems,
    required this.incompleteListCount,
    required this.onTapReceipts,
    this.leftEst,
    this.lastReceipt,
    this.insights,
    this.onStartTrip,
  });

  final int remainingItems;
  final int incompleteListCount;
  final RemainingSpendEstimate? leftEst;
  final LoggedReceipt? lastReceipt;
  final ReceiptSpendInsights? insights;
  final VoidCallback onTapReceipts;
  final VoidCallback? onStartTrip;

  @override
  Widget build(BuildContext context) {
    final headlineParts = <String>[];
    if (remainingItems > 0) {
      headlineParts.add(
        incompleteListCount <= 1
            ? '$remainingItems left to shop'
            : '$remainingItems left · $incompleteListCount lists',
      );
    }
    if (leftEst != null && leftEst!.hasEstimate) {
      headlineParts.add(leftEst!.summaryLine);
    }
    if (headlineParts.isEmpty && lastReceipt != null) {
      headlineParts.add('Last till ${lastReceipt!.formattedTotal}');
    }

    final detailParts = <String>[];
    if (lastReceipt != null) {
      final store = lastReceipt!.storeName.trim();
      final when = formatRelativeTime(lastReceipt!.createdAt);
      detailParts.add(
        [
          if (store.isNotEmpty) store,
          'till ${lastReceipt!.formattedTotal}',
          if (when.isNotEmpty) when,
        ].join(' · '),
      );
    }
    if (insights != null &&
        !insights!.isEmpty &&
        insights!.receiptCount > 1) {
      detailParts.add(insights!.compactLine);
    }

    return Material(
      color: ShoppaColors.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTapReceipts,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ShoppaColors.amber.withOpacity(0.35),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ShoppaColors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  color: ShoppaColors.amber,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headlineParts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ShoppaColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detailParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detailParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ShoppaColors.mist,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onStartTrip != null)
                IconButton(
                  tooltip: 'Start shopping',
                  icon: const Icon(
                    Icons.shopping_bag_outlined,
                    color: ShoppaColors.amber,
                  ),
                  onPressed: onStartTrip,
                )
              else
                const Icon(Icons.chevron_right, color: ShoppaColors.mist),
            ],
          ),
        ),
      ),
    );
  }
}
