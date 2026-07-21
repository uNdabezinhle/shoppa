import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoppa_app/core/token_store.dart';

void main() {
  group('InMemoryTokenStore', () {
    test('persists access and refresh tokens in memory', () async {
      final store = InMemoryTokenStore();
      await store.save(access: 'access', refresh: 'refresh');

      expect(await store.accessToken, 'access');
      expect(await store.refreshToken, 'refresh');
      expect(await store.hasSession, isTrue);
    });

    test('clear removes both tokens', () async {
      final store = InMemoryTokenStore();
      await store.save(access: 'access', refresh: 'refresh');
      await store.clear();

      expect(await store.hasSession, isFalse);
      expect(await store.accessToken, isNull);
    });
  });

  group('SharedPreferencesTokenStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists and clears tokens', () async {
      final store = SharedPreferencesTokenStore();
      await store.save(access: 'a', refresh: 'r');
      expect(await store.accessToken, 'a');
      expect(await store.refreshToken, 'r');
      expect(await store.hasSession, isTrue);

      await store.clear();
      expect(await store.hasSession, isFalse);
      expect(await store.accessToken, isNull);
    });
  });
}