import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/catalogue_repository.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('CatalogueRepository', () {
    late InMemoryTokenStore tokenStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
    });

    test('searchProducts parses paginated catalogue results', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/products');
        expect(request.url.queryParameters['q'], 'milk');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'p-1',
                'name': 'Full Cream Milk 2L',
                'region': 'ZA',
              },
            ],
            'next': null,
            'previous': null,
          }),
          200,
        );
      });
      final repo = CatalogueRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final products = await repo.searchProducts('milk');

      expect(products, hasLength(1));
      expect(products.first.name, 'Full Cream Milk 2L');
    });

    test('fetchStorePrice returns price for product at store', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/products/p-1/store-price');
        expect(request.url.queryParameters['store_id'], 'store-a');
        return http.Response(
          jsonEncode({
            'store_id': 'store-a',
            'price': 3299,
            'confidence': 'high',
          }),
          200,
        );
      });
      final repo = CatalogueRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final price = await repo.fetchStorePrice(
        productId: 'p-1',
        storeId: 'store-a',
      );

      expect(price?.price, 3299);
      expect(price?.confidence, 'high');
    });
  });
}