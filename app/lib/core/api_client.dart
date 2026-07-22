/// Thin HTTP client wrapper matching the API Specification's conventions:
/// versioned base URL, JSON everywhere, bearer auth on authenticated calls.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'token_store.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, {this.fields});

  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic>? fields;

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}

/// Thrown in place of the underlying transport error (SocketException,
/// http.ClientException, TimeoutException, ...) whenever a request never
/// reached the server at all -- as opposed to ApiException, which means
/// the server responded but rejected the request. Callers (ListsRepository
/// in particular, SRS FR-4.2) catch this specifically to fall back to the
/// offline cache/queue rather than surfacing a generic error.
class NetworkUnavailableException implements Exception {
  const NetworkUnavailableException([this.message = 'No network connection.']);

  final String message;

  @override
  String toString() => 'NetworkUnavailableException($message)';
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokenStore,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  /// e.g. https://api.shoppa.app/v1 in production, or a local dev server.
  final String baseUrl;
  final TokenStore tokenStore;
  final http.Client _client;

  Future<void>? _refreshInFlight;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, String>> _headers({bool authenticated = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (authenticated) {
      final token = await tokenStore.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Wraps every transport call: a connection failure (no network, DNS
  /// failure, timeout, ...) surfaces as NetworkUnavailableException
  /// rather than whatever transport-specific exception the underlying
  /// http.Client throws, so callers have one thing to catch regardless
  /// of platform.
  Future<http.Response> _send(Future<http.Response> Function() send) async {
    try {
      return await send();
    } on http.ClientException catch (e) {
      throw NetworkUnavailableException(e.message);
    }
  }

  bool _canAutoRefresh(String path) {
    return path != '/auth/refresh' &&
        path != '/auth/login' &&
        path != '/auth/register';
  }

  /// Transparently renews the access token using the stored refresh token
  /// (SRS FR-1.3). Concurrent 401s share one in-flight refresh.
  Future<bool> refreshTokens() async {
    if (_refreshInFlight != null) {
      await _refreshInFlight;
      return (await tokenStore.accessToken) != null;
    }

    final completer = _doRefresh();
    _refreshInFlight = completer;
    try {
      return await completer;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<bool> _doRefresh() async {
    final refresh = await tokenStore.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final response = await _send(
        () async => _client.post(
          _uri('/auth/refresh'),
          headers: await _headers(authenticated: false),
          body: jsonEncode({'refresh': refresh}),
        ),
      );
      final decoded = _decode(response) as Map<String, dynamic>;
      final access = decoded['access'] as String?;
      if (access == null || access.isEmpty) {
        await tokenStore.clear();
        return false;
      }
      final rotated = decoded['refresh'] as String? ?? refresh;
      await tokenStore.save(access: access, refresh: rotated);
      return true;
    } on ApiException {
      await tokenStore.clear();
      return false;
    }
  }

  Future<dynamic> _request(
    String path,
    Future<http.Response> Function() send, {
    required bool authenticated,
  }) async {
    var retried = false;
    while (true) {
      final response = await _send(send);
      try {
        return _decode(response);
      } on ApiException catch (e) {
        if (e.statusCode == 401 &&
            authenticated &&
            !retried &&
            _canAutoRefresh(path)) {
          retried = true;
          final refreshed = await refreshTokens();
          if (!refreshed) rethrow;
          continue;
        }
        rethrow;
      }
    }
  }

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    return _request(
      path,
      () async => _client.post(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
        body: jsonEncode(body),
      ),
      authenticated: authenticated,
    );
  }

  Future<dynamic> get(
    String path, {
    bool authenticated = true,
    Map<String, String>? queryParameters,
  }) async {
    var uri = _uri(path);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    return _request(
      path,
      () async => _client.get(
        uri,
        headers: await _headers(authenticated: authenticated),
      ),
      authenticated: authenticated,
    );
  }

  Future<dynamic> put(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    return _request(
      path,
      () async => _client.put(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
        body: jsonEncode(body),
      ),
      authenticated: authenticated,
    );
  }

  Future<dynamic> patch(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    return _request(
      path,
      () async => _client.patch(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
        body: jsonEncode(body),
      ),
      authenticated: authenticated,
    );
  }

  Future<void> delete(String path, {bool authenticated = true}) async {
    await _request(
      path,
      () async => _client.delete(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
      ),
      authenticated: authenticated,
    );
  }

  /// Binary download (e.g. list CSV/PDF export) without JSON decoding.
  Future<Uint8List> download(
    String path, {
    bool authenticated = true,
    Map<String, String>? queryParameters,
  }) async {
    var uri = _uri(path);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    var retried = false;
    while (true) {
      final response = await _send(
        () async => _client.get(
          uri,
          headers: await _headers(authenticated: authenticated),
        ),
      );
      if (response.statusCode == 401 &&
          authenticated &&
          !retried &&
          _canAutoRefresh(path)) {
        retried = true;
        final refreshed = await refreshTokens();
        if (!refreshed) {
          throw ApiException(401, 'unauthorized', 'Authentication required.');
        }
        continue;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return Uint8List.fromList(response.bodyBytes);
      }
      try {
        _decode(response);
      } on ApiException {
        rethrow;
      }
      throw ApiException(response.statusCode, 'error', 'Download failed.');
    }
  }

  dynamic _decode(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final error = (decoded is Map<String, dynamic>)
        ? decoded['error'] as Map<String, dynamic>?
        : null;
    throw ApiException(
      response.statusCode,
      error?['code'] as String? ?? 'error',
      error?['message'] as String? ?? 'Request failed.',
      fields: error?['fields'] as Map<String, dynamic>?,
    );
  }
}