/// Device-local aisle overrides keyed by normalized item name.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'aisle_sort.dart';

abstract class AisleOverridesStore {
  /// Map of [aisleMatchKey] → aisle group id.
  Future<Map<String, String>> snapshot();
  Future<void> setOverride(String itemName, String aisleId);
  Future<void> clearOverride(String itemName);
  Future<void> clearAll();
}

class InMemoryAisleOverridesStore implements AisleOverridesStore {
  final Map<String, String> _byName = {};

  @override
  Future<Map<String, String>> snapshot() async =>
      Map<String, String>.from(_byName);

  @override
  Future<void> setOverride(String itemName, String aisleId) async {
    final key = aisleMatchKey(itemName);
    final id = aisleId.trim();
    if (key.isEmpty || aisleGroupById(id) == null) return;
    _byName[key] = id;
  }

  @override
  Future<void> clearOverride(String itemName) async {
    _byName.remove(aisleMatchKey(itemName));
  }

  @override
  Future<void> clearAll() async {
    _byName.clear();
  }
}

class SharedPreferencesAisleOverridesStore implements AisleOverridesStore {
  static const _key = 'shoppa.aisle_overrides.v1';

  @override
  Future<Map<String, String>> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, String>{};
      for (final e in map.entries) {
        final nameKey = aisleMatchKey(e.key);
        final aisleId = '${e.value}'.trim();
        if (nameKey.isEmpty || aisleGroupById(aisleId) == null) continue;
        out[nameKey] = aisleId;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> setOverride(String itemName, String aisleId) async {
    final key = aisleMatchKey(itemName);
    final id = aisleId.trim();
    if (key.isEmpty || aisleGroupById(id) == null) return;
    final next = await snapshot();
    next[key] = id;
    await _save(next);
  }

  @override
  Future<void> clearOverride(String itemName) async {
    final next = await snapshot();
    if (next.remove(aisleMatchKey(itemName)) == null) return;
    await _save(next);
  }

  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _save(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    if (map.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(map));
    }
  }
}

/// Pick dialog labels: all walk aisles (no checked bucket).
List<AisleGroup> aislePickerGroups() => List<AisleGroup>.from(aisleGroups);
