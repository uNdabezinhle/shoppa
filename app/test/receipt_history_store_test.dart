import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/receipt_capture.dart';
import 'package:shoppa_app/core/receipt_history_store.dart';

void main() {
  group('InMemoryReceiptHistoryStore', () {
    test('adds and filters by scope', () async {
      final store = InMemoryReceiptHistoryStore();
      final a = loggedReceiptFromCapture(
        capture: const ReceiptCapture(
          totalCents: 1000,
          storeName: 'Checkers',
          source: ReceiptSource.manual,
        ),
        scopeId: 'list-a',
        pricesFilled: 2,
      );
      final b = loggedReceiptFromCapture(
        capture: const ReceiptCapture(
          totalCents: 2000,
          source: ReceiptSource.pastedText,
        ),
        scopeId: 'list-b',
      );
      await store.add(a);
      await store.add(b);

      expect((await store.forScope('list-a')).single.totalCents, 1000);
      expect((await store.latestForScope('list-a'))?.storeName, 'Checkers');
      expect((await store.recent()).length, 2);

      await store.clearScope('list-a');
      expect(await store.forScope('list-a'), isEmpty);
      expect((await store.forScope('list-b')).length, 1);
    });

    test('tripScopeId is stable and sorted', () {
      expect(
        LoggedReceipt.tripScopeId(['b', 'a', 'a']),
        'trip:a,b',
      );
    });
  });

  group('loggedReceiptFromCapture', () {
    test('maps fields including basket delta', () {
      final r = loggedReceiptFromCapture(
        capture: const ReceiptCapture(
          totalCents: 4499,
          storeName: 'Spar',
          notes: 'card',
          source: ReceiptSource.pastedText,
        ),
        scopeId: 'l1',
        pricesFilled: 3,
        listTitles: const ['Home'],
        basketCents: 4000,
        now: DateTime.utc(2026, 7, 20, 12),
        id: 'fixed',
      );
      expect(r.id, 'fixed');
      expect(r.formattedTotal, 'R44.99');
      expect(r.pricesFilled, 3);
      expect(r.basketCents, 4000);
      expect(r.toJson()['scopeId'], 'l1');
      expect(r.tillVsBasket?.over, isTrue);
      expect(r.tillVsBasket?.deltaCents, 499);
      final roundTrip = LoggedReceipt.fromJson(r.toJson());
      expect(roundTrip.storeName, 'Spar');
      expect(roundTrip.basketCents, 4000);
    });
  });

  group('indexLatestReceiptsByScope', () {
    test('keeps first (newest) receipt per scope', () {
      final newer = loggedReceiptFromCapture(
        capture: const ReceiptCapture(totalCents: 3000, storeName: 'New'),
        scopeId: 'a',
        id: 'new',
      );
      final older = loggedReceiptFromCapture(
        capture: const ReceiptCapture(totalCents: 1000, storeName: 'Old'),
        scopeId: 'a',
        id: 'old',
      );
      final other = loggedReceiptFromCapture(
        capture: const ReceiptCapture(totalCents: 2000),
        scopeId: 'b',
        id: 'b1',
      );
      final map = indexLatestReceiptsByScope([newer, older, other]);
      expect(map['a']?.id, 'new');
      expect(map['a']?.formattedTotal, 'R30.00');
      expect(map['b']?.id, 'b1');
      expect(map.length, 2);
    });
  });

  group('frequentStoreNames / removeById', () {
    test('ranks by frequency then recency', () {
      final rows = [
        loggedReceiptFromCapture(
          capture: const ReceiptCapture(
            totalCents: 1000,
            storeName: 'Checkers',
          ),
          scopeId: 'a',
          id: '1',
        ),
        loggedReceiptFromCapture(
          capture: const ReceiptCapture(
            totalCents: 2000,
            storeName: 'spar',
          ),
          scopeId: 'b',
          id: '2',
        ),
        loggedReceiptFromCapture(
          capture: const ReceiptCapture(
            totalCents: 3000,
            storeName: 'CHECKERS',
          ),
          scopeId: 'c',
          id: '3',
        ),
        loggedReceiptFromCapture(
          capture: const ReceiptCapture(
            totalCents: 4000,
            storeName: 'Woolworths',
          ),
          scopeId: 'd',
          id: '4',
        ),
      ];
      // Newest first: Checkers, spar, CHECKERS, Woolworths
      // Checkers x2, others x1 → Checkers first, then spar (newer than Woolworths)
      expect(frequentStoreNames(rows), ['Checkers', 'spar', 'Woolworths']);
    });

    test('removeById drops one entry', () async {
      final store = InMemoryReceiptHistoryStore();
      final a = loggedReceiptFromCapture(
        capture: const ReceiptCapture(totalCents: 1000),
        scopeId: 'x',
        id: 'keep',
      );
      final b = loggedReceiptFromCapture(
        capture: const ReceiptCapture(totalCents: 2000),
        scopeId: 'x',
        id: 'drop',
      );
      await store.add(a);
      await store.add(b);
      await store.removeById('drop');
      final left = await store.forScope('x');
      expect(left.map((r) => r.id), ['keep']);
    });
  });

  group('ReceiptSpendInsights', () {
    test('aggregates totals, average, and net basket variance', () {
      final rows = [
        loggedReceiptFromCapture(
          capture: const ReceiptCapture(totalCents: 10000),
          scopeId: 'a',
          basketCents: 9000,
          id: '1',
          now: DateTime.utc(2026, 7, 1),
        ),
        loggedReceiptFromCapture(
          capture: const ReceiptCapture(totalCents: 20000),
          scopeId: 'b',
          basketCents: 21000,
          id: '2',
          now: DateTime.utc(2026, 7, 2),
        ),
        loggedReceiptFromCapture(
          capture: const ReceiptCapture(totalCents: 15000),
          scopeId: 'c',
          basketCents: 15000,
          id: '3',
          now: DateTime.utc(2026, 7, 3),
        ),
      ];
      final insights = ReceiptSpendInsights.from(rows);
      expect(insights.receiptCount, 3);
      expect(insights.totalTillCents, 45000);
      expect(insights.averageTillCents, 15000);
      expect(insights.formattedAverage, 'R150.00');
      expect(insights.withBasketCount, 3);
      // +1000 -1000 +0
      expect(insights.netDeltaCents, 0);
      expect(insights.overCount, 1);
      expect(insights.underCount, 1);
      expect(insights.matchCount, 1);
      expect(insights.summaryLine, contains('3 receipts'));
      expect(insights.varianceLine, contains('matched'));
    });

    test('empty and till-only rows', () {
      expect(ReceiptSpendInsights.from([]).isEmpty, isTrue);
      final tillOnly = ReceiptSpendInsights.from([
        loggedReceiptFromCapture(
          capture: const ReceiptCapture(totalCents: 5000),
          scopeId: 'x',
          basketCents: 0,
        ),
      ]);
      expect(tillOnly.receiptCount, 1);
      expect(tillOnly.withBasketCount, 0);
      expect(tillOnly.varianceLine, isNull);
      expect(tillOnly.summaryLine, '1 receipt · R50.00');
    });
  });
}
