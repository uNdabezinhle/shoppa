/// Persists per-list "shopping at" store for check-off price observations.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ShoppingAtStore {
  const ShoppingAtStore({required this.storeId, required this.storeName});

  factory ShoppingAtStore.fromJson(Map<String, dynamic> json) => ShoppingAtStore(
        storeId: json['storeId'] as String,
        storeName: json['storeName'] as String,
      );

  final String storeId;
  final String storeName;

  Map<String, dynamic> toJson() => {
        'storeId': storeId,
        'storeName': storeName,
      };
}

/// Soft default when a list/trip has no saved store yet.
///
/// Preference order: scope → last used anywhere → frequent receipt stores.
String? resolveDefaultStoreName({
  String? scopeStoreName,
  String? lastStoreName,
  List<String> frequentStores = const [],
}) {
  for (final candidate in [
    scopeStoreName,
    lastStoreName,
    ...frequentStores,
  ]) {
    final t = candidate?.trim() ?? '';
    if (t.isNotEmpty) return t;
  }
  return null;
}

abstract class ShoppingSessionStore {
  Future<ShoppingAtStore?> getShoppingAt(String listId);
  Future<void> setShoppingAt(String listId, ShoppingAtStore store);
  Future<void> clearShoppingAt(String listId);

  /// Most recently chosen store across any list/trip (device-local).
  Future<ShoppingAtStore?> getLastStore();
  Future<void> setLastStore(ShoppingAtStore store);
  Future<void> clearLastStore();
}

class InMemoryShoppingSessionStore implements ShoppingSessionStore {
  final Map<String, ShoppingAtStore> _byList = {};
  ShoppingAtStore? _last;

  @override
  Future<ShoppingAtStore?> getShoppingAt(String listId) async =>
      _byList[listId];

  @override
  Future<void> setShoppingAt(String listId, ShoppingAtStore store) async {
    _byList[listId] = store;
    _last = store;
  }

  @override
  Future<void> clearShoppingAt(String listId) async {
    _byList.remove(listId);
  }

  @override
  Future<ShoppingAtStore?> getLastStore() async => _last;

  @override
  Future<void> setLastStore(ShoppingAtStore store) async {
    _last = store;
  }

  @override
  Future<void> clearLastStore() async {
    _last = null;
  }
}

class SharedPreferencesShoppingSessionStore implements ShoppingSessionStore {
  static String _key(String listId) => 'shoppa.shopping_at.$listId';
  static const _lastKey = 'shoppa.shopping_at.last';

  @override
  Future<ShoppingAtStore?> getShoppingAt(String listId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key(listId)));
  }

  @override
  Future<void> setShoppingAt(String listId, ShoppingAtStore store) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(store.toJson());
    await prefs.setString(_key(listId), raw);
    await prefs.setString(_lastKey, raw);
  }

  @override
  Future<void> clearShoppingAt(String listId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(listId));
  }

  @override
  Future<ShoppingAtStore?> getLastStore() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_lastKey));
  }

  @override
  Future<void> setLastStore(ShoppingAtStore store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastKey, jsonEncode(store.toJson()));
  }

  @override
  Future<void> clearLastStore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastKey);
  }

  ShoppingAtStore? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ShoppingAtStore.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
