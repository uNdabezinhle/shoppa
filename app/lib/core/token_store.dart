import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the JWT access/refresh pair for the current session.
abstract class TokenStore {
  Future<void> save({required String access, required String refresh});
  Future<String?> get accessToken;
  Future<String?> get refreshToken;
  Future<bool> get hasSession;
  Future<void> clear();
}

/// Encrypted, persistent storage — survives app restarts (SRS FR-1.3).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'shoppa_access_token';
  static const _refreshKey = 'shoppa_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<void> save({required String access, required String refresh}) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: access),
      _storage.write(key: _refreshKey, value: refresh),
    ]);
  }

  @override
  Future<String?> get accessToken => _storage.read(key: _accessKey);

  @override
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);

  @override
  Future<bool> get hasSession async =>
      (await refreshToken)?.isNotEmpty ?? false;

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}

/// In-memory implementation for unit tests and local development.
class InMemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<String?> get accessToken async => _access;

  @override
  Future<String?> get refreshToken async => _refresh;

  @override
  Future<bool> get hasSession async => _refresh != null && _refresh!.isNotEmpty;

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}