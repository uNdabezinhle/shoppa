/// Local cache + mutation queue for in-store offline shopping (SRS FR-4.2:
/// "Lists shall be fully usable offline and sync when connectivity
/// returns"). Two things live here:
///  - the last-known detail response for a list, so it can render fully
///    without a network round-trip;
///  - a queue of mutations (add item / check item) attempted while
///    offline, replayed against the real API once connectivity returns
///    (see ListsRepository.syncPending).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class QueuedMutation {
  QueuedMutation({
    required this.id,
    required this.listId,
    required this.type,
    required this.payload,
    required this.clientUpdatedAt,
    this.itemId,
  });

  factory QueuedMutation.fromJson(Map<String, dynamic> json) => QueuedMutation(
        id: json['id'] as String,
        listId: json['listId'] as String,
        itemId: json['itemId'] as String?,
        type: json['type'] as String,
        payload: (json['payload'] as Map).cast<String, dynamic>(),
        clientUpdatedAt: json['clientUpdatedAt'] as String,
      );

  /// Local, client-generated id for this queue entry (not a server id).
  final String id;
  final String listId;
  /// Null for "add_item" (the item doesn't exist server-side yet).
  final String? itemId;
  /// "add_item" | "check_item" | "update_item" | "delete_item" | "reorder_items".
  final String type;
  final Map<String, dynamic> payload;
  /// ISO-8601 timestamp of when the user actually made this change,
  /// sent to the server as client_updated_at for last-write-wins
  /// conflict resolution (see the backend's apply_field_updates).
  final String clientUpdatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'listId': listId,
        'itemId': itemId,
        'type': type,
        'payload': payload,
        'clientUpdatedAt': clientUpdatedAt,
      };
}

abstract class OfflineStore {
  Future<void> cacheListJson(String listId, Map<String, dynamic> json);
  Future<Map<String, dynamic>?> getCachedListJson(String listId);
  Future<void> cacheListsIndex(List<Map<String, dynamic>> lists);
  Future<List<Map<String, dynamic>>?> getCachedListsIndex();
  Future<void> enqueue(QueuedMutation mutation);
  Future<List<QueuedMutation>> pendingFor(String listId);
  /// All queued mutations across every list (for background sync).
  Future<List<QueuedMutation>> pendingAll();
  Future<void> remove(String mutationId);
}

/// In-memory implementation for tests and for any caller that doesn't
/// need the cache to survive an app restart.
class InMemoryOfflineStore implements OfflineStore {
  final Map<String, Map<String, dynamic>> _cache = {};
  List<Map<String, dynamic>>? _listsIndex;
  final List<QueuedMutation> _pending = [];

  @override
  Future<void> cacheListJson(String listId, Map<String, dynamic> json) async {
    _cache[listId] = json;
  }

  @override
  Future<Map<String, dynamic>?> getCachedListJson(String listId) async {
    return _cache[listId];
  }

  @override
  Future<void> cacheListsIndex(List<Map<String, dynamic>> lists) async {
    _listsIndex = lists
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>?> getCachedListsIndex() async {
    return _listsIndex
        ?.map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  @override
  Future<void> enqueue(QueuedMutation mutation) async {
    _pending.add(mutation);
  }

  @override
  Future<List<QueuedMutation>> pendingFor(String listId) async {
    return _pending.where((m) => m.listId == listId).toList();
  }

  @override
  Future<List<QueuedMutation>> pendingAll() async {
    return List<QueuedMutation>.from(_pending);
  }

  @override
  Future<void> remove(String mutationId) async {
    _pending.removeWhere((m) => m.id == mutationId);
  }
}

/// Persists across app restarts via shared_preferences -- the real
/// implementation used in main.dart.
class SharedPreferencesOfflineStore implements OfflineStore {
  static const _pendingKey = 'shoppa.pending_mutations';
  static const _listsIndexKey = 'shoppa.cached_lists_index';
  static String _cacheKey(String listId) => 'shoppa.cached_list.$listId';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<void> cacheListJson(String listId, Map<String, dynamic> json) async {
    final prefs = await _prefs;
    await prefs.setString(_cacheKey(listId), jsonEncode(json));
  }

  @override
  Future<Map<String, dynamic>?> getCachedListJson(String listId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_cacheKey(listId));
    if (raw == null) return null;
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  @override
  Future<void> cacheListsIndex(List<Map<String, dynamic>> lists) async {
    final prefs = await _prefs;
    await prefs.setString(_listsIndexKey, jsonEncode(lists));
  }

  @override
  Future<List<Map<String, dynamic>>?> getCachedListsIndex() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_listsIndexKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  @override
  Future<void> enqueue(QueuedMutation mutation) async {
    final prefs = await _prefs;
    final all = await _readAll(prefs);
    all.add(mutation);
    await _writeAll(prefs, all);
  }

  @override
  Future<List<QueuedMutation>> pendingFor(String listId) async {
    final prefs = await _prefs;
    final all = await _readAll(prefs);
    return all.where((m) => m.listId == listId).toList();
  }

  @override
  Future<List<QueuedMutation>> pendingAll() async {
    final prefs = await _prefs;
    return _readAll(prefs);
  }

  @override
  Future<void> remove(String mutationId) async {
    final prefs = await _prefs;
    final all = await _readAll(prefs);
    all.removeWhere((m) => m.id == mutationId);
    await _writeAll(prefs, all);
  }

  Future<List<QueuedMutation>> _readAll(SharedPreferences prefs) async {
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => QueuedMutation.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> _writeAll(
    SharedPreferences prefs,
    List<QueuedMutation> mutations,
  ) async {
    await prefs.setString(
      _pendingKey,
      jsonEncode(mutations.map((m) => m.toJson()).toList()),
    );
  }
}
