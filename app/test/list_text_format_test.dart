import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/list_text_format.dart';
import 'package:shoppa_app/core/lists_repository.dart';

void main() {
  group('formatListAsText', () {
    test('formats title, quantities, and checkboxes', () {
      final list = ShoppaList(
        id: 'l-1',
        title: 'Weekly shop',
        category: 'groceries',
        isRecurring: false,
        itemCount: 3,
        items: [
          ShoppaListItem(
            id: '1',
            name: 'Milk',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: false,
          ),
          ShoppaListItem(
            id: '2',
            name: 'Rice',
            quantity: 1.5,
            unit: 'kg',
            note: 'basmati',
            checked: true,
          ),
          ShoppaListItem(
            id: '3',
            name: 'Bread',
            quantity: 2,
            unit: 'ea',
            note: '',
            checked: false,
          ),
        ],
      );

      final text = formatListAsText(list);
      expect(text, contains('Weekly shop'));
      expect(text, contains('[ ] Milk'));
      expect(text, contains('[x] 1.5 kg Rice — basmati'));
      expect(text, contains('[ ] 2x Bread'));
    });

    test('can omit checked items', () {
      final list = ShoppaList(
        id: 'l-1',
        title: 'Trip',
        category: 'custom',
        isRecurring: false,
        itemCount: 2,
        items: [
          ShoppaListItem(
            id: '1',
            name: 'Done',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: true,
          ),
          ShoppaListItem(
            id: '2',
            name: 'Open',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: false,
          ),
        ],
      );
      final text = formatListAsText(list, includeChecked: false);
      expect(text, contains('Open'));
      expect(text, isNot(contains('Done')));
      expect(text, contains('(remaining items)'));
    });

    test('group by aisle and include prices', () {
      final list = ShoppaList(
        id: 'l-1',
        title: 'Shop',
        category: 'groceries',
        isRecurring: false,
        itemCount: 3,
        items: [
          ShoppaListItem(
            id: '1',
            name: 'Apples',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: false,
          ),
          ShoppaListItem(
            id: '2',
            name: 'Yoghurt',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: false,
            paidPrice: 1850,
          ),
          ShoppaListItem(
            id: '3',
            name: 'Milk',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: true,
            paidPrice: 2599,
          ),
        ],
      );
      final text = formatListAsText(
        list,
        options: const ListTextFormatOptions(
          groupByAisle: true,
          includePrices: true,
        ),
      );
      // Open items by walk-order aisle; checked items under "Checked off".
      expect(text, contains('FRUIT & VEG'));
      expect(text, contains('DAIRY & EGGS'));
      expect(text, contains('CHECKED OFF'));
      expect(text, contains('R18.50'));
      expect(text, contains('R25.99'));
    });

    test('shopping share preset omits checked and uses bullets', () {
      final list = ShoppaList(
        id: 'l-1',
        title: 'Shop',
        category: 'custom',
        isRecurring: false,
        itemCount: 2,
        items: [
          ShoppaListItem(
            id: '1',
            name: 'Done',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: true,
          ),
          ShoppaListItem(
            id: '2',
            name: 'Bread',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: false,
          ),
        ],
      );
      final text = formatListAsText(
        list,
        options: ListTextFormatOptions.shoppingShare,
      );
      expect(text, contains('• Bread'));
      expect(text, isNot(contains('Done')));
      expect(text, contains('BAKERY'));
    });

    test('trip recap preset is checked-only with prices', () {
      final list = ShoppaList(
        id: 'l-1',
        title: 'Shop',
        category: 'custom',
        isRecurring: false,
        itemCount: 2,
        items: [
          ShoppaListItem(
            id: '1',
            name: 'Done',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: true,
            paidPrice: 1000,
          ),
          ShoppaListItem(
            id: '2',
            name: 'Open',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: false,
          ),
        ],
      );
      final text = formatListAsText(
        list,
        options: ListTextFormatOptions.tripRecap,
      );
      expect(text, contains('(checked off)'));
      expect(text, contains('Done'));
      expect(text, contains('R10.00'));
      expect(text, isNot(contains('Open')));
    });

    test('formatSessionRecapAsText includes spend and till delta', () {
      final list = ShoppaList(
        id: 'l-1',
        title: 'Weekly',
        category: 'groceries',
        isRecurring: false,
        itemCount: 2,
        items: [
          ShoppaListItem(
            id: '1',
            name: 'Milk',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: true,
            paidPrice: 2500,
          ),
          ShoppaListItem(
            id: '2',
            name: 'Bread',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: true,
            paidPrice: 1500,
          ),
        ],
      );
      final text = formatSessionRecapAsText(
        list,
        tillCents: 4200,
        basketCents: 4000,
      );
      expect(text, contains('Weekly'));
      expect(text, contains('Trip complete'));
      expect(text, contains('Spent R40.00'));
      expect(text, contains('Till R42.00'));
      expect(text, contains('over basket'));
      expect(text, contains('Milk'));
      expect(text, contains('R25.00'));
    });
  });
}
