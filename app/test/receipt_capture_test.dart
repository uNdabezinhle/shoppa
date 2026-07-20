import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/receipt_capture.dart';

ShoppaListItem _item(
  String id, {
  required bool checked,
  int? paidPrice,
  num quantity = 1,
}) =>
    ShoppaListItem(
      id: id,
      name: id,
      quantity: quantity,
      unit: 'ea',
      note: '',
      checked: checked,
      paidPrice: paidPrice,
    );

void main() {
  group('HeuristicReceiptOcrService', () {
    final ocr = HeuristicReceiptOcrService();

    test('extracts labeled total and store', () async {
      const text = '''
CHECKERS Hyper
Milk 2L        25.99
Bread          18.50
TOTAL R44.49
Thank you
''';
      final r = await ocr.parseText(text);
      expect(r.totalCents, 4449);
      expect(r.storeName.toLowerCase(), contains('checkers'));
      expect(r.source, ReceiptSource.pastedText);
      expect(r.lineHints, isNotEmpty);
    });

    test('falls back to largest money amount', () async {
      final r = await ocr.parseText('Stuff 10.00\nMore 99.50\nFee 1.00');
      expect(r.totalCents, 9950);
    });

    test('empty text yields no total', () async {
      final r = await ocr.parseText('   ');
      expect(r.hasTotal, isFalse);
    });

    test('image bytes mark photo attachment without inventing a total', () async {
      final r = await ocr.parseImageBytes(List<int>.filled(2048, 1));
      expect(r.source, ReceiptSource.ocr);
      expect(r.hasTotal, isFalse);
      expect(r.hasPhoto, isTrue);
      expect(r.photoByteLength, 2048);
      expect(r.notes, contains('Photo attached'));
    });

    test('empty image bytes yield empty OCR capture', () async {
      final r = await ocr.parseImageBytes(const []);
      expect(r.hasPhoto, isFalse);
      expect(r.hasTotal, isFalse);
    });
  });

  group('suggestPricesFromReceiptTotal', () {
    test('splits remainder by quantity among unpriced checked items', () {
      final items = [
        _item('a', checked: true, paidPrice: 1000),
        _item('b', checked: true, quantity: 1),
        _item('c', checked: true, quantity: 3),
        _item('d', checked: false),
      ];
      // Total 50.00, already 10.00 → 40.00 to split 1:3 → 10 + 30
      final suggestions = suggestPricesFromReceiptTotal(
        items: items,
        receiptTotalCents: 5000,
      );
      expect(suggestions.length, 2);
      final byId = {for (final s in suggestions) s.itemId: s.cents};
      expect(byId['b'], 1000);
      expect(byId['c'], 3000);
      expect(byId.values.fold(0, (a, b) => a + b), 4000);
    });

    test('returns empty when nothing missing or remainder non-positive', () {
      expect(
        suggestPricesFromReceiptTotal(
          items: [_item('a', checked: true, paidPrice: 500)],
          receiptTotalCents: 500,
        ),
        isEmpty,
      );
      expect(
        suggestPricesFromReceiptTotal(
          items: [_item('a', checked: true)],
          receiptTotalCents: 0,
        ),
        isEmpty,
      );
    });
  });

  group('TillVsBasket', () {
    test('over / under / match', () {
      const over = TillVsBasket(tillCents: 12000, basketCents: 11500);
      expect(over.deltaCents, 500);
      expect(over.over, isTrue);
      expect(over.signedDeltaLabel, '+R5.00');
      expect(over.variancePhrase, 'R5.00 over basket');
      expect(over.summaryLine, contains('+R5.00'));

      const under = TillVsBasket(tillCents: 10000, basketCents: 11250);
      expect(under.under, isTrue);
      expect(under.signedDeltaLabel, '−R12.50');
      expect(under.variancePhrase, 'R12.50 under basket');

      const match = TillVsBasket(tillCents: 5000, basketCents: 5000);
      expect(match.matches, isTrue);
      expect(match.signedDeltaLabel, 'match');
      expect(match.summaryLine, 'Till R50.00 · matches basket');
    });

    test('till only has no comparison', () {
      const tillOnly = TillVsBasket(tillCents: 9900, basketCents: 0);
      expect(tillOnly.hasComparison, isFalse);
      expect(tillOnly.summaryLine, 'Till R99.00');
      expect(tillOnly.shareLine, 'Till total: R99.00');
    });
  });

  group('unmatchedReceiptLineHints', () {
    test('filters names already on the list and dedupes', () {
      final items = [
        _item('milk', checked: false),
        ShoppaListItem(
          id: '2',
          name: 'Brown bread',
          quantity: 1,
          unit: 'ea',
          note: '',
          checked: true,
        ),
      ];
      final unmatched = unmatchedReceiptLineHints(
        lineHints: const [
          'Milk 2L', // matches milk via containment
          'Chips',
          'chips', // dedupe
          'Brown bread loaf', // matches brown bread
          'Yoghurt',
        ],
        items: items,
      );
      expect(unmatched, ['Chips', 'Yoghurt']);
    });

    test('empty when all hints match', () {
      expect(
        unmatchedReceiptLineHints(
          lineHints: const ['Milk'],
          items: [_item('milk', checked: false)],
        ),
        isEmpty,
      );
    });
  });
}
