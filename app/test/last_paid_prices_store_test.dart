import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/last_paid_prices_store.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/receipt_capture.dart';
import 'package:shoppa_app/core/receipt_history_store.dart';

ShoppaListItem _item(
  String name, {
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
  group('normalizeLastPaidName', () {
    test('collapses case and punctuation', () {
      expect(normalizeLastPaidName('  Milk 2L! '), 'milk 2l');
      expect(normalizeLastPaidName('Brown-Bread'), 'brown bread');
    });
  });

  group('InMemoryLastPaidPricesStore', () {
    test('records and looks up by normalized name', () async {
      final store = InMemoryLastPaidPricesStore();
      await store.record('Milk 2L', 2599);
      expect(await store.getCents('milk 2l'), 2599);
      expect(await store.getCents('MILK 2L'), 2599);
      expect(await store.getCents('Bread'), isNull);
    });

    test('overwrites previous price', () async {
      final store = InMemoryLastPaidPricesStore();
      await store.record('Eggs', 3000);
      await store.record('eggs', 3500);
      expect(await store.getCents('Eggs'), 3500);
    });

    test('ignores empty name and non-positive cents', () async {
      final store = InMemoryLastPaidPricesStore();
      await store.record('  ', 100);
      await store.record('Ok', 0);
      await store.record('Ok', -5);
      expect(await store.getCents('Ok'), isNull);
    });

    test('remove drops entry', () async {
      final store = InMemoryLastPaidPricesStore();
      await store.record('Tea', 1200);
      await store.remove('tea');
      expect(await store.getCents('Tea'), isNull);
    });

    test('snapshot returns all entries', () async {
      final store = InMemoryLastPaidPricesStore();
      await store.record('A', 100);
      await store.record('B', 200);
      final snap = await store.snapshot();
      expect(snap['a'], 100);
      expect(snap['b'], 200);
    });
  });

  group('estimateRemainingSpend', () {
    test('uses line paid price then remembered map', () {
      final items = [
        _item('Milk', paidPrice: 2500),
        _item('Bread'),
        _item('Eggs', checked: true, paidPrice: 9999),
        _item('Unknown'),
      ];
      final est = estimateRemainingSpend(
        items,
        rememberedByName: {
          'bread': 1500,
        },
      );
      expect(est.remainingCount, 3);
      expect(est.pricedCount, 2);
      expect(est.estimatedCents, 4000);
      expect(est.hasEstimate, isTrue);
      expect(est.isComplete, isFalse);
      expect(est.summaryLine, contains('Left est. R40.00'));
      expect(est.summaryLine, contains('2/3'));
    });

    test('empty when no remaining or no prices', () {
      expect(
        estimateRemainingSpend([_item('X', checked: true)]).hasEstimate,
        isFalse,
      );
      expect(
        estimateRemainingSpend([_item('X')]).hasEstimate,
        isFalse,
      );
    });

    test('formatProjectedTripTotal needs both sides', () {
      expect(
        formatProjectedTripTotal(spentCents: 1000, leftEstCents: 2500),
        'Trip est. R35.00',
      );
      expect(
        formatProjectedTripTotal(spentCents: 0, leftEstCents: 2500),
        isNull,
      );
      expect(
        formatProjectedTripTotal(spentCents: 1000, leftEstCents: 0),
        isNull,
      );
    });
  });

  group('listMoneyTeaserBits', () {
    test('includes last till and remaining estimate', () {
      final receipt = loggedReceiptFromCapture(
        capture: const ReceiptCapture(
          totalCents: 12500,
          storeName: 'Checkers',
        ),
        scopeId: 'list-1',
      );
      final bits = listMoneyTeaserBits(
        lastReceipt: receipt,
        items: [
          _item('Milk', paidPrice: 2500),
          _item('Bread'),
        ],
        rememberedByName: {normalizeLastPaidName('Bread'): 1800},
      );
      expect(bits.first, contains('last till R125.00'));
      expect(bits.first, contains('Checkers'));
      expect(bits.any((b) => b.startsWith('Left est.')), isTrue);
    });

    test('empty when no receipt and no priced remaining', () {
      expect(
        listMoneyTeaserBits(items: [_item('Milk')]),
        isEmpty,
      );
    });
  });
}
