import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/auth_state.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('keeps splash while bootstrapping', () {
      expect(
        resolveAuthRedirect(
          bootstrapping: true,
          isAuthenticated: false,
          matchedLocation: '/',
        ),
        isNull,
      );
      expect(
        resolveAuthRedirect(
          bootstrapping: true,
          isAuthenticated: false,
          matchedLocation: '/home',
        ),
        '/',
      );
    });

    test('sends unauthenticated users to login', () {
      expect(
        resolveAuthRedirect(
          bootstrapping: false,
          isAuthenticated: false,
          matchedLocation: '/home',
        ),
        '/login',
      );
      expect(
        resolveAuthRedirect(
          bootstrapping: false,
          isAuthenticated: false,
          matchedLocation: '/login',
        ),
        isNull,
      );
      expect(
        resolveAuthRedirect(
          bootstrapping: false,
          isAuthenticated: false,
          matchedLocation: '/register',
        ),
        isNull,
      );
    });

    test('sends authenticated users away from auth routes', () {
      expect(
        resolveAuthRedirect(
          bootstrapping: false,
          isAuthenticated: true,
          matchedLocation: '/login',
        ),
        '/home',
      );
      expect(
        resolveAuthRedirect(
          bootstrapping: false,
          isAuthenticated: true,
          matchedLocation: '/',
        ),
        '/home',
      );
      expect(
        resolveAuthRedirect(
          bootstrapping: false,
          isAuthenticated: true,
          matchedLocation: '/lists/abc',
        ),
        isNull,
      );
    });
  });
}