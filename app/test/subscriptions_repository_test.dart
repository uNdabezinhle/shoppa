import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/subscriptions_repository.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('SubscriptionsRepository', () {
    late InMemoryTokenStore tokenStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
    });

    test('fetchPlans parses launch tiers', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/subscriptions/plans');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'slug': 'free',
                'name': 'Free',
                'price_monthly': 0,
                'currency_code': 'ZAR',
                'features': [],
                'max_owned_lists': 3,
              },
              {
                'slug': 'professional',
                'name': 'Professional',
                'price_monthly': 9900,
                'currency_code': 'ZAR',
                'features': ['scale_lists'],
                'max_owned_lists': null,
              },
            ],
          }),
          200,
        );
      });
      final repo = SubscriptionsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final plans = await repo.fetchPlans();
      expect(plans, hasLength(2));
      expect(plans.first.slug, 'free');
    });

    test('startCheckout returns session url', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/subscriptions/checkout');
        return http.Response(
          jsonEncode({
            'checkout_url': 'https://checkout.example/session',
            'plan_id': 'professional',
            'dev_mode': true,
          }),
          200,
        );
      });
      final repo = SubscriptionsRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );

      final session = await repo.startCheckout('professional');
      expect(session.checkoutUrl, contains('checkout'));
      expect(session.devMode, isTrue);
    });
  });
}