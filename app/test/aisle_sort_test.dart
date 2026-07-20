import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/aisle_sort.dart';
import 'package:shoppa_app/core/lists_repository.dart';

ShoppaListItem _item(String name, {bool checked = false}) => ShoppaListItem(
      id: name,
      name: name,
      quantity: 1,
      unit: 'ea',
      note: '',
      checked: checked,
    );

void main() {
  group('aisleForName', () {
    test('maps common grocery keywords', () {
      expect(aisleForName('Full cream milk 2L').id, 'dairy');
      expect(aisleForName('Chicken breasts').id, 'meat');
      expect(aisleForName('Bananas').id, 'produce');
      expect(aisleForName('White bread').id, 'bakery');
      expect(aisleForName('Toilet paper 9s').id, 'household');
      expect(aisleForName('Dog food').id, 'pet');
    });

    test('unknown names land in other', () {
      expect(aisleForName('Mystery gadget xyz').id, 'other');
    });
  });

  group('shopRowsByAisle', () {
    test('walk order produce before dairy before other', () {
      final rows = shopRowsByAisle([
        _item('Cheddar cheese'),
        _item('Bananas'),
        _item('Random widget'),
      ]);
      final labels = rows
          .whereType<ShopSectionRow>()
          .map((r) => r.aisle.label)
          .toList();
      expect(labels, ['Fruit & veg', 'Dairy & eggs', 'Other']);
      final itemNames = rows
          .whereType<ShopItemRow>()
          .map((r) => r.item.name)
          .toList();
      expect(itemNames, ['Bananas', 'Cheddar cheese', 'Random widget']);
    });

    test('checked items move to final section', () {
      final rows = shopRowsByAisle([
        _item('Milk', checked: true),
        _item('Apples'),
      ]);
      final sections =
          rows.whereType<ShopSectionRow>().map((r) => r.aisle.id).toList();
      expect(sections, ['produce', 'checked']);
      expect(
        rows.whereType<ShopItemRow>().map((r) => r.item.name).toList(),
        ['Apples', 'Milk'],
      );
    });

    test('includeChecked false hides checked section', () {
      final rows = shopRowsByAisle(
        [
          _item('Milk', checked: true),
          _item('Apples'),
        ],
        includeChecked: false,
      );
      expect(
        rows.whereType<ShopSectionRow>().map((r) => r.aisle.id).toList(),
        ['produce'],
      );
      expect(
        rows.whereType<ShopItemRow>().map((r) => r.item.name).toList(),
        ['Apples'],
      );
    });

    test('shopAisleSections groups items under aisle labels', () {
      final sections = shopAisleSections([
        _item('Milk', checked: true),
        _item('Apples'),
        _item('Cheddar cheese'),
      ]);
      expect(sections.map((s) => s.aisle.id).toList(), [
        'produce',
        'dairy',
        'checked',
      ]);
      expect(sections[0].items.map((i) => i.name).toList(), ['Apples']);
      expect(sections[1].items.map((i) => i.name).toList(), ['Cheddar cheese']);
      expect(sections[2].items.map((i) => i.name).toList(), ['Milk']);
    });

    test('empty list yields no rows', () {
      expect(shopRowsByAisle([]), isEmpty);
      expect(shopAisleSections([]), isEmpty);
    });
  });

  group('store aisle layouts', () {
    test('storeAisleLayoutForName maps common ZA chains', () {
      expect(storeAisleLayoutForName('Checkers Hyper').id, 'checkers');
      expect(storeAisleLayoutForName('Pick n Pay').id, 'picknpay');
      expect(storeAisleLayoutForName('Woolworths Food').id, 'woolworths');
      expect(storeAisleLayoutForName('SPAR').id, 'spar');
      expect(storeAisleLayoutForName('Dis-Chem').id, 'pharmacy');
      expect(storeAisleLayoutForName('Clicks').id, 'pharmacy');
      expect(storeAisleLayoutForName(null).id, 'default');
      expect(storeAisleLayoutForName('Unknown Mart').id, 'default');
    });

    test('resolveStoreAisleLayout prefers explicit layout id', () {
      final layout = resolveStoreAisleLayout(
        storeName: 'Checkers',
        layoutId: 'pharmacy',
      );
      expect(layout.id, 'pharmacy');
      expect(
        resolveStoreAisleLayout(storeName: 'Checkers', layoutId: null).id,
        'checkers',
      );
    });

    test('openListItemsInAisle and formatAisleCheckOffMessage', () {
      final items = [
        _item('Apples'),
        _item('Bananas'),
        _item('Milk'),
        _item('Oranges', checked: true),
      ];
      expect(
        openListItemsInAisle(items, 'produce').map((i) => i.name).toList(),
        ['Apples', 'Bananas'],
      );
      expect(openListItemsInAisle(items, 'checked'), isEmpty);
      expect(
        openListItemsInAisle(items, 'dairy').map((i) => i.name).toList(),
        ['Milk'],
      );
      expect(
        formatAisleCheckOffMessage(aisleLabel: 'Fruit & veg', count: 2),
        'Check off 2 items in Fruit & veg?',
      );
    });

    test('nextOpenAisleGroup walks to the next open aisle', () {
      // Default walk: produce → bakery → meat → dairy → …
      final items = [
        _item('Apples', checked: true),
        _item('Bananas', checked: true),
        _item('Milk'),
        _item('Chicken'),
      ];
      expect(
        nextOpenAisleGroup(items, afterAisleId: 'produce')?.id,
        'meat',
      );
      expect(
        formatNextAisleHint(nextOpenAisleGroup(items, afterAisleId: 'produce')),
        'Next up: Meat & deli',
      );
      expect(
        nextOpenAisleGroup(items, afterAisleId: 'meat')?.id,
        'dairy',
      );
      expect(
        nextOpenAisleGroup(
          [_item('Apples', checked: true)],
          afterAisleId: 'produce',
        ),
        isNull,
      );
      expect(nextOpenAisleGroup(items)?.id, 'meat');
    });

    test('skipPastOpenAisle collapses current and expands next', () {
      final items = [
        _item('Bananas'),
        _item('Chicken'),
        _item('Milk'),
      ];
      final first = skipPastOpenAisle(
        items: items,
        collapsedIds: {},
      );
      expect(first.skippedAisle?.id, 'produce');
      expect(first.nextAisle?.id, 'meat');
      expect(first.collapsedIds, contains('produce'));
      expect(first.collapsedIds, isNot(contains('meat')));
      expect(
        formatAisleSkipMessage(
          skipped: first.skippedAisle,
          next: first.nextAisle,
        ),
        'Skipped Fruit & veg · Next up: Meat & deli',
      );

      final second = skipPastOpenAisle(
        items: items,
        collapsedIds: first.collapsedIds,
        fromAisleId: 'meat',
      );
      expect(second.skippedAisle?.id, 'meat');
      expect(second.nextAisle?.id, 'dairy');
      expect(second.collapsedIds, containsAll(['produce', 'meat']));
      expect(second.collapsedIds, isNot(contains('dairy')));
    });

    test('tripStoreSuggestions merges frequent then known, deduped', () {
      final suggestions = tripStoreSuggestions(
        frequent: ['Checkers', 'My Corner Café', 'checkers'],
        known: const ['Checkers', 'SPAR'],
        limit: 10,
      );
      expect(suggestions.first, 'Checkers');
      expect(suggestions, contains('My Corner Café'));
      expect(suggestions, contains('SPAR'));
      // Exact case-insensitive dups dropped; spelling kept from first hit.
      expect(
        suggestions.where((s) => s.toLowerCase() == 'checkers').length,
        1,
      );
      expect(tripStoreSessionId('  Pick n Pay '), 'name:pick n pay');
      expect(isCatalogueStoreId('abc-123'), isTrue);
      expect(isCatalogueStoreId('name:checkers'), isFalse);
      expect(isCatalogueStoreId(null), isFalse);
    });

    test('pharmacy layout puts personal care before produce', () {
      final sections = shopAisleSections(
        [
          _item('Shampoo'),
          _item('Bananas'),
        ],
        layout: storeAisleLayoutById('pharmacy'),
      );
      expect(sections.map((s) => s.aisle.id).toList(), [
        'personal',
        'produce',
      ]);
    });

    test('pick n pay layout puts dairy before meat', () {
      final sections = shopAisleSections(
        [
          _item('Chicken'),
          _item('Milk'),
        ],
        layout: storeAisleLayoutById('picknpay'),
      );
      expect(sections.map((s) => s.aisle.id).toList(), [
        'dairy',
        'meat',
      ]);
    });
  });
}
