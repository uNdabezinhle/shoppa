/// Pure helpers for list shopping UX (progress + shop-mode display order).
import 'lists_repository.dart';

class ListProgress {
  const ListProgress({required this.total, required this.checked});

  final int total;
  final int checked;

  int get remaining => total - checked;
  double get fraction => total == 0 ? 0.0 : checked / total;
  int get percent => (fraction * 100).round();
  bool get hasItems => total > 0;
  bool get isComplete => total > 0 && checked == total;
}

ListProgress listProgress(List<ShoppaListItem> items) {
  var checked = 0;
  for (final item in items) {
    if (item.checked) checked++;
  }
  return ListProgress(total: items.length, checked: checked);
}

/// Running spend from checked items that recorded a [ShoppaListItem.paidPrice].
class TripSpend {
  const TripSpend({
    required this.spentCents,
    required this.pricedCount,
    required this.checkedCount,
  });

  final int spentCents;
  final int pricedCount;
  final int checkedCount;

  bool get hasSpend => spentCents > 0;
  bool get hasIncompletePricing =>
      checkedCount > 0 && pricedCount < checkedCount;

  String get formatted => 'R${(spentCents / 100).toStringAsFixed(2)}';
}

TripSpend tripSpend(List<ShoppaListItem> items) {
  var spent = 0;
  var priced = 0;
  var checked = 0;
  for (final item in items) {
    if (!item.checked) continue;
    checked++;
    final price = item.paidPrice;
    if (price != null) {
      spent += price;
      priced++;
    }
  }
  return TripSpend(
    spentCents: spent,
    pricedCount: priced,
    checkedCount: checked,
  );
}

/// Step quantity up/down for list item steppers.
/// Whole quantities step by 1; fractional by 0.5. Floor is one step.
double adjustItemQuantity(num current, int direction) {
  final value = current.toDouble();
  final isWhole = value == value.roundToDouble();
  final step = isWhole ? 1.0 : 0.5;
  var next = value + direction * step;
  if (next < step) next = step;
  if (next == next.roundToDouble()) {
    return next.roundToDouble();
  }
  return double.parse(next.toStringAsFixed(2));
}

String formatItemQuantity(num quantity) {
  if (quantity == quantity.roundToDouble()) {
    return quantity.toInt().toString();
  }
  return quantity.toString();
}

/// Sort My Lists: recent (updated_at desc), title A–Z, or item count desc.
/// When [pinnedIds] is set, pinned lists float to the top (order within
/// pinned/unpinned groups still follows [mode]).
enum ListSortMode { recent, title, itemCount }

List<ShoppaList> sortShoppaLists(
  List<ShoppaList> lists, {
  required ListSortMode mode,
  Set<String>? pinnedIds,
}) {
  final out = List<ShoppaList>.from(lists);
  switch (mode) {
    case ListSortMode.recent:
      out.sort((a, b) {
        final ad = a.updatedAtDate;
        final bd = b.updatedAtDate;
        if (ad == null && bd == null) {
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
    case ListSortMode.title:
      out.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case ListSortMode.itemCount:
      out.sort((a, b) {
        final byCount = b.itemCount.compareTo(a.itemCount);
        if (byCount != 0) return byCount;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
  }
  final pins = pinnedIds;
  if (pins == null || pins.isEmpty) return out;
  final pinned = <ShoppaList>[];
  final rest = <ShoppaList>[];
  for (final list in out) {
    if (pins.contains(list.id)) {
      pinned.add(list);
    } else {
      rest.add(list);
    }
  }
  return [...pinned, ...rest];
}

/// Pick a store total from a comparison (shopping-at store, else best).
ShoppaStoreComparison? pickComparisonStore(
  ShoppaComparison comparison, {
  String? preferredStoreId,
}) {
  if (comparison.stores.isEmpty) return null;
  if (preferredStoreId != null) {
    for (final s in comparison.stores) {
      if (s.storeId == preferredStoreId) return s;
    }
  }
  if (comparison.bestStoreId != null) {
    for (final s in comparison.stores) {
      if (s.storeId == comparison.bestStoreId) return s;
    }
  }
  return comparison.stores.first;
}

String formatCents(int cents) => 'R${(cents / 100).toStringAsFixed(2)}';

/// Checked off but no paid price recorded (common with fast check-off).
bool itemNeedsPaidPrice(ShoppaListItem item) =>
    item.checked && item.paidPrice == null;

/// Checked items still missing a paid price, in list order.
List<ShoppaListItem> itemsMissingPaidPrice(List<ShoppaListItem> items) =>
    items.where(itemNeedsPaidPrice).toList();

String _normUnit(String unit) {
  final u = unit.trim().toLowerCase();
  return u.isEmpty ? 'ea' : u;
}

/// Unchecked item with the same name + unit (case-insensitive), if any.
ShoppaListItem? findMatchingListItem(
  List<ShoppaListItem> items, {
  required String name,
  String unit = 'ea',
}) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return null;
  final u = _normUnit(unit);
  for (final item in items) {
    if (item.checked) continue;
    if (item.name.trim().toLowerCase() != n) continue;
    if (_normUnit(item.unit) != u) continue;
    return item;
  }
  return null;
}

/// Case-insensitive filter on name + note (in-list search).
List<ShoppaListItem> filterListItems(
  List<ShoppaListItem> items,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List<ShoppaListItem>.from(items);
  return items
      .where(
        (i) =>
            i.name.toLowerCase().contains(q) ||
            i.note.toLowerCase().contains(q),
      )
      .toList();
}

/// All items, only remaining (unchecked), or only checked-off.
enum ItemViewFilter { all, remaining, checked }

List<ShoppaListItem> applyItemViewFilter(
  List<ShoppaListItem> items,
  ItemViewFilter filter,
) {
  switch (filter) {
    case ItemViewFilter.all:
      return List<ShoppaListItem>.from(items);
    case ItemViewFilter.remaining:
      return items.where((i) => !i.checked).toList();
    case ItemViewFilter.checked:
      return items.where((i) => i.checked).toList();
  }
}

/// Manual = server position (shop mode still groups unchecked first).
/// Name = A–Z by item name (case-insensitive).
enum ItemOrderMode { manual, name }

/// Shop mode: unchecked first, then checked. Preserves relative order within
/// each group (server `position` is not rewritten).
List<ShoppaListItem> itemsForDisplay(
  List<ShoppaListItem> items, {
  required bool shopMode,
  ItemOrderMode order = ItemOrderMode.manual,
}) {
  final base = List<ShoppaListItem>.from(items);
  if (order == ItemOrderMode.name) {
    base.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return base;
  }
  if (!shopMode || base.isEmpty) return base;
  final unchecked = <ShoppaListItem>[];
  final checked = <ShoppaListItem>[];
  for (final item in base) {
    if (item.checked) {
      checked.add(item);
    } else {
      unchecked.add(item);
    }
  }
  return [...unchecked, ...checked];
}

/// Lists with items still left to shop (not empty, not fully checked).
bool listIsIncompleteTrip(ShoppaList list) {
  if (list.itemCount <= 0) return false;
  return list.checkedCount < list.itemCount;
}

/// Deep link to a list detail screen.
///
/// Pass [shop] `true` to open already in shop mode (`?shop=1`).
String listDetailPath(
  String listId, {
  String? title,
  bool shop = false,
}) {
  final params = <String, String>{};
  if (title != null && title.isNotEmpty) {
    params['title'] = title;
  }
  if (shop) {
    params['shop'] = '1';
  }
  if (params.isEmpty) return '/lists/$listId';
  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return '/lists/$listId?$query';
}

/// Human-friendly relative time for list index ("2h ago").
/// [now] is injectable for tests.
String formatRelativeTime(DateTime? when, {DateTime? now}) {
  if (when == null) return '';
  final n = now ?? DateTime.now();
  final local = when.isUtc ? when.toLocal() : when;
  final d = n.difference(local);
  if (d.isNegative || d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  if (d.inDays < 30) {
    final weeks = (d.inDays / 7).floor();
    return '${weeks}w ago';
  }
  if (d.inDays < 365) {
    final months = (d.inDays / 30).floor().clamp(1, 11);
    return '${months}mo ago';
  }
  final years = (d.inDays / 365).floor().clamp(1, 99);
  return '${years}y ago';
}

/// Common quantity presets for the quick-set sheet.
const kQuantityPresets = <num>[1, 2, 3, 4, 6, 12];
