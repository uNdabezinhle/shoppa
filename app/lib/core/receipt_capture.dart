// Receipt capture scaffolding — manual entry + heuristic text parse.
// Full camera OCR can plug into [ReceiptOcrService] later.
import 'lists_repository.dart';

/// Where a receipt total / parse came from.
enum ReceiptSource {
  manual,
  pastedText,
  /// Reserved for on-device / cloud OCR implementations.
  ocr,
}

/// Result of parsing or manually entering a receipt.
class ReceiptCapture {
  const ReceiptCapture({
    this.totalCents,
    this.storeName = '',
    this.notes = '',
    this.rawText = '',
    this.source = ReceiptSource.manual,
    this.lineHints = const [],
    this.itemsToAdd = const [],
    this.hasPhoto = false,
    this.photoByteLength = 0,
  });

  final int? totalCents;
  final String storeName;
  final String notes;
  final String rawText;
  final ReceiptSource source;
  /// Line-item name hints extracted from pasted text (all candidates).
  final List<String> lineHints;
  /// Hints the user chose to add to the list (not already matched).
  final List<String> itemsToAdd;
  /// True when a receipt photo was attached (camera / gallery).
  final bool hasPhoto;
  /// Size of the attached photo in bytes (0 if none).
  final int photoByteLength;

  bool get hasTotal => totalCents != null && totalCents! > 0;

  String get formattedTotal => totalCents == null
      ? ''
      : 'R${(totalCents! / 100).toStringAsFixed(2)}';
}

/// Normalize for rough name matching (case / punctuation insensitive).
String normalizeReceiptItemName(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True when a receipt line hint likely refers to the same product as [itemName].
bool receiptNameMatchesListItem(String hint, String itemName) {
  final a = normalizeReceiptItemName(hint);
  final b = normalizeReceiptItemName(itemName);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  // Containment only when both are reasonably long (avoid "oil" ⊂ "toilet").
  if (a.length >= 4 && b.length >= 4) {
    if (a.contains(b) || b.contains(a)) return true;
  }
  return false;
}

/// Receipt line names that do not appear to match any existing list item.
///
/// Dedupes by normalized name; preserves first-seen display spelling.
List<String> unmatchedReceiptLineHints({
  required List<String> lineHints,
  required List<ShoppaListItem> items,
}) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in lineHints) {
    final name = raw.trim();
    if (name.length < 2) continue;
    final key = normalizeReceiptItemName(name);
    if (key.isEmpty || seen.contains(key)) continue;
    final matched =
        items.any((i) => receiptNameMatchesListItem(name, i.name));
    if (matched) continue;
    seen.add(key);
    out.add(name);
  }
  return out;
}

/// Suggested paid price for a checked item still missing one.
class ReceiptPriceSuggestion {
  const ReceiptPriceSuggestion({
    required this.itemId,
    required this.cents,
  });

  final String itemId;
  final int cents;
}

/// Pluggable OCR / parse backend.
abstract class ReceiptOcrService {
  /// Parse free-text (pasted receipt body, OCR dump, etc.).
  Future<ReceiptCapture> parseText(String text);

  /// Future: image bytes → OCR. Default implementations return empty.
  Future<ReceiptCapture> parseImageBytes(List<int> bytes);
}

/// Heuristic ZA-oriented total extraction from plain text (no ML).
class HeuristicReceiptOcrService implements ReceiptOcrService {
  static final _totalLabel = RegExp(
    r'(?:total|amount\s*due|grand\s*total|card\s*total|amount)\s*[:\-]?\s*'
    r'(?:r\s*)?(\d[\d\s]*[.,]\d{2})',
    caseSensitive: false,
  );

  static final _money = RegExp(
    r'(?:r\s*)?(\d{1,6}[.,]\d{2})\b',
    caseSensitive: false,
  );

  static final _storeLine = RegExp(
    r'^(checkers|pick\s*n\s*pay|pnp|woolworths|spar|shoprite|food\s*lovers|'
    r'makro|game|dischem|clicks)\b',
    caseSensitive: false,
  );

  @override
  Future<ReceiptCapture> parseText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const ReceiptCapture(source: ReceiptSource.pastedText);
    }

    int? total = _firstMoney(_totalLabel, trimmed);
    total ??= _largestMoney(trimmed);

    String store = '';
    for (final line in trimmed.split(RegExp(r'\r?\n'))) {
      final m = _storeLine.firstMatch(line.trim());
      if (m != null) {
        store = _titleCase(m.group(0)!.replaceAll(RegExp(r'\s+'), ' '));
        break;
      }
    }

    final hints = <String>[];
    for (final line in trimmed.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.length < 3 || t.length > 48) continue;
      if (_money.hasMatch(t) && !_totalLabel.hasMatch(t)) {
        final name = t.replaceAll(_money, '').trim();
        if (name.length >= 3 && RegExp(r'[a-zA-Z]').hasMatch(name)) {
          hints.add(name);
        }
      }
      if (hints.length >= 12) break;
    }

    return ReceiptCapture(
      totalCents: total,
      storeName: store,
      rawText: trimmed,
      source: ReceiptSource.pastedText,
      lineHints: hints,
    );
  }

  @override
  Future<ReceiptCapture> parseImageBytes(List<int> bytes) async {
    // On-device ML OCR not wired yet — keep the photo attachment + manual total.
    if (bytes.isEmpty) {
      return const ReceiptCapture(source: ReceiptSource.ocr);
    }
    final kb = (bytes.length / 1024).ceil();
    return ReceiptCapture(
      source: ReceiptSource.ocr,
      hasPhoto: true,
      photoByteLength: bytes.length,
      notes: 'Photo attached ($kb KB). Auto-OCR not available yet — '
          'enter the till total or paste text.',
    );
  }

  int? _firstMoney(RegExp pattern, String text) {
    final m = pattern.firstMatch(text);
    if (m == null) return null;
    return _parseMoney(m.group(1)!);
  }

  int? _largestMoney(String text) {
    var best = 0;
    for (final m in _money.allMatches(text)) {
      final cents = _parseMoney(m.group(1)!);
      if (cents != null && cents > best) best = cents;
    }
    return best > 0 ? best : null;
  }

  int? _parseMoney(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  String _titleCase(String s) {
    return s
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }
}

/// Split [receiptTotalCents] across checked items that still lack a paid price.
///
/// Already-priced checked items are left alone; the remainder of the total
/// (after subtracting those prices) is shared by quantity weight among
/// unpriced checked items. If remainder ≤ 0, returns no suggestions.
List<ReceiptPriceSuggestion> suggestPricesFromReceiptTotal({
  required List<ShoppaListItem> items,
  required int receiptTotalCents,
}) {
  if (receiptTotalCents <= 0) return const [];

  final checked = items.where((i) => i.checked).toList();
  if (checked.isEmpty) return const [];

  var alreadyPriced = 0;
  final need = <ShoppaListItem>[];
  for (final item in checked) {
    final p = item.paidPrice;
    if (p != null) {
      alreadyPriced += p;
    } else {
      need.add(item);
    }
  }
  if (need.isEmpty) return const [];

  var remainder = receiptTotalCents - alreadyPriced;
  if (remainder <= 0) return const [];

  // Weight by quantity (min 1).
  final weights = need.map((i) {
    final q = i.quantity.toDouble();
    return q <= 0 ? 1.0 : q;
  }).toList();
  final weightSum = weights.fold<double>(0, (a, b) => a + b);
  if (weightSum <= 0) return const [];

  final suggestions = <ReceiptPriceSuggestion>[];
  var allocated = 0;
  for (var i = 0; i < need.length; i++) {
    final isLast = i == need.length - 1;
    final cents = isLast
        ? remainder - allocated
        : ((remainder * weights[i]) / weightSum).round();
    final safe = cents < 0 ? 0 : cents;
    if (!isLast) allocated += safe;
    suggestions.add(
      ReceiptPriceSuggestion(itemId: need[i].id, cents: safe),
    );
  }
  return suggestions;
}

String _formatCentsZar(int cents) => 'R${(cents / 100).toStringAsFixed(2)}';

/// Compare a till / receipt total against in-app basket spend (checked paid prices).
///
/// [deltaCents] is till − basket: positive means the till was higher than logged spend.
class TillVsBasket {
  const TillVsBasket({
    required this.tillCents,
    required this.basketCents,
  });

  final int tillCents;
  final int basketCents;

  int get deltaCents => tillCents - basketCents;

  bool get hasTill => tillCents > 0;
  bool get hasBasket => basketCents > 0;
  bool get hasComparison => hasTill && hasBasket;
  bool get matches => hasComparison && deltaCents == 0;
  bool get over => hasComparison && deltaCents > 0;
  bool get under => hasComparison && deltaCents < 0;

  String get formattedTill => _formatCentsZar(tillCents);
  String get formattedBasket => _formatCentsZar(basketCents);
  String get formattedAbsDelta => _formatCentsZar(deltaCents.abs());

  /// e.g. `+R5.00`, `−R2.50`, or `match`.
  String get signedDeltaLabel {
    if (!hasComparison) return '';
    if (matches) return 'match';
    final sign = over ? '+' : '−';
    return '$sign$formattedAbsDelta';
  }

  /// Short human label: "R5.00 over basket", "R2.50 under basket", "matches basket".
  String get variancePhrase {
    if (!hasComparison) return '';
    if (matches) return 'matches basket';
    if (over) return '$formattedAbsDelta over basket';
    return '$formattedAbsDelta under basket';
  }

  /// Progress-strip / snack style: "Till R120.00 · basket R115.00 · +R5.00".
  String get summaryLine {
    if (!hasTill) return '';
    if (!hasBasket) return 'Till $formattedTill';
    if (matches) {
      return 'Till $formattedTill · matches basket';
    }
    return 'Till $formattedTill · basket $formattedBasket · $signedDeltaLabel';
  }

  /// One-line share / recap footer.
  String get shareLine {
    if (!hasTill) return '';
    if (!hasBasket) return 'Till total: $formattedTill';
    if (matches) {
      return 'Till $formattedTill (matches basket spend)';
    }
    return 'Till $formattedTill · basket $formattedBasket ($variancePhrase)';
  }
}

/// Build comparison from a logged receipt and optional live basket spend.
TillVsBasket? tillVsBasketFrom({
  int? tillCents,
  int? basketCents,
}) {
  final till = tillCents ?? 0;
  final basket = basketCents ?? 0;
  if (till <= 0 && basket <= 0) return null;
  return TillVsBasket(tillCents: till, basketCents: basket);
}
