import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoppa_app/core/api_client.dart';
import 'package:shoppa_app/core/auth_repository.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('AuthRepository privacy', () {
    test('exportMyData fetches portable export', () async {
      final tokenStore = InMemoryTokenStore();
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/users/me/data-export');
        return http.Response(
          jsonEncode({
            'user': {'email': 'a@b.com'},
            'owned_lists': [],
            'export_format': 'shoppa-user-export-v1',
          }),
          200,
        );
      });
      final repo = AuthRepository(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokenStore: tokenStore,
          httpClient: mockClient,
        ),
      );
      final data = await repo.exportMyData();
      expect(data['export_format'], 'shoppa-user-export-v1');
    });
  });
}