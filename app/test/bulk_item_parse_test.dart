import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/bulk_item_parse.dart';

void main() {
  group('parseBulkItemLines', () {
    test('parses plain names one per line', () {
      final lines = parseBulkItemLines('Milk\nBread\nEggs');
      expect(lines.map((e) => e.name).toList(), ['Milk', 'Bread', 'Eggs']);
      expect(lines.every((e) => e.quantity == 1), isTrue);
    });

    test('parses quantity prefixes and suffixes', () {
      final lines = parseBulkItemLines('2x Bread\n3 Apples\nMilk x 2');
      expect(lines[0].quantity, 2);
      expect(lines[0].name, 'Bread');
      expect(lines[1].quantity, 3);
      expect(lines[1].name, 'Apples');
      expect(lines[2].quantity, 2);
      expect(lines[2].name, 'Milk');
    });

    test('parses unit prefixes', () {
      final lines = parseBulkItemLines('1.5 kg Rice\n500 ml Cream');
      expect(lines[0].quantity, 1.5);
      expect(lines[0].unit, 'kg');
      expect(lines[0].name, 'Rice');
      expect(lines[1].unit, 'ml');
      expect(lines[1].name, 'Cream');
    });

    test('strips prices and skips totals', () {
      final lines = parseBulkItemLines('''
Full cream milk R 24.99
Bread 18.50
TOTAL R 43.49
Thank you
''');
      expect(lines.map((e) => e.name).toList(), [
        'Full cream milk',
        'Bread',
      ]);
    });

    test('empty input yields empty list', () {
      expect(parseBulkItemLines('  \n\n'), isEmpty);
    });
  });
}
