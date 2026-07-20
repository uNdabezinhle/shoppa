import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/ads_repository.dart';
import '../core/api_client.dart';
import '../core/catalogue_repository.dart';
import '../core/export_download.dart';
import '../core/aisle_sort.dart';
import '../core/list_chat_client.dart';
import '../core/list_realtime_client.dart';
import '../core/list_realtime_patch.dart';
import '../core/list_category_style.dart';
import '../core/list_shop_helpers.dart';
import '../core/bulk_item_parse.dart';
import '../core/list_text_format.dart';
import '../core/lists_repository.dart';
import '../core/last_paid_prices_store.dart';
import '../core/recent_items_store.dart';
import '../core/session_summary.dart';
import '../core/shop_prefs_store.dart';
import '../core/shopping_session_store.dart';
import '../theme/shoppa_theme.dart';
import '../widgets/ad_banner.dart';
import '../widgets/ad_interstitial_sheet.dart';
import '../widgets/ad_native_tile.dart';
import '../widgets/confidence_chip.dart';
import '../widgets/bulk_add_sheet.dart';
import '../core/receipt_capture.dart';
import '../core/receipt_history_store.dart';
import '../widgets/copy_list_text_sheet.dart';
import '../widgets/import_from_list_sheet.dart';
import '../widgets/item_form_dialog.dart';
import '../widgets/list_form_dialog.dart';
import '../widgets/pick_list_sheet.dart';
import '../widgets/presence_banner.dart';
import '../widgets/product_picker_sheet.dart';
import '../widgets/receipt_capture_sheet.dart';
import '../widgets/receipt_history_sheet.dart';
import '../widgets/scale_guests_sheet.dart';
import '../widgets/shopping_at_store_sheet.dart';

/// Item check-off view (SRS FR-2.2, FR-4.1) with a price-capture prompt
/// on check-off (FR-4.3) and a session summary on completion (FR-4.4),
/// sharing (FR-3.1), the per-list activity feed (FR-3.3), and offline
/// usability (FR-4.2): the list stays fully viewable and editable
/// without connectivity, backed by ListsRepository's cache + mutation
/// queue, and flushes that queue as soon as a load succeeds online.
class ListScreen extends StatefulWidget {
  const ListScreen({
    super.key,
    required this.adsRepository,
    required this.listsRepository,
    required this.catalogueRepository,
    required this.realtimeClient,
    required this.chatClient,
    this.currentUserEmail,
    this.accountType = 'personal',
    required this.listId,
    required this.title,
    this.startInShopMode = false,
  });

  final AdsRepository adsRepository;
  final ListsRepository listsRepository;
  final CatalogueRepository catalogueRepository;
  final ListRealtimeClient realtimeClient;
  final ListChatClient chatClient;
  final String? currentUserEmail;
  final String accountType;
  final String listId;
  final String title;
  /// Open already in shop mode (e.g. My Lists “Start shopping”).
  final bool startInShopMode;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  late Future<ShoppaList> _list;
  late final String _adSessionKey;
  late final Future<AdPlacement?> _listBanner;
  StreamSubscription<ListRealtimeEvent>? _realtimeSubscription;
  StreamSubscription<RealtimeConnectionState>? _connectionSubscription;
  Timer? _reloadDebounce;
  int _pendingCount = 0;
  final Map<String, String> _activeEditors = {};
  RealtimeConnectionState _connectionState = RealtimeConnectionState.connecting;
  final _realtimeBroadcast = StreamController<ListRealtimeEvent>.broadcast();
  /// Latest list applied from REST or an incremental WS patch — used so
  /// realtime events don't need to await an in-flight Future.
  ShoppaList? _listSnapshot;
  // SRS FR-5.3/FR-5.4: store the shopper is currently in (comparison sheet).
  // Persisted per list so it survives leave/restart; cleared via the ✕ chip.
  String? _shoppingAtStoreId;
  String? _shoppingAtStoreName;
  final ShoppingSessionStore _sessionStore =
      SharedPreferencesShoppingSessionStore();
  bool _shopMode = false;
  /// When true (default in shop mode), group remaining items by aisle.
  bool _aisleOrder = true;
  /// Aisle group ids the shopper collapsed (tap sticky header to toggle).
  final Set<String> _collapsedAisleIds = {};
  /// Preferred store aisle layout id; null = auto from shopping-at / receipt.
  String? _aisleLayoutId;
  /// All / remaining / checked-off view filter.
  ItemViewFilter _itemFilter = ItemViewFilter.all;
  /// Manual position order, or A–Z by name.
  ItemOrderMode _itemOrder = ItemOrderMode.manual;
  bool _dismissedStoreNudge = false;
  final _searchController = TextEditingController();
  final _quickAddController = TextEditingController();
  final _quickAddFocus = FocusNode();
  String _searchQuery = '';
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  /// Cached list comparison for basket estimate on the progress strip.
  ShoppaComparison? _comparison;
  bool _comparisonLoading = false;
  bool _quickAddBusy = false;
  final RecentItemsStore _recentItems = SharedPreferencesRecentItemsStore();
  List<String> _recentNames = const [];
  final ShopPrefsStore _shopPrefs = SharedPreferencesShopPrefsStore();
  /// When true, check-off skips the price dialog (faster in-store shopping).
  bool _skipPricePrompt = false;
  /// When true in shop mode: larger check targets, hide search/filters chrome.
  bool _focusShop = false;
  /// When true in shop mode, prevent the display from sleeping.
  bool _keepScreenOn = true;
  final ReceiptHistoryStore _receiptHistory =
      SharedPreferencesReceiptHistoryStore();
  final LastPaidPricesStore _lastPaidPrices =
      SharedPreferencesLastPaidPricesStore();
  /// Snapshot for remaining-spend estimates (refreshed on price memory writes).
  Map<String, int> _lastPaidSnapshot = const {};
  LoggedReceipt? _latestReceipt;
  late String _displayTitle;

  @override
  void initState() {
    super.initState();
    _displayTitle = widget.title;
    _shopMode = widget.startInShopMode;
    _adSessionKey = '${widget.listId}-${DateTime.now().microsecondsSinceEpoch}';
    _listBanner = _loadListBanner();
    _list = _loadAndSync();
    _list.then((_) {
      _refreshPendingCount();
      _refreshComparison();
    }, onError: (_) {});
    _restoreShoppingAtStore();
    _loadRecentNames();
    _loadShopPrefs();
    _loadLatestReceipt();
    _loadLastPaidSnapshot();
    // SRS FR-3.2: item/scale events patch the in-memory list; collaborator
    // events still trigger a debounced full detail refetch.
    _connectionSubscription = widget.realtimeClient.connectionState.listen(
      (state) {
        if (!mounted) return;
        setState(() => _connectionState = state);
      },
    );
    _realtimeSubscription = widget.realtimeClient
        .connect(widget.listId)
        .listen((event) {
      if (!_realtimeBroadcast.isClosed) _realtimeBroadcast.add(event);
      _onRealtimeEvent(event);
    });
  }

  void _onRealtimeEvent(ListRealtimeEvent event) {
    if (event.event == 'presence.joined') {
      final userId = event.payload['user_id'] as String?;
      final email = event.payload['email'] as String?;
      if (userId != null &&
          email != null &&
          email != widget.currentUserEmail &&
          mounted) {
        setState(() => _activeEditors[userId] = email);
      }
      return;
    }
    if (event.event == 'presence.left') {
      final userId = event.payload['user_id'] as String?;
      if (userId != null && mounted) {
        setState(() => _activeEditors.remove(userId));
      }
      return;
    }
    final current = _listSnapshot;
    if (current == null) {
      _scheduleReload();
      return;
    }
    final patched = applyListRealtimeEvent(current, event);
    if (patched == null) {
      _scheduleReload();
      return;
    }
    if (identical(patched, current)) return;
    _setListSnapshot(patched);
  }

  void _setListSnapshot(ShoppaList list) {
    _listSnapshot = list;
    if (!mounted) return;
    setState(() {
      _list = Future.value(list);
    });
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _realtimeSubscription?.cancel();
    _connectionSubscription?.cancel();
    _searchController.dispose();
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    unawaited(_realtimeBroadcast.close());
    unawaited(_releaseKeepAwake());
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
        final merged =
            await widget.listsRepository.fetchListDetail(widget.listId);
        _listSnapshot = merged;
        return merged;
      }
    }
    _listSnapshot = list;
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
    _list.then((_) {
      _refreshPendingCount();
      _refreshComparison();
    }, onError: (_) {});
  }

  Future<void> _refreshComparison() async {
    if (_comparisonLoading) return;
    _comparisonLoading = true;
    try {
      final comparison =
          await widget.listsRepository.fetchComparison(widget.listId);
      if (!mounted) return;
      setState(() => _comparison = comparison);
    } catch (_) {
      // Offline or no priced items — leave previous estimate if any.
    } finally {
      _comparisonLoading = false;
    }
  }

  Future<void> _toggle(ShoppaListItem item, bool canEdit) async {
    if (!canEdit) {
      _showViewOnlySnack();
      return;
    }
    final checking = !item.checked;
    int? paidPrice;
    if (checking && !_skipPricePrompt) {
      // SRS FR-4.3: confirm or enter the actual price when checking off.
      // Fast check-off (shop prefs) skips this for quicker in-store trips.
      if (!mounted) return;
      paidPrice = await _promptForPrice(item);
      if (!mounted) return;
    }
    try {
      await widget.listsRepository.setItemChecked(
        widget.listId,
        item.id,
        checked: checking,
        paidPrice: paidPrice,
        storeId: checking ? _observationStoreId : null,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update item: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();

    // Optimistic trip-complete detection before the reload finishes.
    final snapItems = _listSnapshot?.items ?? const <ShoppaListItem>[];
    var checkedCount = 0;
    for (final i in snapItems) {
      final isChecked = i.id == item.id ? checking : i.checked;
      if (isChecked) checkedCount++;
    }
    final justCompleted =
        checking && snapItems.isNotEmpty && checkedCount == snapItems.length;

    // Collapse the aisle once nothing open remains; expand the next walk aisle.
    AisleGroup? nextAisle;
    if (checking && _shopMode && _aisleOrder) {
      final aisleId = aisleForItem(item).id;
      final projectedItems = <ShoppaListItem>[];
      for (final i in snapItems) {
        if (i.id == item.id) {
          projectedItems.add(
            ShoppaListItem(
              id: i.id,
              name: i.name,
              quantity: i.quantity,
              unit: i.unit,
              note: i.note,
              checked: true,
              paidPrice: paidPrice ?? i.paidPrice,
              productId: i.productId,
              position: i.position,
              hasPromotion: i.hasPromotion,
            ),
          );
        } else {
          projectedItems.add(i);
        }
      }
      final stillOpen = projectedItems.any(
        (i) => !i.checked && aisleForItem(i).id == aisleId,
      );
      if (!stillOpen) {
        nextAisle = nextOpenAisleGroup(
          projectedItems,
          layout: _activeAisleLayout,
          afterAisleId: aisleId,
        );
        setState(() {
          _collapsedAisleIds.add(aisleId);
          if (nextAisle != null) {
            _collapsedAisleIds.remove(nextAisle.id);
          }
        });
      }
    }

    _reload();
    if (!mounted) return;

    if (justCompleted) {
      try {
        final list = await _list;
        if (!mounted) return;
        if (listProgress(list.items ?? const []).isComplete) {
          await _openSessionSummary(list);
          return;
        }
      } catch (_) {
        // Fall through to undo snackbar if reload fails.
      }
    }

    if (!checking) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextAisle == null
              ? 'Checked off ${item.name}'
              : 'Checked off ${item.name} · ${formatNextAisleHint(nextAisle)}',
        ),
        backgroundColor: ShoppaColors.panel2,
        action: SnackBarAction(
          label: 'Undo',
          textColor: ShoppaColors.amber,
          onPressed: () async {
            try {
              await widget.listsRepository.setItemChecked(
                widget.listId,
                item.id,
                checked: false,
                clientUpdatedAt: DateTime.now().toUtc(),
              );
              _reload();
            } catch (_) {}
          },
        ),
      ),
    );
  }

  /// Returns the entered price in minor units (cents), or null if the
  /// user skipped/cancelled/entered something unparsable.
  Future<int?> _promptForPrice(ShoppaListItem item) async {
    ProductStorePrice? storePrice;
    final obsStoreId = _observationStoreId;
    if (item.productId != null && obsStoreId != null) {
      storePrice = await widget.catalogueRepository.fetchStorePrice(
        productId: item.productId!,
        storeId: obsStoreId,
      );
    }
    // Prefer live store suggestion; then this line’s paid price; then
    // device memory of the last paid price for this name (any list).
    final lastPaid = item.paidPrice;
    final remembered = lastPaid == null && storePrice == null
        ? await _lastPaidPrices.getCents(item.name)
        : null;
    final suggestedCents = storePrice?.price ?? lastPaid ?? remembered;
    final usingLastPaid = storePrice == null && lastPaid != null;
    final usingRemembered =
        storePrice == null && lastPaid == null && remembered != null;
    final controller = TextEditingController(
      text: suggestedCents != null
          ? (suggestedCents / 100).toStringAsFixed(2)
          : '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Price paid for ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (storePrice != null) ...[
              Row(
                children: [
                  const Text(
                    'Suggested price',
                    style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  ConfidenceChip(confidence: storePrice.confidence, compact: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                ConfidenceChip.legendHint(storePrice.confidence),
                style: const TextStyle(color: ShoppaColors.faint, fontSize: 11),
              ),
              const SizedBox(height: 8),
            ] else if (usingLastPaid) ...[
              const Text(
                'Last paid on this list',
                style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
              ),
              const SizedBox(height: 8),
            ] else if (usingRemembered) ...[
              const Text(
                'Last paid for this item (remembered)',
                style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'e.g. 45.99', prefixText: 'R '),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
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
    final cents = (parsed * 100).round();
    if (cents > 0) {
      await _rememberPaidPrice(item.name, cents);
    }
    return cents;
  }

  void _showViewOnlySnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You have view-only access to this list.')),
    );
  }

  Future<void> _loadRecentNames() async {
    final names = await _recentItems.getRecent();
    if (!mounted) return;
    setState(() => _recentNames = names);
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
      // Apply focus filter when deep-linked into shop mode with focus pref on.
      if (_shopMode && focus) {
        _itemFilter = ItemViewFilter.remaining;
      }
    });
    await _syncKeepAwake();
  }

  StoreAisleLayout get _activeAisleLayout => resolveStoreAisleLayout(
        storeName: _shoppingAtStoreName ?? _latestReceipt?.storeName,
        layoutId: _aisleLayoutId,
      );

  /// Catalogue store id for price observations; null for free-text names.
  String? get _observationStoreId =>
      isCatalogueStoreId(_shoppingAtStoreId) ? _shoppingAtStoreId : null;

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
                title: const Text('Auto from store name'),
                subtitle: Text(
                  storeAisleLayoutForName(
                    _shoppingAtStoreName ?? _latestReceipt?.storeName,
                  ).label,
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
      storeName: _shoppingAtStoreName ?? _latestReceipt?.storeName,
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

  Future<void> _toggleSkipPricePrompt() async {
    final next = !_skipPricePrompt;
    setState(() => _skipPricePrompt = next);
    await _shopPrefs.setSkipPricePrompt(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Fast check-off on — price prompt skipped'
              : 'Price prompt on check-off restored',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  Future<void> _toggleFocusShop() async {
    final next = !_focusShop;
    setState(() {
      _focusShop = next;
      if (next) {
        _itemFilter = ItemViewFilter.remaining;
        _searchQuery = '';
        _searchController.clear();
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
              ? 'Screen stays on while shopping'
              : 'Screen can sleep while shopping',
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Hold the display awake only while shop mode + preference allow it.
  Future<void> _syncKeepAwake() async {
    try {
      if (_shopMode && _keepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Unsupported on some desktop/web builds — ignore.
    }
  }

  Future<void> _releaseKeepAwake() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  bool get _shopFocusActive => _shopMode && _focusShop;

  Future<void> _rememberNames(Iterable<String> names) async {
    await _recentItems.recordMany(names);
    await _loadRecentNames();
  }

  /// Adds a new line, or bumps quantity on an existing unchecked match
  /// (same name + unit, case-insensitive).
  ///
  /// When [liveItems] is provided (bulk paste/import), merges against that
  /// working copy and patches it so subsequent lines see updated qty without
  /// a network round-trip between each row.
  Future<bool> _addOrMergeItem({
    required String name,
    num quantity = 1,
    String unit = 'ea',
    String note = '',
    String? productId,
    bool showMergeSnack = true,
    List<ShoppaListItem>? liveItems,
  }) async {
    final pool = liveItems ?? _listSnapshot?.items ?? const [];
    final existing = findMatchingListItem(pool, name: name, unit: unit);
    if (existing != null) {
      final nextQty = existing.quantity + quantity;
      await widget.listsRepository.updateItem(
        widget.listId,
        existing.id,
        quantity: nextQty,
      );
      if (liveItems != null) {
        final idx = liveItems.indexWhere((i) => i.id == existing.id);
        if (idx >= 0) {
          liveItems[idx] = ShoppaListItem(
            id: existing.id,
            name: existing.name,
            quantity: nextQty,
            unit: existing.unit,
            note: existing.note,
            checked: existing.checked,
            productId: existing.productId,
            paidPrice: existing.paidPrice,
            position: existing.position,
            hasPromotion: existing.hasPromotion,
          );
        }
      }
      if (showMergeSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated “${existing.name}”: qty $nextQty ${existing.unit}',
            ),
            backgroundColor: ShoppaColors.panel2,
          ),
        );
      }
      return true; // merged
    }
    final created = await widget.listsRepository.addItem(
      widget.listId,
      name: name,
      quantity: quantity,
      unit: unit,
      note: note,
      productId: productId,
    );
    liveItems?.add(created);
    return false; // created
  }

  Future<void> _addItem() async {
    final product = await showProductPickerSheet(
      context,
      catalogueRepository: widget.catalogueRepository,
    );
    final values = await showItemFormDialog(
      context,
      initialName: product?.name,
      title: product == null ? 'Add item' : 'Add catalogue item',
    );
    if (values == null) return;
    try {
      final name = values['name'] as String;
      await _addOrMergeItem(
        name: name,
        quantity: values['quantity'] as num,
        unit: values['unit'] as String,
        note: values['note'] as String,
        productId: product?.id,
      );
      await _rememberNames([name]);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _duplicateItem(ShoppaListItem item) async {
    try {
      await widget.listsRepository.addItem(
        widget.listId,
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        note: item.note,
        productId: item.productId,
      );
      await _rememberNames([item.name]);
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Duplicated “${item.name}”'),
          backgroundColor: ShoppaColors.panel2,
        ),
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
          content: Text('Could not duplicate: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _showAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ShoppaColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add item'),
              subtitle: const Text('Catalogue search or free text'),
              onTap: () => Navigator.pop(ctx, 'single'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_outlined),
              title: const Text('Paste many'),
              subtitle: const Text('One item per line'),
              onTap: () => Navigator.pop(ctx, 'paste'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('From receipt text'),
              subtitle: const Text('Paste lines from a receipt (no camera)'),
              onTap: () => Navigator.pop(ctx, 'receipt'),
            ),
            ListTile(
              leading: const Icon(Icons.library_add_outlined),
              title: const Text('Import from list'),
              subtitle: const Text('Copy items from another list'),
              onTap: () => Navigator.pop(ctx, 'import'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'single') {
      await _addItem();
    } else if (choice == 'import') {
      await _importFromList();
    } else {
      await _bulkAddItems(fromReceipt: choice == 'receipt');
    }
  }

  Future<void> _bulkAddItems({required bool fromReceipt}) async {
    final parsed = await showBulkAddSheet(
      context,
      title: fromReceipt ? 'From receipt text' : 'Paste items',
    );
    if (parsed == null || parsed.isEmpty || !mounted) return;

    try {
      final live = List<ShoppaListItem>.from(_listSnapshot?.items ?? const []);
      var created = 0;
      var merged = 0;
      for (final line in parsed) {
        final didMerge = await _addOrMergeItem(
          name: line.name,
          quantity: line.quantity,
          unit: line.unit,
          showMergeSnack: false,
          liveItems: live,
        );
        if (didMerge) {
          merged++;
        } else {
          created++;
        }
      }
      await _rememberNames(parsed.map((p) => p.name));
      _reload();
      if (!mounted) return;
      final parts = <String>[];
      if (created > 0) {
        parts.add('Added $created');
      }
      if (merged > 0) {
        parts.add('merged $merged');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parts.isEmpty ? 'Nothing to add' : parts.join(', ')),
          backgroundColor: ShoppaColors.panel2,
        ),
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
          content: Text('Could not add items: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _importFromList() async {
    final chosen = await showImportFromListSheet(
      context,
      listsRepository: widget.listsRepository,
      currentListId: widget.listId,
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    try {
      final live = List<ShoppaListItem>.from(_listSnapshot?.items ?? const []);
      var created = 0;
      var merged = 0;
      for (final item in chosen) {
        final didMerge = await _addOrMergeItem(
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          note: item.note,
          productId: item.productId,
          showMergeSnack: false,
          liveItems: live,
        );
        if (didMerge) {
          merged++;
        } else {
          created++;
        }
      }
      await _rememberNames(chosen.map((i) => i.name));
      _reload();
      if (!mounted) return;
      final parts = <String>[];
      if (created > 0) {
        parts.add('Imported $created');
      }
      if (merged > 0) {
        parts.add('merged $merged');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parts.isEmpty ? 'Nothing to import' : parts.join(', ')),
          backgroundColor: ShoppaColors.panel2,
        ),
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
          content: Text('Could not import: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _quickAddSubmit() async {
    if (_quickAddBusy) return;
    final text = _quickAddController.text.trim();
    if (text.isEmpty) return;
    final parsed = parseBulkItemLines(text);
    if (parsed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not parse that item')),
      );
      return;
    }
    setState(() => _quickAddBusy = true);
    try {
      final live = List<ShoppaListItem>.from(_listSnapshot?.items ?? const []);
      for (final line in parsed) {
        await _addOrMergeItem(
          name: line.name,
          quantity: line.quantity,
          unit: line.unit,
          showMergeSnack: parsed.length == 1,
          liveItems: live,
        );
      }
      await _rememberNames(parsed.map((p) => p.name));
      _quickAddController.clear();
      _reload();
      if (!mounted) return;
      _quickAddFocus.requestFocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ShoppaColors.rose),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    } finally {
      if (mounted) setState(() => _quickAddBusy = false);
    }
  }

  Future<void> _removeCheckedItems(ShoppaList list) async {
    final checked = (list.items ?? []).where((i) => i.checked).toList();
    if (checked.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No checked items to remove')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove checked items?'),
        content: Text(
          'Permanently remove ${checked.length} checked item'
          '${checked.length == 1 ? '' : 's'} from this list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ShoppaColors.rose),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final item in checked) {
      try {
        await widget.listsRepository.deleteItem(widget.listId, item.id);
      } catch (_) {}
    }
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed ${checked.length} item${checked.length == 1 ? '' : 's'}',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  Future<void> _copyListAsText(ShoppaList? list) async {
    ShoppaList? source = list;
    if (source?.items == null) {
      try {
        source = await widget.listsRepository.fetchListDetail(widget.listId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load list: $e'),
            backgroundColor: ShoppaColors.rose,
          ),
        );
        return;
      }
    }
    if (source == null || !mounted) return;
    final result = await showCopyListTextSheet(context, list: source);
    if (result == null || !mounted) return;
    final options = result.options;
    final text = formatListAsText(source, options: options);
    final n = (source.items ?? const <ShoppaListItem>[])
        .where(
          (i) => options.checkedOnly
              ? i.checked
              : (options.includeChecked || !i.checked),
        )
        .length;

    if (result.action == ListTextExportAction.share) {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      try {
        await Share.share(
          text,
          subject: source.title,
          sharePositionOrigin: origin,
        );
      } catch (_) {
        // Web / desktop without a share target — fall back to clipboard.
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Share unavailable — copied $n line${n == 1 ? '' : 's'} instead',
            ),
            backgroundColor: ShoppaColors.panel2,
          ),
        );
      }
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied $n line${n == 1 ? '' : 's'} — paste into WhatsApp or notes',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  Future<void> _editItemNote(ShoppaListItem item) async {
    final controller = TextEditingController(text: item.note);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.note.isEmpty ? 'Add note' : 'Edit note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
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
    if (result == null || !mounted) return;
    if (result == item.note) return;
    try {
      await widget.listsRepository.updateItem(
        widget.listId,
        item.id,
        note: result,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ShoppaColors.rose),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save note: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _uncheckAll(ShoppaList list) async {
    final checked = (list.items ?? []).where((i) => i.checked).toList();
    if (checked.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing is checked off')),
      );
      return;
    }
    await _startNewTrip(list);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Unchecked ${checked.length} item${checked.length == 1 ? '' : 's'}',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
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

  /// Set or change paid price (works after fast check-off or any time).
  Future<void> _setPaidPrice(ShoppaListItem item) async {
    if (!mounted) return;
    final paidPrice = await _promptForPrice(item);
    if (paidPrice == null || !mounted) return;
    try {
      await widget.listsRepository.setItemChecked(
        widget.listId,
        item.id,
        checked: true,
        paidPrice: paidPrice,
        storeId: _observationStoreId,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Price set: ${formatCents(paidPrice)} for ${item.name}',
          ),
          backgroundColor: ShoppaColors.panel2,
        ),
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
          content: Text('Could not set price: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _loadLatestReceipt() async {
    final latest = await _receiptHistory.latestForScope(widget.listId);
    if (!mounted) return;
    setState(() => _latestReceipt = latest);
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

  Future<void> _showReceiptHistory() async {
    await showReceiptHistorySheet(
      context,
      store: _receiptHistory,
      scopeId: widget.listId,
      title: 'Receipt history',
    );
    await _loadLatestReceipt();
  }

  /// Log till total; optionally fill missing paid prices from the receipt.
  Future<void> _logReceipt(ShoppaList list) async {
    if (!list.canEdit) {
      _showViewOnlySnack();
      return;
    }
    final items = list.items ?? const <ShoppaListItem>[];
    final recentReceipts = await _receiptHistory.recent(limit: 40);
    final storeSuggestions = frequentStoreNames(recentReceipts);
    final capture = await showReceiptCaptureSheet(
      context,
      items: items,
      initialStoreName: _shoppingAtStoreName ?? _latestReceipt?.storeName,
      suggestedStores: storeSuggestions,
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
            'Receipt ${capture.formattedTotal}'
            '${capture.storeName.isNotEmpty ? ' at ${capture.storeName}' : ''}.\n\n'
            'Fill ${suggestions.length} checked item'
            '${suggestions.length == 1 ? '' : 's'} still missing prices '
            '(split by quantity)?',
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
        final byId = {for (final i in items) i.id: i};
        for (final s in suggestions) {
          try {
            await widget.listsRepository.setItemChecked(
              widget.listId,
              s.itemId,
              checked: true,
              paidPrice: s.cents,
              storeId: _observationStoreId,
              clientUpdatedAt: DateTime.now().toUtc(),
            );
            final name = byId[s.itemId]?.name;
            if (name != null && s.cents > 0) {
              await _rememberPaidPrice(name, s.cents);
            }
            applied++;
          } catch (_) {}
        }
        _reload();
      }
    }

    // Snapshot basket spend (checked paid prices), after any receipt fills.
    var pricedItems = items;
    if (applied > 0) {
      try {
        final refreshed =
            await widget.listsRepository.fetchListDetail(widget.listId);
        pricedItems = refreshed.items ?? items;
      } catch (_) {}
    }
    final spendAfter = tripSpend(pricedItems);
    final logged = loggedReceiptFromCapture(
      capture: capture,
      scopeId: widget.listId,
      pricesFilled: applied,
      listTitles: [list.title],
      basketCents: spendAfter.spentCents,
    );
    await _receiptHistory.add(logged);
    if (!mounted) return;
    setState(() => _latestReceipt = logged);
    // Seed free-text shopping-at when none is set yet.
    final receiptStore = capture.storeName.trim();
    if (receiptStore.isNotEmpty &&
        (_shoppingAtStoreName == null ||
            _shoppingAtStoreName!.trim().isEmpty)) {
      await _setShoppingAtByName(receiptStore);
    }

    var addedFromReceipt = 0;
    if (capture.itemsToAdd.isNotEmpty && list.canEdit) {
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add receipt items?'),
          content: Text(
            'Add ${capture.itemsToAdd.length} item'
            '${capture.itemsToAdd.length == 1 ? '' : 's'} found on the '
            'receipt but not on this list?\n\n'
            '${capture.itemsToAdd.take(8).join('\n')}'
            '${capture.itemsToAdd.length > 8 ? '\n…' : ''}\n\n'
            'They’ll be added as checked (already bought).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add items'),
            ),
          ],
        ),
      );
      if (add == true && mounted) {
        try {
          final bulk = await widget.listsRepository.addItemsBulk(
            widget.listId,
            capture.itemsToAdd
                .map(
                  (name) => BulkItemInput(
                    name: name,
                    note: 'from receipt',
                  ),
                )
                .toList(),
          );
          for (final item in bulk.created) {
            try {
              await widget.listsRepository.setItemChecked(
                widget.listId,
                item.id,
                checked: true,
                storeId: _observationStoreId,
                clientUpdatedAt: DateTime.now().toUtc(),
              );
              addedFromReceipt++;
            } catch (_) {}
          }
          if (addedFromReceipt > 0) _reload();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not add receipt items: $e'),
                backgroundColor: ShoppaColors.rose,
              ),
            );
          }
        }
      }
    }

    if (!mounted) return;
    final note = capture.notes.isNotEmpty ? ' · ${capture.notes}' : '';
    final store =
        capture.storeName.isNotEmpty ? ' · ${capture.storeName}' : '';
    final vs = logged.tillVsBasket;
    final deltaHint = vs != null && vs.hasComparison
        ? ' · ${vs.variancePhrase}'
        : '';
    final addHint =
        addedFromReceipt > 0 ? ' · added $addedFromReceipt items' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          applied > 0
              ? 'Receipt ${capture.formattedTotal}$store — filled $applied prices$deltaHint$addHint$note'
              : 'Receipt logged: ${capture.formattedTotal}$store$deltaHint$addHint$note',
        ),
        backgroundColor: ShoppaColors.panel2,
        action: SnackBarAction(
          label: 'History',
          textColor: ShoppaColors.amber,
          onPressed: _showReceiptHistory,
        ),
      ),
    );
  }

  /// Walk checked items missing a price (from trip summary or overflow).
  Future<void> _fillMissingPrices(ShoppaList list) async {
    final missing = itemsMissingPaidPrice(list.items ?? const []);
    if (missing.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All checked items already have prices')),
      );
      return;
    }
    var filled = 0;
    var skipped = 0;
    for (final item in missing) {
      if (!mounted) return;
      final paidPrice = await _promptForPrice(item);
      if (!mounted) return;
      if (paidPrice == null) {
        skipped++;
        continue;
      }
      try {
        await widget.listsRepository.setItemChecked(
          widget.listId,
          item.id,
          checked: true,
          paidPrice: paidPrice,
          storeId: _observationStoreId,
          clientUpdatedAt: DateTime.now().toUtc(),
        );
        filled++;
      } catch (_) {
        skipped++;
      }
    }
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped == 0
              ? 'Recorded $filled price${filled == 1 ? '' : 's'}'
              : 'Recorded $filled, skipped $skipped',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  /// Delete with snackbar Undo (re-adds the line; new id is fine).
  Future<void> _deleteItemWithUndo(ShoppaListItem item) async {
    try {
      await widget.listsRepository.deleteItem(widget.listId, item.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ShoppaColors.rose),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not remove: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
      return;
    }
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${item.name}'),
        backgroundColor: ShoppaColors.panel2,
        action: SnackBarAction(
          label: 'Undo',
          textColor: ShoppaColors.amber,
          onPressed: () async {
            try {
              await widget.listsRepository.addItem(
                widget.listId,
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                note: item.note,
                productId: item.productId,
              );
              _reload();
            } catch (_) {}
          },
        ),
      ),
    );
  }

  void _onItemMenuAction(String value, ShoppaListItem item) {
    if (value == 'edit') {
      _editItem(item);
    } else if (value == 'note') {
      _editItemNote(item);
    } else if (value == 'duplicate') {
      _duplicateItem(item);
    } else if (value == 'link') {
      _linkItemToCatalogue(item);
    } else if (value == 'price') {
      _setPaidPrice(item);
    } else if (value == 'delete') {
      _deleteItemWithUndo(item);
    }
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
    final selected = _selectedIds.contains(item.id);
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _selectMode && selected
            ? ShoppaColors.amber.withOpacity(0.12)
            : item.checked
                ? ShoppaColors.panel2.withOpacity(0.5)
                : ShoppaColors.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            if (_selectMode) {
              _toggleSelected(item.id);
            } else {
              _toggle(item, list.canEdit);
            }
          },
          onLongPress: list.canEdit && !_selectMode
              ? () => _enterSelectMode(item)
              : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.all(_shopFocusActive ? 18 : 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _selectMode && selected
                    ? ShoppaColors.amber
                    : ShoppaColors.line,
              ),
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
                  _selectMode
                      ? (selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank)
                      : item.checked
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                  size: _shopFocusActive ? 32 : 24,
                  color: _selectMode
                      ? (selected ? ShoppaColors.amber : ShoppaColors.faint)
                      : item.checked
                          ? ShoppaColors.green
                          : ShoppaColors.faint,
                ),
                SizedBox(width: _shopFocusActive ? 16 : 12),
                Expanded(child: _itemDetails(item)),
                if (list.canEdit && !_selectMode) ...[
                  if (itemNeedsPaidPrice(item))
                    IconButton(
                      tooltip: 'Set paid price',
                      icon: Icon(
                        Icons.payments_outlined,
                        size: _shopFocusActive ? 24 : 20,
                      ),
                      color: ShoppaColors.amber,
                      onPressed: () => _setPaidPrice(item),
                    ),
                  if (!_shopFocusActive) _quantityStepper(item),
                  if (!_shopMode && item.productId == null)
                    IconButton(
                      tooltip: 'Link to catalogue',
                      icon: const Icon(Icons.link, size: 20),
                      color: ShoppaColors.amber,
                      onPressed: () => _linkItemToCatalogue(item),
                    ),
                  if (!_shopFocusActive)
                    PopupMenuButton<String>(
                      tooltip: 'Item actions',
                      icon: const Icon(
                        Icons.more_vert,
                        size: 20,
                        color: ShoppaColors.mist,
                      ),
                      onSelected: (value) => _onItemMenuAction(value, item),
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'price',
                          child: Text(
                            item.paidPrice != null
                                ? 'Edit paid price'
                                : 'Set paid price',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'note',
                          child: Text(
                            item.note.isEmpty ? 'Add note' : 'Edit note',
                          ),
                        ),
                        if (!_shopMode) ...[
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate'),
                          ),
                          if (item.productId == null)
                            const PopupMenuItem(
                              value: 'link',
                              child: Text('Link to catalogue'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (_selectMode || !list.canEdit) {
      return KeyedSubtree(key: ValueKey(item.id), child: tile);
    }

    // Shop mode: swipe right to check / uncheck (tile stays in place).
    if (_shopMode) {
      return Dismissible(
        key: ValueKey('shop-${item.id}'),
        direction: DismissDirection.startToEnd,
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: item.checked ? ShoppaColors.mist : ShoppaColors.green,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            item.checked ? Icons.undo : Icons.check,
            color: Colors.white,
          ),
        ),
        confirmDismiss: (_) async {
          await _toggle(item, true);
          return false;
        },
        child: tile,
      );
    }

    if (onDismissed == null) {
      return KeyedSubtree(key: ValueKey(item.id), child: tile);
    }

    // Edit mode: swipe left to delete with Undo snackbar (no confirm dialog).
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
      onDismissed: (_) => _deleteItemWithUndo(item),
      child: tile,
    );
  }

  Future<void> _pullToRefresh() async {
    final future = _loadAndSync();
    if (!mounted) return;
    setState(() => _list = future);
    try {
      await future;
      await _refreshPendingCount();
      await _refreshComparison();
    } catch (_) {}
  }

  Widget _buildEmptyItems(ShoppaList list) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
      children: [
        const Icon(
          Icons.shopping_basket_outlined,
          size: 48,
          color: ShoppaColors.faint,
        ),
        const SizedBox(height: 16),
        const Text(
          'No items yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ShoppaColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          list.canEdit
              ? (_shopMode
                  ? 'Exit shop mode to add items, or pull to refresh.'
                  : 'Add one item, paste a list, or import from another list.')
              : 'This list is empty.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: ShoppaColors.mist, fontSize: 13),
        ),
        if (list.canEdit && !_shopMode && !_selectMode) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _bulkAddItems(fromReceipt: false),
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('Paste many'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _importFromList,
            icon: const Icon(Icons.library_add_outlined),
            label: const Text('Import from list'),
          ),
        ],
      ],
    );
  }

  Widget _buildNoSearchMatches() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
      children: [
        const Icon(Icons.search_off, size: 40, color: ShoppaColors.faint),
        const SizedBox(height: 12),
        const Text(
          'No items match your search',
          textAlign: TextAlign.center,
          style: TextStyle(color: ShoppaColors.mist),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
          child: const Text('Clear search'),
        ),
      ],
    );
  }

  Widget _buildEmptyFilterState({
    required int remainingCount,
    required int checkedCount,
  }) {
    final isRemaining = _itemFilter == ItemViewFilter.remaining;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
      children: [
        Icon(
          isRemaining ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 48,
          color: isRemaining ? ShoppaColors.green : ShoppaColors.faint,
        ),
        const SizedBox(height: 12),
        Text(
          isRemaining
              ? 'Nothing left — all items are checked'
              : 'No checked items yet',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ShoppaColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: () => setState(() => _itemFilter = ItemViewFilter.all),
          child: Text(
            isRemaining
                ? 'Show all ($checkedCount checked)'
                : 'Show all ($remainingCount left)',
          ),
        ),
      ],
    );
  }

  Widget _quantityStepper(ShoppaListItem item) {
    final qtyLabel = formatItemQuantity(item.quantity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _qtyIconButton(
          icon: Icons.remove,
          onPressed: () => _nudgeQuantity(item, -1),
        ),
        Tooltip(
          message: 'Tap for quantity presets',
          child: InkWell(
            onTap: () => _pickQuantity(item),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                qtyLabel,
                style: const TextStyle(
                  color: ShoppaColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        _qtyIconButton(
          icon: Icons.add,
          onPressed: () => _nudgeQuantity(item, 1),
        ),
      ],
    );
  }

  Widget _qtyIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        color: ShoppaColors.mist,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
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
                  fontSize: _shopFocusActive ? 17 : 14,
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
          '${item.unit.isEmpty ? 'ea' : item.unit}'
          '${item.note.isNotEmpty ? ' · ${item.note}' : ''}'
          '${item.paidPrice != null ? ' · ${formatCents(item.paidPrice!)}' : ''}'
          '${itemNeedsPaidPrice(item) ? ' · price?' : ''}'
          '${item.productId != null ? ' · catalogue' : ''}',
          style: TextStyle(
            color: itemNeedsPaidPrice(item)
                ? ShoppaColors.amber
                : ShoppaColors.mist,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget? _buildSelectBar() {
    if (!_selectMode) return null;
    final n = _selectedIds.length;
    return Material(
      elevation: 8,
      color: ShoppaColors.panel,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                n == 0 ? 'Select items' : '$n selected',
                style: const TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: n == 0 ? null : () => _bulkSetChecked(true),
                      child: const Text('Check'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: n == 0 ? null : () => _bulkSetChecked(false),
                      child: const Text('Uncheck'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: n == 0 ? null : _bulkDeleteSelected,
                      style: FilledButton.styleFrom(
                        backgroundColor: ShoppaColors.rose,
                      ),
                      child: const Text('Delete'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: n == 0 ? null : () => _bulkCopyOrMove(move: false),
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('Copy to list'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: n == 0 ? null : () => _bulkCopyOrMove(move: true),
                      icon: const Icon(Icons.drive_file_move_outline, size: 18),
                      label: const Text('Move to list'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isProfessional => widget.accountType == 'professional';

  Future<AdPlacement?> _loadListBanner() async {
    try {
      final ads = await widget.adsRepository.fetchPlacements(
        surface: 'list',
        adFormat: 'banner',
      );
      return ads.placements.isEmpty ? null : ads.placements.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportList(String type) async {
    try {
      final result = await widget.listsRepository.exportList(
        widget.listId,
        type: type,
        title: _displayTitle,
      );
      if (!mounted) return;
      if (type == 'csv' && result.textPreview != null) {
        await Clipboard.setData(ClipboardData(text: result.textPreview!));
      }
      final status = await saveListExport(
        bytes: result.bytes,
        filename: result.filename,
        contentType: result.contentType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == 'csv' ? 'CSV copied to clipboard · $status' : status,
          ),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _scaleForGuests() async {
    final result = await showScaleGuestsSheet(context);
    if (result == null) return;
    try {
      final guests = result['guests']?.toInt();
      final factor = result['factor'];
      await widget.listsRepository.scaleList(
        widget.listId,
        guests: guests,
        factor: factor,
      );
      _reload();
      if (mounted) {
        final msg = guests != null
            ? 'Scaled list for $guests guests'
            : 'Scaled list by factor $factor';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: ShoppaColors.panel2,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not scale list: $e'),
            backgroundColor: ShoppaColors.rose,
          ),
        );
      }
    }
  }

  Future<void> _startNewTrip(ShoppaList list) async {
    final items = (list.items ?? []).where((i) => i.checked).toList();
    for (final item in items) {
      try {
        await widget.listsRepository.setItemChecked(
          widget.listId,
          item.id,
          checked: false,
          clientUpdatedAt: DateTime.now().toUtc(),
        );
      } catch (_) {}
    }
    _reload();
  }

  Future<void> _togglePublish(ShoppaList list) async {
    try {
      await widget.listsRepository.updateList(
        list.id,
        isPublic: !list.isPublic,
      );
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update publish setting: $e'),
            backgroundColor: ShoppaColors.rose,
          ),
        );
      }
    }
  }

  Future<void> _openShareSheet(ShoppaList list) async {
    final left = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ShareSheet(
        listsRepository: widget.listsRepository,
        listId: widget.listId,
        canManage: list.isOwner,
        currentUserEmail: widget.currentUserEmail,
        realtimeEvents: _realtimeBroadcast.stream,
      ),
    );
    if (left == true && mounted) {
      Navigator.of(context).maybePop();
    }
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

  Future<void> _openChatSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ChatSheet(
        listsRepository: widget.listsRepository,
        chatClient: widget.chatClient,
        listId: widget.listId,
        currentUserEmail: widget.currentUserEmail,
      ),
    );
  }

  Future<void> _restoreShoppingAtStore() async {
    final saved = await _sessionStore.getShoppingAt(widget.listId);
    if (!mounted || saved == null) return;
    setState(() {
      _shoppingAtStoreId = saved.storeId;
      _shoppingAtStoreName = saved.storeName;
    });
    _refreshComparison();
  }

  Future<void> _linkItemToCatalogue(ShoppaListItem item) async {
    final product = await showProductPickerSheet(
      context,
      catalogueRepository: widget.catalogueRepository,
    );
    if (product == null || !mounted) return;
    try {
      await widget.listsRepository.updateItem(
        widget.listId,
        item.id,
        name: product.name,
        productId: product.id,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Linked “${product.name}” to catalogue'),
          backgroundColor: ShoppaColors.panel2,
        ),
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
          content: Text('Could not link product: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  /// SRS FR-5.3: shows per-store totals for this list. Tapping a store
  /// sets it as "shopping at" (SRS FR-5.4), so subsequent check-offs
  /// submit a price observation for that store without asking per item.
  Future<void> _openComparisonSheet() async {
    final selected = await showModalBottomSheet<ShoppaStoreComparison>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ComparisonSheet(
        adsRepository: widget.adsRepository,
        listsRepository: widget.listsRepository,
        listId: widget.listId,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _shoppingAtStoreId = selected.storeId;
      _shoppingAtStoreName = selected.name;
      _dismissedStoreNudge = true;
    });
    await _sessionStore.setShoppingAt(
      widget.listId,
      ShoppingAtStore(storeId: selected.storeId, storeName: selected.name),
    );
    _refreshComparison();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Shopping at ${selected.name}')),
    );
  }

  Future<void> _clearShoppingAtStore() async {
    setState(() {
      _shoppingAtStoreId = null;
      _shoppingAtStoreName = null;
    });
    await _sessionStore.clearShoppingAt(widget.listId);
  }

  /// Free-text store (aisle walk). Catalogue compare still sets a real store id.
  Future<void> _setShoppingAtByName(String? name) async {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      await _clearShoppingAtStore();
      return;
    }
    setState(() {
      _shoppingAtStoreId = tripStoreSessionId(trimmed);
      _shoppingAtStoreName = trimmed;
      _dismissedStoreNudge = true;
    });
    await _sessionStore.setShoppingAt(
      widget.listId,
      ShoppingAtStore(
        storeId: tripStoreSessionId(trimmed),
        storeName: trimmed,
      ),
    );
  }

  Future<void> _pickShoppingAtStore() async {
    final recentReceipts = await _receiptHistory.recent(limit: 40);
    if (!mounted) return;
    final picked = await showShoppingAtStoreSheet(
      context,
      currentStoreName: _shoppingAtStoreName,
      suggestedStores: frequentStoreNames(recentReceipts),
      subtitle:
          'Sets aisle walk order. Use Compare for live catalogue prices.',
    );
    if (picked == null || !mounted) return;
    if (picked.isEmpty) {
      await _clearShoppingAtStore();
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
    await _setShoppingAtByName(picked);
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

  void _toggleShopMode() {
    setState(() {
      _shopMode = !_shopMode;
      if (_shopMode) {
        _exitSelectMode(notify: false);
        if (_focusShop) {
          _itemFilter = ItemViewFilter.remaining;
          _searchQuery = '';
          _searchController.clear();
        }
      }
    });
    unawaited(_syncKeepAwake());
  }

  void _cycleItemOrder() {
    setState(() {
      _itemOrder = _itemOrder == ItemOrderMode.manual
          ? ItemOrderMode.name
          : ItemOrderMode.manual;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _itemOrder == ItemOrderMode.name
              ? 'Items sorted A–Z'
              : 'Items in list order',
        ),
        backgroundColor: ShoppaColors.panel2,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _exitSelectMode({bool notify = true}) {
    void clear() {
      _selectMode = false;
      _selectedIds.clear();
    }

    if (notify) {
      setState(clear);
    } else {
      clear();
    }
  }

  void _enterSelectMode([ShoppaListItem? seed]) {
    setState(() {
      _selectMode = true;
      _selectedIds.clear();
      if (seed != null) _selectedIds.add(seed.id);
    });
  }

  void _toggleSelected(String itemId) {
    setState(() {
      if (_selectedIds.contains(itemId)) {
        _selectedIds.remove(itemId);
      } else {
        _selectedIds.add(itemId);
      }
    });
  }

  Future<void> _nudgeQuantity(ShoppaListItem item, int direction) async {
    final next = adjustItemQuantity(item.quantity, direction);
    if (next == item.quantity) return;
    await _setQuantity(item, next);
  }

  Future<void> _setQuantity(ShoppaListItem item, num quantity) async {
    if (quantity == item.quantity) return;
    try {
      await widget.listsRepository.updateItem(
        widget.listId,
        item.id,
        quantity: quantity,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ShoppaColors.rose),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update quantity: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _pickQuantity(ShoppaListItem item) async {
    final chosen = await showModalBottomSheet<num>(
      context: context,
      backgroundColor: ShoppaColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Quantity · ${item.name}',
                  style: const TextStyle(
                    color: ShoppaColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Unit: ${item.unit.isEmpty ? 'ea' : item.unit}',
                  style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in kQuantityPresets)
                      ChoiceChip(
                        label: Text(formatItemQuantity(q)),
                        selected: item.quantity == q,
                        onSelected: (_) => Navigator.pop(ctx, q),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final custom = await _promptCustomQuantity(item);
                    if (custom != null) await _setQuantity(item, custom);
                  },
                  child: const Text('Custom…'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen != null) await _setQuantity(item, chosen);
  }

  Future<num?> _promptCustomQuantity(ShoppaListItem item) async {
    final controller = TextEditingController(
      text: formatItemQuantity(item.quantity),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quantity for ${item.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity',
            suffixText: item.unit.isEmpty ? 'ea' : item.unit,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return null;
    final parsed = num.tryParse(result.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<void> _bulkSetChecked(bool checked) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    for (final id in ids) {
      try {
        await widget.listsRepository.setItemChecked(
          widget.listId,
          id,
          checked: checked,
          clientUpdatedAt: DateTime.now().toUtc(),
        );
      } catch (_) {}
    }
    _exitSelectMode();
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          checked
              ? 'Checked ${ids.length} item${ids.length == 1 ? '' : 's'}'
              : 'Unchecked ${ids.length} item${ids.length == 1 ? '' : 's'}',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  Future<void> _bulkCopyOrMove({required bool move}) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final items = (_listSnapshot?.items ?? [])
        .where((i) => ids.contains(i.id))
        .toList();
    if (items.isEmpty) return;

    final dest = await showPickListSheet(
      context,
      listsRepository: widget.listsRepository,
      excludeListId: widget.listId,
      title: move ? 'Move to list' : 'Copy to list',
    );
    if (dest == null || !mounted) return;

    var okCount = 0;
    for (final item in items) {
      try {
        await widget.listsRepository.addItem(
          dest.id,
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          note: item.note,
          productId: item.productId,
        );
        if (move) {
          await widget.listsRepository.deleteItem(widget.listId, item.id);
        }
        okCount++;
      } catch (_) {}
    }
    _exitSelectMode();
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          move
              ? 'Moved $okCount item${okCount == 1 ? '' : 's'} to “${dest.title}”'
              : 'Copied $okCount item${okCount == 1 ? '' : 's'} to “${dest.title}”',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  Future<void> _editListDetails(ShoppaList list) async {
    if (!list.isOwner) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the owner can edit list details')),
      );
      return;
    }
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
      final updated = await widget.listsRepository.updateList(
        list.id,
        title: values['title'] as String,
        category: values['category'] as String,
        isRecurring: values['is_recurring'] as bool,
        eventName: values['event_name'] as String?,
        eventDate: values['event_date'] as String?,
      );
      if (!mounted) return;
      setState(() => _displayTitle = updated.title);
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('List updated'),
          backgroundColor: ShoppaColors.panel2,
        ),
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
          content: Text('Could not update list: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _duplicateThisList() async {
    try {
      final clone =
          await widget.listsRepository.duplicateList(widget.listId);
      if (!mounted) return;
      context.push(
        listDetailPath(clone.id, title: clone.title),
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
          content: Text('Could not duplicate: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  Future<void> _bulkDeleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove items?'),
        content: Text(
          'Remove ${ids.length} selected item${ids.length == 1 ? '' : 's'} '
          'from this list?',
        ),
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
    if (ok != true) return;
    for (final id in ids) {
      try {
        await widget.listsRepository.deleteItem(widget.listId, id);
      } catch (_) {}
    }
    _exitSelectMode();
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed ${ids.length} item${ids.length == 1 ? '' : 's'}',
        ),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  /// SRS FR-4.4: a session summary of spend (and, once price_intelligence
  /// exists, savings) on completion. Computed purely from the
  /// already-loaded list -- no extra request, so it works offline too.
  Future<void> _openSessionSummary(ShoppaList list) async {
    try {
      final checkoutAds = await widget.adsRepository.fetchPlacements(
        surface: 'checkout',
        sessionKey: _adSessionKey,
      );
      for (final placement in checkoutAds.placements) {
        if (!mounted) return;
        if (placement.isInterstitial || placement.isRewarded) {
          await showAdInterstitialSheet(
            context,
            placement: placement,
            adsRepository: widget.adsRepository,
            sessionKey: _adSessionKey,
          );
        }
      }
    } catch (_) {}

    ShoppaComparison? comparison;
    try {
      comparison = await widget.listsRepository.fetchComparison(widget.listId);
    } catch (_) {}
    final summary = SessionSummary.fromItems(
      list.items ?? [],
      comparison: comparison,
    );
    final receipt = _latestReceipt;
    final tillCmp = receipt == null
        ? null
        : TillVsBasket(
            tillCents: receipt.totalCents,
            basketCents: summary.totalSpentCents > 0
                ? summary.totalSpentCents
                : receipt.basketCents,
          );
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(summary.isComplete ? 'Trip complete' : 'Session summary'),
        content: SingleChildScrollView(
          child: Column(
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
              if (tillCmp != null && tillCmp.hasTill) ...[
                const SizedBox(height: 8),
                Text(
                  tillCmp.shareLine,
                  style: TextStyle(
                    color: !tillCmp.hasComparison
                        ? ShoppaColors.mist
                        : (tillCmp.matches
                            ? ShoppaColors.green
                            : (tillCmp.over
                                ? ShoppaColors.amber
                                : ShoppaColors.mist)),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (receipt!.storeName.isNotEmpty)
                  Text(
                    receipt.storeName,
                    style: const TextStyle(
                      color: ShoppaColors.mist,
                      fontSize: 12,
                    ),
                  ),
              ],
              if (summary.hasSavings) ...[
                const SizedBox(height: 8),
                Text(
                  'You could save up to ${summary.formattedPotentialSavings} shopping at the best store',
                  style: const TextStyle(
                    color: ShoppaColors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              if (summary.hasIncompletePricing) ...[
                const SizedBox(height: 8),
                Text(
                  '${summary.checkedWithoutPrice} checked without a recorded price',
                  style: const TextStyle(color: ShoppaColors.amber, fontSize: 12),
                ),
              ],
              if (!summary.hasSavings) ...[
                const SizedBox(height: 8),
                const Text(
                  'Link items to the catalogue to see savings vs other stores.',
                  style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (summary.checkedItems > 0)
            TextButton(
              onPressed: () => Navigator.of(context).pop('share_recap'),
              child: const Text('Share recap'),
            ),
          if (list.canEdit && summary.checkedItems > 0)
            TextButton(
              onPressed: () => Navigator.of(context).pop('log_receipt'),
              child: const Text('Log receipt'),
            ),
          if (summary.hasIncompletePricing && list.canEdit)
            TextButton(
              onPressed: () => Navigator.of(context).pop('fill_prices'),
              child: const Text('Add missing prices'),
            ),
          if (summary.checkedItems > 0 && list.canEdit)
            TextButton(
              onPressed: () => Navigator.of(context).pop('new_trip'),
              child: const Text('Start new trip'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: const Text('Keep shopping'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('done'),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (action == 'share_recap' && mounted) {
      await _shareSessionRecap(list, summary: summary);
    } else if (action == 'log_receipt' && mounted) {
      await _logReceipt(list);
    } else if (action == 'fill_prices' && mounted) {
      await _fillMissingPrices(list);
    } else if (action == 'new_trip' && mounted) {
      await _startNewTrip(list);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checked items cleared — ready for a new trip'),
          ),
        );
      }
    }
  }

  Future<void> _shareSessionRecap(
    ShoppaList list, {
    SessionSummary? summary,
  }) async {
    final receipt = _latestReceipt;
    final text = formatSessionRecapAsText(
      list,
      summary: summary,
      tillCents: receipt?.totalCents,
      basketCents: receipt != null
          ? (receipt.basketCents > 0
              ? receipt.basketCents
              : (summary?.totalSpentCents ??
                  tripSpend(list.items ?? const []).spentCents))
          : null,
    );
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      await Share.share(
        text,
        subject: '${list.title} · trip recap',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Share unavailable — recap copied'),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
    }
  }

  Future<void> _onOverflowAction(String value, ShoppaList? list) async {
    if (value == 'set_store') {
      await _pickShoppingAtStore();
    } else if (value == 'compare') {
      await _openComparisonSheet();
    } else if (value == 'aisle_order') {
      setState(() => _aisleOrder = !_aisleOrder);
    } else if (value == 'collapse_aisles') {
      final items = list?.items ?? _listSnapshot?.items ?? const [];
      setState(() {
        for (final s in shopAisleSections(
          items,
          includeChecked: true,
          separateChecked: true,
          layout: _activeAisleLayout,
        )) {
          _collapsedAisleIds.add(s.aisle.id);
        }
      });
    } else if (value == 'expand_aisles') {
      setState(() => _collapsedAisleIds.clear());
    } else if (value == 'aisle_layout') {
      await _pickAisleLayout();
    } else if (value == 'item_order') {
      _cycleItemOrder();
    } else if (value == 'skip_price') {
      await _toggleSkipPricePrompt();
    } else if (value == 'focus_shop') {
      await _toggleFocusShop();
    } else if (value == 'keep_screen') {
      await _toggleKeepScreenOn();
    } else if (value == 'chat') {
      _openChatSheet();
    } else if (value == 'activity') {
      _openActivitySheet();
    } else if (value == 'share') {
      if (list != null) _openShareSheet(list);
    } else if (value == 'copy_text') {
      await _copyListAsText(list);
    } else if (value == 'edit_list') {
      if (list != null) await _editListDetails(list);
    } else if (value == 'duplicate_list') {
      await _duplicateThisList();
    } else if (value == 'uncheck_all') {
      if (list != null && list.canEdit) await _uncheckAll(list);
    } else if (value == 'remove_checked') {
      if (list != null && list.canEdit) await _removeCheckedItems(list);
    } else if (value == 'fill_prices') {
      if (list != null && list.canEdit) await _fillMissingPrices(list);
    } else if (value == 'log_receipt') {
      if (list != null && list.canEdit) await _logReceipt(list);
    } else if (value == 'receipt_history') {
      await _showReceiptHistory();
    } else if (value == 'select') {
      if (list != null && list.canEdit) _enterSelectMode();
    } else if (value == 'export_csv') {
      await _exportList('csv');
    } else if (value == 'export_pdf') {
      await _exportList('pdf');
    } else if (value == 'scale') {
      await _scaleForGuests();
    } else if (value == 'publish') {
      if (list != null) await _togglePublish(list);
    }
  }

  /// Check off every open item still in [section] (no price prompts — fast walk).
  Future<void> _checkOffAisle(AisleSection section, ShoppaList list) async {
    if (!list.canEdit || section.aisle.id == 'checked') {
      if (!list.canEdit) _showViewOnlySnack();
      return;
    }
    final fromSection = section.items.where((i) => !i.checked).toList();
    final allOpen = openListItemsInAisle(
      list.items ?? const [],
      section.aisle.id,
    );
    final targets = fromSection.isNotEmpty ? fromSection : allOpen;
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

    final ids = targets.map((t) => t.id).toList();
    try {
      for (final item in targets) {
        await widget.listsRepository.setItemChecked(
          widget.listId,
          item.id,
          checked: true,
          clientUpdatedAt: DateTime.now().toUtc(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update aisle: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    final snapItems = _listSnapshot?.items ?? const <ShoppaListItem>[];
    final idSet = ids.toSet();
    final projectedItems = snapItems.map((i) {
      if (!idSet.contains(i.id)) return i;
      return ShoppaListItem(
        id: i.id,
        name: i.name,
        quantity: i.quantity,
        unit: i.unit,
        note: i.note,
        checked: true,
        paidPrice: i.paidPrice,
        productId: i.productId,
        position: i.position,
        hasPromotion: i.hasPromotion,
      );
    }).toList();
    final nextAisle = nextOpenAisleGroup(
      projectedItems,
      layout: _activeAisleLayout,
      afterAisleId: section.aisle.id,
    );
    setState(() {
      _collapsedAisleIds.add(section.aisle.id);
      if (nextAisle != null) {
        _collapsedAisleIds.remove(nextAisle.id);
      }
    });
    _reload();
    if (!mounted) return;

    final allDone = snapItems.isNotEmpty &&
        snapItems.every((i) => i.checked || idSet.contains(i.id));
    if (allDone) {
      try {
        final refreshed = await _list;
        if (!mounted) return;
        if (listProgress(refreshed.items ?? const []).isComplete) {
          await _openSessionSummary(refreshed);
          return;
        }
      } catch (_) {}
    }

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
          onPressed: () async {
            try {
              for (final id in ids) {
                await widget.listsRepository.setItemChecked(
                  widget.listId,
                  id,
                  checked: false,
                  clientUpdatedAt: DateTime.now().toUtc(),
                );
              }
              _reload();
            } catch (_) {}
          },
        ),
      ),
    );
  }

  /// Sticky aisle header + item rows for one shop-mode section.
  List<Widget> _listAisleSlivers({
    required AisleSection section,
    required ShoppaList list,
  }) {
    final aisleId = section.aisle.id;
    final collapsed = _collapsedAisleIds.contains(aisleId);
    final openInSection =
        section.items.where((i) => !i.checked).length;
    return [
      SliverPersistentHeader(
        pinned: true,
        delegate: _AisleStickyHeaderDelegate(
          label: section.aisle.label,
          countLabel: collapsed
              ? '$openInSection left'
              : '${section.items.length}',
          collapsed: collapsed,
          onToggle: () {
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
                  list.canEdit
              ? () => _checkOffAisle(section, list)
              : null,
        ),
      ),
      if (!collapsed)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = section.items[index];
                return _buildItemTile(
                  item: item,
                  list: list,
                  index: index,
                  onDismissed: null,
                );
              },
              childCount: section.items.length,
            ),
          ),
        ),
    ];
  }

  Widget _buildProgressStrip(ShoppaList list, ListProgress progress) {
    final canTap = progress.hasItems && progress.checked > 0;
    final spend = tripSpend(list.items ?? const []);
    final cat = listCategoryStyle(list.category);
    return Material(
      color: ShoppaColors.panel2.withOpacity(0.45),
      child: InkWell(
        onTap: canTap ? () => _openSessionSummary(list) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cat.color.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cat.color.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.icon, size: 14, color: cat.color),
                        const SizedBox(width: 5),
                        Text(
                          cat.label,
                          style: TextStyle(
                            color: cat.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (list.isRecurring) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'Recurring',
                      style: TextStyle(
                        color: ShoppaColors.mist,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (list.eventName.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        list.eventName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ShoppaColors.mist,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                ],
              ),
              if (progress.hasItems) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${progress.checked} of ${progress.total} checked'
                        ' · ${progress.percent}%',
                        style: const TextStyle(
                          color: ShoppaColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (progress.remaining > 0)
                      Text(
                        '${progress.remaining} left',
                        style: const TextStyle(
                          color: ShoppaColors.mist,
                          fontSize: 12,
                        ),
                      )
                    else
                      const Text(
                        'All done',
                        style: TextStyle(
                          color: ShoppaColors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (canTap) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 16,
                        color: ShoppaColors.mist,
                      ),
                    ],
                  ],
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
                    list.items ?? const [],
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
                  onTap: _showReceiptHistory,
                  child: Builder(
                    builder: (context) {
                      final receipt = _latestReceipt!;
                      // Prefer live basket when spend exists; else snapshot at log.
                      final liveBasket = spend.spentCents;
                      final cmp = TillVsBasket(
                        tillCents: receipt.totalCents,
                        basketCents: liveBasket > 0
                            ? liveBasket
                            : receipt.basketCents,
                      );
                      final when = formatRelativeTime(receipt.createdAt);
                      final store = receipt.storeName.isNotEmpty
                          ? ' · ${receipt.storeName}'
                          : '';
                      final whenBit = when.isNotEmpty ? ' · $when' : '';
                      final line = cmp.hasComparison
                          ? '${cmp.summaryLine}$store$whenBit'
                          : 'Last till ${receipt.formattedTotal}$store$whenBit';
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
              if (_comparison != null && !_comparison!.isEmpty) ...[
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    final store = pickComparisonStore(
                      _comparison!,
                      preferredStoreId: _observationStoreId,
                    );
                    if (store == null) return const SizedBox.shrink();
                    final label = _observationStoreId != null &&
                            store.storeId == _observationStoreId
                        ? 'Est. ${formatCents(store.total)} at ${store.name}'
                        : 'Best est. ${formatCents(store.total)} at ${store.name}';
                    final saves = _comparison!.bestSaves;
                    final saveHint = saves != null &&
                            saves > 0 &&
                            store.storeId != _comparison!.bestStoreId
                        ? ' · save up to ${formatCents(saves)} elsewhere'
                        : '';
                    return Text(
                      '$label$saveHint',
                      style: const TextStyle(
                        color: ShoppaColors.mist,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
              if (progress.hasItems) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 6,
                    backgroundColor: ShoppaColors.line,
                    color: progress.isComplete
                        ? ShoppaColors.green
                        : cat.color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: _exitSelectMode,
              )
            : null,
        title: Text(
          _selectMode
              ? (_selectedIds.isEmpty
                  ? 'Select items'
                  : '${_selectedIds.length} selected')
              : (_shopMode
                  ? 'Shopping · $_displayTitle'
                  : _displayTitle),
        ),
        actions: [
          if (!_selectMode) ...[
            IconButton(
              tooltip: _shopMode ? 'Exit shop mode' : 'Shop mode',
              icon: Icon(
                _shopMode ? Icons.shopping_cart : Icons.shopping_cart_outlined,
              ),
              onPressed: _toggleShopMode,
            ),
            if (_shopMode)
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
            if (!_shopFocusActive)
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
            if (!_shopMode)
              IconButton(
                tooltip: 'Compare prices',
                icon: const Icon(Icons.storefront_outlined),
                onPressed: _openComparisonSheet,
              ),
          ],
          FutureBuilder<ShoppaList>(
            future: _list,
            builder: (context, snapshot) {
              final list = snapshot.data;
              if (_selectMode) {
                final allIds = (list?.items ?? []).map((i) => i.id).toList();
                final allSelected =
                    allIds.isNotEmpty && _selectedIds.length == allIds.length;
                return IconButton(
                  tooltip: allSelected ? 'Clear selection' : 'Select all',
                  icon: Icon(
                    allSelected ? Icons.deselect : Icons.select_all,
                  ),
                  onPressed: allIds.isEmpty
                      ? null
                      : () {
                          setState(() {
                            if (allSelected) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds
                                ..clear()
                                ..addAll(allIds);
                            }
                          });
                        },
                );
              }
              return PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) => _onOverflowAction(value, list),
                itemBuilder: (context) {
                  final items = <PopupMenuEntry<String>>[
                    if (_shopMode)
                      PopupMenuItem(
                        value: 'set_store',
                        child: Text(
                          _shoppingAtStoreName != null &&
                                  _shoppingAtStoreName!.trim().isNotEmpty
                              ? 'Change store ($_shoppingAtStoreName)'
                              : 'Set store',
                        ),
                      ),
                    if (_shopMode)
                      const PopupMenuItem(
                        value: 'compare',
                        child: Text('Compare prices'),
                      ),
                    if (_shopMode)
                      PopupMenuItem(
                        value: 'aisle_order',
                        child: Text(
                          _aisleOrder && _itemOrder == ItemOrderMode.manual
                              ? 'Simple order (no aisles)'
                              : 'Sort by aisle',
                        ),
                      ),
                    if (_shopMode && _aisleOrder)
                      PopupMenuItem(
                        value: 'aisle_layout',
                        child: Text(
                          'Aisle walk: ${_activeAisleLayout.label}',
                        ),
                      ),
                    if (_shopMode && _aisleOrder)
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
                    PopupMenuItem(
                      value: 'item_order',
                      child: Text(
                        _itemOrder == ItemOrderMode.name
                            ? 'List order (manual)'
                            : 'Sort items A–Z',
                      ),
                    ),
                    if (_shopMode)
                      PopupMenuItem(
                        value: 'skip_price',
                        child: Text(
                          _skipPricePrompt
                              ? 'Ask price on check-off'
                              : 'Fast check-off (skip price)',
                        ),
                      ),
                    if (_shopMode)
                      PopupMenuItem(
                        value: 'focus_shop',
                        child: Text(
                          _focusShop
                              ? 'Exit focus mode'
                              : 'Focus mode (bigger checks)',
                        ),
                      ),
                    if (_shopMode)
                      PopupMenuItem(
                        value: 'keep_screen',
                        child: Text(
                          _keepScreenOn
                              ? 'Allow screen to sleep'
                              : 'Keep screen on',
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'chat',
                      child: Text('Chat'),
                    ),
                    const PopupMenuItem(
                      value: 'activity',
                      child: Text('Activity'),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('Invite collaborators'),
                    ),
                    const PopupMenuItem(
                      value: 'copy_text',
                      child: Text('Share / copy as text'),
                    ),
                    if (list != null && list.isOwner)
                      const PopupMenuItem(
                        value: 'edit_list',
                        child: Text('Edit list details'),
                      ),
                    const PopupMenuItem(
                      value: 'duplicate_list',
                      child: Text('Duplicate list'),
                    ),
                    if (list != null && list.canEdit)
                      const PopupMenuItem(
                        value: 'select',
                        child: Text('Select items'),
                      ),
                    if (list != null && list.canEdit)
                      const PopupMenuItem(
                        value: 'uncheck_all',
                        child: Text('Uncheck all (new trip)'),
                      ),
                    if (list != null && list.canEdit)
                      const PopupMenuItem(
                        value: 'remove_checked',
                        child: Text('Remove checked items'),
                      ),
                    if (list != null &&
                        list.canEdit &&
                        itemsMissingPaidPrice(list.items ?? const []).isNotEmpty)
                      const PopupMenuItem(
                        value: 'fill_prices',
                        child: Text('Add missing prices'),
                      ),
                    if (list != null && list.canEdit)
                      const PopupMenuItem(
                        value: 'log_receipt',
                        child: Text('Log receipt / till total'),
                      ),
                    const PopupMenuItem(
                      value: 'receipt_history',
                      child: Text('Receipt history'),
                    ),
                    const PopupMenuItem(
                      value: 'export_csv',
                      child: Text('Export CSV'),
                    ),
                    const PopupMenuItem(
                      value: 'export_pdf',
                      child: Text('Export PDF'),
                    ),
                  ];
                  if (_isProfessional && list != null && list.isOwner) {
                    items.addAll([
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'scale',
                        child: Text('Scale for guests'),
                      ),
                      PopupMenuItem(
                        value: 'publish',
                        child: Text(
                          list.isPublic
                              ? 'Unpublish list'
                              : 'Publish publicly',
                        ),
                      ),
                    ]);
                  }
                  return items;
                },
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load list: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: ShoppaColors.rose),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _pullToRefresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final list = snapshot.data!;
          final rawItems = list.items ?? [];
          final progress = listProgress(rawItems);
          final searchMatched = filterListItems(rawItems, _searchQuery);
          final filtered = applyItemViewFilter(searchMatched, _itemFilter);
          // Aisle walk order only when not sorting A–Z.
          final useAisle = _shopMode &&
              _aisleOrder &&
              _itemOrder == ItemOrderMode.manual &&
              _searchQuery.trim().isEmpty &&
              _itemFilter != ItemViewFilter.checked;
          final items = useAisle
              ? filtered
              : itemsForDisplay(
                  filtered,
                  shopMode: _shopMode,
                  order: _itemOrder,
                );
          final aisleSections = useAisle
              ? shopAisleSections(
                  filtered,
                  includeChecked: _itemFilter == ItemViewFilter.all,
                  separateChecked: _itemFilter == ItemViewFilter.all,
                  layout: _activeAisleLayout,
                )
              : null;
          final checkedCount =
              rawItems.where((i) => i.checked).length;
          final remainingCount = rawItems.length - checkedCount;
          final showStoreNudge = !_dismissedStoreNudge &&
              list.canEdit &&
              rawItems.isNotEmpty &&
              _shoppingAtStoreName == null;
          final allowReorder = list.canEdit &&
              !_shopMode &&
              !_selectMode &&
              _searchQuery.trim().isEmpty &&
              _itemOrder == ItemOrderMode.manual &&
              _itemFilter == ItemViewFilter.all;
          return RefreshIndicator(
            onRefresh: _pullToRefresh,
            child: Column(
            children: [
              if (!_shopMode)
                PresenceBanner(
                  editorEmails: _activeEditors.values.toList(),
                  connected:
                      _connectionState == RealtimeConnectionState.connected,
                ),
              if (list.fromCache)
                _InfoBanner(
                  text:
                      'Offline — showing the last synced version of this list.',
                  color: ShoppaColors.amber,
                )
              else if (_pendingCount > 0)
                _InfoBanner(
                  text: _pendingCount == 1
                      ? '1 change waiting to sync.'
                      : '$_pendingCount changes waiting to sync.',
                  color: ShoppaColors.amber,
                ),
              if (!list.isOwner && !_shopMode)
                _InfoBanner(
                  text: list.canEdit
                      ? 'Shared with you — you can edit this list.'
                      : 'Shared with you — view only.',
                  color: ShoppaColors.mist,
                ),
              _buildProgressStrip(list, progress),
              if (!_shopFocusActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search items…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                    ),
                  ),
                ),
              if (!_shopFocusActive && rawItems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: Text('All (${rawItems.length})'),
                          selected: _itemFilter == ItemViewFilter.all,
                          onSelected: (_) => setState(
                            () => _itemFilter = ItemViewFilter.all,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text('Left ($remainingCount)'),
                          selected: _itemFilter == ItemViewFilter.remaining,
                          onSelected: (_) => setState(
                            () => _itemFilter = ItemViewFilter.remaining,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text('Checked ($checkedCount)'),
                          selected: _itemFilter == ItemViewFilter.checked,
                          onSelected: (_) => setState(
                            () => _itemFilter = ItemViewFilter.checked,
                          ),
                        ),
                        if (_itemOrder == ItemOrderMode.name) ...[
                          const SizedBox(width: 8),
                          InputChip(
                            avatar: const Icon(Icons.sort_by_alpha, size: 16),
                            label: const Text('A–Z'),
                            onPressed: _cycleItemOrder,
                            onDeleted: _cycleItemOrder,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (_shopMode && !_shopFocusActive && _searchQuery.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _itemOrder == ItemOrderMode.name
                          ? 'Sorted A–Z · swipe right to check'
                          : (_aisleOrder
                              ? 'Sorted by aisle · swipe right to check'
                              : 'Swipe right to check · tap qty for presets'),
                      style: const TextStyle(
                        color: ShoppaColors.mist,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              if (_shopFocusActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      remainingCount == 0
                          ? 'All done · swipe or tap to uncheck'
                          : '$remainingCount left · swipe right to check',
                      style: const TextStyle(
                        color: ShoppaColors.mist,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (showStoreNudge && !_shopFocusActive)
                Material(
                  color: ShoppaColors.amber.withOpacity(0.12),
                  child: InkWell(
                    onTap: _pickShoppingAtStore,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Set store for aisle walk order',
                              style: TextStyle(
                                color: ShoppaColors.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _dismissedStoreNudge = true),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: ShoppaColors.mist,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!_shopMode)
                FutureBuilder<AdPlacement?>(
                  future: _listBanner,
                  builder: (context, adSnapshot) {
                    final banner = adSnapshot.data;
                    if (banner == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: AdBanner(
                        placement: banner,
                        adsRepository: widget.adsRepository,
                      ),
                    );
                  },
                ),
              if (_shoppingAtStoreName != null)
                Material(
                  color: ShoppaColors.panel2.withOpacity(0.6),
                  child: InkWell(
                    onTap: _pickShoppingAtStore,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                          if (!isCatalogueStoreId(_shoppingAtStoreId))
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text(
                                'aisles',
                                style: TextStyle(
                                  color: ShoppaColors.mist,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          GestureDetector(
                            onTap: _clearShoppingAtStore,
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: ShoppaColors.mist,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_shopMode &&
                  _aisleOrder &&
                  _itemOrder == ItemOrderMode.manual)
                Material(
                  color: ShoppaColors.panel2.withOpacity(0.35),
                  child: InkWell(
                    onTap: _pickAisleLayout,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.route_outlined,
                            size: 16,
                            color: ShoppaColors.amber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _aisleLayoutId == null
                                  ? 'Walk order: ${_activeAisleLayout.label} (auto)'
                                  : 'Walk order: ${_activeAisleLayout.label}',
                              style: const TextStyle(
                                color: ShoppaColors.mist,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.expand_more,
                            size: 16,
                            color: ShoppaColors.mist,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: rawItems.isEmpty
                    ? _buildEmptyItems(list)
                    : searchMatched.isEmpty
                        ? _buildNoSearchMatches()
                        : filtered.isEmpty
                            ? _buildEmptyFilterState(
                                remainingCount: remainingCount,
                                checkedCount: checkedCount,
                              )
                        : aisleSections != null
                            ? CustomScrollView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 8),
                                  ),
                                  for (final section in aisleSections)
                                    ..._listAisleSlivers(
                                      section: section,
                                      list: list,
                                    ),
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 8),
                                  ),
                                ],
                              )
                            : allowReorder
                                ? ReorderableListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
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
                                        // Non-null enables swipe-to-delete + Undo.
                                        onDismissed: () {},
                                      );
                                    },
                                  )
                                : ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
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
                                        onDismissed: list.canEdit && !_shopMode
                                            ? () {}
                                            : null,
                                      );
                                    },
                                  ),
              ),
              if (list.canEdit && !_shopMode && !_selectMode) ...[
                Builder(
                  builder: (context) {
                    final onList = (list.items ?? [])
                        .map((i) => i.name.toLowerCase())
                        .toSet();
                    final chips = _recentNames
                        .where((n) => !onList.contains(n.toLowerCase()))
                        .toList();
                    if (chips.isEmpty) return const SizedBox.shrink();
                    return SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      itemCount: chips.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final name = chips[index];
                        return ActionChip(
                          label: Text(name),
                          onPressed: _quickAddBusy
                              ? null
                              : () async {
                                  setState(() => _quickAddBusy = true);
                                  try {
                                    await _addOrMergeItem(name: name);
                                    await _rememberNames([name]);
                                    _reload();
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Could not add: $e'),
                                        backgroundColor: ShoppaColors.rose,
                                      ),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _quickAddBusy = false);
                                    }
                                  }
                                },
                        );
                      },
                    ),
                  );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _quickAddController,
                    focusNode: _quickAddFocus,
                    enabled: !_quickAddBusy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _quickAddSubmit(),
                    decoration: InputDecoration(
                      hintText: 'Quick add… e.g. 2x Milk',
                      prefixIcon:
                          const Icon(Icons.add_circle_outline, size: 20),
                      isDense: true,
                      suffixIcon: _quickAddBusy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Add',
                              icon: const Icon(Icons.send, size: 20),
                              onPressed: _quickAddSubmit,
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          );
        },
      ),
      floatingActionButton: FutureBuilder<ShoppaList>(
        future: _list,
        builder: (context, snapshot) {
          final list = snapshot.data;
          if (list == null || !list.canEdit || _shopMode || _selectMode) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton(
            onPressed: _showAddMenu,
            backgroundColor: ShoppaColors.amber,
            tooltip: 'Add items',
            child: const Icon(Icons.add, color: Colors.white),
          );
        },
      ),
      bottomNavigationBar: _buildSelectBar(),
    );
  }
}

/// Collaborator management sheet (SRS FR-3.1). Anyone on the list can see
/// who else is on it; owner can invite/remove/change permission; a
/// collaborator can leave themselves.
class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.listsRepository,
    required this.listId,
    required this.canManage,
    this.currentUserEmail,
    this.realtimeEvents,
  });

  final ListsRepository listsRepository;
  final String listId;
  final bool canManage;
  final String? currentUserEmail;
  final Stream<ListRealtimeEvent>? realtimeEvents;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late Future<List<ShoppaCollaborator>> _collaborators;
  final _emailController = TextEditingController();
  String _permission = 'view';
  String? _error;
  StreamSubscription<ListRealtimeEvent>? _collaboratorEvents;

  @override
  void initState() {
    super.initState();
    _collaborators = widget.listsRepository.fetchCollaborators(widget.listId);
    _collaboratorEvents = widget.realtimeEvents
        ?.where(
          (e) =>
              e.event == 'collaborator.joined' ||
              e.event == 'collaborator.removed' ||
              e.event == 'collaborator.updated',
        )
        .listen((_) => _reload());
  }

  @override
  void dispose() {
    _collaboratorEvents?.cancel();
    _emailController.dispose();
    super.dispose();
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
      final result = await widget.listsRepository.shareList(
        widget.listId,
        email: email,
        permission: _permission,
      );
      _emailController.clear();
      _reload();
      if (mounted && result.isPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Invite sent to ${result.userEmail}. They’ll join when they sign up.',
            ),
            backgroundColor: ShoppaColors.panel2,
          ),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _remove(ShoppaCollaborator c) async {
    try {
      if (c.isPending) {
        await widget.listsRepository.cancelInvite(widget.listId, c.id);
      } else if (c.userId != null) {
        await widget.listsRepository.removeCollaborator(
          widget.listId,
          c.userId!,
        );
      }
      _reload();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _setPermission(ShoppaCollaborator c, String permission) async {
    if (c.permission == permission || c.isPending || c.userId == null) return;
    try {
      await widget.listsRepository.updateCollaboratorPermission(
        widget.listId,
        c.userId!,
        permission: permission,
      );
      _reload();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _leave(ShoppaCollaborator me) async {
    if (me.userId == null) return;
    try {
      await widget.listsRepository.leaveList(widget.listId, me.userId!);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myEmail = widget.currentUserEmail?.toLowerCase();
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
                children: collaborators.map((c) {
                  final isMe = !c.isPending &&
                      myEmail != null &&
                      c.userEmail.toLowerCase() == myEmail;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.userEmail),
                    subtitle: Text(
                      c.isPending
                          ? 'Pending · ${c.permission} (waiting for signup)'
                          : c.permission,
                      style: TextStyle(
                        color: c.isPending
                            ? ShoppaColors.amber
                            : ShoppaColors.mist,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.canManage && !c.isPending)
                          DropdownButton<String>(
                            value: c.permission,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                value: 'view',
                                child: Text('View'),
                              ),
                              DropdownMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) _setPermission(c, value);
                            },
                          ),
                        if (widget.canManage)
                          IconButton(
                            tooltip: c.isPending ? 'Cancel invite' : 'Remove',
                            icon: const Icon(
                              Icons.close,
                              color: ShoppaColors.rose,
                            ),
                            onPressed: () => _remove(c),
                          )
                        else if (isMe)
                          TextButton(
                            onPressed: () => _leave(c),
                            child: const Text('Leave'),
                          ),
                      ],
                    ),
                  );
                }).toList(),
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
                      helperText: 'Works even if they don’t have Shoppa yet',
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
                child: const Text('Share / invite'),
              ),
            ),
          ] else if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
          ],
        ],
      ),
    );
  }
}

/// Read-only activity feed (SRS FR-3.3).
class _ActivitySheet extends StatefulWidget {
  const _ActivitySheet({required this.listsRepository, required this.listId});

  final ListsRepository listsRepository;
  final String listId;

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  late Future<List<ShoppaActivityEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _entries = widget.listsRepository.fetchActivity(widget.listId);
  }

  void _reload() =>
      setState(() => _entries = widget.listsRepository.fetchActivity(widget.listId));

  static const _labels = {
    'item_added': 'added an item',
    'item_updated': 'updated an item',
    'item_checked': 'checked off an item',
    'item_removed': 'removed an item',
    'collaborator_joined': 'shared this list',
    'collaborator_removed': 'removed a collaborator',
    'list_scaled': 'scaled this list',
    'list_created': 'created this list',
    'list_updated': 'updated this list',
    'list_published': 'published this list',
    'list_unpublished': 'unpublished this list',
  };

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Activity',
                  style: TextStyle(
                    color: ShoppaColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _reload,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: FutureBuilder<List<ShoppaActivityEntry>>(
              future: _entries,
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
                          TextSpan(
                            text: ' · ${_formatTime(entry.createdAt)}',
                            style: const TextStyle(
                              color: ShoppaColors.faint,
                              fontSize: 11,
                            ),
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

/// Per-list chat thread (SRS FR-3.4).
class _ChatSheet extends StatefulWidget {
  const _ChatSheet({
    required this.listsRepository,
    required this.chatClient,
    required this.listId,
    this.currentUserEmail,
  });

  final ListsRepository listsRepository;
  final ListChatClient chatClient;
  final String listId;
  final String? currentUserEmail;

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  late Future<List<ShoppaChatMessage>> _messages;
  final _controller = TextEditingController();
  StreamSubscription<ListChatEvent>? _subscription;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messages = widget.listsRepository.fetchMessages(widget.listId);
    _subscription = widget.chatClient.connect(widget.listId).listen((event) {
      if (event.event == 'message.created' && mounted) _reload();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _reload() =>
      setState(() => _messages = widget.listsRepository.fetchMessages(widget.listId));

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    setState(() => _error = null);
    try {
      await widget.listsRepository.sendMessage(widget.listId, body);
      _controller.clear();
      _reload();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
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
            'Chat',
            style: TextStyle(
              color: ShoppaColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: FutureBuilder<List<ShoppaChatMessage>>(
              future: _messages,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Text(
                    'No messages yet — say hi to your collaborators.',
                    style: TextStyle(color: ShoppaColors.mist),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: messages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMine = msg.authorEmail == widget.currentUserEmail;
                    return Align(
                      alignment:
                          isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? ShoppaColors.amber.withOpacity(0.18)
                              : ShoppaColors.panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ShoppaColors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMine)
                              Text(
                                msg.authorEmail.split('@').first,
                                style: const TextStyle(
                                  color: ShoppaColors.mist,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              msg.body,
                              style: const TextStyle(color: ShoppaColors.ink),
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
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Message…'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _send,
                icon: const Icon(Icons.send, color: ShoppaColors.amber),
              ),
            ],
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
  const _ComparisonSheet({
    required this.adsRepository,
    required this.listsRepository,
    required this.listId,
  });

  final AdsRepository adsRepository;
  final ListsRepository listsRepository;
  final String listId;

  String _formatMoney(int minorUnits, String currencyCode) {
    final symbol = currencyCode == 'ZAR' ? 'R' : '$currencyCode ';
    return '$symbol${(minorUnits / 100).toStringAsFixed(2)}';
  }

  Future<_ComparisonPayload> _loadComparisonPayload() async {
    final comparison = await listsRepository.fetchComparison(listId);
    AdPlacement? nativeAd;
    try {
      final ads = await adsRepository.fetchPlacements(
        surface: 'list',
        adFormat: 'native',
      );
      if (ads.placements.isNotEmpty) nativeAd = ads.placements.first;
    } catch (_) {}
    return _ComparisonPayload(comparison: comparison, nativeAd: nativeAd);
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
            child: FutureBuilder<_ComparisonPayload>(
              future: _loadComparisonPayload(),
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
                final payload = snapshot.data!;
                final comparison = payload.comparison;
                final nativeAd = payload.nativeAd;
                if (comparison.isEmpty) {
                  return const Text(
                    'Not enough priced items on this list yet to compare '
                    'stores.',
                    style: TextStyle(color: ShoppaColors.mist),
                  );
                }
                final itemCount =
                    comparison.stores.length + (nativeAd != null ? 1 : 0);
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: itemCount,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    if (nativeAd != null && index == 1) {
                      return AdNativeTile(
                        placement: nativeAd,
                        adsRepository: adsRepository,
                      );
                    }
                    var storeIndex = index;
                    if (nativeAd != null && index > 1) storeIndex -= 1;
                    final store = comparison.stores[storeIndex];
                    final isBest = store.storeId == comparison.bestStoreId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Navigator.of(context).pop(store),
                      title: Text(
                        store.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            ConfidenceChip(
                              confidence: store.confidence,
                              compact: true,
                            ),
                            if (isBest &&
                                comparison.bestSaves != null &&
                                comparison.bestSaves! > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                'saves ${_formatMoney(comparison.bestSaves!, comparison.currencyCode)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: ShoppaColors.mist,
                                ),
                              ),
                            ],
                          ],
                        ),
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

/// Pinned aisle label while scrolling shop mode (stays under the app bar).
class _AisleStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _AisleStickyHeaderDelegate({
    required this.label,
    required this.countLabel,
    required this.collapsed,
    this.onToggle,
    this.onCheckOffAisle,
  });

  final String label;
  final String countLabel;
  final bool collapsed;
  final VoidCallback? onToggle;
  /// Bulk check-off for remaining items in this aisle.
  final VoidCallback? onCheckOffAisle;

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
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 18,
                color: ShoppaColors.mist,
              ),
              const SizedBox(width: 2),
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
  bool shouldRebuild(covariant _AisleStickyHeaderDelegate oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.countLabel != countLabel ||
        oldDelegate.collapsed != collapsed ||
        oldDelegate.onToggle != onToggle ||
        oldDelegate.onCheckOffAisle != onCheckOffAisle;
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

class _ComparisonPayload {
  const _ComparisonPayload({required this.comparison, this.nativeAd});

  final ShoppaComparison comparison;
  final AdPlacement? nativeAd;
}
