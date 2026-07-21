import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/aisle_overrides_store.dart';
import '../core/aisle_sort.dart';
import '../core/bulk_item_parse.dart';
import '../core/last_paid_prices_store.dart';
import '../core/list_shop_helpers.dart';
import '../core/lists_repository.dart';
import '../core/multi_list_trip.dart';
import '../core/receipt_capture.dart';
import '../core/receipt_history_store.dart';
import '../core/recent_items_store.dart';
import '../core/shop_prefs_store.dart';
import '../core/shopping_session_store.dart';
import '../theme/shoppa_theme.dart';
import '../widgets/receipt_capture_sheet.dart';
import '../widgets/receipt_history_sheet.dart';
import '../widgets/shopping_at_store_sheet.dart';

/// Combined shop session across multiple lists (remaining items only).
class MultiListTripScreen extends StatefulWidget {
  const MultiListTripScreen({
    super.key,
    required this.listsRepository,
    required this.listIds,
  });

  final ListsRepository listsRepository;
  final List<String> listIds;

  @override
  State<MultiListTripScreen> createState() => _MultiListTripScreenState();
}

class _MultiListTripScreenState extends State<MultiListTripScreen> {
  final ShopPrefsStore _shopPrefs = SharedPreferencesShopPrefsStore();
  final ReceiptHistoryStore _receiptHistory =
      SharedPreferencesReceiptHistoryStore();
  final LastPaidPricesStore _lastPaidPrices =
      SharedPreferencesLastPaidPricesStore();
  final RecentItemsStore _recentItems = SharedPreferencesRecentItemsStore();
  final ShoppingSessionStore _sessionStore =
      SharedPreferencesShoppingSessionStore();
  final AisleOverridesStore _aisleOverridesStore =
      SharedPreferencesAisleOverridesStore();
  Map<String, int> _lastPaidSnapshot = const {};
  /// Device-local item name → aisle id overrides for walk grouping.
  Map<String, String> _aisleOverrides = const {};
  late Future<List<ShoppaList>> _load;
  List<TripLine> _lines = const [];
  List<ShoppaList> _sourceLists = const [];
  List<String> _listTitles = const [];
  bool _skipPricePrompt = false;
  /// Bigger checks + less chrome while walking the store.
  bool _focusShop = false;
  bool _hideChecked = false;
  bool _duplicatesOnly = false;
  /// Aisle group ids the shopper collapsed (tap header to toggle).
  final Set<String> _collapsedAisleIds = {};
  /// Aisles the shopper skipped (still have open items) — for restore / recap.
  final Set<String> _skippedAisleIds = {};
  /// Sticky header keys so we can scroll an aisle into view.
  final Map<String, GlobalKey> _aisleHeaderKeys = {};
  /// When set, only show items from this source list.
  String? _filterListId;
  bool _keepScreenOn = true;
  bool _busy = false;
  bool _quickAddBusy = false;
  String? _aisleLayoutId;
  /// Explicit “shopping at” for this trip (not from receipt alone).
  String? _tripStoreName;
  String? _addToListId;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quickAddController = TextEditingController();
  final FocusNode _quickAddFocus = FocusNode();
  List<String> _recentNames = const [];
  String? _error;
  LoggedReceipt? _latestReceipt;

  String get _tripScopeId => LoggedReceipt.tripScopeId(widget.listIds);

  @override
  void initState() {
    super.initState();
    _load = _fetchLists();
    _loadShopPrefs();
    _loadAisleOverrides();
    _loadLatestReceipt();
    _loadTripStore();
    _loadLastPaidSnapshot();
    _loadRecentNames();
  }

  AisleGroup _aisleOf(ShoppaListItem item) =>
      aisleForItem(item, aisleOverrides: _aisleOverrides);

  GlobalKey _headerKeyForAisle(String aisleId) =>
      _aisleHeaderKeys.putIfAbsent(aisleId, GlobalKey.new);

  void _scrollToAisle(String? aisleId) {
    final id = aisleId?.trim() ?? '';
    if (id.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _aisleHeaderKeys[id]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        alignment: 0.06,
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _loadAisleOverrides() async {
    final snap = await _aisleOverridesStore.snapshot();
    if (!mounted) return;
    setState(() => _aisleOverrides = snap);
  }

  /// Store name used for aisle auto-detect and receipt prefill.
  String? get _effectiveStoreName {
    final trip = _tripStoreName?.trim();
    if (trip != null && trip.isNotEmpty) return trip;
    final receipt = _latestReceipt?.storeName.trim();
    if (receipt != null && receipt.isNotEmpty) return receipt;
    return null;
  }

  Future<void> _loadTripStore() async {
    final saved = await _sessionStore.getShoppingAt(_tripScopeId);
    if (!mounted) return;
    final scopeName = saved?.storeName.trim();
    if (scopeName != null && scopeName.isNotEmpty) {
      setState(() => _tripStoreName = scopeName);
      return;
    }
    // Soft default: last store used anywhere, else most frequent from receipts.
    final last = await _sessionStore.getLastStore();
    final recent = await _receiptHistory.recent(limit: 40);
    if (!mounted) return;
    final fallback = resolveDefaultStoreName(
      lastStoreName: last?.storeName,
      frequentStores: frequentStoreNames(recent),
    );
    if (fallback == null) return;
    await _setTripStore(fallback);
  }

  Future<void> _setTripStore(String? name) async {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      setState(() => _tripStoreName = null);
      await _sessionStore.clearShoppingAt(_tripScopeId);
      return;
    }
    setState(() => _tripStoreName = trimmed);
    await _sessionStore.setShoppingAt(
      _tripScopeId,
      ShoppingAtStore(
        storeId: tripStoreSessionId(trimmed),
        storeName: trimmed,
      ),
    );
  }

  Future<void> _pickTripStore() async {
    final recentReceipts = await _receiptHistory.recent(limit: 40);
    if (!mounted) return;
    final picked = await showShoppingAtStoreSheet(
      context,
      currentStoreName: _tripStoreName,
      suggestedStores: frequentStoreNames(recentReceipts),
    );
    if (picked == null || !mounted) return;
    if (picked.isEmpty) {
      await _setTripStore(null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Store cleared'),
          backgroundColor: ShoppaColors.panel2,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await _setTripStore(picked);
    if (!mounted) return;
    final layout = resolveStoreAisleLayout(
      storeName: picked,
      layoutId: _aisleLayoutId,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _aisleLayoutId == null
              ? 'Shopping at $picked · walk: ${layout.label}'
              : 'Shopping at $picked',
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadRecentNames() async {
    final names = await _recentItems.getRecent(limit: 10);
    if (!mounted) return;
    setState(() => _recentNames = names);
  }

  Future<void> _loadLastPaidSnapshot() async {
    final snap = await _lastPaidPrices.snapshot();
    if (!mounted) return;
    setState(() => _lastPaidSnapshot = snap);
  }

  Future<void> _rememberPaidPrice(String name, int cents) async {
    if (cents <= 0) return;
    await _lastPaidPrices.record(name, cents);
    await _loadLastPaidSnapshot();
  }

  Future<void> _loadLatestReceipt() async {
    final latest = await _receiptHistory.latestForScope(_tripScopeId);
    if (!mounted) return;
    setState(() => _latestReceipt = latest);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    unawaited(_releaseKeepAwake());
    super.dispose();
  }

  Future<void> _loadShopPrefs() async {
    final skip = await _shopPrefs.getSkipPricePrompt();
    final focus = await _shopPrefs.getFocusShopMode();
    final keepOn = await _shopPrefs.getKeepScreenOn();
    final layoutId = await _shopPrefs.getAisleLayoutId();
    if (!mounted) return;
    setState(() {
      _skipPricePrompt = skip;
      _focusShop = focus;
      _keepScreenOn = keepOn;
      _aisleLayoutId = layoutId;
      if (focus) {
        _hideChecked = true;
        _searchQuery = '';
        _searchController.clear();
      }
    });
    await _syncKeepAwake();
  }

  Future<void> _toggleFocusShop() async {
    final next = !_focusShop;
    setState(() {
      _focusShop = next;
      if (next) {
        _hideChecked = true;
        _searchQuery = '';
        _searchController.clear();
        _duplicatesOnly = false;
      }
    });
    await _shopPrefs.setFocusShopMode(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Focus mode — bigger checks, remaining items only'
              : 'Focus mode off',
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleKeepScreenOn() async {
    final next = !_keepScreenOn;
    setState(() => _keepScreenOn = next);
    await _shopPrefs.setKeepScreenOn(next);
    await _syncKeepAwake();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Screen stays on during this trip'
              : 'Screen can sleep during this trip',
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  StoreAisleLayout get _activeAisleLayout => resolveStoreAisleLayout(
        storeName: _effectiveStoreName,
        layoutId: _aisleLayoutId,
      );

  Future<void> _pickAisleLayout() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Aisle walk order'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'auto'),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto from store'),
                subtitle: Text(
                  _effectiveStoreName == null
                      ? storeAisleLayoutForName(null).label
                      : '${storeAisleLayoutForName(_effectiveStoreName).label}'
                          ' · $_effectiveStoreName',
                ),
                trailing: _aisleLayoutId == null
                    ? const Icon(Icons.check, color: ShoppaColors.green)
                    : null,
              ),
            ),
            for (final layout in storeAisleLayouts)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, layout.id),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(layout.label),
                  trailing: _aisleLayoutId == layout.id
                      ? const Icon(Icons.check, color: ShoppaColors.green)
                      : null,
                ),
              ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;
    final id = selected == 'auto' ? null : selected;
    setState(() => _aisleLayoutId = id);
    await _shopPrefs.setAisleLayoutId(id);
    if (!mounted) return;
    final layout = resolveStoreAisleLayout(
      storeName: _effectiveStoreName,
      layoutId: id,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? 'Aisle order: auto (${layout.label})'
              : 'Aisle order: ${layout.label}',
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _syncKeepAwake() async {
    try {
      if (_keepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  Future<void> _releaseKeepAwake() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  Future<List<ShoppaList>> _fetchLists() async {
    if (widget.listIds.isEmpty) {
      throw StateError('No lists selected for this trip');
    }
    final results = await Future.wait(
      widget.listIds.map(widget.listsRepository.fetchListDetail),
    );
    final lines = buildTripLines(results, includeChecked: false);
    if (mounted) {
      setState(() {
        _sourceLists = results;
        _lines = lines;
        _listTitles = results.map((l) => l.title).toList();
        // Keep preferred add target when still valid.
        final target = resolveTripAddTarget(
          results,
          preferredListId: _addToListId,
        );
        _addToListId = target?.id;
        _error = null;
      });
    }
    return results;
  }

  ShoppaList? get _addTarget => resolveTripAddTarget(
        _sourceLists,
        preferredListId: _addToListId,
      );

  List<ShoppaList> get _editableLists => tripEditableLists(_sourceLists);

  Future<void> _pickAddTargetList() async {
    final editable = _editableLists;
    if (editable.length <= 1) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ShoppaColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Add items to',
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final list in editable)
              ListTile(
                title: Text(
                  list.title,
                  style: const TextStyle(color: ShoppaColors.ink),
                ),
                trailing: list.id == _addTarget?.id
                    ? const Icon(Icons.check, color: ShoppaColors.green)
                    : null,
                onTap: () => Navigator.pop(ctx, list.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _addToListId = selected);
  }

  Future<void> _quickAddSubmit([String? forcedName]) async {
    if (_quickAddBusy || _busy) return;
    final target = _addTarget;
    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No list you can edit on this trip'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
      return;
    }
    final text = (forcedName ?? _quickAddController.text).trim();
    if (text.isEmpty) return;
    final parsed = parseBulkItemLines(text);
    if (parsed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not parse that item')),
      );
      return;
    }
    setState(() {
      _quickAddBusy = true;
      _busy = true;
    });
    try {
      var createdCount = 0;
      var mergedCount = 0;
      String? singleName;
      num? singleQty;
      var singleUnit = 'ea';
      var nextLines = List<TripLine>.from(_lines);

      for (final line in parsed) {
        final pool = tripItemsForList(nextLines, target.id);
        final existing = findMatchingListItem(
          pool,
          name: line.name,
          unit: line.unit,
        );
        if (existing != null) {
          final nextQty = existing.quantity + line.quantity;
          final updated = await widget.listsRepository.updateItem(
            target.id,
            existing.id,
            quantity: nextQty,
            clientUpdatedAt: DateTime.now().toUtc(),
          );
          final key = '${target.id}:${existing.id}';
          nextLines = nextLines
              .map((l) => l.key == key ? l.copyWithItem(updated) : l)
              .toList();
          mergedCount++;
          singleName = updated.name;
          singleQty = updated.quantity;
          singleUnit = updated.unit;
        } else {
          final created = await widget.listsRepository.addItem(
            target.id,
            name: line.name,
            quantity: line.quantity,
            unit: line.unit,
          );
          nextLines = [
            ...nextLines,
            TripLine(
              listId: target.id,
              listTitle: target.title,
              item: created,
            ),
          ];
          createdCount++;
          singleName = created.name;
          singleQty = created.quantity;
          singleUnit = created.unit;
        }
      }

      await _recentItems.recordMany(parsed.map((p) => p.name));
      await _loadRecentNames();
      if (!mounted) return;
      setState(() {
        _lines = nextLines;
        _quickAddController.clear();
        _quickAddBusy = false;
        _busy = false;
      });
      if (!mounted) return;
      final label = formatTripQuickAddResult(
        listTitle: target.title,
        createdCount: createdCount,
        mergedCount: mergedCount,
        singleName: singleName,
        singleQty: singleQty,
        singleUnit: singleUnit,
      );
      if (label.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(label),
            backgroundColor: ShoppaColors.panel2,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _quickAddFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quickAddBusy = false;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Widget _buildQuickAddBar() {
    final target = _addTarget;
    if (target == null) return const SizedBox.shrink();
    final multi = _editableLists.length > 1;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: ShoppaColors.panel,
      elevation: 8,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_focusShop && _recentNames.isNotEmpty) ...[
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recentNames.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        final name = _recentNames[i];
                        return ActionChip(
                          label: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: _quickAddBusy || _busy
                              ? null
                              : () => _quickAddSubmit(name),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (multi)
                      TextButton(
                        onPressed: _quickAddBusy ? null : _pickAddTargetList,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 40),
                          foregroundColor: ShoppaColors.amber,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 88),
                              child: Text(
                                target.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Icon(Icons.expand_more, size: 18),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          target.title,
                          style: const TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _quickAddController,
                        focusNode: _quickAddFocus,
                        enabled: !_quickAddBusy && !_busy,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          color: ShoppaColors.ink,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: multi
                              ? 'Add to ${target.title}…'
                              : 'Quick add item…',
                          hintStyle: const TextStyle(
                            color: ShoppaColors.faint,
                            fontSize: 13,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _quickAddSubmit(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Add item',
                      onPressed: _quickAddBusy || _busy
                          ? null
                          : () => _quickAddSubmit(),
                      icon: _quickAddBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle, color: ShoppaColors.amber),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _load = _fetchLists();
      _error = null;
    });
    try {
      await _load;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  int get _remaining => _lines.where((l) => !l.item.checked).length;
  int get _total => _lines.length;
  int get _checked => _total - _remaining;
  TripSpend get _spend => tripSpendFromLines(_lines);

  String _tripText({required TripTextMode mode}) {
    final receipt = _latestReceipt;
    return formatTripAsText(
      _lines,
      title: 'Today’s trip',
      listTitles: _listTitles,
      mode: mode,
      includePrices: true,
      groupByList: true,
      tillCents: receipt?.totalCents,
      basketCents: receipt != null
          ? (receipt.basketCents > 0
              ? receipt.basketCents
              : _spend.spentCents)
          : null,
    );
  }

  Future<void> _shareTripText({required TripTextMode mode}) async {
    final text = _tripText(mode: mode);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      await Share.share(
        text,
        subject: mode == TripTextMode.checked
            ? 'Trip recap'
            : (mode == TripTextMode.remaining
                ? 'Still to buy'
                : 'Today’s trip'),
        sharePositionOrigin: origin,
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Share unavailable — copied trip text'),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
    }
  }

  Future<void> _copyTripText({required TripTextMode mode}) async {
    final text = _tripText(mode: mode);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == TripTextMode.checked
              ? 'Trip recap copied'
              : (mode == TripTextMode.remaining
                  ? 'Remaining items copied'
                  : 'Trip list copied'),
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  Future<int?> _promptForPrice(ShoppaListItem item) async {
    final remembered = item.paidPrice == null
        ? await _lastPaidPrices.getCents(item.name)
        : null;
    final suggested = item.paidPrice ?? remembered;
    final usingRemembered =
        item.paidPrice == null && remembered != null;
    final controller = TextEditingController(
      text: suggested != null
          ? (suggested / 100).toStringAsFixed(2)
          : '',
    );
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Price for ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.paidPrice != null)
              const Text(
                'Last paid on this list',
                style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
              )
            else if (usingRemembered)
              const Text(
                'Last paid for this item (remembered)',
                style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
              ),
            if (item.paidPrice != null || usingRemembered)
              const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: 'R ',
                hintText: '0.00',
                labelText: 'Paid price (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () {
              final raw = controller.text.trim().replaceAll(',', '.');
              if (raw.isEmpty) {
                Navigator.pop(ctx, null);
                return;
              }
              final rands = double.tryParse(raw);
              if (rands == null || rands < 0) {
                Navigator.pop(ctx, null);
                return;
              }
              Navigator.pop(ctx, (rands * 100).round());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      await _rememberPaidPrice(item.name, result);
    }
    return result;
  }

  Future<void> _toggle(TripLine line) async {
    if (_busy) return;
    final checking = !line.item.checked;
    int? paidPrice;
    if (checking && !_skipPricePrompt) {
      paidPrice = await _promptForPrice(line.item);
      if (!mounted) return;
    }

    setState(() => _busy = true);
    try {
      final updated = await widget.listsRepository.setItemChecked(
        line.listId,
        line.item.id,
        checked: checking,
        paidPrice: paidPrice,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      final nextLines = _lines
          .map((l) => l.key == line.key ? l.copyWithItem(updated) : l)
          .toList();
      AisleGroup? nextAisle;
      if (checking) {
        final aisleId = _aisleOf(updated).id;
        final stillOpen = nextLines.any(
          (l) => !l.item.checked && _aisleOf(l.item).id == aisleId,
        );
        if (!stillOpen) {
          nextAisle = nextOpenAisleGroup(
            nextLines.map((l) => l.item).toList(),
            layout: _activeAisleLayout,
            afterAisleId: aisleId,
            aisleOverrides: _aisleOverrides,
          );
        }
      }
      setState(() {
        _lines = nextLines;
        if (checking) {
          final aisleId = _aisleOf(updated).id;
          final stillOpen = nextLines.any(
            (l) => !l.item.checked && _aisleOf(l.item).id == aisleId,
          );
          if (!stillOpen) {
            _collapsedAisleIds.add(aisleId);
            _skippedAisleIds.remove(aisleId);
            if (nextAisle != null) {
              _collapsedAisleIds.remove(nextAisle.id);
            }
          }
        }
        _busy = false;
      });
      if (checking && nextAisle != null) {
        _scrollToAisle(nextAisle.id);
      }
      if (checking && _lines.every((l) => l.item.checked)) {
        await _showTripComplete();
        return;
      }
      if (checking && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nextAisle == null
                  ? 'Checked off ${line.item.name}'
                  : 'Checked off ${line.item.name} · ${formatNextAisleHint(nextAisle)}',
            ),
            backgroundColor: ShoppaColors.panel2,
            action: SnackBarAction(
              label: 'Undo',
              textColor: ShoppaColors.amber,
              onPressed: () => _forceUncheck(line.key),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  /// Check off every open copy of this product across trip lists (one purchase).
  ///
  /// Paid price is applied only to [line] so basket spend is not double-counted.
  Future<void> _checkOffAllMatches(TripLine line) async {
    if (_busy || line.item.checked) return;
    final matches = matchingOpenTripLines(line, _lines);
    if (matches.length <= 1) {
      await _toggle(line);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Check off “${line.item.name}”?'),
        content: Text(
          'This item is on ${matches.length} lists. Check it off everywhere '
          '(price is recorded once on ${line.listTitle})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Check off ${matches.length}'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    int? paidPrice;
    if (!_skipPricePrompt) {
      paidPrice = await _promptForPrice(line.item);
      if (!mounted) return;
    }

    setState(() => _busy = true);
    final keys = matches.map((m) => m.key).toList();
    try {
      var next = List<TripLine>.from(_lines);
      for (final match in matches) {
        final isPrimary = match.key == line.key;
        final updated = await widget.listsRepository.setItemChecked(
          match.listId,
          match.item.id,
          checked: true,
          paidPrice: isPrimary ? paidPrice : null,
          clientUpdatedAt: DateTime.now().toUtc(),
        );
        next = next
            .map((l) => l.key == match.key ? l.copyWithItem(updated) : l)
            .toList();
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _lines = next;
        _busy = false;
      });
      if (_lines.every((l) => l.item.checked)) {
        await _showTripComplete();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Checked off ${line.item.name} on ${matches.length} lists',
          ),
          backgroundColor: ShoppaColors.panel2,
          action: SnackBarAction(
            label: 'Undo',
            textColor: ShoppaColors.amber,
            onPressed: () => _forceUncheckKeys(keys),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  /// Collapse current open aisle and expand the next — items stay unchecked.
  void _skipPastAisle({String? fromAisleId}) {
    if (_busy) return;
    final items = _lines.map((l) => l.item).toList();
    final result = skipPastOpenAisle(
      items: items,
      collapsedIds: _collapsedAisleIds,
      layout: _activeAisleLayout,
      fromAisleId: fromAisleId,
      aisleOverrides: _aisleOverrides,
    );
    if (result.skippedAisle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No open aisles to skip'),
          backgroundColor: ShoppaColors.panel2,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _collapsedAisleIds
        ..clear()
        ..addAll(result.collapsedIds);
      _skippedAisleIds.add(result.skippedAisle!.id);
    });
    HapticFeedback.selectionClick();
    _scrollToAisle(result.nextAisle?.id);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          formatAisleSkipMessage(
            skipped: result.skippedAisle,
            next: result.nextAisle,
          ),
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Re-expand aisles that were skipped and still have open items.
  void _restoreSkippedAisles() {
    final openIds = <String>{};
    for (final l in _lines) {
      if (l.item.checked) continue;
      openIds.add(_aisleOf(l.item).id);
    }
    final restore = _skippedAisleIds.where(openIds.contains).toSet();
    if (restore.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No skipped aisles left behind'),
          backgroundColor: ShoppaColors.panel2,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _collapsedAisleIds.removeAll(restore);
      // Keep skip history so recap still knows; user can expand again.
    });
    final first = nextOpenAisleGroup(
      _lines.map((l) => l.item).toList(),
      layout: _activeAisleLayout,
      aisleOverrides: _aisleOverrides,
    );
    _scrollToAisle(first?.id ?? restore.first);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restore.length == 1
              ? 'Restored 1 skipped aisle'
              : 'Restored ${restore.length} skipped aisles',
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _moveLineToAisle(TripLine line) async {
    final current = _aisleOf(line.item);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Aisle for “${line.item.name}”'),
        children: [
          for (final g in aislePickerGroups())
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.id),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(g.label),
                trailing: g.id == current.id
                    ? const Icon(Icons.check, color: ShoppaColors.green)
                    : null,
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Reset to auto'),
              subtitle: Text('Use name-based guess'),
            ),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.isEmpty) {
      await _aisleOverridesStore.clearOverride(line.item.name);
    } else {
      await _aisleOverridesStore.setOverride(line.item.name, picked);
    }
    final snap = await _aisleOverridesStore.snapshot();
    if (!mounted) return;
    setState(() => _aisleOverrides = snap);
    final aisle = _aisleOf(line.item);
    _collapsedAisleIds.remove(aisle.id);
    _scrollToAisle(aisle.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          picked.isEmpty
              ? 'Aisle reset for ${line.item.name}'
              : 'Moved ${line.item.name} to ${aisle.label}',
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _checkOffAisle(TripAisleSection section) async {
    if (_busy || section.aisle.id == 'checked') return;
    final open = openTripLinesInAisle(
      _lines,
      section.aisle.id,
      aisleOverrides: _aisleOverrides,
    );
    // Prefer visible section lines when filtered (search / list / overlaps).
    final fromSection = section.lines.where((l) => !l.item.checked).toList();
    final targets = fromSection.isNotEmpty ? fromSection : open;
    if (targets.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Done with ${section.aisle.label}?'),
        content: Text(
          '${formatAisleCheckOffMessage(aisleLabel: section.aisle.label, count: targets.length)} '
          'Prices are not recorded — set them later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              targets.length == 1
                  ? 'Check off 1'
                  : 'Check off ${targets.length}',
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final keys = targets.map((t) => t.key).toList();
    try {
      var next = List<TripLine>.from(_lines);
      for (final target in targets) {
        final updated = await widget.listsRepository.setItemChecked(
          target.listId,
          target.item.id,
          checked: true,
          clientUpdatedAt: DateTime.now().toUtc(),
        );
        next = next
            .map((l) => l.key == target.key ? l.copyWithItem(updated) : l)
            .toList();
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final nextAisle = nextOpenAisleGroup(
        next.map((l) => l.item).toList(),
        layout: _activeAisleLayout,
        afterAisleId: section.aisle.id,
        aisleOverrides: _aisleOverrides,
      );
      setState(() {
        _lines = next;
        _collapsedAisleIds.add(section.aisle.id);
        _skippedAisleIds.remove(section.aisle.id);
        if (nextAisle != null) {
          _collapsedAisleIds.remove(nextAisle.id);
        }
        _busy = false;
      });
      if (nextAisle != null) {
        _scrollToAisle(nextAisle.id);
      }
      if (_lines.every((l) => l.item.checked)) {
        await _showTripComplete();
        return;
      }
      if (!mounted) return;
      final base = targets.length == 1
          ? 'Checked off 1 in ${section.aisle.label}'
          : 'Checked off ${targets.length} in ${section.aisle.label}';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextAisle == null
                ? base
                : '$base · ${formatNextAisleHint(nextAisle)}',
          ),
          backgroundColor: ShoppaColors.panel2,
          action: SnackBarAction(
            label: 'Undo',
            textColor: ShoppaColors.amber,
            onPressed: () => _forceUncheckKeys(keys),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update aisle: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _forceUncheckKeys(List<String> lineKeys) async {
    if (_busy || lineKeys.isEmpty) return;
    setState(() => _busy = true);
    try {
      var next = List<TripLine>.from(_lines);
      for (final key in lineKeys) {
        TripLine? line;
        for (final l in next) {
          if (l.key == key) {
            line = l;
            break;
          }
        }
        if (line == null || !line.item.checked) continue;
        final updated = await widget.listsRepository.setItemChecked(
          line.listId,
          line.item.id,
          checked: false,
          clientUpdatedAt: DateTime.now().toUtc(),
        );
        next = next
            .map((l) => l.key == key ? l.copyWithItem(updated) : l)
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _lines = next;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not undo: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _nudgeQuantity(TripLine line, int direction) async {
    if (_busy) return;
    final next = adjustItemQuantity(line.item.quantity, direction);
    if (next == line.item.quantity) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.listsRepository.updateItem(
        line.listId,
        line.item.id,
        quantity: next,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      setState(() {
        _lines = _lines
            .map((l) => l.key == line.key ? l.copyWithItem(updated) : l)
            .toList();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update quantity: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _setPaidPrice(TripLine line) async {
    if (_busy) return;
    final paidPrice = await _promptForPrice(line.item);
    if (paidPrice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.listsRepository.setItemChecked(
        line.listId,
        line.item.id,
        checked: true,
        paidPrice: paidPrice,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      setState(() {
        _lines = _lines
            .map((l) => l.key == line.key ? l.copyWithItem(updated) : l)
            .toList();
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Price set: ${formatCents(paidPrice)} for ${line.item.name}',
          ),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not set price: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _editNote(TripLine line) async {
    if (_busy) return;
    final item = line.item;
    final controller = TextEditingController(text: item.note);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.note.isEmpty ? 'Add note' : 'Edit note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'e.g. brand, size, aisle tip',
            labelText: item.name,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (item.note.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Clear'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    if (result == item.note) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.listsRepository.updateItem(
        line.listId,
        item.id,
        note: result,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      setState(() {
        _lines = _lines
            .map((l) => l.key == line.key ? l.copyWithItem(updated) : l)
            .toList();
        _busy = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isEmpty
                ? 'Note cleared on ${item.name}'
                : 'Note saved on ${item.name}',
          ),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save note: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _toggleSkipPricePrompt() async {
    final next = !_skipPricePrompt;
    await _shopPrefs.setSkipPricePrompt(next);
    if (!mounted) return;
    setState(() => _skipPricePrompt = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Fast check-off on — prices won’t be asked'
              : 'Price prompt on when checking items',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  /// Undo check-off without re-prompting for price.
  Future<void> _forceUncheck(String lineKey) async {
    TripLine? line;
    for (final l in _lines) {
      if (l.key == lineKey) {
        line = l;
        break;
      }
    }
    if (line == null || !line.item.checked || _busy) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.listsRepository.setItemChecked(
        line.listId,
        line.item.id,
        checked: false,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      setState(() {
        _lines = _lines
            .map((l) => l.key == lineKey ? l.copyWithItem(updated) : l)
            .toList();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not undo: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _logReceipt() async {
    final items = _lines.map((l) => l.item).toList();
    final recentReceipts = await _receiptHistory.recent(limit: 40);
    final storeSuggestions = frequentStoreNames(recentReceipts);
    final capture = await showReceiptCaptureSheet(
      context,
      items: items,
      initialStoreName: _effectiveStoreName,
      suggestedStores: tripStoreSuggestions(frequent: storeSuggestions),
    );
    if (capture == null || !capture.hasTotal || !mounted) return;

    final suggestions = suggestPricesFromReceiptTotal(
      items: items,
      receiptTotalCents: capture.totalCents!,
    );
    var applied = 0;
    if (suggestions.isNotEmpty) {
      final apply = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Apply receipt total?'),
          content: Text(
            'Fill ${suggestions.length} missing prices from '
            '${capture.formattedTotal} (split by quantity)?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Total only'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fill prices'),
            ),
          ],
        ),
      );
      if (apply == true) {
        final byId = {for (final s in suggestions) s.itemId: s.cents};
        for (final line in List<TripLine>.from(_lines)) {
          final cents = byId[line.item.id];
          if (cents == null || line.item.paidPrice != null) continue;
          try {
            final updated = await widget.listsRepository.setItemChecked(
              line.listId,
              line.item.id,
              checked: true,
              paidPrice: cents,
              clientUpdatedAt: DateTime.now().toUtc(),
            );
            if (cents > 0) {
              await _rememberPaidPrice(line.item.name, cents);
            }
            applied++;
            if (!mounted) return;
            setState(() {
              _lines = _lines
                  .map((l) => l.key == line.key ? l.copyWithItem(updated) : l)
                  .toList();
            });
          } catch (_) {}
        }
      }
    }
    final basketCents = tripSpend(
      _lines.map((l) => l.item).toList(),
    ).spentCents;
    final logged = loggedReceiptFromCapture(
      capture: capture,
      scopeId: _tripScopeId,
      pricesFilled: applied,
      listTitles: _listTitles,
      basketCents: basketCents,
    );
    await _receiptHistory.add(logged);
    // Also attach a copy under each source list for per-list history.
    for (final listId in widget.listIds) {
      await _receiptHistory.add(
        loggedReceiptFromCapture(
          capture: capture,
          scopeId: listId,
          pricesFilled: applied,
          listTitles: _listTitles,
          basketCents: basketCents,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _latestReceipt = logged);
    // Seed trip store from the receipt when the shopper has not set one yet.
    final receiptStore = capture.storeName.trim();
    if (receiptStore.isNotEmpty &&
        (_tripStoreName == null || _tripStoreName!.trim().isEmpty)) {
      await _setTripStore(receiptStore);
    }
    final vs = logged.tillVsBasket;
    final deltaHint =
        vs != null && vs.hasComparison ? ' · ${vs.variancePhrase}' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          applied > 0
              ? 'Receipt ${capture.formattedTotal} — filled $applied prices$deltaHint'
              : 'Receipt logged: ${capture.formattedTotal}$deltaHint',
        ),
        backgroundColor: ShoppaColors.panel2,
        action: SnackBarAction(
          label: 'History',
          textColor: ShoppaColors.amber,
          onPressed: () {
            showReceiptHistorySheet(
              context,
              store: _receiptHistory,
              scopeId: _tripScopeId,
              title: 'Trip receipt history',
            );
          },
        ),
      ),
    );
  }

  Future<void> _showTripComplete() async {
    if (!mounted) return;
    final spend = _spend;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trip complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All $_total items from ${_listTitles.length} list'
              '${_listTitles.length == 1 ? '' : 's'} are checked off.',
            ),
            if (spend.hasSpend) ...[
              const SizedBox(height: 12),
              Text(
                spend.hasIncompletePricing
                    ? 'Spent ${spend.formatted} · ${spend.pricedCount}/${spend.checkedCount} priced'
                    : 'Spent ${spend.formatted}',
                style: const TextStyle(
                  color: ShoppaColors.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_latestReceipt != null) ...[
              const SizedBox(height: 8),
              Text(
                TillVsBasket(
                  tillCents: _latestReceipt!.totalCents,
                  basketCents: spend.spentCents > 0
                      ? spend.spentCents
                      : _latestReceipt!.basketCents,
                ).shareLine,
                style: const TextStyle(
                  color: ShoppaColors.mist,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_listTitles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _listTitles.join(' · '),
                style: const TextStyle(
                  color: ShoppaColors.mist,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'receipt'),
            child: const Text('Log receipt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'share'),
            child: const Text('Share recap'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'copy'),
            child: const Text('Copy recap'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'done'),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'receipt') {
      await _logReceipt();
    } else if (action == 'share') {
      await _shareTripText(mode: TripTextMode.checked);
    } else if (action == 'copy') {
      await _copyTripText(mode: TripTextMode.checked);
    } else if (action == 'done') {
      Navigator.pop(context);
    }
  }

  /// End trip early with left-behind list + restore skipped aisles.
  Future<void> _showEndTripRecap() async {
    if (!mounted) return;
    final left = leftBehindTripLines(_lines);
    final spend = _spend;
    final openAisleIds = <String>{
      for (final l in left) _aisleOf(l.item).id,
    };
    final skippedStillOpen =
        _skippedAisleIds.where(openAisleIds.contains).toList();
    final preview = left.take(8).toList();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          left.isEmpty ? 'Trip recap' : 'End trip?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_checked of $_total checked · ${formatLeftBehindCount(left.length)}',
              ),
              if (spend.hasSpend) ...[
                const SizedBox(height: 8),
                Text(
                  spend.hasIncompletePricing
                      ? 'Spent ${spend.formatted} · ${spend.pricedCount}/${spend.checkedCount} priced'
                      : 'Spent ${spend.formatted}',
                  style: const TextStyle(
                    color: ShoppaColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (left.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  skippedStillOpen.isEmpty
                      ? 'Left behind'
                      : 'Left behind · ${skippedStillOpen.length} skipped aisle'
                          '${skippedStillOpen.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: ShoppaColors.mist,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final line in preview)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· ${line.item.name} (${_aisleOf(line.item).label})',
                      style: const TextStyle(
                        color: ShoppaColors.ink,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (left.length > preview.length)
                  Text(
                    '…and ${left.length - preview.length} more',
                    style: const TextStyle(
                      color: ShoppaColors.mist,
                      fontSize: 12,
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          if (skippedStillOpen.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'restore'),
              child: const Text('Restore skipped'),
            ),
          if (left.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'expand'),
              child: const Text('Show left behind'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Keep shopping'),
          ),
          if (left.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'share_left'),
              child: const Text('Share left'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'leave'),
            child: Text(left.isEmpty ? 'Done' : 'Leave for later'),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'stay') return;
    if (action == 'restore') {
      _restoreSkippedAisles();
      return;
    }
    if (action == 'expand') {
      setState(() {
        _collapsedAisleIds.removeAll(openAisleIds);
      });
      final first = nextOpenAisleGroup(
        _lines.map((l) => l.item).toList(),
        layout: _activeAisleLayout,
        aisleOverrides: _aisleOverrides,
      );
      _scrollToAisle(first?.id);
      return;
    }
    if (action == 'share_left') {
      await _shareTripText(mode: TripTextMode.remaining);
      return;
    }
    if (action == 'leave') {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleBits = _listTitles.isEmpty
        ? 'Today’s trip'
        : (_listTitles.length <= 2
            ? _listTitles.join(' · ')
            : '${_listTitles.first} +${_listTitles.length - 1}');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _remaining == 0 && _total > 0
              ? 'Trip complete'
              : 'Trip · $titleBits',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_lines.isNotEmpty)
            IconButton(
              tooltip: _focusShop ? 'Exit focus mode' : 'Focus mode',
              icon: Icon(
                _focusShop
                    ? Icons.center_focus_strong
                    : Icons.center_focus_weak_outlined,
                color: _focusShop ? ShoppaColors.amber : null,
              ),
              onPressed: _toggleFocusShop,
            ),
          if (_checked > 0 && !_focusShop)
            IconButton(
              tooltip: _hideChecked ? 'Show checked' : 'Hide checked',
              icon: Icon(
                _hideChecked
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _hideChecked = !_hideChecked),
            ),
          if (_lines.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Trip options',
              onSelected: (value) async {
                if (value == 'share_recap') {
                  await _shareTripText(mode: TripTextMode.checked);
                } else if (value == 'share_left') {
                  await _shareTripText(mode: TripTextMode.remaining);
                } else if (value == 'share_all') {
                  await _shareTripText(mode: TripTextMode.all);
                } else if (value == 'copy_recap') {
                  await _copyTripText(mode: TripTextMode.checked);
                } else if (value == 'copy_left') {
                  await _copyTripText(mode: TripTextMode.remaining);
                } else if (value == 'log_receipt') {
                  await _logReceipt();
                } else if (value == 'skip_price') {
                  await _toggleSkipPricePrompt();
                } else if (value == 'focus_shop') {
                  await _toggleFocusShop();
                } else if (value == 'keep_screen') {
                  await _toggleKeepScreenOn();
                } else if (value == 'hide_checked') {
                  setState(() => _hideChecked = !_hideChecked);
                } else if (value == 'duplicates_only') {
                  setState(() => _duplicatesOnly = !_duplicatesOnly);
                } else if (value == 'collapse_aisles') {
                  setState(() {
                    final open = _hideChecked
                        ? _lines.where((l) => !l.item.checked).toList()
                        : _lines;
                    final afterDups = filterCrossListDuplicates(
                      open,
                      enabled: _duplicatesOnly,
                    );
                    for (final s in tripAisleSections(
                      afterDups,
                      separateChecked: !_hideChecked && !_duplicatesOnly,
                      includeChecked: !_hideChecked && !_duplicatesOnly,
                      layout: _activeAisleLayout,
                      aisleOverrides: _aisleOverrides,
                    )) {
                      _collapsedAisleIds.add(s.aisle.id);
                    }
                  });
                } else if (value == 'expand_aisles') {
                  setState(() => _collapsedAisleIds.clear());
                } else if (value == 'aisle_layout') {
                  await _pickAisleLayout();
                } else if (value == 'set_store') {
                  await _pickTripStore();
                } else if (value == 'skip_aisle') {
                  _skipPastAisle();
                } else if (value == 'restore_skipped') {
                  _restoreSkippedAisles();
                } else if (value == 'end_trip') {
                  await _showEndTripRecap();
                }
              },
              itemBuilder: (ctx) => [
                if (_checked > 0) ...[
                  const PopupMenuItem(
                    value: 'share_recap',
                    child: Text('Share trip recap'),
                  ),
                  const PopupMenuItem(
                    value: 'copy_recap',
                    child: Text('Copy trip recap'),
                  ),
                ],
                if (_remaining > 0) ...[
                  const PopupMenuItem(
                    value: 'share_left',
                    child: Text('Share remaining'),
                  ),
                  const PopupMenuItem(
                    value: 'copy_left',
                    child: Text('Copy remaining'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'share_all',
                  child: Text('Share full trip'),
                ),
                PopupMenuItem(
                  value: 'aisle_layout',
                  child: Text(
                    'Aisle walk: ${_activeAisleLayout.label}',
                  ),
                ),
                PopupMenuItem(
                  value: 'set_store',
                  child: Text(
                    _tripStoreName != null && _tripStoreName!.trim().isNotEmpty
                        ? 'Change store ($_tripStoreName)'
                        : 'Set store',
                  ),
                ),
                if (!_focusShop)
                  PopupMenuItem(
                    value: 'hide_checked',
                    child: Text(
                      _hideChecked
                          ? 'Show checked items'
                          : 'Hide checked items',
                    ),
                  ),
                if (!_focusShop)
                  PopupMenuItem(
                    value: 'duplicates_only',
                    child: Text(
                      _duplicatesOnly
                          ? 'Show all items'
                          : 'Show overlaps only',
                    ),
                  ),
                if (_collapsedAisleIds.isNotEmpty)
                  const PopupMenuItem(
                    value: 'expand_aisles',
                    child: Text('Expand all aisles'),
                  )
                else
                  const PopupMenuItem(
                    value: 'collapse_aisles',
                    child: Text('Collapse all aisles'),
                  ),
                if (_remaining > 0)
                  const PopupMenuItem(
                    value: 'skip_aisle',
                    child: Text('Skip to next aisle'),
                  ),
                if (_remaining > 0 && _skippedAisleIds.isNotEmpty)
                  const PopupMenuItem(
                    value: 'restore_skipped',
                    child: Text('Restore skipped aisles'),
                  ),
                if (_total > 0)
                  PopupMenuItem(
                    value: 'end_trip',
                    child: Text(
                      _remaining > 0 ? 'End trip / left behind' : 'Trip recap',
                    ),
                  ),
                PopupMenuItem(
                  value: 'focus_shop',
                  child: Text(
                    _focusShop
                        ? 'Exit focus mode'
                        : 'Focus mode (bigger checks)',
                  ),
                ),
                PopupMenuItem(
                  value: 'keep_screen',
                  child: Text(
                    _keepScreenOn
                        ? 'Allow screen to sleep'
                        : 'Keep screen on',
                  ),
                ),
                PopupMenuItem(
                  value: 'skip_price',
                  child: Text(
                    _skipPricePrompt
                        ? 'Ask for prices on check-off'
                        : 'Fast check-off (skip prices)',
                  ),
                ),
                const PopupMenuItem(
                  value: 'log_receipt',
                  child: Text('Log receipt / till total'),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          if (!_focusShop) ...[
            IconButton(
              tooltip: 'Log receipt',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: _busy ? null : _logReceipt,
            ),
            IconButton(
              tooltip: 'Receipt history',
              icon: const Icon(Icons.history),
              onPressed: () => showReceiptHistorySheet(
                context,
                store: _receiptHistory,
                scopeId: _tripScopeId,
                title: 'Trip receipt history',
              ),
            ),
          ],
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<ShoppaList>>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              _lines.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && _lines.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load trip: ${snapshot.error}',
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

          // Focus mode always walks remaining items only.
          final afterHide = (_hideChecked || _focusShop)
              ? _lines.where((l) => !l.item.checked).toList()
              : _lines;
          // Duplicates are computed on the full open trip (not search-filtered)
          // so filtering still shows “also on …” for remaining matches.
          final crossListIndex = indexCrossListDuplicates(_lines);
          final crossListGroups = crossListDuplicateGroupCount(crossListIndex);
          // Auto-clear duplicates filter when nothing left to show.
          if (_duplicatesOnly && crossListGroups == 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _duplicatesOnly) {
                setState(() => _duplicatesOnly = false);
              }
            });
          }
          final afterDups = filterCrossListDuplicates(
            afterHide,
            enabled: _duplicatesOnly,
            index: crossListIndex,
          );
          // Drop list filter if that list left the trip.
          if (_filterListId != null &&
              !_sourceLists.any((s) => s.id == _filterListId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _filterListId != null) {
                setState(() => _filterListId = null);
              }
            });
          }
          final afterListFilter = filterTripLinesByListId(
            afterDups,
            _filterListId,
          );
          final viewLines = filterTripLines(afterListFilter, _searchQuery);
          final searchActive = _searchQuery.trim().isNotEmpty;
          final listFilterOptions = tripListFilterOptions(
            _lines,
            sourceLists: _sourceLists,
          );
          final listFilterActive = _filterListId != null;
          final aisleLayout = _activeAisleLayout;
          final sections = tripAisleSections(
            viewLines,
            separateChecked:
                !_hideChecked && !_duplicatesOnly && !_focusShop,
            includeChecked:
                !_hideChecked && !_duplicatesOnly && !_focusShop,
            layout: aisleLayout,
            aisleOverrides: _aisleOverrides,
          );

          final spend = _spend;
          return Column(
            children: [
              Material(
                color: ShoppaColors.panel2.withOpacity(0.45),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _total == 0
                            ? 'Nothing left on these lists'
                            : '$_checked of $_total checked · $_remaining left',
                        style: const TextStyle(
                          color: ShoppaColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_total > 0) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (_checked / _total).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: ShoppaColors.line.withOpacity(0.7),
                            color: _remaining == 0
                                ? ShoppaColors.green
                                : ShoppaColors.amber,
                          ),
                        ),
                      ],
                      if (!_focusShop) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _pickTripStore,
                          child: Text(
                            _tripStoreName != null &&
                                    _tripStoreName!.trim().isNotEmpty
                                ? 'Store: $_tripStoreName'
                                : (_effectiveStoreName != null
                                    ? 'Store: $_effectiveStoreName (from receipt)'
                                    : 'Tap to set store'),
                            style: TextStyle(
                              color: _tripStoreName != null &&
                                      _tripStoreName!.trim().isNotEmpty
                                  ? ShoppaColors.green
                                  : ShoppaColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: _pickAisleLayout,
                          child: Text(
                            _aisleLayoutId == null
                                ? 'Walk order: ${aisleLayout.label} (auto)'
                                : 'Walk order: ${aisleLayout.label}',
                            style: const TextStyle(
                              color: ShoppaColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                        Text(
                          _remaining == 0
                              ? 'All done · swipe or tap to uncheck'
                              : '$_remaining left · swipe right to check',
                          style: const TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (spend.hasSpend) ...[
                        const SizedBox(height: 4),
                        Text(
                          spend.hasIncompletePricing
                              ? 'Spent ${spend.formatted} · ${spend.pricedCount}/${spend.checkedCount} priced'
                              : 'Spent ${spend.formatted}',
                          style: const TextStyle(
                            color: ShoppaColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      Builder(
                        builder: (context) {
                          final leftEst = estimateRemainingSpend(
                            _lines.map((l) => l.item).toList(),
                            rememberedByName: _lastPaidSnapshot,
                          );
                          final projected = formatProjectedTripTotal(
                            spentCents: spend.spentCents,
                            leftEstCents: leftEst.estimatedCents,
                          );
                          if (!leftEst.hasEstimate && projected == null) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              [
                                if (leftEst.hasEstimate) leftEst.summaryLine,
                                if (projected != null) projected,
                              ].join(' · '),
                              style: const TextStyle(
                                color: ShoppaColors.mist,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                      if (_latestReceipt != null) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            showReceiptHistorySheet(
                              context,
                              store: _receiptHistory,
                              scopeId: _tripScopeId,
                              title: 'Trip receipt history',
                            );
                          },
                          child: Builder(
                            builder: (context) {
                              final receipt = _latestReceipt!;
                              final liveBasket = spend.spentCents;
                              final cmp = TillVsBasket(
                                tillCents: receipt.totalCents,
                                basketCents: liveBasket > 0
                                    ? liveBasket
                                    : receipt.basketCents,
                              );
                              final store = receipt.storeName.isNotEmpty
                                  ? ' · ${receipt.storeName}'
                                  : '';
                              final line = cmp.hasComparison
                                  ? '${cmp.summaryLine}$store'
                                  : 'Till ${receipt.formattedTotal}$store';
                              final color = !cmp.hasComparison
                                  ? ShoppaColors.mist
                                  : (cmp.matches
                                      ? ShoppaColors.green
                                      : (cmp.over
                                          ? ShoppaColors.amber
                                          : ShoppaColors.mist));
                              return Text(
                                line,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      if (_listTitles.length > 1) ...[
                        const SizedBox(height: 4),
                        Text(
                          _listTitles.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (_total > 0) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _total == 0 ? 0 : _checked / _total,
                            minHeight: 6,
                            backgroundColor: ShoppaColors.line,
                            color: _remaining == 0
                                ? ShoppaColors.green
                                : ShoppaColors.amber,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Material(
                  color: ShoppaColors.rose.withOpacity(0.15),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: ShoppaColors.rose),
                    ),
                  ),
                ),
              if (_lines.isNotEmpty && !_focusShop)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      color: ShoppaColors.ink,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search items, notes, lists…',
                      hintStyle: const TextStyle(
                        color: ShoppaColors.faint,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 22,
                        color: ShoppaColors.mist,
                      ),
                      suffixIcon: searchActive
                          ? IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: ShoppaColors.panel2.withOpacity(0.55),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: ShoppaColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: ShoppaColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: ShoppaColors.amber,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              if (!_focusShop && listFilterOptions.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text('All ($_remaining)'),
                            selected: !listFilterActive,
                            onSelected: (_) => setState(() {
                              _filterListId = null;
                            }),
                            selectedColor: ShoppaColors.amber.withOpacity(0.28),
                            checkmarkColor: ShoppaColors.amber,
                            labelStyle: TextStyle(
                              color: !listFilterActive
                                  ? ShoppaColors.ink
                                  : ShoppaColors.mist,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            side: BorderSide(
                              color: !listFilterActive
                                  ? ShoppaColors.amber
                                  : ShoppaColors.line,
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        for (final opt in listFilterOptions)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(
                                opt.open > 0
                                    ? '${opt.title} (${opt.open})'
                                    : opt.title,
                              ),
                              selected: _filterListId == opt.id,
                              onSelected: (_) => setState(() {
                                if (_filterListId == opt.id) {
                                  _filterListId = null;
                                } else {
                                  _filterListId = opt.id;
                                  // Prefer quick-add into the focused list.
                                  _addToListId = opt.id;
                                }
                              }),
                              selectedColor:
                                  ShoppaColors.amber.withOpacity(0.28),
                              checkmarkColor: ShoppaColors.amber,
                              labelStyle: TextStyle(
                                color: _filterListId == opt.id
                                    ? ShoppaColors.ink
                                    : ShoppaColors.mist,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              side: BorderSide(
                                color: _filterListId == opt.id
                                    ? ShoppaColors.amber
                                    : ShoppaColors.line,
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (!_focusShop && (crossListGroups > 0 || _duplicatesOnly))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Material(
                    color: ShoppaColors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.copy_all_outlined,
                            size: 18,
                            color: ShoppaColors.amber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _duplicatesOnly
                                  ? (viewLines.isEmpty
                                      ? (searchActive
                                          ? 'No overlaps match “${_searchQuery.trim()}”'
                                          : 'No overlapping items left')
                                      : 'Showing overlaps only (${viewLines.length})')
                                  : (crossListGroups == 1
                                      ? '1 item appears on more than one list'
                                      : '$crossListGroups items appear on more than one list'),
                              style: const TextStyle(
                                color: ShoppaColors.ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(
                              () => _duplicatesOnly = !_duplicatesOnly,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: ShoppaColors.amber,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _duplicatesOnly ? 'Show all' : 'Overlaps only',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _lines.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(28),
                        children: const [
                          SizedBox(height: 48),
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 48,
                            color: ShoppaColors.faint,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No remaining items',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ShoppaColors.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Everything on the selected lists is already checked off.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ShoppaColors.mist,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      )
                    : viewLines.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(28),
                        children: [
                          const SizedBox(height: 48),
                          Icon(
                            searchActive
                                ? Icons.search_off
                                : (listFilterActive
                                    ? Icons.filter_list_off
                                    : (_duplicatesOnly
                                        ? Icons.copy_all_outlined
                                        : Icons.visibility_off_outlined)),
                            size: 48,
                            color: ShoppaColors.faint,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            searchActive
                                ? 'No items match “${_searchQuery.trim()}”'
                                : (listFilterActive
                                    ? 'Nothing left on this list'
                                    : (_duplicatesOnly
                                        ? 'No overlaps to show'
                                        : 'Nothing to show')),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: ShoppaColors.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            searchActive
                                ? 'Try another search or clear the filter.'
                                : (listFilterActive
                                    ? 'Everything on the selected list is checked off, or hidden by other filters.'
                                    : (_duplicatesOnly
                                        ? 'Shared items are checked off, or none appear on more than one list.'
                                        : (_hideChecked
                                            ? 'All visible items are checked. Turn off “Hide checked” to see them.'
                                            : 'Nothing left on these lists.'))),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: ShoppaColors.mist,
                              fontSize: 13,
                            ),
                          ),
                          if (searchActive) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: const Text('Clear search'),
                              ),
                            ),
                          ] else if (listFilterActive) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () => setState(
                                  () => _filterListId = null,
                                ),
                                child: const Text('Show all lists'),
                              ),
                            ),
                          ] else if (_duplicatesOnly) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () => setState(
                                  () => _duplicatesOnly = false,
                                ),
                                child: const Text('Show all items'),
                              ),
                            ),
                          ],
                        ],
                      )
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 8),
                            ),
                            for (final section in sections)
                              ..._tripAisleSlivers(
                                section: section,
                                searchActive: searchActive,
                                crossListIndex: crossListIndex,
                              ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 28),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _buildQuickAddBar(),
    );
  }

  /// Sticky aisle header + item rows for one walk-order section.
  List<Widget> _tripAisleSlivers({
    required TripAisleSection section,
    required bool searchActive,
    required Map<String, Map<String, String>> crossListIndex,
  }) {
    final aisleId = section.aisle.id;
    final collapsed =
        !searchActive && _collapsedAisleIds.contains(aisleId);
    final openInSection =
        section.lines.where((l) => !l.item.checked).length;
    return [
      // GlobalKey on the sliver enables Scrollable.ensureVisible after skip/done.
      SliverPersistentHeader(
        key: _headerKeyForAisle(aisleId),
        pinned: true,
        delegate: _TripAisleStickyHeaderDelegate(
          label: section.aisle.label,
          countLabel: collapsed
              ? '$openInSection left'
              : '${section.lines.length}',
          collapsed: collapsed,
          canCollapse: !searchActive,
          onToggle: searchActive
              ? null
              : () {
                  setState(() {
                    if (collapsed) {
                      _collapsedAisleIds.remove(aisleId);
                    } else {
                      _collapsedAisleIds.add(aisleId);
                    }
                  });
                },
          onCheckOffAisle: openInSection > 0 &&
                  aisleId != 'checked' &&
                  !_busy
              ? () => _checkOffAisle(section)
              : null,
          onSkipAisle: openInSection > 0 &&
                  aisleId != 'checked' &&
                  !_busy
              ? () => _skipPastAisle(fromAisleId: aisleId)
              : null,
        ),
      ),
      if (!collapsed)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final line = section.lines[index];
                final crossHint = formatCrossListDuplicateHint(
                  otherListsWithSameItem(line, crossListIndex),
                );
                return _TripLineTile(
                  line: line,
                  enabled: !_busy,
                  focusMode: _focusShop,
                  crossListHint: crossHint,
                  onTap: _busy ? null : () => _toggle(line),
                  onSwipeToggle: _busy ? null : () => _toggle(line),
                  onQtyNudge: _busy || _focusShop
                      ? null
                      : (dir) => _nudgeQuantity(line, dir),
                  onSetPrice: _busy ? null : () => _setPaidPrice(line),
                  onEditNote: _busy ? null : () => _editNote(line),
                  onMoveAisle: _busy || line.item.checked
                      ? null
                      : () => _moveLineToAisle(line),
                  onCheckOffAll: crossHint != null && !_busy
                      ? () => _checkOffAllMatches(line)
                      : null,
                );
              },
              childCount: section.lines.length,
            ),
          ),
        ),
    ];
  }
}

/// Pinned aisle label while scrolling the trip (stays under the app bar).
class _TripAisleStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TripAisleStickyHeaderDelegate({
    required this.label,
    required this.countLabel,
    required this.collapsed,
    required this.canCollapse,
    this.onToggle,
    this.onCheckOffAisle,
    this.onSkipAisle,
  });

  final String label;
  final String countLabel;
  final bool collapsed;
  final bool canCollapse;
  final VoidCallback? onToggle;
  /// Bulk check-off for remaining items in this aisle.
  final VoidCallback? onCheckOffAisle;
  /// Collapse this aisle and expand the next open one (no check-offs).
  final VoidCallback? onSkipAisle;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      elevation: overlapsContent ? 1.5 : 0,
      color: ShoppaColors.panel,
      child: InkWell(
        onTap: onToggle,
        onLongPress: onCheckOffAisle,
        child: Container(
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: overlapsContent
                    ? ShoppaColors.line
                    : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              if (canCollapse)
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                  color: ShoppaColors.mist,
                ),
              if (canCollapse) const SizedBox(width: 2),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: ShoppaColors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Text(
                countLabel,
                style: TextStyle(
                  color: ShoppaColors.mist.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onSkipAisle != null)
                IconButton(
                  tooltip: 'Skip aisle',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(
                    Icons.skip_next,
                    size: 18,
                    color: ShoppaColors.mist,
                  ),
                  onPressed: onSkipAisle,
                ),
              if (onCheckOffAisle != null)
                IconButton(
                  tooltip: 'Check off aisle',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(
                    Icons.done_all,
                    size: 18,
                    color: ShoppaColors.green,
                  ),
                  onPressed: onCheckOffAisle,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TripAisleStickyHeaderDelegate oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.countLabel != countLabel ||
        oldDelegate.collapsed != collapsed ||
        oldDelegate.canCollapse != canCollapse ||
        oldDelegate.onToggle != onToggle ||
        oldDelegate.onCheckOffAisle != onCheckOffAisle ||
        oldDelegate.onSkipAisle != onSkipAisle;
  }
}

class _TripLineTile extends StatelessWidget {
  const _TripLineTile({
    required this.line,
    this.onTap,
    this.onSwipeToggle,
    this.onQtyNudge,
    this.onSetPrice,
    this.onEditNote,
    this.onMoveAisle,
    this.onCheckOffAll,
    this.crossListHint,
    this.enabled = true,
    this.focusMode = false,
  });

  final TripLine line;
  final VoidCallback? onTap;
  final VoidCallback? onSwipeToggle;
  final void Function(int direction)? onQtyNudge;
  final VoidCallback? onSetPrice;
  final VoidCallback? onEditNote;
  final VoidCallback? onMoveAisle;
  /// Check off every open copy of this product across trip lists.
  final VoidCallback? onCheckOffAll;
  /// e.g. “Also on Party” when the same open item is on another trip list.
  final String? crossListHint;
  final bool enabled;
  final bool focusMode;

  @override
  Widget build(BuildContext context) {
    final item = line.item;
    final checked = item.checked;
    final qtyLabel = formatItemQuantity(item.quantity);
    final hasMenu = onSetPrice != null ||
        onEditNote != null ||
        onMoveAisle != null ||
        onCheckOffAll != null;
    final metaParts = <String>[
      line.listTitle,
      if (item.unit.isNotEmpty && item.unit != 'ea') item.unit,
      if (item.paidPrice != null) formatCents(item.paidPrice!),
    ];
    final hasCrossList = crossListHint != null && crossListHint!.isNotEmpty;
    final checkSize = focusMode ? 40.0 : 32.0;
    final nameSize = focusMode ? 18.0 : 16.0;
    final tile = Padding(
      padding: EdgeInsets.only(bottom: focusMode ? 12 : 10),
      child: Material(
        color: ShoppaColors.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onEditNote ?? onSetPrice,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              focusMode ? 12 : 10,
              focusMode ? 16 : 12,
              focusMode ? 10 : 8,
              focusMode ? 16 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasCrossList
                    ? ShoppaColors.amber.withOpacity(0.55)
                    : ShoppaColors.line,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  checked
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: checkSize,
                  color: checked ? ShoppaColors.green : ShoppaColors.faint,
                ),
                SizedBox(width: focusMode ? 14 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                color: ShoppaColors.ink,
                                fontSize: nameSize,
                                fontWeight: FontWeight.w600,
                                decoration: checked
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (hasCrossList)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.copy_all_outlined,
                                size: 16,
                                color: ShoppaColors.amber,
                              ),
                            ),
                        ],
                      ),
                      if (metaParts.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          metaParts.join(' · '),
                          style: TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: focusMode ? 13 : 12,
                          ),
                        ),
                      ],
                      if (hasCrossList) ...[
                        const SizedBox(height: 3),
                        GestureDetector(
                          onTap: onCheckOffAll,
                          child: Text(
                            onCheckOffAll != null
                                ? '$crossListHint · tap to check all'
                                : crossListHint!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ShoppaColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (item.note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ShoppaColors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onQtyNudge != null && !checked) ...[
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      color: ShoppaColors.mist,
                      icon: const Icon(Icons.remove),
                      onPressed: () => onQtyNudge!(-1),
                    ),
                  ),
                  Text(
                    qtyLabel,
                    style: const TextStyle(
                      color: ShoppaColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      color: ShoppaColors.mist,
                      icon: const Icon(Icons.add),
                      onPressed: () => onQtyNudge!(1),
                    ),
                  ),
                ],
                if (hasMenu)
                  PopupMenuButton<String>(
                    tooltip: 'Item options',
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.more_vert,
                      size: 20,
                      color: ShoppaColors.mist,
                    ),
                    onSelected: (value) {
                      if (value == 'note') onEditNote?.call();
                      if (value == 'price') onSetPrice?.call();
                      if (value == 'aisle') onMoveAisle?.call();
                      if (value == 'check_all') onCheckOffAll?.call();
                    },
                    itemBuilder: (ctx) => [
                      if (onCheckOffAll != null)
                        const PopupMenuItem(
                          value: 'check_all',
                          child: Text('Check off on all lists'),
                        ),
                      if (onMoveAisle != null)
                        const PopupMenuItem(
                          value: 'aisle',
                          child: Text('Move to aisle…'),
                        ),
                      if (onEditNote != null)
                        PopupMenuItem(
                          value: 'note',
                          child: Text(
                            item.note.isEmpty ? 'Add note' : 'Edit note',
                          ),
                        ),
                      if (onSetPrice != null)
                        PopupMenuItem(
                          value: 'price',
                          child: Text(
                            item.paidPrice != null
                                ? 'Edit paid price'
                                : 'Set paid price',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onSwipeToggle == null || !enabled) {
      return KeyedSubtree(key: ValueKey(line.key), child: tile);
    }

    // Swipe right to check / uncheck (tile stays in place — same as shop mode).
    return Dismissible(
      key: ValueKey('trip-${line.key}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: checked ? ShoppaColors.mist : ShoppaColors.green,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          checked ? Icons.undo : Icons.check,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (_) async {
        onSwipeToggle!();
        return false;
      },
      child: tile,
    );
  }
}
