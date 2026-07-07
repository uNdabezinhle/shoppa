import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('ApiClient token refresh', () {
    late InMemoryTokenStore tokenStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
    });

    test('retries an authenticated request after a 401 with a token refresh',
        () async {
      await tokenStore.save(access: 'expired-access', refresh: 'valid-refresh');
      var meCalls = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          expect(jsonDecode(request.body), {'refresh': 'valid-refresh'});
          return http.Response(
            jsonEncode({
              'access': 'new-access',
              'refresh': 'rotated-refresh',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/users/me')) {
          meCalls++;
          if (meCalls == 1) {
            return http.Response(
              jsonEncode({
                'error': {'code': 'unauthorized', 'message': 'Unauthorized'},
              }),
              401,
            );
          }
          expect(request.headers['Authorization'], 'Bearer new-access');
          return http.Response(
            jsonEncode({
              'id': 'user-id',
              'email': 'shopper@example.com',
              'account_type': 'personal',
              'region': 'ZA',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final client = ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokenStore: tokenStore,
        httpClient: mockClient,
      );

      final json = await client.get('/users/me');
      expect(json['email'], 'shopper@example.com');
      expect(meCalls, 2);
      expect(await tokenStore.accessToken, 'new-access');
      expect(await tokenStore.refreshToken, 'rotated-refresh');
    });

    test('clears tokens when refresh fails', () async {
      await tokenStore.save(access: 'expired-access', refresh: 'bad-refresh');

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'unauthorized', 'message': 'Token is invalid'},
            }),
            401,
          );
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'unauthorized', 'message': 'Unauthorized'},
          }),
          401,
        );
      });

      final client = ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokenStore: tokenStore,
        httpClient: mockClient,
      );

      expect(
        () => client.get('/users/me'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      expect(await tokenStore.hasSession, isFalse);
    });
  });
}