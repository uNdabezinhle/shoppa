import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/list_shop_helpers.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/shopping_session_store.dart';

ShoppaListItem _item(
  String id, {
  required bool checked,
  int? paidPrice,
}) =>
    ShoppaListItem(
      id: id,
      name: id,
      quantity: 1,
      unit: 'ea',
      note: '',
      checked: checked,
      paidPrice: paidPrice,
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

  group('tripSpend', () {
    test('sums paid prices on checked items only', () {
      final items = [
        _item('a', checked: true, paidPrice: 1999),
        _item('b', checked: false, paidPrice: 5000),
        _item('c', checked: true, paidPrice: 500),
        _item('d', checked: true),
      ];
      final s = tripSpend(items);
      expect(s.spentCents, 2499);
      expect(s.pricedCount, 2);
      expect(s.checkedCount, 3);
      expect(s.hasSpend, isTrue);
      expect(s.hasIncompletePricing, isTrue);
      expect(s.formatted, 'R24.99');
    });

    test('empty when nothing priced', () {
      final s = tripSpend([_item('a', checked: true)]);
      expect(s.hasSpend, isFalse);
      expect(s.spentCents, 0);
    });
  });

  group('adjustItemQuantity', () {
    test('steps whole quantities by 1 with floor 1', () {
      expect(adjustItemQuantity(1, 1), 2);
      expect(adjustItemQuantity(2, -1), 1);
      expect(adjustItemQuantity(1, -1), 1);
    });

    test('steps fractional quantities by 0.5', () {
      expect(adjustItemQuantity(1.5, 1), 2);
      expect(adjustItemQuantity(1.5, -1), 1);
      expect(adjustItemQuantity(0.5, -1), 0.5);
    });
  });

  group('sortShoppaLists', () {
    ShoppaList listOf(
      String title, {
      String? updatedAt,
      int itemCount = 0,
    }) =>
        ShoppaList(
          id: title,
          title: title,
          category: 'custom',
          isRecurring: false,
          itemCount: itemCount,
          updatedAt: updatedAt,
        );

    test('recent puts newest first', () {
      final sorted = sortShoppaLists(
        [
          listOf('Old', updatedAt: '2026-01-01T00:00:00Z'),
          listOf('New', updatedAt: '2026-06-01T00:00:00Z'),
          listOf('Mid', updatedAt: '2026-03-01T00:00:00Z'),
        ],
        mode: ListSortMode.recent,
      );
      expect(sorted.map((e) => e.title).toList(), ['New', 'Mid', 'Old']);
    });

    test('title sorts A–Z', () {
      final sorted = sortShoppaLists(
        [listOf('Zed'), listOf('Alpha'), listOf('Milk')],
        mode: ListSortMode.title,
      );
      expect(sorted.map((e) => e.title).toList(), ['Alpha', 'Milk', 'Zed']);
    });

    test('itemCount sorts descending', () {
      final sorted = sortShoppaLists(
        [
          listOf('a', itemCount: 2),
          listOf('b', itemCount: 9),
          listOf('c', itemCount: 5),
        ],
        mode: ListSortMode.itemCount,
      );
      expect(sorted.map((e) => e.title).toList(), ['b', 'c', 'a']);
    });

    test('pinned ids float to top within mode order', () {
      final sorted = sortShoppaLists(
        [
          listOf('Old', updatedAt: '2026-01-01T00:00:00Z'),
          listOf('New', updatedAt: '2026-06-01T00:00:00Z'),
          listOf('Mid', updatedAt: '2026-03-01T00:00:00Z'),
        ],
        mode: ListSortMode.recent,
        pinnedIds: {'Old'},
      );
      expect(sorted.map((e) => e.title).toList(), ['Old', 'New', 'Mid']);
    });
  });

  group('itemNeedsPaidPrice', () {
    test('true only when checked without paid price', () {
      expect(
        itemNeedsPaidPrice(_item('a', checked: true)),
        isTrue,
      );
      expect(
        itemNeedsPaidPrice(_item('b', checked: true, paidPrice: 100)),
        isFalse,
      );
      expect(
        itemNeedsPaidPrice(_item('c', checked: false)),
        isFalse,
      );
      expect(
        itemsMissingPaidPrice([
          _item('a', checked: true),
          _item('b', checked: true, paidPrice: 50),
          _item('c', checked: false),
        ]).map((e) => e.id),
        ['a'],
      );
    });
  });

  group('findMatchingListItem', () {
    test('matches unchecked name+unit case-insensitively', () {
      final milk = ShoppaListItem(
        id: '1',
        name: 'Milk',
        quantity: 1,
        unit: 'ea',
        note: '',
        checked: false,
      );
      final bread = ShoppaListItem(
        id: '2',
        name: 'Bread',
        quantity: 1,
        unit: 'ea',
        note: '',
        checked: true,
      );
      final list = [milk, bread];
      expect(findMatchingListItem(list, name: 'milk')?.id, '1');
      expect(findMatchingListItem(list, name: 'Bread'), isNull);
      expect(findMatchingListItem(list, name: 'Milk', unit: 'kg'), isNull);
    });
  });

  group('pickComparisonStore', () {
    test('prefers shopping-at store', () {
      final comparison = ShoppaComparison(
        currencyCode: 'ZAR',
        stores: [
          ShoppaStoreComparison(
            storeId: 'a',
            name: 'A',
            total: 1000,
            confidence: 'high',
          ),
          ShoppaStoreComparison(
            storeId: 'b',
            name: 'B',
            total: 800,
            confidence: 'high',
          ),
        ],
        bestStoreId: 'b',
        bestSaves: 200,
      );
      expect(
        pickComparisonStore(comparison, preferredStoreId: 'a')?.storeId,
        'a',
      );
      expect(pickComparisonStore(comparison)?.storeId, 'b');
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

    test('name order sorts A–Z ignoring shop grouping', () {
      final items = [
        _item('zebra', checked: false),
        _item('apple', checked: true),
        _item('Milk', checked: false),
      ];
      expect(
        itemsForDisplay(
          items,
          shopMode: true,
          order: ItemOrderMode.name,
        ).map((e) => e.id).toList(),
        ['apple', 'Milk', 'zebra'],
      );
    });
  });

  group('applyItemViewFilter', () {
    test('remaining and checked subsets', () {
      final items = [
        _item('a', checked: true),
        _item('b', checked: false),
        _item('c', checked: true),
      ];
      expect(
        applyItemViewFilter(items, ItemViewFilter.remaining).map((e) => e.id),
        ['b'],
      );
      expect(
        applyItemViewFilter(items, ItemViewFilter.checked).map((e) => e.id),
        ['a', 'c'],
      );
      expect(
        applyItemViewFilter(items, ItemViewFilter.all).length,
        3,
      );
    });
  });

  group('formatRelativeTime', () {
    test('minutes hours days', () {
      final now = DateTime(2026, 7, 20, 12, 0);
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 10)), now: now),
        'just now',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
      expect(formatRelativeTime(null, now: now), '');
    });
  });

  group('listIsIncompleteTrip', () {
    test('true when some items remain', () {
      expect(
        listIsIncompleteTrip(
          ShoppaList(
            id: '1',
            title: 't',
            category: 'custom',
            isRecurring: false,
            itemCount: 5,
            checkedCount: 2,
          ),
        ),
        isTrue,
      );
      expect(
        listIsIncompleteTrip(
          ShoppaList(
            id: '2',
            title: 't',
            category: 'custom',
            isRecurring: false,
            itemCount: 3,
            checkedCount: 3,
          ),
        ),
        isFalse,
      );
      expect(
        listIsIncompleteTrip(
          ShoppaList(
            id: '3',
            title: 't',
            category: 'custom',
            isRecurring: false,
            itemCount: 0,
          ),
        ),
        isFalse,
      );
    });
  });

  group('filterListItems', () {
    test('matches name and note case-insensitively', () {
      final items = [
        ShoppaListItem(
          id: '1',
          name: 'Full Cream Milk',
          quantity: 1,
          unit: 'ea',
          note: '2L',
          checked: false,
        ),
        ShoppaListItem(
          id: '2',
          name: 'Bread',
          quantity: 1,
          unit: 'ea',
          note: 'brown',
          checked: false,
        ),
      ];
      expect(filterListItems(items, 'milk').map((e) => e.id), ['1']);
      expect(filterListItems(items, 'BROWN').map((e) => e.id), ['2']);
      expect(filterListItems(items, '').length, 2);
    });
  });

  group('listDetailPath', () {
    test('builds path with optional title and shop mode', () {
      expect(listDetailPath('abc'), '/lists/abc');
      expect(
        listDetailPath('abc', title: 'Weekly shop'),
        '/lists/abc?title=Weekly+shop',
      );
      expect(
        listDetailPath('abc', title: 'Weekly shop', shop: true),
        '/lists/abc?title=Weekly+shop&shop=1',
      );
      expect(listDetailPath('abc', shop: true), '/lists/abc?shop=1');
      final uri = Uri.parse(listDetailPath('id', title: 'A & B', shop: true));
      expect(uri.path, '/lists/id');
      expect(uri.queryParameters['title'], 'A & B');
      expect(uri.queryParameters['shop'], '1');
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
