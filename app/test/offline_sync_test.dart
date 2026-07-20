import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/offline_store.dart';
import 'package:shoppa_app/core/token_store.dart';

/// Covers SRS FR-4.2 ("Lists shall be fully usable offline and sync when
/// connectivity returns") and FR-3.2/FR-4.5-adjacent conflict handling on
/// the client side: the offline cache fallback, optimistic queued writes,
/// and syncPending's replay/drop behavior.
void main() {
  group('offline cache + mutation queue', () {
    late InMemoryTokenStore tokenStore;
    late InMemoryOfflineStore offlineStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
      offlineStore = InMemoryOfflineStore();
    });

    ListsRepository repoWith(http.Client mockClient) => ListsRepository(
          ApiClient(
            baseUrl: 'http://localhost:8000/v1',
            tokenStore: tokenStore,
            httpClient: mockClient,
          ),
          offlineStore: offlineStore,
        );

    final sampleDetailJson = {
      'id': 'l-1',
      'title': 'Braai',
      'category': 'groceries',
      'is_recurring': false,
      'item_count': 1,
      'role': 'owner',
      'items': [
        {
          'id': 'i-1',
          'name': 'Boerewors',
          'quantity': '1.00',
          'unit': 'ea',
          'note': '',
          'checked': false,
          'paid_price': null,
        },
      ],
    };

    test('fetchListDetail caches a successful online response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleDetailJson), 200);
      });
      final repo = repoWith(mockClient);

      final list = await repo.fetchListDetail('l-1');

      expect(list.fromCache, false);
      expect(await offlineStore.getCachedListJson('l-1'), isNotNull);
    });

    test('fetchListDetail falls back to cache when offline', () async {
      await offlineStore.cacheListJson('l-1', sampleDetailJson);
      final mockClient = MockClient((request) async {
        throw http.ClientException('simulated network failure');
      });
      final repo = repoWith(mockClient);

      final list = await repo.fetchListDetail('l-1');

      expect(list.fromCache, true);
      expect(list.title, 'Braai');
      expect(list.items, hasLength(1));
    });

    test('fetchListDetail rethrows when offline with no cache at all', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('simulated network failure');
      });
      final repo = repoWith(mockClient);

      expect(
        () => repo.fetchListDetail('never-cached'),
        throwsA(isA<NetworkUnavailableException>()),
      );
    });

    test('addItem queues optimistically when offline and appends to cache',
        () async {
      await offlineStore.cacheListJson('l-1', sampleDetailJson);
      final mockClient = MockClient((request) async {
        throw http.ClientException('simulated network failure');
      });
      final repo = repoWith(mockClient);

      final item = await repo.addItem('l-1', name: 'Rolls', quantity: 6);

      expect(item.name, 'Rolls');
      expect(item.checked, false);
      final pending = await offlineStore.pendingFor('l-1');
      expect(pending, hasLength(1));
      expect(pending.first.type, 'add_item');

      final cached = await offlineStore.getCachedListJson('l-1');
      final cachedItems = cached!['items'] as List;
      expect(cachedItems, hasLength(2));
    });

    test('setItemChecked queues and merges into the cached item when offline',
        () async {
      await offlineStore.cacheListJson('l-1', sampleDetailJson);
      final mockClient = MockClient((request) async {
        throw http.ClientException('simulated network failure');
      });
      final repo = repoWith(mockClient);

      final item = await repo.setItemChecked('l-1', 'i-1',
          checked: true, paidPrice: 4599);

      expect(item.checked, true);
      expect(item.paidPrice, 4599);
      expect(item.name, 'Boerewors'); // merged, not clobbered

      final pending = await offlineStore.pendingFor('l-1');
      expect(pending, hasLength(1));
      expect(pending.first.type, 'check_item');
      expect(pending.first.payload['client_updated_at'], isNotNull);
    });

    test('syncPending replays queued mutations and clears them once online',
        () async {
      final requestedPaths = <String>[];
      final mockClient = MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response(jsonEncode({'id': 'i-1', 'name': 'ok'}), 200);
      });
      await offlineStore.enqueue(QueuedMutation(
        id: 'q-1',
        listId: 'l-1',
        itemId: 'i-1',
        type: 'check_item',
        payload: {'checked': true},
        clientUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final repo = repoWith(mockClient);
      final synced = await repo.syncPending('l-1');

      expect(synced, 1);
      expect(requestedPaths, contains('/v1/lists/l-1/items/i-1'));
      expect(await offlineStore.pendingFor('l-1'), isEmpty);
    });

    test('syncPending stops early (without losing the rest) if still offline',
        () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('still offline');
      });
      await offlineStore.enqueue(QueuedMutation(
        id: 'q-1',
        listId: 'l-1',
        itemId: 'i-1',
        type: 'check_item',
        payload: {'checked': true},
        clientUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      await offlineStore.enqueue(QueuedMutation(
        id: 'q-2',
        listId: 'l-1',
        itemId: 'i-2',
        type: 'check_item',
        payload: {'checked': true},
        clientUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final repo = repoWith(mockClient);
      final synced = await repo.syncPending('l-1');

      expect(synced, 0);
      expect(await offlineStore.pendingFor('l-1'), hasLength(2));
    });

    test('syncPending drops a mutation the server rejects outright', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'not_found', 'message': 'Gone'},
          }),
          404,
        );
      });
      await offlineStore.enqueue(QueuedMutation(
        id: 'q-1',
        listId: 'l-1',
        itemId: 'i-1',
        type: 'check_item',
        payload: {'checked': true},
        clientUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final repo = repoWith(mockClient);
      final synced = await repo.syncPending('l-1');

      expect(synced, 0);
      expect(await offlineStore.pendingFor('l-1'), isEmpty);
    });

    test('syncAllPending flushes queues for every list', () async {
      final requestedPaths = <String>[];
      final mockClient = MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response(jsonEncode({'id': 'ok'}), 200);
      });
      await offlineStore.enqueue(QueuedMutation(
        id: 'q-1',
        listId: 'l-1',
        itemId: 'i-1',
        type: 'check_item',
        payload: {'checked': true},
        clientUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      await offlineStore.enqueue(QueuedMutation(
        id: 'q-2',
        listId: 'l-2',
        itemId: 'i-2',
        type: 'check_item',
        payload: {'checked': true},
        clientUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final repo = repoWith(mockClient);
      final synced = await repo.syncAllPending();

      expect(synced, 2);
      expect(requestedPaths, contains('/v1/lists/l-1/items/i-1'));
      expect(requestedPaths, contains('/v1/lists/l-2/items/i-2'));
      expect(await offlineStore.pendingAll(), isEmpty);
    });

    test('fetchLists online flushes pending mutations without opening detail',
        () async {
      final requestedPaths = <String>[];
      final mockClient = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/v1/lists' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 'l-1',
                  'title': 'Groceries',
                  'category': 'groceries',
                  'is_recurring': false,
                  'item_count': 1,
                },
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'id': 'i-1', 'checked': true}), 200);
      });
      await offlineStore.enqueue(QueuedMutation(
        id: 'q-1',
        listId: 'l-1',
        itemId: 'i-1',
        type: 'check_item',
        payload: {'checked': true},
        clientUpdatedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final repo = repoWith(mockClient);
      final lists = await repo.fetchLists();

      expect(lists, hasLength(1));
      expect(requestedPaths, contains('/v1/lists/l-1/items/i-1'));
      expect(await offlineStore.pendingAll(), isEmpty);
      // Index is fetched again after a successful background sync.
      expect(
        requestedPaths.where((p) => p == '/v1/lists').length,
        greaterThanOrEqualTo(2),
      );
    });
  });
}
