import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('ListsRepository', () {
    late InMemoryTokenStore tokenStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
    });

    test('fetchLists parses a paginated results envelope', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/lists');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'l-1',
                'title': 'Monthly Groceries',
                'category': 'groceries',
                'is_recurring': true,
                'item_count': 8,
              },
            ],
            'next': null,
            'previous': null,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final lists = await repo.fetchLists();

      expect(lists, hasLength(1));
      expect(lists.first.title, 'Monthly Groceries');
      expect(lists.first.isRecurring, true);
      expect(lists.first.itemCount, 8);
    });

    test('fetchListDetail parses nested items', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'l-1',
            'title': 'Monthly Groceries',
            'category': 'groceries',
            'is_recurring': false,
            'item_count': 1,
            'items': [
              {
                'id': 'i-1',
                'name': 'Full Cream Milk 2L',
                'quantity': '2.00',
                'unit': 'ea',
                'note': '',
                'checked': false,
                'paid_price': null,
              },
            ],
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final list = await repo.fetchListDetail('l-1');

      expect(list.items, hasLength(1));
      expect(list.items!.first.name, 'Full Cream Milk 2L');
      expect(list.items!.first.quantity, 2);
    });

    test('setItemChecked PATCHes checked and paid_price', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v1/lists/l-1/items/i-1');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'i-1',
            'name': 'Bread',
            'quantity': '1.00',
            'unit': 'ea',
            'note': '',
            'checked': true,
            'paid_price': 1799,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final item = await repo.setItemChecked(
        'l-1',
        'i-1',
        checked: true,
        paidPrice: 1799,
      );

      expect(sentBody['checked'], true);
      expect(sentBody['paid_price'], 1799);
      expect(item.paidPrice, 1799);
    });

    test('fetchListDetail exposes the caller role', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'l-1',
            'title': 'Braai',
            'category': 'groceries',
            'is_recurring': false,
            'item_count': 0,
            'role': 'view',
            'items': [],
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final list = await repo.fetchListDetail('l-1');

      expect(list.role, 'view');
      expect(list.canEdit, false);
      expect(list.isOwner, false);
    });

    test('shareList POSTs email and permission to /collaborators', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/lists/l-1/collaborators');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'c-1',
            'user_id': 'u-2',
            'user_email': 'friend@example.com',
            'permission': 'edit',
          }),
          201,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final collaborator = await repo.shareList(
        'l-1',
        email: 'friend@example.com',
        permission: 'edit',
      );

      expect(sentBody['email'], 'friend@example.com');
      expect(sentBody['permission'], 'edit');
      expect(collaborator.userEmail, 'friend@example.com');
      expect(collaborator.permission, 'edit');
    });

    test('fetchCollaborators parses the paginated results envelope', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/lists/l-1/collaborators');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'c-1',
                'user_id': 'u-2',
                'user_email': 'friend@example.com',
                'permission': 'view',
              },
            ],
            'next': null,
            'previous': null,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final collaborators = await repo.fetchCollaborators('l-1');

      expect(collaborators, hasLength(1));
      expect(collaborators.first.userEmail, 'friend@example.com');
    });

    test('removeCollaborator DELETEs the collaborator by user id', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/lists/l-1/collaborators/u-2');
        return http.Response('', 204);
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      await repo.removeCollaborator('l-1', 'u-2');
    });

    test('fetchActivity parses actor, action, and detail', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/lists/l-1/activity');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'a-1',
                'actor_email': 'friend@example.com',
                'action': 'item_added',
                'detail': 'Boerewors',
                'created_at': '2026-07-07T09:00:00Z',
              },
            ],
            'next': null,
            'previous': null,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final entries = await repo.fetchActivity('l-1');

      expect(entries, hasLength(1));
      expect(entries.first.action, 'item_added');
      expect(entries.first.actorEmail, 'friend@example.com');
      expect(entries.first.detail, 'Boerewors');
    });

    test('setItemChecked forwards store_id when provided', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'i-1',
            'name': 'Milk',
            'quantity': '1.00',
            'unit': 'ea',
            'note': '',
            'checked': true,
            'paid_price': 2599,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      await repo.setItemChecked(
        'l-1',
        'i-1',
        checked: true,
        paidPrice: 2599,
        storeId: 'store-a',
      );

      expect(sentBody['store_id'], 'store-a');
    });

    test('setItemChecked omits store_id when not provided', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'i-1',
            'name': 'Milk',
            'quantity': '1.00',
            'unit': 'ea',
            'note': '',
            'checked': true,
            'paid_price': 2599,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      await repo.setItemChecked('l-1', 'i-1', checked: true, paidPrice: 2599);

      expect(sentBody.containsKey('store_id'), false);
    });

    test('fetchComparison parses stores ranked with best/saves', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/lists/l-1/comparison');
        return http.Response(
          jsonEncode({
            'currency_code': 'ZAR',
            'stores': [
              {
                'store_id': 'store-a',
                'name': 'Store A',
                'total': 48750,
                'confidence': 'high',
              },
              {
                'store_id': 'store-b',
                'name': 'Store B',
                'total': 50990,
                'confidence': 'medium',
              },
            ],
            'best': {'store_id': 'store-a', 'saves': 2240},
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final comparison = await repo.fetchComparison('l-1');

      expect(comparison.currencyCode, 'ZAR');
      expect(comparison.stores, hasLength(2));
      expect(comparison.stores.first.name, 'Store A');
      expect(comparison.stores.first.total, 48750);
      expect(comparison.bestStoreId, 'store-a');
      expect(comparison.bestSaves, 2240);
      expect(comparison.isEmpty, false);
    });

    test('fetchComparison with no priced items reports empty', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'currency_code': 'ZAR', 'stores': [], 'best': null}),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final comparison = await repo.fetchComparison('l-1');

      expect(comparison.isEmpty, true);
      expect(comparison.bestStoreId, isNull);
    });

    test('fetchListDetail parses has_promotion per item', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'l-1',
            'title': 'Groceries',
            'category': 'groceries',
            'is_recurring': false,
            'item_count': 2,
            'items': [
              {
                'id': 'i-1',
                'name': 'Milk',
                'quantity': '1.00',
                'unit': 'ea',
                'note': '',
                'checked': false,
                'has_promotion': true,
              },
              {
                'id': 'i-2',
                'name': 'Rice',
                'quantity': '1.00',
                'unit': 'ea',
                'note': '',
                'checked': false,
                'has_promotion': false,
              },
            ],
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final list = await repo.fetchListDetail('l-1');

      expect(list.items!.first.hasPromotion, true);
      expect(list.items!.last.hasPromotion, false);
    });

    test('fetchPromotions parses matched promotions', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/promotions');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'p-1',
                'store_id': 'store-a',
                'store_name': 'Store A',
                'product_id': 'prod-1',
                'product_name': 'Full cream milk 2L',
                'category': 'groceries',
                'title': '20% off milk',
                'description': 'This week only',
              },
            ],
            'next': null,
            'previous': null,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final promotions = await repo.fetchPromotions();

      expect(promotions, hasLength(1));
      expect(promotions.first.storeName, 'Store A');
      expect(promotions.first.title, '20% off milk');
    });

    test('optOutOfPromotions posts store_id', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/promotions/opt-out');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'o-1', 'category': '', 'created_at': '2026-07-07T00:00:00Z'}),
          201,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      await repo.optOutOfPromotions(storeId: 'store-a');

      expect(sentBody['store_id'], 'store-a');
      expect(sentBody.containsKey('category'), false);
    });

    test('optOutOfPromotions posts category', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'o-1', 'category': 'groceries', 'created_at': '2026-07-07T00:00:00Z'}),
          201,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      await repo.optOutOfPromotions(category: 'groceries');

      expect(sentBody['category'], 'groceries');
      expect(sentBody.containsKey('store_id'), false);
    });

    test('fetchLists parses collaborator previews', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'l-1',
                'title': 'Shared Braai',
                'category': 'groceries',
                'is_recurring': false,
                'item_count': 2,
                'collaborators': [
                  {
                    'user_id': 'u-1',
                    'email': 'owner@example.com',
                    'initials': 'OW',
                  },
                  {
                    'user_id': 'u-2',
                    'email': 'friend@example.com',
                    'initials': 'FR',
                  },
                ],
              },
            ],
            'next': null,
            'previous': null,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final lists = await repo.fetchLists();

      expect(lists.first.collaborators, hasLength(2));
      expect(lists.first.collaborators.last.initials, 'FR');
    });

    test('addItem sends product_id when provided', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'i-1',
            'product_id': 'p-1',
            'name': 'Full Cream Milk 2L',
            'quantity': '1.00',
            'unit': 'ea',
            'note': '',
            'checked': false,
          }),
          201,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final item = await repo.addItem(
        'l-1',
        name: 'Full Cream Milk 2L',
        productId: 'p-1',
      );

      expect(sentBody['product_id'], 'p-1');
      expect(item.name, 'Full Cream Milk 2L');
    });

    test('sendMessage POSTs body to /messages', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/lists/l-1/messages');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'm-1',
            'author_id': 'u-1',
            'author_email': 'owner@example.com',
            'body': 'On my way',
            'created_at': '2026-07-07T10:00:00Z',
          }),
          201,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final message = await repo.sendMessage('l-1', 'On my way');

      expect(sentBody['body'], 'On my way');
      expect(message.body, 'On my way');
    });

    test('updateList PATCHes title and category', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v1/lists/l-1');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'l-1',
            'title': 'Weekly Shop',
            'category': 'groceries',
            'is_recurring': true,
            'item_count': 0,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final list = await repo.updateList(
        'l-1',
        title: 'Weekly Shop',
        category: 'groceries',
        isRecurring: true,
      );

      expect(sentBody['title'], 'Weekly Shop');
      expect(sentBody['category'], 'groceries');
      expect(sentBody['is_recurring'], true);
      expect(list.title, 'Weekly Shop');
    });

    test('deleteList DELETEs the list', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/lists/l-1');
        return http.Response('', 204);
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      await repo.deleteList('l-1');
    });

    test('updateItem PATCHes name, quantity, unit, and note', () async {
      late Map<String, dynamic> sentBody;
      final mockClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v1/lists/l-1/items/i-1');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'i-1',
            'name': 'Low-fat milk 1L',
            'quantity': '2.00',
            'unit': 'ea',
            'note': 'organic',
            'checked': false,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final item = await repo.updateItem(
        'l-1',
        'i-1',
        name: 'Low-fat milk 1L',
        quantity: 2,
        unit: 'ea',
        note: 'organic',
      );

      expect(sentBody['name'], 'Low-fat milk 1L');
      expect(sentBody['quantity'], 2);
      expect(sentBody['unit'], 'ea');
      expect(sentBody['note'], 'organic');
      expect(item.name, 'Low-fat milk 1L');
    });

    test('deleteItem DELETEs the item', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/lists/l-1/items/i-1');
        return http.Response('', 204);
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      await repo.deleteItem('l-1', 'i-1');
    });

    test('reorderItems PATCHes each item position', () async {
      final paths = <String>[];
      final mockClient = MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          jsonEncode({
            'id': 'i-1',
            'name': 'Item',
            'quantity': '1.00',
            'unit': 'ea',
            'note': '',
            'checked': false,
          }),
          200,
        );
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      await repo.reorderItems('l-1', ['i-2', 'i-1', 'i-3']);

      expect(paths, [
        '/v1/lists/l-1/items/i-2',
        '/v1/lists/l-1/items/i-1',
        '/v1/lists/l-1/items/i-3',
      ]);
    });

    test('optOutOfPromotions asserts exactly one target', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{}', 201);
      });
      final repo = ListsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      expect(
        () => repo.optOutOfPromotions(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
