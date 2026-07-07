import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

/// Holds the authenticated user and notifies [GoRouter] when it changes.
class AuthState extends ChangeNotifier {
  AuthState(this._authRepository);

  final AuthRepository _authRepository;

  bool bootstrapping = true;
  ShoppaUser? user;

  bool get isAuthenticated => user != null;

  Future<void> bootstrap() async {
    bootstrapping = true;
    notifyListeners();
    user = await _authRepository.restoreSession();
    bootstrapping = false;
    notifyListeners();
  }

  void setUser(ShoppaUser value) {
    user = value;
    notifyListeners();
  }

  Future<void> logout() async {
    await _authRepository.logout();
    user = null;
    notifyListeners();
  }
}

/// Pure redirect logic for unit tests and [createAppRouter].
String? resolveAuthRedirect({
  required bool bootstrapping,
  required bool isAuthenticated,
  required String matchedLocation,
}) {
  if (bootstrapping) {
    return matchedLocation == '/' ? null : '/';
  }

  const publicRoutes = {'/login', '/register'};
  final isPublic = publicRoutes.contains(matchedLocation);

  if (!isAuthenticated && !isPublic) {
    return '/login';
  }

  if (isAuthenticated &&
      (matchedLocation == '/' ||
          matchedLocation == '/login' ||
          matchedLocation == '/register')) {
    return '/home';
  }

  return null;
}