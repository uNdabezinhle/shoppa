import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/shopping_session_store.dart';

void main() {
  group('resolveDefaultStoreName', () {
    test('prefers scope, then last, then frequent', () {
      expect(
        resolveDefaultStoreName(
          scopeStoreName: 'Checkers',
          lastStoreName: 'SPAR',
          frequentStores: const ['Pick n Pay'],
        ),
        'Checkers',
      );
      expect(
        resolveDefaultStoreName(
          lastStoreName: 'SPAR',
          frequentStores: const ['Pick n Pay'],
        ),
        'SPAR',
      );
      expect(
        resolveDefaultStoreName(
          frequentStores: const ['Pick n Pay', 'Checkers'],
        ),
        'Pick n Pay',
      );
      expect(resolveDefaultStoreName(scopeStoreName: '  '), isNull);
      expect(resolveDefaultStoreName(), isNull);
    });
  });

  group('InMemoryShoppingSessionStore', () {
    test('setShoppingAt updates last store; clear keeps last', () async {
      final store = InMemoryShoppingSessionStore();
      await store.setShoppingAt(
        'list-a',
        const ShoppingAtStore(storeId: 'name:checkers', storeName: 'Checkers'),
      );
      expect((await store.getLastStore())?.storeName, 'Checkers');
      await store.clearShoppingAt('list-a');
      expect(await store.getShoppingAt('list-a'), isNull);
      expect((await store.getLastStore())?.storeName, 'Checkers');
    });
  });
}
