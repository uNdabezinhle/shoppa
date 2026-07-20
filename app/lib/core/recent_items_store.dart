/// Client-side recently used item names for quick-add chips.
import 'package:shared_preferences/shared_preferences.dart';

abstract class RecentItemsStore {
  Future<List<String>> getRecent({int limit = 12});
  Future<void> record(String name);
  Future<void> recordMany(Iterable<String> names);
}

class InMemoryRecentItemsStore implements RecentItemsStore {
  final List<String> _names = [];

  @override
  Future<List<String>> getRecent({int limit = 12}) async {
    return _names.take(limit).toList();
  }

  @override
  Future<void> record(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return;
    _names.removeWhere((n) => n.toLowerCase() == cleaned.toLowerCase());
    _names.insert(0, cleaned);
    if (_names.length > 40) {
      _names.removeRange(40, _names.length);
    }
  }

  @override
  Future<void> recordMany(Iterable<String> names) async {
    // Last name is newest (matches bulk-add order).
    for (final name in names) {
      await record(name);
    }
  }
}

class SharedPreferencesRecentItemsStore implements RecentItemsStore {
  static const _key = 'shoppa.recent_item_names';

  @override
  Future<List<String>> getRecent({int limit = 12}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    return raw.take(limit).toList();
  }

  @override
  Future<void> record(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const <String>[];
    final next = <String>[
      cleaned,
      ...existing.where((n) => n.toLowerCase() != cleaned.toLowerCase()),
    ];
    if (next.length > 40) {
      next.removeRange(40, next.length);
    }
    await prefs.setStringList(_key, next);
  }

  @override
  Future<void> recordMany(Iterable<String> names) async {
    for (final name in names) {
      await record(name);
    }
  }
}
