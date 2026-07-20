import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/recent_items_store.dart';

void main() {
  group('InMemoryRecentItemsStore', () {
    test('records newest first and dedupes case-insensitively', () async {
      final store = InMemoryRecentItemsStore();
      await store.record('Milk');
      await store.record('Bread');
      await store.record('milk');
      final recent = await store.getRecent();
      expect(recent, ['milk', 'Bread']);
    });

    test('recordMany preserves order of last names as newest', () async {
      final store = InMemoryRecentItemsStore();
      await store.recordMany(['A', 'B', 'C']);
      expect(await store.getRecent(), ['C', 'B', 'A']);
    });
  });
}
