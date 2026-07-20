/// Remembers the last multi-list trip selection (device-local).
import 'package:shared_preferences/shared_preferences.dart';

import 'lists_repository.dart';

abstract class LastTripListsStore {
  Future<List<String>> getListIds();
  Future<void> setListIds(Iterable<String> ids);
  Future<void> clear();
}

class InMemoryLastTripListsStore implements LastTripListsStore {
  List<String> _ids = const [];

  @override
  Future<List<String>> getListIds() async => List<String>.from(_ids);

  @override
  Future<void> setListIds(Iterable<String> ids) async {
    _ids = _normalizeTripListIds(ids);
  }

  @override
  Future<void> clear() async {
    _ids = const [];
  }
}

class SharedPreferencesLastTripListsStore implements LastTripListsStore {
  static const _key = 'shoppa.last_trip_list_ids';

  @override
  Future<List<String>> getListIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _normalizeTripListIds(prefs.getStringList(_key) ?? const []);
  }

  @override
  Future<void> setListIds(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final next = _normalizeTripListIds(ids);
    if (next.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setStringList(_key, next);
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

List<String> _normalizeTripListIds(Iterable<String> ids) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in ids) {
    final id = raw.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    out.add(id);
  }
  return out;
}

/// Prefill trip multi-select: remembered ids still eligible, else all eligible.
Set<String> initialTripListSelection({
  required Iterable<ShoppaList> eligible,
  required Iterable<String> lastTripIds,
}) {
  final eligibleIds = <String>{};
  for (final list in eligible) {
    final id = list.id.trim();
    if (id.isNotEmpty) eligibleIds.add(id);
  }
  if (eligibleIds.isEmpty) return {};

  final remembered = <String>{};
  for (final raw in lastTripIds) {
    final id = raw.trim();
    if (eligibleIds.contains(id)) remembered.add(id);
  }
  if (remembered.isNotEmpty) return remembered;
  return eligibleIds;
}
