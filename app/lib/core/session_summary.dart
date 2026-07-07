/// Session summary shown when finishing a shopping trip (SRS FR-4.4:
/// "present a session summary of spend and savings on completion").
/// Savings come from the list comparison when catalogue-linked items
/// have prices (M3 / FR-5.3).
import 'lists_repository.dart';

class SessionSummary {
  SessionSummary({
    required this.totalItems,
    required this.checkedItems,
    required this.totalSpentCents,
    required this.checkedWithoutPrice,
    this.potentialSavingsCents,
  });

  factory SessionSummary.fromItems(
    List<ShoppaListItem> items, {
    ShoppaComparison? comparison,
  }) {
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
      potentialSavingsCents:
          comparison?.bestSaves != null && comparison!.bestSaves! > 0
              ? comparison.bestSaves
              : null,
    );
  }

  final int totalItems;
  final int checkedItems;
  final int totalSpentCents;
  final int checkedWithoutPrice;
  final int? potentialSavingsCents;

  bool get isComplete => totalItems > 0 && checkedItems == totalItems;
  bool get hasIncompletePricing => checkedWithoutPrice > 0;
  bool get hasSavings =>
      potentialSavingsCents != null && potentialSavingsCents! > 0;

  String get formattedTotalSpent =>
      'R${(totalSpentCents / 100).toStringAsFixed(2)}';

  String get formattedPotentialSavings =>
      'R${(potentialSavingsCents! / 100).toStringAsFixed(2)}';
}