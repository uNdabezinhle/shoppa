import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/last_trip_lists_store.dart';
import 'package:shoppa_app/core/lists_repository.dart';

ShoppaList _list(String id) => ShoppaList(
      id: id,
      title: id,
      category: 'groceries',
      isRecurring: false,
      itemCount: 1,
    );

void main() {
  group('InMemoryLastTripListsStore', () {
    test('stores unique non-empty ids', () async {
      final store = InMemoryLastTripListsStore();
      await store.setListIds(['b', 'a', 'b', ' ', 'a']);
      expect(await store.getListIds(), ['b', 'a']);
      await store.clear();
      expect(await store.getListIds(), isEmpty);
    });
  });

  group('initialTripListSelection', () {
    test('uses remembered ids that are still eligible', () {
      final eligible = [_list('a'), _list('b'), _list('c')];
      expect(
        initialTripListSelection(
          eligible: eligible,
          lastTripIds: ['c', 'gone', 'a'],
        ),
        {'c', 'a'},
      );
    });

    test('falls back to all eligible when none remembered match', () {
      final eligible = [_list('a'), _list('b')];
      expect(
        initialTripListSelection(
          eligible: eligible,
          lastTripIds: ['gone'],
        ),
        {'a', 'b'},
      );
      expect(
        initialTripListSelection(
          eligible: eligible,
          lastTripIds: const [],
        ),
        {'a', 'b'},
      );
    });
  });
}
