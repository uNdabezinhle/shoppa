import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/notifications_repository.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('NotificationsRepository', () {
    late InMemoryTokenStore tokenStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
    });

    test('fetchNotifications parses paginated feed', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/notifications');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'n-1',
                'kind': 'price_drop',
                'title': 'Price drop on Full Cream Milk 2L',
                'body': 'Checkers: now R32.99 (was R34.99)',
                'is_read': false,
                'created_at': '2026-07-07T10:00:00Z',
                'payload': {'product_id': 'p-1'},
              },
            ],
            'next': null,
            'previous': null,
          }),
          200,
        );
      });
      final repo = NotificationsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final notes = await repo.fetchNotifications();

      expect(notes, hasLength(1));
      expect(notes.first.kind, 'price_drop');
      expect(notes.first.isRead, isFalse);
    });

    test('markRead patches notification and returns updated row', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v1/notifications/n-1/read');
        return http.Response(
          jsonEncode({
            'id': 'n-1',
            'kind': 'price_drop',
            'title': 'Price drop on Full Cream Milk 2L',
            'body': 'Checkers: now R32.99 (was R34.99)',
            'is_read': true,
            'created_at': '2026-07-07T10:00:00Z',
            'payload': {},
          }),
          200,
        );
      });
      final repo = NotificationsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final note = await repo.markRead('n-1');

      expect(note.isRead, isTrue);
    });

    test('unreadCount counts unread notifications', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'n-1',
                'kind': 'price_drop',
                'title': 'A',
                'body': 'B',
                'is_read': false,
                'created_at': '2026-07-07T10:00:00Z',
              },
              {
                'id': 'n-2',
                'kind': 'price_drop',
                'title': 'C',
                'body': 'D',
                'is_read': true,
                'created_at': '2026-07-07T09:00:00Z',
              },
            ],
          }),
          200,
        );
      });
      final repo = NotificationsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      expect(await repo.unreadCount(), 1);
    });
  });
}