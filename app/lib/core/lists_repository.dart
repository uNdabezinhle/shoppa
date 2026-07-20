/// Wraps the Shopping Lists endpoints (API Specification §6.1/6.2, SRS
/// §3.2) for use by the Mall (home) and List screens. Also implements the
/// offline cache + mutation queue behind FR-4.2 -- see OfflineStore and
/// syncPending() below.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'api_client.dart';
import 'offline_store.dart';

class ShoppaListItem {
  ShoppaListItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.note,
    required this.checked,
    this.productId,
    this.paidPrice,
    this.hasPromotion = false,
  });

  factory ShoppaListItem.fromJson(Map<String, dynamic> json) => ShoppaListItem(
        id: json['id'] as String,
        name: json['name'] as String,
        quantity: num.parse(json['quantity'].toString()),
        unit: json['unit'] as String? ?? 'ea',
        note: json['note'] as String? ?? '',
        checked: json['checked'] as bool? ?? false,
        productId: json['product_id'] as String?,
        paidPrice: json['paid_price'] as int?,
        hasPromotion: json['has_promotion'] as bool? ?? false,
      );

  final String id;
  final String name;
  final num quantity;
  final String unit;
  final String note;
  final bool checked;
  final String? productId;
  final int? paidPrice;
  /// SRS FR-7.2: a live, non-opted-out promotion matches this item's
  /// product. False for free-text items (no product_id) by definition.
  final bool hasPromotion;
}

class ShoppaCollaboratorPreview {
  ShoppaCollaboratorPreview({
    required this.userId,
    required this.email,
    required this.initials,
  });

  factory ShoppaCollaboratorPreview.fromJson(Map<String, dynamic> json) =>
      ShoppaCollaboratorPreview(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        initials: json['initials'] as String,
      );

  final String userId;
  final String email;
  final String initials;
}

class ShoppaChatMessage {
  ShoppaChatMessage({
    required this.id,
    required this.authorId,
    required this.authorEmail,
    required this.body,
    required this.createdAt,
  });

  factory ShoppaChatMessage.fromJson(Map<String, dynamic> json) =>
      ShoppaChatMessage(
        id: json['id'] as String,
        authorId: json['author_id'] as String,
        authorEmail: json['author_email'] as String,
        body: json['body'] as String,
        createdAt: json['created_at'] as String,
      );

  final String id;
  final String authorId;
  final String authorEmail;
  final String body;
  final String createdAt;
}

class ListExportResult {
  ListExportResult({
    required this.bytes,
    required this.contentType,
    required this.filename,
    this.textPreview,
  });

  final Uint8List bytes;
  final String contentType;
  final String filename;
  final String? textPreview;
}

class ShoppaList {
  ShoppaList({
    required this.id,
    required this.title,
    required this.category,
    required this.isRecurring,
    required this.itemCount,
    this.isPublic = false,
    this.eventName = '',
    this.eventDate,
    this.role,
    this.collaborators = const [],
    this.items,
    this.fromCache = false,
  });

  factory ShoppaList.fromJson(Map<String, dynamic> json, {bool fromCache = false}) =>
      ShoppaList(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String,
        isRecurring: json['is_recurring'] as bool? ?? false,
        itemCount: json['item_count'] as int? ?? 0,
        isPublic: json['is_public'] as bool? ?? false,
        eventName: json['event_name'] as String? ?? '',
        eventDate: json['event_date'] as String?,
        role: json['role'] as String?,
        collaborators: (json['collaborators'] as List? ?? [])
            .map((e) =>
                ShoppaCollaboratorPreview.fromJson(e as Map<String, dynamic>))
            .toList(),
        items: json['items'] != null
            ? (json['items'] as List)
                .map((e) => ShoppaListItem.fromJson(e as Map<String, dynamic>))
                .toList()
            : null,
        fromCache: fromCache,
      );

  final String id;
  final String title;
  final String category;
  final bool isRecurring;
  final int itemCount;
  final bool isPublic;
  final String eventName;
  final String? eventDate;
  final List<ShoppaCollaboratorPreview> collaborators;
  /// "owner", "edit", or "view" (API Specification role field, SRS
  /// FR-3.1) -- null only if the server response omitted it.
  final String? role;
  final List<ShoppaListItem>? items;
  /// True when this came from the offline cache rather than a live
  /// request (SRS FR-4.2) -- lets the UI show an "offline" indicator.
  final bool fromCache;

  bool get canEdit => role == 'owner' || role == 'edit';
  bool get isOwner => role == 'owner';
}

class ShoppaCollaborator {
  ShoppaCollaborator({
    required this.userId,
    required this.userEmail,
    required this.permission,
  });

  factory ShoppaCollaborator.fromJson(Map<String, dynamic> json) =>
      ShoppaCollaborator(
        userId: json['user_id'] as String,
        userEmail: json['user_email'] as String,
        permission: json['permission'] as String,
      );

  final String userId;
  final String userEmail;
  final String permission;
}

class ShoppaActivityEntry {
  ShoppaActivityEntry({
    required this.action,
    required this.detail,
    required this.createdAt,
    this.actorEmail,
  });

  factory ShoppaActivityEntry.fromJson(Map<String, dynamic> json) =>
      ShoppaActivityEntry(
        action: json['action'] as String,
        detail: json['detail'] as String? ?? '',
        createdAt: json['created_at'] as String,
        actorEmail: json['actor_email'] as String?,
      );

  final String action;
  final String detail;
  final String createdAt;
  final String? actorEmail;
}

class ShoppaStoreComparison {
  ShoppaStoreComparison({
    required this.storeId,
    required this.name,
    required this.total,
    required this.confidence,
  });

  factory ShoppaStoreComparison.fromJson(Map<String, dynamic> json) =>
      ShoppaStoreComparison(
        storeId: json['store_id'] as String,
        name: json['name'] as String,
        total: json['total'] as int,
        confidence: json['confidence'] as String,
      );

  final String storeId;
  final String name;
  final int total;
  final String confidence;
}

/// GET /lists/{id}/comparison (SRS FR-5.3, API Specification §6.4).
class ShoppaComparison {
  ShoppaComparison({
    required this.currencyCode,
    required this.stores,
    this.bestStoreId,
    this.bestSaves,
  });

  factory ShoppaComparison.fromJson(Map<String, dynamic> json) {
    final best = json['best'] as Map<String, dynamic>?;
    return ShoppaComparison(
      currencyCode: json['currency_code'] as String? ?? 'ZAR',
      stores: (json['stores'] as List? ?? [])
          .map((e) => ShoppaStoreComparison.fromJson(e as Map<String, dynamic>))
          .toList(),
      bestStoreId: best?['store_id'] as String?,
      bestSaves: best?['saves'] as int?,
    );
  }

  final String currencyCode;
  final List<ShoppaStoreComparison> stores;
  final String? bestStoreId;
  final int? bestSaves;

  bool get isEmpty => stores.isEmpty;
}

/// GET /promotions (SRS FR-7.1, API Specification §6.6).
class ShoppaPromotion {
  ShoppaPromotion({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.productName,
    required this.category,
    required this.title,
    required this.description,
  });

  factory ShoppaPromotion.fromJson(Map<String, dynamic> json) => ShoppaPromotion(
        id: json['id'] as String,
        storeId: json['store_id'] as String,
        storeName: json['store_name'] as String,
        productName: json['product_name'] as String,
        category: json['category'] as String? ?? '',
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
      );

  final String id;
  final String storeId;
  final String storeName;
  final String productName;
  final String category;
  final String title;
  final String description;
}

class ListsRepository {
  ListsRepository(this._client, {OfflineStore? offlineStore})
      : _offlineStore = offlineStore ?? InMemoryOfflineStore();

  final ApiClient _client;
  final OfflineStore _offlineStore;

  Future<List<ShoppaList>> fetchLists() async {
    try {
      final json = await _client.get('/lists') as Map<String, dynamic>;
      final results = json['results'] as List;
      final maps = results
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      await _offlineStore.cacheListsIndex(maps);
      return maps
          .map((e) => ShoppaList.fromJson(e))
          .toList(growable: false);
    } on NetworkUnavailableException {
      final cached = await _offlineStore.getCachedListsIndex();
      if (cached == null) rethrow;
      return cached
          .map((e) => ShoppaList.fromJson(e, fromCache: true))
          .toList(growable: false);
    }
  }

  /// SRS FR-4.2: falls back to the last cached detail response when the
  /// network is unavailable, rather than failing outright -- the list
  /// stays fully viewable/usable in-store without connectivity.
  Future<ShoppaList> fetchListDetail(String listId) async {
    try {
      final json = await _client.get('/lists/$listId') as Map<String, dynamic>;
      await _offlineStore.cacheListJson(listId, json);
      return ShoppaList.fromJson(json);
    } on NetworkUnavailableException {
      final cached = await _offlineStore.getCachedListJson(listId);
      if (cached == null) rethrow;
      return ShoppaList.fromJson(cached, fromCache: true);
    }
  }

  Future<ShoppaList> createList({
    required String title,
    String category = 'custom',
    bool isRecurring = false,
  }) async {
    final json = await _client.post('/lists', {
      'title': title,
      'category': category,
      'is_recurring': isRecurring,
    }, authenticated: true) as Map<String, dynamic>;
    return ShoppaList.fromJson(json);
  }

  /// SRS FR-4.2: queues the add locally (with an optimistic local id) when
  /// offline, instead of failing -- it's synced via syncPending() once
  /// connectivity returns.
  Future<ShoppaListItem> addItem(
    String listId, {
    required String name,
    num quantity = 1,
    String unit = 'ea',
    String note = '',
    String? productId,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'note': note,
      if (productId != null) 'product_id': productId,
    };
    try {
      final json = await _client.post('/lists/$listId/items', payload,
          authenticated: true) as Map<String, dynamic>;
      return ShoppaListItem.fromJson(json);
    } on NetworkUnavailableException {
      return _queueAddItem(listId, payload);
    }
  }

  /// SRS FR-4.2/FR-4.3: queues the check-off (with its paid price, if
  /// given) locally when offline. [clientUpdatedAt] lets a caller pin the
  /// moment the user actually made the change (used when replaying a
  /// queued mutation in syncPending) rather than "now". [storeId] --
  /// which store this was paid at -- is forwarded so the server can
  /// record an implicit price observation (SRS FR-5.4); omit it if the
  /// user hasn't picked a store for this shopping session.
  Future<ShoppaListItem> setItemChecked(
    String listId,
    String itemId, {
    required bool checked,
    int? paidPrice,
    String? storeId,
    DateTime? clientUpdatedAt,
  }) async {
    final now = clientUpdatedAt ?? DateTime.now().toUtc();
    final body = <String, dynamic>{'checked': checked};
    if (paidPrice != null) body['paid_price'] = paidPrice;
    if (storeId != null) body['store_id'] = storeId;
    if (clientUpdatedAt != null) {
      body['client_updated_at'] = now.toIso8601String();
    }
    try {
      final json =
          await _client.patch('/lists/$listId/items/$itemId', body)
              as Map<String, dynamic>;
      await _replaceItemInCache(listId, itemId, json);
      return ShoppaListItem.fromJson(json);
    } on NetworkUnavailableException {
      return _queueCheckItem(
        listId,
        itemId,
        checked: checked,
        paidPrice: paidPrice,
        storeId: storeId,
        clientUpdatedAt: now,
      );
    }
  }

  /// SRS FR-5.3: per-store totals and suggested savings for this list,
  /// in the user's region.
  Future<ShoppaComparison> fetchComparison(String listId) async {
    final json = await _client.get('/lists/$listId/comparison')
        as Map<String, dynamic>;
    return ShoppaComparison.fromJson(json);
  }

  Future<ShoppaList> updateList(
    String listId, {
    String? title,
    String? category,
    bool? isRecurring,
    bool? isPublic,
    String? eventName,
    String? eventDate,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (category != null) body['category'] = category;
    if (isRecurring != null) body['is_recurring'] = isRecurring;
    if (isPublic != null) body['is_public'] = isPublic;
    if (eventName != null) body['event_name'] = eventName;
    if (eventDate != null) body['event_date'] = eventDate;
    final json =
        await _client.patch('/lists/$listId', body) as Map<String, dynamic>;
    return ShoppaList.fromJson(json);
  }

  /// FR-8.1: scale all item quantities by guest count or factor.
  Future<ShoppaList> scaleList(
    String listId, {
    int? guests,
    num? factor,
  }) async {
    final body = <String, dynamic>{};
    if (guests != null) body['guests'] = guests;
    if (factor != null) body['factor'] = factor;
    final json = await _client.post('/lists/$listId/scale', body)
        as Map<String, dynamic>;
    return ShoppaList.fromJson(json);
  }

  /// FR-8.2: published lists from other users.
  Future<List<ShoppaList>> fetchPublicLists() async {
    final json = await _client.get('/lists/public') as Map<String, dynamic>;
    return (json['results'] as List)
        .map((e) => ShoppaList.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// FR-8.2: clone a list the caller can access (including public).
  Future<ShoppaList> duplicateList(String listId) async {
    final json = await _client.post('/lists/$listId/duplicate', {})
        as Map<String, dynamic>;
    return ShoppaList.fromJson(json);
  }

  /// FR-8.4: export list as CSV or PDF bytes.
  Future<ListExportResult> exportList(
    String listId, {
    String type = 'csv',
    String? title,
  }) async {
    final bytes = await _client.download(
      '/lists/$listId/export',
      queryParameters: {'type': type},
    );
    final contentType = type == 'pdf' ? 'application/pdf' : 'text/csv';
    final base = (title == null || title.trim().isEmpty)
        ? 'list-export'
        : title.trim().replaceAll(RegExp(r'[^\w.\- ]+'), '_');
    return ListExportResult(
      bytes: bytes,
      contentType: contentType,
      filename: '$base.$type',
      textPreview: type == 'csv' ? utf8.decode(bytes) : null,
    );
  }

  Future<void> deleteList(String listId) {
    return _client.delete('/lists/$listId');
  }

  Future<ShoppaListItem> updateItem(
    String listId,
    String itemId, {
    String? name,
    num? quantity,
    String? unit,
    String? note,
    int? position,
    DateTime? clientUpdatedAt,
  }) async {
    final now = clientUpdatedAt ?? DateTime.now().toUtc();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (quantity != null) body['quantity'] = quantity;
    if (unit != null) body['unit'] = unit;
    if (note != null) body['note'] = note;
    if (position != null) body['position'] = position;
    if (clientUpdatedAt != null) {
      body['client_updated_at'] = now.toIso8601String();
    }
    try {
      final json = await _client.patch('/lists/$listId/items/$itemId', body)
          as Map<String, dynamic>;
      await _replaceItemInCache(listId, itemId, json);
      return ShoppaListItem.fromJson(json);
    } on NetworkUnavailableException {
      return _queueUpdateItem(listId, itemId, body, now);
    }
  }

  Future<void> deleteItem(String listId, String itemId) async {
    try {
      await _client.delete('/lists/$listId/items/$itemId');
      await _removeItemFromCache(listId, itemId);
    } on NetworkUnavailableException {
      await _queueDeleteItem(listId, itemId);
    }
  }

  /// Reorders items by PATCHing each item's position (FR-2.2).
  Future<void> reorderItems(String listId, List<String> orderedItemIds) async {
    final now = DateTime.now().toUtc();
    try {
      for (var i = 0; i < orderedItemIds.length; i++) {
        await _client.patch('/lists/$listId/items/${orderedItemIds[i]}', {
          'position': i,
        });
      }
    } on NetworkUnavailableException {
      await _offlineStore.enqueue(QueuedMutation(
        id: _generateLocalId(),
        listId: listId,
        type: 'reorder_items',
        payload: {'positions': orderedItemIds},
        clientUpdatedAt: now.toIso8601String(),
      ));
      await _reorderCache(listId, orderedItemIds);
    }
  }

  /// Replays this list's queued offline mutations against the real API,
  /// in the order they were made (SRS FR-4.2). Stops -- without throwing
  /// -- at the first mutation that still can't reach the network, so a
  /// flaky reconnect doesn't lose track of what's left to sync. A
  /// mutation the server rejects outright (ApiException -- e.g. the list
  /// was deleted meanwhile) is dropped rather than retried forever.
  /// Returns how many mutations were successfully synced.
  Future<int> syncPending(String listId) async {
    final pending = await _offlineStore.pendingFor(listId);
    var synced = 0;
    for (final mutation in pending) {
      try {
        if (mutation.type == 'add_item') {
          await _client.post(
            '/lists/$listId/items',
            mutation.payload,
            authenticated: true,
          );
        } else if (mutation.type == 'check_item' && mutation.itemId != null) {
          await _client.patch(
            '/lists/$listId/items/${mutation.itemId}',
            mutation.payload,
          );
        } else if (mutation.type == 'update_item' && mutation.itemId != null) {
          await _client.patch(
            '/lists/$listId/items/${mutation.itemId}',
            mutation.payload,
          );
        } else if (mutation.type == 'delete_item' && mutation.itemId != null) {
          await _client.delete('/lists/$listId/items/${mutation.itemId}');
        } else if (mutation.type == 'reorder_items') {
          final ids = (mutation.payload['positions'] as List).cast<String>();
          for (var i = 0; i < ids.length; i++) {
            await _client.patch('/lists/$listId/items/${ids[i]}', {
              'position': i,
            });
          }
        }
        await _offlineStore.remove(mutation.id);
        synced++;
      } on NetworkUnavailableException {
        break;
      } on ApiException {
        await _offlineStore.remove(mutation.id);
      }
    }
    return synced;
  }

  Future<int> pendingCount(String listId) async {
    return (await _offlineStore.pendingFor(listId)).length;
  }

  Future<ShoppaListItem> _queueAddItem(
    String listId,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc();
    final localId = _generateLocalId();
    final optimisticJson = <String, dynamic>{
      'id': localId,
      'product_id': null,
      'name': payload['name'],
      'quantity': payload['quantity'].toString(),
      'unit': payload['unit'],
      'note': payload['note'],
      'checked': false,
      'paid_price': null,
      'created_at': now.toIso8601String(),
    };
    await _offlineStore.enqueue(QueuedMutation(
      id: _generateLocalId(),
      listId: listId,
      itemId: localId,
      type: 'add_item',
      payload: payload,
      clientUpdatedAt: now.toIso8601String(),
    ));
    await _appendItemToCache(listId, optimisticJson);
    return ShoppaListItem.fromJson(optimisticJson);
  }

  Future<ShoppaListItem> _queueCheckItem(
    String listId,
    String itemId, {
    required bool checked,
    int? paidPrice,
    String? storeId,
    required DateTime clientUpdatedAt,
  }) async {
    final payload = <String, dynamic>{
      'checked': checked,
      if (paidPrice != null) 'paid_price': paidPrice,
      if (storeId != null) 'store_id': storeId,
      'client_updated_at': clientUpdatedAt.toIso8601String(),
    };
    await _offlineStore.enqueue(QueuedMutation(
      id: _generateLocalId(),
      listId: listId,
      itemId: itemId,
      type: 'check_item',
      payload: payload,
      clientUpdatedAt: clientUpdatedAt.toIso8601String(),
    ));
    final optimistic = await _mergeItemInCache(listId, itemId, {
      'checked': checked,
      if (paidPrice != null) 'paid_price': paidPrice,
    });
    return optimistic ??
        ShoppaListItem(
          id: itemId,
          name: '',
          quantity: 1,
          unit: 'ea',
          note: '',
          checked: checked,
          paidPrice: paidPrice,
        );
  }

  Future<void> _appendItemToCache(
    String listId,
    Map<String, dynamic> itemJson,
  ) async {
    final cached = await _offlineStore.getCachedListJson(listId);
    if (cached == null) return;
    final items =
        ((cached['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    final updated = Map<String, dynamic>.from(cached);
    updated['items'] = [...items, itemJson];
    updated['item_count'] = (cached['item_count'] as int? ?? items.length) + 1;
    await _offlineStore.cacheListJson(listId, updated);
  }

  Future<void> _replaceItemInCache(
    String listId,
    String itemId,
    Map<String, dynamic> itemJson,
  ) async {
    await _rewriteItemInCache(listId, itemId, (_) => itemJson);
  }

  Future<ShoppaListItem?> _mergeItemInCache(
    String listId,
    String itemId,
    Map<String, dynamic> fields,
  ) async {
    return _rewriteItemInCache(listId, itemId, (item) => {...item, ...fields});
  }

  /// Shared plumbing for both cache-update paths above: finds [itemId]
  /// inside the cached list detail (if any) and replaces it with
  /// whatever [transform] returns, then writes the cache back. Returns
  /// the resulting item, or null if there's no cache or the item isn't
  /// in it yet (e.g. it was itself added while offline and hasn't been
  /// through a successful fetch since).
  Future<ShoppaListItem?> _rewriteItemInCache(
    String listId,
    String itemId,
    Map<String, dynamic> Function(Map<String, dynamic> item) transform,
  ) async {
    final cached = await _offlineStore.getCachedListJson(listId);
    if (cached == null) return null;
    final items =
        ((cached['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    Map<String, dynamic>? updatedItemJson;
    final updatedItems = items.map((item) {
      if (item['id'] != itemId) return item;
      final merged = transform(item);
      updatedItemJson = merged;
      return merged;
    }).toList();
    if (updatedItemJson == null) return null;
    final updatedList = Map<String, dynamic>.from(cached);
    updatedList['items'] = updatedItems;
    await _offlineStore.cacheListJson(listId, updatedList);
    return ShoppaListItem.fromJson(updatedItemJson!);
  }

  Future<ShoppaListItem> _queueUpdateItem(
    String listId,
    String itemId,
    Map<String, dynamic> body,
    DateTime clientUpdatedAt,
  ) async {
    final payload = Map<String, dynamic>.from(body);
    if (!payload.containsKey('client_updated_at')) {
      payload['client_updated_at'] = clientUpdatedAt.toIso8601String();
    }
    await _offlineStore.enqueue(QueuedMutation(
      id: _generateLocalId(),
      listId: listId,
      itemId: itemId,
      type: 'update_item',
      payload: payload,
      clientUpdatedAt: clientUpdatedAt.toIso8601String(),
    ));
    final optimistic = await _mergeItemInCache(listId, itemId, {
      if (payload['name'] != null) 'name': payload['name'],
      if (payload['quantity'] != null) 'quantity': payload['quantity'].toString(),
      if (payload['unit'] != null) 'unit': payload['unit'],
      if (payload['note'] != null) 'note': payload['note'],
      if (payload['position'] != null) 'position': payload['position'],
    });
    return optimistic ??
        ShoppaListItem(
          id: itemId,
          name: payload['name'] as String? ?? '',
          quantity: payload['quantity'] as num? ?? 1,
          unit: payload['unit'] as String? ?? 'ea',
          note: payload['note'] as String? ?? '',
          checked: false,
        );
  }

  Future<void> _queueDeleteItem(String listId, String itemId) async {
    final now = DateTime.now().toUtc();
    await _offlineStore.enqueue(QueuedMutation(
      id: _generateLocalId(),
      listId: listId,
      itemId: itemId,
      type: 'delete_item',
      payload: const {},
      clientUpdatedAt: now.toIso8601String(),
    ));
    await _removeItemFromCache(listId, itemId);
  }

  Future<void> _removeItemFromCache(String listId, String itemId) async {
    final cached = await _offlineStore.getCachedListJson(listId);
    if (cached == null) return;
    final items =
        ((cached['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    final updatedItems = items.where((item) => item['id'] != itemId).toList();
    final updated = Map<String, dynamic>.from(cached);
    updated['items'] = updatedItems;
    updated['item_count'] = updatedItems.length;
    await _offlineStore.cacheListJson(listId, updated);
  }

  Future<void> _reorderCache(String listId, List<String> orderedIds) async {
    final cached = await _offlineStore.getCachedListJson(listId);
    if (cached == null) return;
    final items =
        ((cached['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    final byId = {for (final item in items) item['id'] as String: item};
    final reordered = orderedIds
        .where(byId.containsKey)
        .map((id) => byId[id]!)
        .toList();
    final updated = Map<String, dynamic>.from(cached);
    updated['items'] = reordered;
    await _offlineStore.cacheListJson(listId, updated);
  }

  String _generateLocalId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  /// SRS FR-3.1: share a list at view or edit permission.
  Future<ShoppaCollaborator> shareList(
    String listId, {
    required String email,
    required String permission,
  }) async {
    final json = await _client.post('/lists/$listId/collaborators', {
      'email': email,
      'permission': permission,
    }, authenticated: true) as Map<String, dynamic>;
    return ShoppaCollaborator.fromJson(json);
  }

  Future<List<ShoppaCollaborator>> fetchCollaborators(String listId) async {
    final json =
        await _client.get('/lists/$listId/collaborators') as Map<String, dynamic>;
    final results = json['results'] as List;
    return results
        .map((e) => ShoppaCollaborator.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeCollaborator(String listId, String userId) {
    return _client.delete('/lists/$listId/collaborators/$userId');
  }

  /// Owner: change collaborator view/edit permission.
  Future<ShoppaCollaborator> updateCollaboratorPermission(
    String listId,
    String userId, {
    required String permission,
  }) async {
    final json = await _client.patch(
      '/lists/$listId/collaborators/$userId',
      {'permission': permission},
      authenticated: true,
    ) as Map<String, dynamic>;
    return ShoppaCollaborator.fromJson(json);
  }

  /// Collaborator self-leave (DELETE own collaborator row).
  Future<void> leaveList(String listId, String userId) {
    return removeCollaborator(listId, userId);
  }

  /// SRS FR-3.3: per-list activity feed.
  Future<List<ShoppaActivityEntry>> fetchActivity(String listId) async {
    final json =
        await _client.get('/lists/$listId/activity') as Map<String, dynamic>;
    final results = json['results'] as List;
    return results
        .map((e) => ShoppaActivityEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// SRS FR-7.1: promotions matched to the caller's list contents, minus
  /// anything they've opted out of.
  Future<List<ShoppaPromotion>> fetchPromotions() async {
    final json = await _client.get('/promotions') as Map<String, dynamic>;
    final results = json['results'] as List;
    return results
        .map((e) => ShoppaPromotion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// SRS FR-3.4: per-list chat history.
  Future<List<ShoppaChatMessage>> fetchMessages(String listId) async {
    final json =
        await _client.get('/lists/$listId/messages') as Map<String, dynamic>;
    final results = json['results'] as List;
    return results
        .map((e) => ShoppaChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// SRS FR-3.4: send a chat message (also pushed via WebSocket).
  Future<ShoppaChatMessage> sendMessage(String listId, String body) async {
    final json = await _client.post(
      '/lists/$listId/messages',
      {'body': body},
      authenticated: true,
    ) as Map<String, dynamic>;
    return ShoppaChatMessage.fromJson(json);
  }

  /// SRS FR-7.3: opt out of promotions from one store, or from an entire
  /// category. Exactly one of [storeId]/[category] must be given.
  Future<void> optOutOfPromotions({String? storeId, String? category}) {
    assert(
      (storeId == null) != (category == null),
      'Provide exactly one of storeId or category.',
    );
    return _client.post('/promotions/opt-out', {
      if (storeId != null) 'store_id': storeId,
      if (category != null) 'category': category,
    }, authenticated: true);
  }
}
