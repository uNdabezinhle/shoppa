// Plain-text formatting for sharing a list outside Shoppa (WhatsApp, notes).
import 'aisle_sort.dart';
import 'list_shop_helpers.dart';
import 'lists_repository.dart';
import 'receipt_capture.dart';
import 'session_summary.dart';

/// Options for [formatListAsText] / copy-to-clipboard sheet.
class ListTextFormatOptions {
  const ListTextFormatOptions({
    this.includeChecked = true,
    this.checkboxStyle = true,
    this.groupByAisle = false,
    this.includePrices = false,
    this.checkedOnly = false,
  });

  /// When false, only remaining (unchecked) items are included.
  final bool includeChecked;
  final bool checkboxStyle;
  /// Walk-order aisle headers (shop-friendly WhatsApp paste).
  final bool groupByAisle;
  /// Append paid price when present (e.g. trip recap).
  final bool includePrices;
  /// When true, only checked items (ignores [includeChecked] for filtering).
  final bool checkedOnly;

  /// Remaining-only, bullets, aisle groups — good for “what we still need”.
  static const shoppingShare = ListTextFormatOptions(
    includeChecked: false,
    checkboxStyle: false,
    groupByAisle: true,
  );

  /// Full list with checkboxes (default).
  static const fullChecklist = ListTextFormatOptions();

  /// Checked-off items with paid prices — body of a trip recap share.
  static const tripRecap = ListTextFormatOptions(
    includeChecked: true,
    checkedOnly: true,
    checkboxStyle: false,
    groupByAisle: false,
    includePrices: true,
  );
}

/// Human-readable list text. Round-trips reasonably with [parseBulkItemLines]
/// when [groupByAisle] and [includePrices] are off.
String formatListAsText(
  ShoppaList list, {
  bool includeChecked = true,
  bool checkboxStyle = true,
  bool groupByAisle = false,
  bool includePrices = false,
  bool checkedOnly = false,
  ListTextFormatOptions? options,
}) {
  final opts = options ??
      ListTextFormatOptions(
        includeChecked: includeChecked,
        checkboxStyle: checkboxStyle,
        groupByAisle: groupByAisle,
        includePrices: includePrices,
        checkedOnly: checkedOnly,
      );

  final buf = StringBuffer();
  buf.writeln(list.title);
  if (list.eventName.isNotEmpty) {
    final date = list.eventDate != null ? ' · ${list.eventDate}' : '';
    buf.writeln('${list.eventName}$date');
  }
  if (opts.checkedOnly) {
    buf.writeln('(checked off)');
  } else if (!opts.includeChecked) {
    buf.writeln('(remaining items)');
  }
  buf.writeln();

  final allItems = list.items ?? const <ShoppaListItem>[];
  final items = opts.checkedOnly
      ? allItems.where((i) => i.checked).toList()
      : (opts.includeChecked
          ? allItems
          : allItems.where((i) => !i.checked).toList());

  if (items.isEmpty) {
    buf.writeln(
      opts.checkedOnly
          ? '(nothing checked yet)'
          : (opts.includeChecked ? '(no items)' : '(nothing left to buy)'),
    );
    return buf.toString().trimRight();
  }

  if (opts.groupByAisle) {
    final sections = shopAisleSections(
      items,
      separateChecked: opts.includeChecked,
      includeChecked: opts.includeChecked,
    );
    for (final section in sections) {
      buf.writeln(section.aisle.label.toUpperCase());
      for (final item in section.items) {
        buf.writeln(_formatItemLine(item, opts));
      }
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  for (final item in items) {
    buf.writeln(_formatItemLine(item, opts));
  }
  return buf.toString().trimRight();
}

/// Full trip recap for session summary share (spend, till vs basket, items).
String formatSessionRecapAsText(
  ShoppaList list, {
  SessionSummary? summary,
  int? tillCents,
  int? basketCents,
  bool includeItemLines = true,
}) {
  final items = list.items ?? const <ShoppaListItem>[];
  final s = summary ?? SessionSummary.fromItems(items);
  final buf = StringBuffer();
  buf.writeln(list.title);
  if (list.eventName.isNotEmpty) {
    final date = list.eventDate != null ? ' · ${list.eventDate}' : '';
    buf.writeln('${list.eventName}$date');
  }
  if (s.isComplete) {
    buf.writeln('Trip complete · ${s.checkedItems} items');
  } else {
    buf.writeln('${s.checkedItems} of ${s.totalItems} checked');
  }
  if (s.totalSpentCents > 0) {
    final priced = s.checkedItems - s.checkedWithoutPrice;
    buf.writeln(
      s.hasIncompletePricing
          ? 'Spent ${s.formattedTotalSpent} ($priced/${s.checkedItems} priced)'
          : 'Spent ${s.formattedTotalSpent}',
    );
  } else if (s.checkedItems > 0) {
    buf.writeln('Spent (no prices recorded)');
  }
  final till = tillCents ?? 0;
  if (till > 0) {
    final basket = basketCents ?? s.totalSpentCents;
    buf.writeln(
      TillVsBasket(tillCents: till, basketCents: basket).shareLine,
    );
  }
  if (s.hasSavings) {
    buf.writeln(
      'Could save up to ${s.formattedPotentialSavings} at best store',
    );
  }
  if (!includeItemLines) {
    return buf.toString().trimRight();
  }
  final checked = items.where((i) => i.checked).toList();
  if (checked.isEmpty) {
    buf.writeln();
    buf.writeln('(nothing checked yet)');
    return buf.toString().trimRight();
  }
  buf.writeln();
  for (final item in checked) {
    buf.writeln(
      _formatItemLine(item, ListTextFormatOptions.tripRecap),
    );
  }
  return buf.toString().trimRight();
}

String _formatItemLine(ShoppaListItem item, ListTextFormatOptions opts) {
  final qty = _formatQty(item);
  final mark = opts.checkboxStyle
      ? (item.checked ? '[x] ' : '[ ] ')
      : (item.checked ? '✓ ' : '• ');
  final note = item.note.isNotEmpty ? ' — ${item.note}' : '';
  final price = opts.includePrices && item.paidPrice != null
      ? ' · ${formatCents(item.paidPrice!)}'
      : '';
  return '$mark$qty${item.name}$note$price';
}

String _formatQty(ShoppaListItem item) {
  if (item.quantity == 1 && (item.unit == 'ea' || item.unit.isEmpty)) {
    return '';
  }
  final q = item.quantity == item.quantity.roundToDouble()
      ? item.quantity.toInt().toString()
      : item.quantity.toString();
  if (item.unit == 'ea' || item.unit.isEmpty) {
    return '${q}x ';
  }
  return '$q ${item.unit} ';
}
