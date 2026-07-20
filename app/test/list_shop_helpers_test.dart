import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/list_shop_helpers.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/shopping_session_store.dart';

ShoppaListItem _item(String id, {required bool checked}) => ShoppaListItem(
      id: id,
      name: id,
      quantity: 1,
      unit: 'ea',
      note: '',
      checked: checked,
      hasPromotion: false,
    );

void main() {
  group('listProgress', () {
    test('empty list', () {
      final p = listProgress([]);
      expect(p.total, 0);
      expect(p.checked, 0);
      expect(p.fraction, 0);
      expect(p.isComplete, isFalse);
    });

    test('partial and complete', () {
      final items = [
        _item('a', checked: true),
        _item('b', checked: false),
        _item('c', checked: true),
      ];
      final p = listProgress(items);
      expect(p.total, 3);
      expect(p.checked, 2);
      expect(p.remaining, 1);
      expect(p.percent, 67);
      expect(listProgress([
        _item('a', checked: true),
        _item('b', checked: true),
      ]).isComplete, isTrue);
    });
  });

  group('itemsForDisplay', () {
    test('shop mode puts unchecked first', () {
      final items = [
        _item('checked1', checked: true),
        _item('open1', checked: false),
        _item('checked2', checked: true),
        _item('open2', checked: false),
      ];
      final ordered = itemsForDisplay(items, shopMode: true);
      expect(ordered.map((e) => e.id).toList(), [
        'open1',
        'open2',
        'checked1',
        'checked2',
      ]);
    });

    test('edit mode preserves order', () {
      final items = [
        _item('a', checked: true),
        _item('b', checked: false),
      ];
      expect(
        itemsForDisplay(items, shopMode: false).map((e) => e.id).toList(),
        ['a', 'b'],
      );
    });
  });

  group('InMemoryShoppingSessionStore', () {
    test('set get clear', () async {
      final store = InMemoryShoppingSessionStore();
      expect(await store.getShoppingAt('list-1'), isNull);
      await store.setShoppingAt(
        'list-1',
        const ShoppingAtStore(storeId: 's1', storeName: 'Checkers'),
      );
      final got = await store.getShoppingAt('list-1');
      expect(got?.storeId, 's1');
      expect(got?.storeName, 'Checkers');
      await store.clearShoppingAt('list-1');
      expect(await store.getShoppingAt('list-1'), isNull);
    });
  });
}
