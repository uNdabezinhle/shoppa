import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/auth_repository.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('AuthRepository', () {
    late InMemoryTokenStore tokenStore;

    setUp(() {
      tokenStore = InMemoryTokenStore();
    });

    test('register posts to /auth/register and parses the created user', () async {
      late Uri capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'id': 'a5f1c2e0-0000-0000-0000-000000000001',
            'email': 'shopper@example.com',
            'account_type': 'personal',
            'region': 'ZA',
          }),
          201,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokenStore: tokenStore,
        httpClient: mockClient,
      );
      final repo = AuthRepository(client);

      final user = await repo.register(
        email: 'shopper@example.com',
        password: 'a-strong-passw0rd!',
      );

      expect(capturedUri.toString(), 'http://localhost:8000/v1/auth/register');
      expect(user.email, 'shopper@example.com');
      expect(user.accountType, 'personal');
    });

    test('login stores the token pair and returns the user', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access': 'access-token',
            'refresh': 'refresh-token',
            'user': {
              'id': 'a5f1c2e0-0000-0000-0000-000000000001',
              'email': 'shopper@example.com',
              'account_type': 'personal',
              'region': 'ZA',
            },
          }),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokenStore: tokenStore,
        httpClient: mockClient,
      );
      final repo = AuthRepository(client);

      final user = await repo.login(
        email: 'shopper@example.com',
        password: 'a-strong-passw0rd!',
      );

      expect(user.email, 'shopper@example.com');
      expect(await tokenStore.accessToken, 'access-token');
      expect(await tokenStore.refreshToken, 'refresh-token');
    });

    test('a non-2xx response throws ApiException with the error envelope', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'validation_error',
              'message': 'One or more fields are invalid.',
              'fields': {
                'email': ['This email is already registered.']
              },
            },
          }),
          422,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokenStore: tokenStore,
        httpClient: mockClient,
      );
      final repo = AuthRepository(client);

      expect(
        () => repo.register(email: 'dup@example.com', password: 'x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.code, 'code', 'validation_error'),
        ),
      );
    });

    test('fetchMe sends the bearer token on the request', () async {
      await tokenStore.save(access: 'stored-access-token', refresh: 'r');
      late Map<String, String> capturedHeaders;
      final mockClient = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response(
          jsonEncode({
            'id': 'a5f1c2e0-0000-0000-0000-000000000001',
            'email': 'shopper@example.com',
            'account_type': 'personal',
            'region': 'ZA',
          }),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokenStore: tokenStore,
        httpClient: mockClient,
      );
      final repo = AuthRepository(client);

      await repo.fetchMe();

      expect(capturedHeaders['Authorization'], 'Bearer stored-access-token');
    });
  });
}
