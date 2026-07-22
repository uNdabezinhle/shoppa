import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/token_store.dart';
import 'package:shoppa_app/core/verify_repository.dart';

void main() {
  group('VerifyRepository', () {
    late InMemoryTokenStore tokens;

    setUp(() async {
      tokens = InMemoryTokenStore();
      await tokens.save(access: 'a', refresh: 'r');
    });

    test('verify parses traffic-light payload', () async {
      final client = ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokenStore: tokens,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/products/verify');
          expect(request.url.queryParameters['gtin'], '6001234567899');
          return http.Response(
            jsonEncode({
              'gtin': '6001234567899',
              'status': 'found',
              'product': {
                'name': 'Milk',
                'brand': 'Demo',
                'ingredients_text': 'milk',
                'allergens': ['en:milk'],
                'traces': [],
                'nutriments': {},
                'categories': [],
              },
              'sources': {
                'open_food_facts': true,
                'shoppa_catalogue': false,
                'shoppa_product_id': null,
              },
              'verification': {
                'level': 'red',
                'reasons': ['Contains milk'],
                'matched_allergens': ['en:milk'],
                'trace_matches': [],
              },
              'cached': false,
              'fetched_at': '2026-01-01T00:00:00Z',
              'disclaimer': 'Not medical advice',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final repo = VerifyRepository(client);
      final result = await repo.verify('6001234567899');
      expect(result.status, 'found');
      expect(result.verification.level, 'red');
      expect(result.product?.name, 'Milk');
    });
  });
}
