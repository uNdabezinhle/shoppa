import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'verify_repository.dart';

/// Device-local cache of verify results for offline / load-shedding resilience.
abstract class VerifyCacheStore {
  Future<void> put(VerifyResult result);
  Future<VerifyResult?> get(String gtin);
  Future<List<VerifyResult>> recent({int limit = 50});
  Future<void> clear();
}

class SharedPreferencesVerifyCacheStore implements VerifyCacheStore {
  static const _key = 'shoppa.verify_cache_v1';
  static const _max = 50;

  Future<Map<String, dynamic>> _readMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
  }

  @override
  Future<void> put(VerifyResult result) async {
    final map = await _readMap();
    map[result.gtin] = {
      ...result.toJson(),
      '_cached_at': DateTime.now().toUtc().toIso8601String(),
    };
    // Evict oldest beyond max by _cached_at
    if (map.length > _max) {
      final entries = map.entries.toList()
        ..sort((a, b) {
          final at = (a.value as Map)['_cached_at'] as String? ?? '';
          final bt = (b.value as Map)['_cached_at'] as String? ?? '';
          return at.compareTo(bt);
        });
      while (entries.length > _max) {
        map.remove(entries.removeAt(0).key);
      }
    }
    await _writeMap(map);
  }

  @override
  Future<VerifyResult?> get(String gtin) async {
    final map = await _readMap();
    final raw = map[gtin];
    if (raw is! Map) return null;
    return VerifyResult.fromJson(
      Map<String, dynamic>.from(raw),
      offline: true,
    );
  }

  @override
  Future<List<VerifyResult>> recent({int limit = 50}) async {
    final map = await _readMap();
    final entries = map.entries.toList()
      ..sort((a, b) {
        final at = (a.value as Map)['_cached_at'] as String? ?? '';
        final bt = (b.value as Map)['_cached_at'] as String? ?? '';
        return bt.compareTo(at);
      });
    return entries.take(limit).map((e) {
      return VerifyResult.fromJson(
        Map<String, dynamic>.from(e.value as Map),
        offline: true,
      );
    }).toList();
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
