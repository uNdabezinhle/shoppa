import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the JWT access/refresh pair for the current session.
abstract class TokenStore {
  Future<void> save({required String access, required String refresh});
  Future<String?> get accessToken;
  Future<String?> get refreshToken;
  Future<bool> get hasSession;
  Future<void> clear();
}

/// Platform-appropriate store: secure on mobile/desktop, prefs on web.
///
/// WebCrypto-backed [FlutterSecureStorage] often throws [OperationError] in
/// Chrome (corrupt keys / plugin quirks); SharedPreferences is reliable there.
TokenStore createDefaultTokenStore() {
  if (kIsWeb) {
    return SharedPreferencesTokenStore();
  }
  return SecureTokenStore();
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
  Future<String?> get accessToken async {
    try {
      return await _storage.read(key: _accessKey);
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<String?> get refreshToken async {
    try {
      return await _storage.read(key: _refreshKey);
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<bool> get hasSession async =>
      (await refreshToken)?.isNotEmpty ?? false;

  @override
  Future<void> clear() async {
    try {
      await Future.wait([
        _storage.delete(key: _accessKey),
        _storage.delete(key: _refreshKey),
      ]);
    } catch (_) {
      // Best-effort wipe when the platform store is broken.
    }
  }
}

/// Web / fallback token store using SharedPreferences.
class SharedPreferencesTokenStore implements TokenStore {
  SharedPreferencesTokenStore();

  static const _accessKey = 'shoppa_access_token';
  static const _refreshKey = 'shoppa_refresh_token';

  @override
  Future<void> save({required String access, required String refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  @override
  Future<String?> get accessToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessKey);
  }

  @override
  Future<String?> get refreshToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshKey);
  }

  @override
  Future<bool> get hasSession async =>
      (await refreshToken)?.isNotEmpty ?? false;

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
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
