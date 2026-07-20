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

abstract class ShoppingSessionStore {
  Future<ShoppingAtStore?> getShoppingAt(String listId);
  Future<void> setShoppingAt(String listId, ShoppingAtStore store);
  Future<void> clearShoppingAt(String listId);
}

class InMemoryShoppingSessionStore implements ShoppingSessionStore {
  final Map<String, ShoppingAtStore> _byList = {};

  @override
  Future<ShoppingAtStore?> getShoppingAt(String listId) async =>
      _byList[listId];

  @override
  Future<void> setShoppingAt(String listId, ShoppingAtStore store) async {
    _byList[listId] = store;
  }

  @override
  Future<void> clearShoppingAt(String listId) async {
    _byList.remove(listId);
  }
}

class SharedPreferencesShoppingSessionStore implements ShoppingSessionStore {
  static String _key(String listId) => 'shoppa.shopping_at.$listId';

  @override
  Future<ShoppingAtStore?> getShoppingAt(String listId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(listId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ShoppingAtStore.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setShoppingAt(String listId, ShoppingAtStore store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(listId), jsonEncode(store.toJson()));
  }

  @override
  Future<void> clearShoppingAt(String listId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(listId));
  }
}
