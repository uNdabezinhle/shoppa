import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/list_realtime_client.dart';
import 'package:shoppa_app/core/list_realtime_patch.dart';
import 'package:shoppa_app/core/lists_repository.dart';

ShoppaList _list({List<ShoppaListItem>? items}) => ShoppaList(
      id: 'l-1',
      title: 'Groceries',
      category: 'groceries',
      isRecurring: false,
      itemCount: items?.length ?? 0,
      role: 'owner',
      items: items,
    );

ShoppaListItem _item(
  String id, {
  String name = 'Milk',
  bool checked = false,
  int position = 0,
  num quantity = 1,
}) =>
    ShoppaListItem(
      id: id,
      name: name,
      quantity: quantity,
      unit: 'ea',
      note: '',
      checked: checked,
      position: position,
    );

Map<String, dynamic> _itemJson(
  String id, {
  String name = 'Milk',
  bool checked = false,
  int position = 0,
  num quantity = 1,
}) =>
    {
      'id': id,
      'name': name,
      'quantity': quantity.toString(),
      'unit': 'ea',
      'note': '',
      'checked': checked,
      'position': position,
      'paid_price': null,
      'product_id': null,
      'has_promotion': false,
    };

void main() {
  group('applyListRealtimeEvent', () {
    test('item.added appends and sorts by position', () {
      final list = _list(items: [_item('i-1', position: 0)]);
      final next = applyListRealtimeEvent(
        list,
        ListRealtimeEvent(
          event: 'item.added',
          payload: _itemJson('i-2', name: 'Bread', position: 1),
        ),
      );

      expect(next, isNotNull);
      expect(next!.items, hasLength(2));
      expect(next.items!.map((i) => i.id), ['i-1', 'i-2']);
      expect(next.itemCount, 2);
    });

    test('item.checked updates the matching item in place', () {
      final list = _list(items: [
        _item('i-1', name: 'Milk', checked: false),
        _item('i-2', name: 'Bread', checked: false, position: 1),
      ]);
      final next = applyListRealtimeEvent(
        list,
        ListRealtimeEvent(
          event: 'item.checked',
          payload: _itemJson('i-1', name: 'Milk', checked: true),
        ),
      );

      expect(next!.items!.first.checked, isTrue);
      expect(next.items!.last.checked, isFalse);
    });

    test('successive position patches settle into the new order', () {
      // Mirrors reorderItems: one PATCH per item with unique positions.
      var list = _list(items: [
        _item('a', name: 'A', position: 0),
        _item('b', name: 'B', position: 1),
        _item('c', name: 'C', position: 2),
      ]);
      for (final patch in [
        _itemJson('c', name: 'C', position: 0),
        _itemJson('a', name: 'A', position: 1),
        _itemJson('b', name: 'B', position: 2),
      ]) {
        list = applyListRealtimeEvent(
          list,
          ListRealtimeEvent(event: 'item.updated', payload: patch),
        )!;
      }

      expect(list.items!.map((i) => i.id).toList(), ['c', 'a', 'b']);
    });

    test('item.removed drops the item and updates itemCount', () {
      final list = _list(items: [
        _item('i-1'),
        _item('i-2', name: 'Bread', position: 1),
      ]);
      final next = applyListRealtimeEvent(
        list,
        ListRealtimeEvent(
          event: 'item.removed',
          payload: {'id': 'i-1'},
        ),
      );

      expect(next!.items!.map((i) => i.id), ['i-2']);
      expect(next.itemCount, 1);
    });

    test('list.scaled replaces every quantity from payload items', () {
      final list = _list(items: [
        _item('i-1', quantity: 1),
        _item('i-2', name: 'Bread', quantity: 2, position: 1),
      ]);
      final next = applyListRealtimeEvent(
        list,
        ListRealtimeEvent(
          event: 'list.scaled',
          payload: {
            'items': [
              _itemJson('i-1', quantity: 5),
              _itemJson('i-2', name: 'Bread', quantity: 10, position: 1),
            ],
          },
        ),
      );

      expect(next!.items!.map((i) => i.quantity), [5, 10]);
    });

    test('presence events are no-ops (same list instance)', () {
      final list = _list(items: [_item('i-1')]);
      final next = applyListRealtimeEvent(
        list,
        ListRealtimeEvent(
          event: 'presence.joined',
          payload: {'user_id': 'u-2', 'email': 'x@y.com'},
        ),
      );
      expect(identical(next, list), isTrue);
    });

    test('collaborator events request a full reload', () {
      final list = _list(items: [_item('i-1')]);
      expect(
        applyListRealtimeEvent(
          list,
          ListRealtimeEvent(
            event: 'collaborator.joined',
            payload: {'user_id': 'u-2'},
          ),
        ),
        isNull,
      );
    });

    test('missing items on the list forces full reload', () {
      final list = _list(items: null);
      expect(
        applyListRealtimeEvent(
          list,
          ListRealtimeEvent(
            event: 'item.added',
            payload: _itemJson('i-1'),
          ),
        ),
        isNull,
      );
    });

    test('malformed item payload forces full reload', () {
      final list = _list(items: [_item('i-1')]);
      expect(
        applyListRealtimeEvent(
          list,
          ListRealtimeEvent(
            event: 'item.added',
            payload: {'id': 'i-2'}, // no name
          ),
        ),
        isNull,
      );
    });
  });
}
