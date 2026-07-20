import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/list_shop_helpers.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/pinned_lists_store.dart';

void main() {
  group('InMemoryPinnedListsStore', () {
    test('toggle pin and unpin', () async {
      final store = InMemoryPinnedListsStore();
      expect(await store.isPinned('a'), isFalse);
      await store.toggle('a');
      expect(await store.isPinned('a'), isTrue);
      expect(await store.getPinnedIds(), {'a'});
      await store.toggle('a');
      expect(await store.isPinned('a'), isFalse);
    });
  });

  group('withPinnedFirst', () {
    test('moves pinned ids to front preserving order', () {
      final items = ['a', 'b', 'c', 'd'];
      expect(
        withPinnedFirst(
          items,
          pinnedIds: {'c', 'a'},
          idOf: (e) => e,
        ),
        ['a', 'c', 'b', 'd'],
      );
    });
  });

  group('sortShoppaLists with pins', () {
    ShoppaList listOf(String id, {String? updatedAt}) => ShoppaList(
          id: id,
          title: id,
          category: 'custom',
          isRecurring: false,
          itemCount: 0,
          updatedAt: updatedAt,
        );

    test('pinned float above recent sort', () {
      final sorted = sortShoppaLists(
        [
          listOf('old', updatedAt: '2026-01-01T00:00:00Z'),
          listOf('new', updatedAt: '2026-06-01T00:00:00Z'),
          listOf('mid', updatedAt: '2026-03-01T00:00:00Z'),
        ],
        mode: ListSortMode.recent,
        pinnedIds: {'old'},
      );
      expect(sorted.map((e) => e.id).toList(), ['old', 'new', 'mid']);
    });
  });
}
