/// Session summary shown when finishing a shopping trip (SRS FR-4.4:
/// "present a session summary of spend and savings on completion").
/// Savings requires a comparison price, which doesn't exist until
/// price_intelligence (Phase 3) lands -- this is scoped to spend and
/// completion stats for now, computed purely from what's already on the
/// list (no extra network call), so it works offline too.
import 'lists_repository.dart';

class SessionSummary {
  SessionSummary({
    required this.totalItems,
    required this.checkedItems,
    required this.totalSpentCents,
    required this.checkedWithoutPrice,
  });

  factory SessionSummary.fromItems(List<ShoppaListItem> items) {
    var checked = 0;
    var spent = 0;
    var withoutPrice = 0;
    for (final item in items) {
      if (!item.checked) continue;
      checked++;
      final price = item.paidPrice;
      if (price != null) {
        spent += price;
      } else {
        withoutPrice++;
      }
    }
    return SessionSummary(
      totalItems: items.length,
      checkedItems: checked,
      totalSpentCents: spent,
      checkedWithoutPrice: withoutPrice,
    );
  }

  final int totalItems;
  final int checkedItems;
  /// Sum of paid_price (minor units/cents) across checked items that have
  /// a recorded price. Items checked off without a price (skipped at
  /// check-off, see FR-4.3) are excluded from this total but counted in
  /// checkedWithoutPrice so the summary can flag that it's partial.
  final int totalSpentCents;
  final int checkedWithoutPrice;

  bool get isComplete => totalItems > 0 && checkedItems == totalItems;
  bool get hasIncompletePricing => checkedWithoutPrice > 0;

  /// Rand-formatted total, e.g. "R123.45". Currency/locale beyond ZAR is
  /// out of scope until multi-region launch (Architecture §5.1).
  String get formattedTotalSpent =>
      'R${(totalSpentCents / 100).toStringAsFixed(2)}';
}
