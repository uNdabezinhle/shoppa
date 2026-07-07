import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/delivery_repository.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('DeliveryRepository', () {
    late InMemoryTokenStore tokenStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
    });

    test('fetchDeliveryQuotes parses ranked platform quotes', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/lists/list-1/delivery-quotes');
        return http.Response(
          jsonEncode({
            'currency_code': 'ZAR',
            'quotes': [
              {
                'platform': 'checkers_6060',
                'display_name': 'Checkers 60/60',
                'subtotal': 5098,
                'delivery_fee': 2500,
                'total': 7598,
                'eta_minutes': 60,
                'available_items': 2,
                'total_items': 2,
                'order_url':
                    'https://checkers_6060.shoppa.app/order?aff=shoppa&list_id=list-1',
              },
            ],
          }),
          200,
        );
      });
      final repo = DeliveryRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final payload = await repo.fetchDeliveryQuotes('list-1');

      expect(payload.currencyCode, 'ZAR');
      expect(payload.quotes, hasLength(1));
      expect(payload.quotes.first.platform, 'checkers_6060');
      expect(payload.quotes.first.isFullyAvailable, isTrue);
    });
  });
}