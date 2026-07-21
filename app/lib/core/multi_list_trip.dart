// Helpers for multi-list shopping trips (combined remaining items).
import 'aisle_sort.dart';
import 'list_shop_helpers.dart';
import 'lists_repository.dart';
import 'receipt_capture.dart';

/// One remaining (or in-session) item tied to its source list.
class TripLine {
  const TripLine({
    required this.listId,
    required this.listTitle,
    required this.item,
  });

  final String listId;
  final String listTitle;
  final ShoppaListItem item;

  String get key => '$listId:${item.id}';

  TripLine copyWithItem(ShoppaListItem item) => TripLine(
        listId: listId,
        listTitle: listTitle,
        item: item,
      );
}

/// Deep link for a multi-list trip (`/trip?lists=id1,id2`).
String multiListTripPath(Iterable<String> listIds) {
  final ids = listIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  if (ids.isEmpty) return '/trip';
  final encoded = ids.map(Uri.encodeQueryComponent).join(',');
  return '/trip?lists=$encoded';
}

/// Parse `lists` query values (comma-separated, order preserved first-seen).
List<String> parseTripListIds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final part in raw.split(',')) {
    final id = Uri.decodeQueryComponent(part.trim());
    if (id.isEmpty || seen.contains(id)) continue;
    seen.add(id);
    out.add(id);
  }
  return out;
}

/// Build trip lines from loaded lists (remaining items by default).
List<TripLine> buildTripLines(
  List<ShoppaList> lists, {
  bool includeChecked = false,
}) {
  final lines = <TripLine>[];
  for (final list in lists) {
    for (final item in list.items ?? const <ShoppaListItem>[]) {
      if (!includeChecked && item.checked) continue;
      lines.add(
        TripLine(
          listId: list.id,
          listTitle: list.title,
          item: item,
        ),
      );
    }
  }
  return lines;
}

/// Lists the current user can add items to during a multi-list trip.
List<ShoppaList> tripEditableLists(List<ShoppaList> lists) =>
    lists.where((l) => l.canEdit).toList(growable: false);

/// Resolve which list receives a trip quick-add.
///
/// Prefers [preferredListId] when that list is editable; otherwise the first
/// editable list. Returns null when nothing is writable.
ShoppaList? resolveTripAddTarget(
  List<ShoppaList> lists, {
  String? preferredListId,
}) {
  final editable = tripEditableLists(lists);
  if (editable.isEmpty) return null;
  if (preferredListId != null && preferredListId.isNotEmpty) {
    for (final list in editable) {
      if (list.id == preferredListId) return list;
    }
  }
  return editable.first;
}

/// Open (unchecked) items for [listId] currently on the trip.
List<ShoppaListItem> tripItemsForList(List<TripLine> lines, String listId) {
  return lines
      .where((l) => l.listId == listId)
      .map((l) => l.item)
      .toList(growable: false);
}

/// Snack / status line after trip quick-add (create and/or qty merge).
String formatTripQuickAddResult({
  required String listTitle,
  required int createdCount,
  required int mergedCount,
  String? singleName,
  num? singleQty,
  String singleUnit = 'ea',
}) {
  if (createdCount <= 0 && mergedCount <= 0) return '';
  if (createdCount == 1 && mergedCount == 0 && singleName != null) {
    return 'Added $singleName to $listTitle';
  }
  if (mergedCount == 1 && createdCount == 0 && singleName != null) {
    final qty = singleQty ?? 0;
    final unit = singleUnit == 'ea' || singleUnit.isEmpty ? '' : ' $singleUnit';
    return 'Updated “$singleName”: qty $qty$unit';
  }
  if (createdCount > 0 && mergedCount > 0) {
    return 'Added $createdCount · merged $mergedCount on $listTitle';
  }
  if (mergedCount > 0) {
    return 'Merged $mergedCount item${mergedCount == 1 ? '' : 's'} on $listTitle';
  }
  return 'Added $createdCount item${createdCount == 1 ? '' : 's'} to $listTitle';
}

/// Normalize name + unit for cross-list duplicate matching.
String tripItemMatchKey(ShoppaListItem item) {
  final n = item.name.trim().toLowerCase();
  final u = item.unit.trim().toLowerCase();
  final unit = u.isEmpty ? 'ea' : u;
  return '$n|$unit';
}

/// Index of open items that appear on 2+ lists: match key → listId → title.
///
/// Used to warn “also on Party” when the same product sits on multiple trip lists.
Map<String, Map<String, String>> indexCrossListDuplicates(List<TripLine> lines) {
  final byKey = <String, Map<String, String>>{};
  for (final line in lines) {
    if (line.item.checked) continue;
    final key = tripItemMatchKey(line.item);
    if (key.startsWith('|')) continue;
    byKey.putIfAbsent(key, () => {})[line.listId] = line.listTitle;
  }
  byKey.removeWhere((_, lists) => lists.length < 2);
  return byKey;
}

/// Other list titles that still need the same item as [line] (open only).
List<String> otherListsWithSameItem(
  TripLine line,
  Map<String, Map<String, String>> crossListIndex,
) {
  if (line.item.checked) return const [];
  final lists = crossListIndex[tripItemMatchKey(line.item)];
  if (lists == null || lists.length < 2) return const [];
  final others = lists.entries
      .where((e) => e.key != line.listId)
      .map((e) => e.value)
      .toList()
    ..sort();
  return others;
}

/// e.g. `Also on Party` or `Also on Party · Weekly`.
String? formatCrossListDuplicateHint(List<String> otherListTitles) {
  if (otherListTitles.isEmpty) return null;
  if (otherListTitles.length == 1) {
    return 'Also on ${otherListTitles.first}';
  }
  return 'Also on ${otherListTitles.join(' · ')}';
}

/// How many open product names appear on more than one trip list.
int crossListDuplicateGroupCount(Map<String, Map<String, String>> index) =>
    index.length;

/// Open trip lines that match [line]'s name + unit (includes [line] itself).
List<TripLine> matchingOpenTripLines(TripLine line, List<TripLine> all) {
  if (line.item.checked) return const [];
  final key = tripItemMatchKey(line.item);
  if (key.startsWith('|')) return const [];
  return all
      .where((l) => !l.item.checked && tripItemMatchKey(l.item) == key)
      .toList(growable: false);
}

/// Keep only open lines whose name+unit appears on 2+ lists.
///
/// When [enabled] is false, returns [lines] unchanged. Checked lines are
/// dropped while filtering (they are no longer cross-list risks).
List<TripLine> filterCrossListDuplicates(
  List<TripLine> lines, {
  required bool enabled,
  Map<String, Map<String, String>>? index,
}) {
  if (!enabled) return lines;
  final dupIndex = index ?? indexCrossListDuplicates(lines);
  if (dupIndex.isEmpty) return const [];
  return lines
      .where((l) {
        if (l.item.checked) return false;
        return dupIndex.containsKey(tripItemMatchKey(l.item));
      })
      .toList(growable: false);
}

/// Aisle sections for trip lines (walk order; checked optional at end).
class TripAisleSection {
  const TripAisleSection({required this.aisle, required this.lines});

  final AisleGroup aisle;
  final List<TripLine> lines;
}

/// Open (unchecked) trip lines that belong to [aisleId] (not the checked bucket).
List<TripLine> openTripLinesInAisle(
  List<TripLine> lines,
  String aisleId, {
  Map<String, String>? aisleOverrides,
}) {
  if (aisleId.isEmpty || aisleId == 'checked') return const [];
  return lines
      .where(
        (l) =>
            !l.item.checked &&
            aisleForItem(l.item, aisleOverrides: aisleOverrides).id == aisleId,
      )
      .toList(growable: false);
}

/// Remaining (unchecked) lines for end-of-trip “left behind” recap.
List<TripLine> leftBehindTripLines(List<TripLine> lines) =>
    lines.where((l) => !l.item.checked).toList(growable: false);

/// Expand every aisle that still has open items (clear those collapse flags).
Set<String> expandOpenAisleIds({
  required Set<String> collapsedIds,
  required Iterable<String> openAisleIds,
}) {
  if (collapsedIds.isEmpty) return collapsedIds;
  final open = openAisleIds.toSet();
  if (open.isEmpty) return Set<String>.from(collapsedIds);
  return collapsedIds.where((id) => !open.contains(id)).toSet();
}

/// One item that failed during a multi-list batch check-off / undo.
class TripBatchFailure {
  const TripBatchFailure({
    required this.lineKey,
    required this.listId,
    required this.listTitle,
    required this.itemName,
    required this.message,
  });

  final String lineKey;
  final String listId;
  final String listTitle;
  final String itemName;
  final String message;
}

/// Outcome of applying check-off (or undo) across several trip lines.
class TripBatchOutcome {
  const TripBatchOutcome({
    required this.succeededKeys,
    required this.failures,
  });

  final List<String> succeededKeys;
  final List<TripBatchFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
  bool get allFailed =>
      succeededKeys.isEmpty && failures.isNotEmpty;
  bool get allSucceeded => failures.isEmpty && succeededKeys.isNotEmpty;
  int get attempted => succeededKeys.length + failures.length;
}

/// Snack / dialog headline for a batch outcome.
String formatTripBatchOutcome(TripBatchOutcome outcome) {
  final ok = outcome.succeededKeys.length;
  final bad = outcome.failures.length;
  if (outcome.allSucceeded) {
    if (ok == 1) return 'Updated 1 item';
    return 'Updated $ok items';
  }
  if (outcome.allFailed) {
    if (bad == 1) return 'Could not update 1 item';
    return 'Could not update $bad items';
  }
  return 'Updated $ok · $bad failed';
}

/// Per-list failure lines for a dialog body (newest failures first-seen).
List<String> formatTripBatchFailureLines(
  TripBatchOutcome outcome, {
  int limit = 6,
}) {
  if (outcome.failures.isEmpty) return const [];
  final byList = <String, List<String>>{};
  for (final f in outcome.failures) {
    byList.putIfAbsent(f.listTitle, () => []).add(f.itemName);
  }
  final lines = <String>[];
  for (final e in byList.entries) {
    final names = e.value;
    final shown = names.take(3).join(', ');
    final extra = names.length > 3 ? ' +${names.length - 3}' : '';
    lines.add('${e.key}: $shown$extra');
    if (lines.length >= limit) break;
  }
  return lines;
}

/// Apply [item] onto [lines] when keys match; returns a new list.
List<TripLine> replaceTripLineItem(
  List<TripLine> lines,
  String lineKey,
  ShoppaListItem item,
) {
  return lines
      .map((l) => l.key == lineKey ? l.copyWithItem(item) : l)
      .toList(growable: false);
}

List<TripAisleSection> tripAisleSections(
  List<TripLine> lines, {
  bool separateChecked = true,
  bool includeChecked = true,
  StoreAisleLayout? layout,
  Map<String, String>? aisleOverrides,
}) {
  if (lines.isEmpty) return const [];

  final open = <TripLine>[];
  final done = <TripLine>[];
  for (final line in lines) {
    if (separateChecked && line.item.checked) {
      if (includeChecked) done.add(line);
    } else if (!line.item.checked || !separateChecked) {
      open.add(line);
    }
  }

  final byAisle = <String, List<TripLine>>{};
  for (final line in open) {
    final aisle = aisleForItem(line.item, aisleOverrides: aisleOverrides);
    byAisle.putIfAbsent(aisle.id, () => []).add(line);
  }

  final walk = aisleGroupsForLayout(layout ?? storeAisleLayoutById('default'));
  final sections = <TripAisleSection>[];
  for (final group in walk) {
    final groupLines = byAisle[group.id];
    if (groupLines == null || groupLines.isEmpty) continue;
    sections.add(TripAisleSection(aisle: group, lines: groupLines));
  }

  if (done.isNotEmpty) {
    sections.add(
      TripAisleSection(
        aisle: const AisleGroup(id: 'checked', label: 'Checked off', order: 99),
        lines: done,
      ),
    );
  }
  return sections;
}

/// Filter trip lines by free-text query (item name, note, list title).
/// Empty/whitespace query returns [lines] unchanged.
List<TripLine> filterTripLines(List<TripLine> lines, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return lines;
  return lines
      .where((l) {
        if (l.item.name.toLowerCase().contains(q)) return true;
        if (l.listTitle.toLowerCase().contains(q)) return true;
        if (l.item.note.toLowerCase().contains(q)) return true;
        return false;
      })
      .toList(growable: false);
}

/// Keep only lines from one source list. Null/empty [listId] is a no-op.
List<TripLine> filterTripLinesByListId(List<TripLine> lines, String? listId) {
  final id = listId?.trim() ?? '';
  if (id.isEmpty) return lines;
  return lines.where((l) => l.listId == id).toList(growable: false);
}

/// Open (unchecked) line counts keyed by list id.
Map<String, int> tripOpenCountByListId(List<TripLine> lines) {
  final out = <String, int>{};
  for (final l in lines) {
    if (l.item.checked) continue;
    out[l.listId] = (out[l.listId] ?? 0) + 1;
  }
  return out;
}

/// Stable chip labels for trip list filters (id + title + open count).
List<({String id, String title, int open})> tripListFilterOptions(
  List<TripLine> lines, {
  List<ShoppaList>? sourceLists,
}) {
  final openById = tripOpenCountByListId(lines);
  final titles = <String, String>{};
  for (final l in lines) {
    titles.putIfAbsent(l.listId, () => l.listTitle);
  }
  if (sourceLists != null) {
    for (final s in sourceLists) {
      titles.putIfAbsent(s.id, () => s.title);
    }
  }
  // Prefer source list order when available; else first-seen in lines.
  final orderedIds = <String>[];
  final seen = <String>{};
  if (sourceLists != null) {
    for (final s in sourceLists) {
      if (seen.add(s.id)) orderedIds.add(s.id);
    }
  }
  for (final l in lines) {
    if (seen.add(l.listId)) orderedIds.add(l.listId);
  }
  return [
    for (final id in orderedIds)
      (id: id, title: titles[id] ?? id, open: openById[id] ?? 0),
  ];
}

/// Remaining-item counts for incomplete source lists (for picker UI).
int remainingItemCount(ShoppaList list) {
  if (list.items != null) {
    return list.items!.where((i) => !i.checked).length;
  }
  // Summary rows only expose checked/total.
  final left = list.itemCount - list.checkedCount;
  return left < 0 ? 0 : left;
}

/// Whether a list is a good multi-trip candidate.
bool listEligibleForTrip(ShoppaList list) => listIsIncompleteTrip(list);

/// Spend across trip lines (checked items with a paid price).
TripSpend tripSpendFromLines(List<TripLine> lines) =>
    tripSpend(lines.map((l) => l.item).toList());

/// Plain-text trip summary for share / clipboard.
///
/// [mode]:
/// - `remaining` — still to buy
/// - `checked` — trip recap of checked-off lines
/// - `all` — full session snapshot
String formatTripAsText(
  List<TripLine> lines, {
  String title = 'Today’s trip',
  List<String> listTitles = const [],
  TripTextMode mode = TripTextMode.all,
  bool includePrices = true,
  bool groupByList = true,
  /// Optional till total for recap (with basket spend comparison when spend exists).
  int? tillCents,
  int? basketCents,
}) {
  final filtered = switch (mode) {
    TripTextMode.remaining => lines.where((l) => !l.item.checked).toList(),
    TripTextMode.checked => lines.where((l) => l.item.checked).toList(),
    TripTextMode.all => List<TripLine>.from(lines),
  };

  final buf = StringBuffer();
  buf.writeln(title);
  if (listTitles.isNotEmpty) {
    buf.writeln(listTitles.join(' · '));
  }
  final spend = tripSpendFromLines(
    mode == TripTextMode.remaining
        ? lines.where((l) => l.item.checked).toList()
        : (mode == TripTextMode.checked
            ? filtered
            : lines.where((l) => l.item.checked).toList()),
  );
  if (mode == TripTextMode.checked || mode == TripTextMode.all) {
    final checkedN = lines.where((l) => l.item.checked).length;
    final leftN = lines.where((l) => !l.item.checked).length;
    if (mode == TripTextMode.checked) {
      buf.writeln('$checkedN checked');
    } else {
      buf.writeln('$checkedN checked · $leftN left');
    }
    if (spend.hasSpend) {
      buf.writeln(
        spend.hasIncompletePricing
            ? 'Spent ${spend.formatted} (${spend.pricedCount}/${spend.checkedCount} priced)'
            : 'Spent ${spend.formatted}',
      );
    }
    final till = tillCents ?? 0;
    if (till > 0) {
      final basket = basketCents ?? spend.spentCents;
      final cmp = TillVsBasket(tillCents: till, basketCents: basket);
      buf.writeln(cmp.shareLine);
    }
  } else {
    buf.writeln('(${filtered.length} remaining)');
  }
  buf.writeln();

  if (filtered.isEmpty) {
    buf.writeln(
      mode == TripTextMode.remaining
          ? '(nothing left to buy)'
          : (mode == TripTextMode.checked
              ? '(nothing checked yet)'
              : '(no items)'),
    );
    return buf.toString().trimRight();
  }

  if (groupByList) {
    final byList = <String, List<TripLine>>{};
    final order = <String>[];
    for (final line in filtered) {
      byList.putIfAbsent(line.listId, () {
        order.add(line.listId);
        return [];
      }).add(line);
    }
    for (final listId in order) {
      final group = byList[listId]!;
      buf.writeln(group.first.listTitle.toUpperCase());
      for (final line in group) {
        buf.writeln(_formatTripItemLine(line, includePrices: includePrices));
      }
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  for (final line in filtered) {
    buf.writeln(_formatTripItemLine(line, includePrices: includePrices));
  }
  return buf.toString().trimRight();
}

enum TripTextMode { remaining, checked, all }

String _formatTripItemLine(TripLine line, {required bool includePrices}) {
  final item = line.item;
  final mark = item.checked ? '[x] ' : '[ ] ';
  final qty = _formatTripQty(item);
  final note = item.note.isNotEmpty ? ' — ${item.note}' : '';
  final price = includePrices && item.paidPrice != null
      ? ' · ${formatCents(item.paidPrice!)}'
      : '';
  return '$mark$qty${item.name}$note$price';
}

String _formatTripQty(ShoppaListItem item) {
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
