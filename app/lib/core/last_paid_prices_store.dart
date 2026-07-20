// Device-local memory of last paid prices by item name (cross-list prefill).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'lists_repository.dart';
import 'receipt_history_store.dart';

/// Normalize item names for last-paid lookup (case / punctuation insensitive).
String normalizeLastPaidName(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

abstract class LastPaidPricesStore {
  /// Most recent paid price in cents for this name, if any.
  Future<int?> getCents(String name);

  /// Remember a paid price (overwrites previous for the same name).
  Future<void> record(String name, int cents);

  /// Remove one entry (optional hygiene).
  Future<void> remove(String name);

  /// Full snapshot (normalized name → cents) for bulk estimates.
  Future<Map<String, int>> snapshot();
}

class InMemoryLastPaidPricesStore implements LastPaidPricesStore {
  final Map<String, int> _byName = {};

  @override
  Future<int?> getCents(String name) async {
    final key = normalizeLastPaidName(name);
    if (key.isEmpty) return null;
    return _byName[key];
  }

  @override
  Future<void> record(String name, int cents) async {
    final key = normalizeLastPaidName(name);
    if (key.isEmpty || cents <= 0) return;
    _byName[key] = cents;
  }

  @override
  Future<void> remove(String name) async {
    _byName.remove(normalizeLastPaidName(name));
  }

  @override
  Future<Map<String, int>> snapshot() async => Map<String, int>.from(_byName);
}

class SharedPreferencesLastPaidPricesStore implements LastPaidPricesStore {
  static const _key = 'shoppa.last_paid_prices.v1';
  static const _maxEntries = 200;

  Future<Map<String, int>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, int> map) async {
    final prefs = await SharedPreferences.getInstance();
    // Drop oldest-ish keys if oversized (map order is insertion in Dart 3
    // for LinkedHashMap from json — trim by taking last N keys).
    var out = map;
    if (out.length > _maxEntries) {
      final keys = out.keys.toList();
      final keep = keys.sublist(keys.length - _maxEntries);
      out = {for (final k in keep) k: out[k]!};
    }
    await prefs.setString(_key, jsonEncode(out));
  }

  @override
  Future<int?> getCents(String name) async {
    final key = normalizeLastPaidName(name);
    if (key.isEmpty) return null;
    final all = await _load();
    return all[key];
  }

  @override
  Future<void> record(String name, int cents) async {
    final key = normalizeLastPaidName(name);
    if (key.isEmpty || cents <= 0) return;
    final all = await _load();
    // Re-insert so this name stays among the “newest” when trimming.
    all.remove(key);
    all[key] = cents;
    await _save(all);
  }

  @override
  Future<void> remove(String name) async {
    final key = normalizeLastPaidName(name);
    if (key.isEmpty) return;
    final all = await _load();
    all.remove(key);
    await _save(all);
  }

  @override
  Future<Map<String, int>> snapshot() async => _load();
}

/// Estimate spend still left on unchecked items.
///
/// Uses each line’s [ShoppaListItem.paidPrice] when set (e.g. after a prior
/// trip), otherwise [rememberedByName] from [LastPaidPricesStore].
class RemainingSpendEstimate {
  const RemainingSpendEstimate({
    required this.remainingCount,
    required this.pricedCount,
    required this.estimatedCents,
  });

  final int remainingCount;
  final int pricedCount;
  final int estimatedCents;

  bool get hasEstimate => pricedCount > 0 && estimatedCents > 0;
  bool get isComplete =>
      remainingCount > 0 && pricedCount == remainingCount;

  String get formatted =>
      'R${(estimatedCents / 100).toStringAsFixed(2)}';

  /// e.g. `Left est. R42.50` or `Left est. R42.50 (3/5 priced)`.
  String get summaryLine {
    if (!hasEstimate) return '';
    if (isComplete) return 'Left est. $formatted';
    return 'Left est. $formatted ($pricedCount/$remainingCount priced)';
  }
}

RemainingSpendEstimate estimateRemainingSpend(
  List<ShoppaListItem> items, {
  Map<String, int> rememberedByName = const {},
}) {
  var remaining = 0;
  var priced = 0;
  var cents = 0;
  for (final item in items) {
    if (item.checked) continue;
    remaining++;
    final line = item.paidPrice;
    final remembered = rememberedByName[normalizeLastPaidName(item.name)];
    final p = (line != null && line > 0) ? line : remembered;
    if (p != null && p > 0) {
      priced++;
      cents += p;
    }
  }
  return RemainingSpendEstimate(
    remainingCount: remaining,
    pricedCount: priced,
    estimatedCents: cents,
  );
}

/// Projected full-trip total when both spent and remaining estimate exist.
String? formatProjectedTripTotal({
  required int spentCents,
  required int leftEstCents,
}) {
  if (spentCents <= 0 || leftEstCents <= 0) return null;
  final total = spentCents + leftEstCents;
  return 'Trip est. R${(total / 100).toStringAsFixed(2)}';
}

/// Subtitle fragments for My Lists rows: last till + remaining spend estimate.
List<String> listMoneyTeaserBits({
  LoggedReceipt? lastReceipt,
  List<ShoppaListItem>? items,
  Map<String, int> rememberedByName = const {},
}) {
  final bits = <String>[];
  if (lastReceipt != null && lastReceipt.totalCents > 0) {
    final store = lastReceipt.storeName.trim();
    bits.add(
      store.isEmpty
          ? 'last till ${lastReceipt.formattedTotal}'
          : 'last till ${lastReceipt.formattedTotal} · $store',
    );
  }
  if (items != null && items.isNotEmpty) {
    final est = estimateRemainingSpend(
      items,
      rememberedByName: rememberedByName,
    );
    if (est.hasEstimate) bits.add(est.summaryLine);
  }
  return bits;
}
