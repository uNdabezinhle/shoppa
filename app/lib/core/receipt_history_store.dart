// Device-local history of logged till totals (receipt capture scaffolding).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'receipt_capture.dart';

/// One saved receipt log (not a photo — totals + metadata for now).
class LoggedReceipt {
  const LoggedReceipt({
    required this.id,
    required this.scopeId,
    required this.totalCents,
    required this.createdAt,
    this.storeName = '',
    this.notes = '',
    this.source = ReceiptSource.manual,
    this.pricesFilled = 0,
    this.listTitles = const [],
    this.basketCents = 0,
  });

  factory LoggedReceipt.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String? ?? 'manual';
    final source = ReceiptSource.values.firstWhere(
      (s) => s.name == sourceName,
      orElse: () => ReceiptSource.manual,
    );
    return LoggedReceipt(
      id: json['id'] as String,
      scopeId: json['scopeId'] as String,
      totalCents: (json['totalCents'] as num).toInt(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      storeName: json['storeName'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      source: source,
      pricesFilled: (json['pricesFilled'] as num?)?.toInt() ?? 0,
      listTitles: (json['listTitles'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      basketCents: (json['basketCents'] as num?)?.toInt() ?? 0,
    );
  }

  /// Unique log id.
  final String id;
  /// List id, or multi-list trip key (`trip:a,b`).
  final String scopeId;
  final int totalCents;
  final DateTime createdAt;
  final String storeName;
  final String notes;
  final ReceiptSource source;
  final int pricesFilled;
  final List<String> listTitles;
  /// In-app checked spend (paid prices) at the moment the till was logged.
  final int basketCents;

  String get formattedTotal =>
      'R${(totalCents / 100).toStringAsFixed(2)}';

  /// Till vs basket snapshot saved with this log (null if no basket spend).
  TillVsBasket? get tillVsBasket {
    if (totalCents <= 0) return null;
    return TillVsBasket(
      tillCents: totalCents,
      basketCents: basketCents,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scopeId': scopeId,
        'totalCents': totalCents,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'storeName': storeName,
        'notes': notes,
        'source': source.name,
        'pricesFilled': pricesFilled,
        'listTitles': listTitles,
        'basketCents': basketCents,
      };

  /// Stable scope for a multi-list trip.
  static String tripScopeId(Iterable<String> listIds) {
    final sorted = listIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return 'trip:${sorted.join(',')}';
  }
}

abstract class ReceiptHistoryStore {
  Future<void> add(LoggedReceipt receipt);
  Future<List<LoggedReceipt>> forScope(String scopeId, {int limit = 30});
  Future<List<LoggedReceipt>> recent({int limit = 30});
  Future<LoggedReceipt?> latestForScope(String scopeId);
  Future<void> clearScope(String scopeId);
  /// Remove one log by id (device-local only).
  Future<void> removeById(String id);
}

class InMemoryReceiptHistoryStore implements ReceiptHistoryStore {
  final List<LoggedReceipt> _all = [];

  @override
  Future<void> add(LoggedReceipt receipt) async {
    _all.insert(0, receipt);
  }

  @override
  Future<List<LoggedReceipt>> forScope(String scopeId, {int limit = 30}) async {
    return _all.where((r) => r.scopeId == scopeId).take(limit).toList();
  }

  @override
  Future<List<LoggedReceipt>> recent({int limit = 30}) async {
    return _all.take(limit).toList();
  }

  @override
  Future<LoggedReceipt?> latestForScope(String scopeId) async {
    for (final r in _all) {
      if (r.scopeId == scopeId) return r;
    }
    return null;
  }

  @override
  Future<void> clearScope(String scopeId) async {
    _all.removeWhere((r) => r.scopeId == scopeId);
  }

  @override
  Future<void> removeById(String id) async {
    _all.removeWhere((r) => r.id == id);
  }
}

class SharedPreferencesReceiptHistoryStore implements ReceiptHistoryStore {
  static const _key = 'shoppa.receipt_history.v1';
  static const _maxEntries = 100;

  Future<List<LoggedReceipt>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => LoggedReceipt.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<LoggedReceipt> all) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = all.take(_maxEntries).toList();
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Future<void> add(LoggedReceipt receipt) async {
    final all = await _loadAll();
    all.insert(0, receipt);
    await _saveAll(all);
  }

  @override
  Future<List<LoggedReceipt>> forScope(String scopeId, {int limit = 30}) async {
    final all = await _loadAll();
    return all.where((r) => r.scopeId == scopeId).take(limit).toList();
  }

  @override
  Future<List<LoggedReceipt>> recent({int limit = 30}) async {
    final all = await _loadAll();
    return all.take(limit).toList();
  }

  @override
  Future<LoggedReceipt?> latestForScope(String scopeId) async {
    final list = await forScope(scopeId, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> clearScope(String scopeId) async {
    final all = await _loadAll();
    all.removeWhere((r) => r.scopeId == scopeId);
    await _saveAll(all);
  }

  @override
  Future<void> removeById(String id) async {
    final all = await _loadAll();
    all.removeWhere((r) => r.id == id);
    await _saveAll(all);
  }
}

/// Map each scope to its newest receipt.
///
/// [receipts] should be newest-first (as returned by [ReceiptHistoryStore.recent]).
/// First occurrence of a [LoggedReceipt.scopeId] wins.
Map<String, LoggedReceipt> indexLatestReceiptsByScope(
  Iterable<LoggedReceipt> receipts,
) {
  final out = <String, LoggedReceipt>{};
  for (final r in receipts) {
    out.putIfAbsent(r.scopeId, () => r);
  }
  return out;
}

/// Most-used store names from logged receipts (most recent first among ties).
///
/// Frequency wins; when counts match, the store seen more recently ranks higher.
/// Display spelling comes from the most recent log for that store.
List<String> frequentStoreNames(
  Iterable<LoggedReceipt> receipts, {
  int limit = 6,
}) {
  final counts = <String, int>{};
  final firstIndex = <String, int>{};
  final display = <String, String>{};
  var i = 0;
  for (final r in receipts) {
    final name = r.storeName.trim();
    if (name.isEmpty) {
      i++;
      continue;
    }
    final key = name.toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
    firstIndex.putIfAbsent(key, () => i);
    // First in [receipts] is newest — keep that spelling.
    display.putIfAbsent(key, () => name);
    i++;
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final c = counts[b]!.compareTo(counts[a]!);
      if (c != 0) return c;
      return (firstIndex[a] ?? 0).compareTo(firstIndex[b] ?? 0);
    });
  return keys.take(limit).map((k) => display[k]!).toList();
}

/// Build a history entry from a capture + optional fill count.
LoggedReceipt loggedReceiptFromCapture({
  required ReceiptCapture capture,
  required String scopeId,
  int pricesFilled = 0,
  List<String> listTitles = const [],
  int basketCents = 0,
  DateTime? now,
  String? id,
}) {
  final when = now ?? DateTime.now();
  return LoggedReceipt(
    id: id ?? 'rcpt-${when.microsecondsSinceEpoch}',
    scopeId: scopeId,
    totalCents: capture.totalCents ?? 0,
    createdAt: when,
    storeName: capture.storeName,
    notes: capture.notes,
    source: capture.source,
    pricesFilled: pricesFilled,
    listTitles: listTitles,
    basketCents: basketCents,
  );
}

/// Aggregate till / basket stats over logged receipts (device-local).
class ReceiptSpendInsights {
  const ReceiptSpendInsights({
    required this.receiptCount,
    required this.totalTillCents,
    required this.withBasketCount,
    required this.netDeltaCents,
    required this.overCount,
    required this.underCount,
    required this.matchCount,
  });

  factory ReceiptSpendInsights.from(Iterable<LoggedReceipt> receipts) {
    var count = 0;
    var totalTill = 0;
    var withBasket = 0;
    var netDelta = 0;
    var over = 0;
    var under = 0;
    var match = 0;
    for (final r in receipts) {
      if (r.totalCents <= 0) continue;
      count++;
      totalTill += r.totalCents;
      final vs = r.tillVsBasket;
      if (vs == null || !vs.hasComparison) continue;
      withBasket++;
      netDelta += vs.deltaCents;
      if (vs.matches) {
        match++;
      } else if (vs.over) {
        over++;
      } else if (vs.under) {
        under++;
      }
    }
    return ReceiptSpendInsights(
      receiptCount: count,
      totalTillCents: totalTill,
      withBasketCount: withBasket,
      netDeltaCents: netDelta,
      overCount: over,
      underCount: under,
      matchCount: match,
    );
  }

  final int receiptCount;
  final int totalTillCents;
  final int withBasketCount;
  final int netDeltaCents;
  final int overCount;
  final int underCount;
  final int matchCount;

  bool get isEmpty => receiptCount == 0;

  int get averageTillCents =>
      receiptCount == 0 ? 0 : (totalTillCents / receiptCount).round();

  String get formattedTotal =>
      'R${(totalTillCents / 100).toStringAsFixed(2)}';

  String get formattedAverage =>
      'R${(averageTillCents / 100).toStringAsFixed(2)}';

  String get formattedAbsNetDelta =>
      'R${(netDeltaCents.abs() / 100).toStringAsFixed(2)}';

  /// e.g. `3 receipts · avg R120.00 · total R360.00`
  String get summaryLine {
    if (isEmpty) return '';
    if (receiptCount == 1) {
      return '1 receipt · $formattedTotal';
    }
    return '$receiptCount receipts · avg $formattedAverage · total $formattedTotal';
  }

  /// Basket comparison roll-up when any logs had basket spend.
  String? get varianceLine {
    if (withBasketCount == 0) return null;
    if (netDeltaCents == 0) {
      return withBasketCount == 1
          ? 'Matched basket'
          : 'Basket matched till overall ($withBasketCount logs)';
    }
    final direction = netDeltaCents > 0 ? 'over' : 'under';
    if (withBasketCount == 1) {
      return '$formattedAbsNetDelta $direction basket';
    }
    return 'Net $formattedAbsNetDelta $direction basket '
        '($overCount over · $underCount under · $matchCount match)';
  }

  /// Compact mall / chip style line.
  String get compactLine {
    if (isEmpty) return '';
    if (receiptCount == 1) return formattedTotal;
    final variance = varianceLine;
    if (variance != null && withBasketCount > 0) {
      return 'avg $formattedAverage · $variance';
    }
    return 'avg $formattedAverage · $receiptCount trips';
  }
}
