// Parse multi-line paste / receipt-style text into list items.
// Camera OCR is out of scope; this is the manual "type or paste receipt" path.

class ParsedListLine {
  const ParsedListLine({
    required this.name,
    this.quantity = 1,
    this.unit = 'ea',
  });

  final String name;
  final num quantity;
  final String unit;
}

final _skipLine = RegExp(
  r'^(total|sub\s*total|subtotal|change|cash|card|eft|vat|tax|thank|'
  r'balance|amount|paid|due|tel|phone|date|time|till|cashier|'
  r'invoice|receipt|store|checkers|pick\s*n\s*pay|woolworths|spar|'
  r'-{2,}|={2,}|\*{2,})\b',
  caseSensitive: false,
);

final _trailingPrice = RegExp(
  r'\s+(?:R\s*)?\d+[.,]\d{2}\s*$',
  caseSensitive: false,
);

final _leadingPrice = RegExp(
  r'^(?:R\s*)?\d+[.,]\d{2}\s+',
  caseSensitive: false,
);

final _qtyPrefix = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s*[x×]\s+(.+)$',
  caseSensitive: false,
);

final _qtyPrefixSpace = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s+(.+)$',
);

final _qtySuffix = RegExp(
  r'^(.+?)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*$',
  caseSensitive: false,
);

final _unitPrefix = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l|lt|litre|liter|pack|pk)\s+(.+)$',
  caseSensitive: false,
);

/// Parse pasted list or rough receipt text into addable lines.
/// Blank lines, totals, and pure prices are skipped.
List<ParsedListLine> parseBulkItemLines(String text) {
  final results = <ParsedListLine>[];
  for (var raw in text.split(RegExp(r'\r?\n'))) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    if (_skipLine.hasMatch(line)) continue;

    line = line.replaceFirst(_leadingPrice, '').trim();
    line = line.replaceFirst(_trailingPrice, '').trim();
    if (line.isEmpty) continue;
    if (RegExp(r'^(?:R\s*)?\d+[.,]\d{2}$', caseSensitive: false).hasMatch(line)) {
      continue;
    }

    final unitMatch = _unitPrefix.firstMatch(line);
    if (unitMatch != null) {
      final qty = _parseNum(unitMatch.group(1)!);
      final unit = _normalizeUnit(unitMatch.group(2)!);
      final name = unitMatch.group(3)!.trim();
      if (name.isNotEmpty && qty > 0) {
        results.add(ParsedListLine(name: name, quantity: qty, unit: unit));
        continue;
      }
    }

    final prefixX = _qtyPrefix.firstMatch(line);
    if (prefixX != null) {
      final qty = _parseNum(prefixX.group(1)!);
      final name = prefixX.group(2)!.trim();
      if (name.isNotEmpty && qty > 0) {
        results.add(ParsedListLine(name: name, quantity: qty));
        continue;
      }
    }

    final suffixX = _qtySuffix.firstMatch(line);
    if (suffixX != null) {
      final name = suffixX.group(1)!.trim();
      final qty = _parseNum(suffixX.group(2)!);
      if (name.isNotEmpty && qty > 0 && !_looksLikeBarePrice(name)) {
        results.add(ParsedListLine(name: name, quantity: qty));
        continue;
      }
    }

    // "2 Bread" but not years/barcodes that are long pure numbers alone.
    final prefixSpace = _qtyPrefixSpace.firstMatch(line);
    if (prefixSpace != null) {
      final qty = _parseNum(prefixSpace.group(1)!);
      final rest = prefixSpace.group(2)!.trim();
      // Avoid treating "2024 Invoice" style as qty when rest is tiny keywords.
      if (rest.isNotEmpty &&
          qty > 0 &&
          qty <= 99 &&
          !RegExp(r'^\d+$').hasMatch(rest)) {
        results.add(ParsedListLine(name: rest, quantity: qty));
        continue;
      }
    }

    results.add(ParsedListLine(name: line));
  }
  return results;
}

num _parseNum(String raw) => num.parse(raw.replaceAll(',', '.'));

String _normalizeUnit(String raw) {
  switch (raw.toLowerCase()) {
    case 'lt':
    case 'litre':
    case 'liter':
      return 'l';
    case 'pk':
      return 'pack';
    default:
      return raw.toLowerCase();
  }
}

bool _looksLikeBarePrice(String s) =>
    RegExp(r'^(?:R\s*)?\d+[.,]\d{2}$', caseSensitive: false).hasMatch(s.trim());
