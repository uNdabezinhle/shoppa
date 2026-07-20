/// Client-side pinned list IDs for My Lists (favorites float to the top).
import 'package:shared_preferences/shared_preferences.dart';

abstract class PinnedListsStore {
  Future<Set<String>> getPinnedIds();
  Future<void> setPinned(String listId, bool pinned);
  Future<bool> isPinned(String listId);
  Future<void> toggle(String listId);
}

class InMemoryPinnedListsStore implements PinnedListsStore {
  final Set<String> _ids = {};

  @override
  Future<Set<String>> getPinnedIds() async => Set<String>.from(_ids);

  @override
  Future<void> setPinned(String listId, bool pinned) async {
    if (pinned) {
      _ids.add(listId);
    } else {
      _ids.remove(listId);
    }
  }

  @override
  Future<bool> isPinned(String listId) async => _ids.contains(listId);

  @override
  Future<void> toggle(String listId) async {
    if (_ids.contains(listId)) {
      _ids.remove(listId);
    } else {
      _ids.add(listId);
    }
  }
}

class SharedPreferencesPinnedListsStore implements PinnedListsStore {
  static const _key = 'shoppa.pinned_list_ids';

  @override
  Future<Set<String>> getPinnedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    return raw.toSet();
  }

  @override
  Future<void> setPinned(String listId, bool pinned) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getStringList(_key) ?? const <String>[]).toSet();
    if (pinned) {
      next.add(listId);
    } else {
      next.remove(listId);
    }
    await prefs.setStringList(_key, next.toList());
  }

  @override
  Future<bool> isPinned(String listId) async {
    final ids = await getPinnedIds();
    return ids.contains(listId);
  }

  @override
  Future<void> toggle(String listId) async {
    final pinned = await isPinned(listId);
    await setPinned(listId, !pinned);
  }
}

/// Pinned lists first, preserving relative order within each group.
List<T> withPinnedFirst<T>(
  List<T> items, {
  required Set<String> pinnedIds,
  required String Function(T) idOf,
}) {
  if (pinnedIds.isEmpty || items.isEmpty) {
    return List<T>.from(items);
  }
  final pinned = <T>[];
  final rest = <T>[];
  for (final item in items) {
    if (pinnedIds.contains(idOf(item))) {
      pinned.add(item);
    } else {
      rest.add(item);
    }
  }
  return [...pinned, ...rest];
}
