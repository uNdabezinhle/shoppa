import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/session_summary.dart';

ShoppaListItem _item({
  required String name,
  bool checked = false,
  int? paidPrice,
}) =>
    ShoppaListItem(
      id: name,
      name: name,
      quantity: 1,
      unit: 'ea',
      note: '',
      checked: checked,
      paidPrice: paidPrice,
    );

void main() {
  group('SessionSummary', () {
    test('empty list is not complete and has no spend', () {
      final summary = SessionSummary.fromItems([]);

      expect(summary.totalItems, 0);
      expect(summary.checkedItems, 0);
      expect(summary.totalSpentCents, 0);
      expect(summary.isComplete, false);
      expect(summary.hasIncompletePricing, false);
    });

    test('sums paid_price only across checked items', () {
      final summary = SessionSummary.fromItems([
        _item(name: 'Milk', checked: true, paidPrice: 2599),
        _item(name: 'Bread', checked: true, paidPrice: 1799),
        _item(name: 'Eggs', checked: false, paidPrice: 5000),
      ]);

      expect(summary.checkedItems, 2);
      expect(summary.totalSpentCents, 4398);
      expect(summary.formattedTotalSpent, 'R43.98');
    });

    test('flags items checked off without a recorded price', () {
      final summary = SessionSummary.fromItems([
        _item(name: 'Milk', checked: true, paidPrice: 2599),
        _item(name: 'Bread', checked: true), // skipped at check-off
      ]);

      expect(summary.checkedItems, 2);
      expect(summary.checkedWithoutPrice, 1);
      expect(summary.hasIncompletePricing, true);
      expect(summary.totalSpentCents, 2599); // unpriced item excluded
    });

    test('isComplete is true only when every item is checked', () {
      final partial = SessionSummary.fromItems([
        _item(name: 'Milk', checked: true),
        _item(name: 'Bread', checked: false),
      ]);
      final complete = SessionSummary.fromItems([
        _item(name: 'Milk', checked: true),
        _item(name: 'Bread', checked: true),
      ]);

      expect(partial.isComplete, false);
      expect(complete.isComplete, true);
    });
  });
}
