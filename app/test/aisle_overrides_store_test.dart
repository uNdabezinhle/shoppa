import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/aisle_overrides_store.dart';
import 'package:shoppa_app/core/aisle_sort.dart';
import 'package:shoppa_app/core/lists_repository.dart';

ShoppaListItem _item(String name) => ShoppaListItem(
      id: name,
      name: name,
      quantity: 1,
      unit: 'ea',
      note: '',
      checked: false,
    );

void main() {
  group('aisleMatchKey / aisleForItem overrides', () {
    test('override moves cream to personal care', () {
      expect(aisleForItem(_item('Hand cream')).id, 'dairy');
      final overrides = {aisleMatchKey('Hand cream'): 'personal'};
      expect(
        aisleForItem(_item('Hand cream'), aisleOverrides: overrides).id,
        'personal',
      );
      expect(
        aisleForItem(_item('  HAND CREAM '), aisleOverrides: overrides).id,
        'personal',
      );
    });

    test('shopAisleSections honours overrides', () {
      final sections = shopAisleSections(
        [_item('Hand cream'), _item('Milk')],
        aisleOverrides: {aisleMatchKey('Hand cream'): 'personal'},
      );
      expect(sections.map((s) => s.aisle.id).toList(), ['dairy', 'personal']);
    });
  });

  group('InMemoryAisleOverridesStore', () {
    test('set and clear by name', () async {
      final store = InMemoryAisleOverridesStore();
      await store.setOverride('Bananas', 'bakery');
      expect((await store.snapshot())[aisleMatchKey('Bananas')], 'bakery');
      await store.clearOverride('bananas');
      expect(await store.snapshot(), isEmpty);
    });

    test('rejects unknown aisle ids', () async {
      final store = InMemoryAisleOverridesStore();
      await store.setOverride('Milk', 'not-an-aisle');
      expect(await store.snapshot(), isEmpty);
    });
  });

  group('formatLeftBehindCount', () {
    test('phrases', () {
      expect(formatLeftBehindCount(0), 'Nothing left behind');
      expect(formatLeftBehindCount(1), '1 left behind');
      expect(formatLeftBehindCount(4), '4 left behind');
    });
  });

  group('override labels', () {
    test('counts unique names and formats header chip', () {
      final overrides = {
        aisleMatchKey('Milk'): 'dairy',
        aisleMatchKey('Hand cream'): 'personal',
      };
      expect(
        countAisleOverridesForNames(
          ['Milk', 'milk', 'Hand cream', 'Bread'],
          overrides,
        ),
        2,
      );
      expect(formatAisleOverrideCountLabel(0), isNull);
      expect(formatAisleOverrideCountLabel(1), '1 moved');
      expect(formatAisleOverrideCountLabel(3), '3 moved');
      expect(itemHasAisleOverride('Hand cream', overrides), isTrue);
      expect(itemHasAisleOverride('Bread', overrides), isFalse);
    });
  });
}
