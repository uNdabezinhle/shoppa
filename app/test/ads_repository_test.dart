import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/ads_repository.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('AdsRepository', () {
    late InMemoryTokenStore tokenStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
    });

    test('fetchPlacements parses banner creative', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/ads/placements');
        expect(request.url.queryParameters['surface'], 'home');
        return http.Response(
          jsonEncode({
            'ads_free': false,
            'results': [
              {
                'id': 'ad-1',
                'slug': 'home-pro-banner',
                'title': 'Go ad-free',
                'body': 'Upgrade today',
                'cta_text': 'See plans',
                'cta_url': 'https://app.shoppa.app/subscriptions',
                'surface': 'home',
                'ad_format': 'banner',
                'sponsor_name': null,
              },
            ],
          }),
          200,
        );
      });
      final repo = AdsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );
      final result = await repo.fetchPlacements(surface: 'home', adFormat: 'banner');
      expect(result.adsFree, isFalse);
      expect(result.placements, hasLength(1));
      expect(result.placements.first.isBanner, isTrue);
    });
  });
}