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

/// Shop mode: unchecked first, then checked. Preserves relative order within
/// each group (server `position` is not rewritten).
List<ShoppaListItem> itemsForDisplay(
  List<ShoppaListItem> items, {
  required bool shopMode,
}) {
  if (!shopMode || items.isEmpty) return List<ShoppaListItem>.from(items);
  final unchecked = <ShoppaListItem>[];
  final checked = <ShoppaListItem>[];
  for (final item in items) {
    if (item.checked) {
      checked.add(item);
    } else {
      unchecked.add(item);
    }
  }
  return [...unchecked, ...checked];
}
