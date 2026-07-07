/// Thin HTTP client wrapper matching the API Specification's conventions:
/// versioned base URL, JSON everywhere, bearer auth on authenticated calls.
import 'dart:convert';

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

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    final response = await _send(
      () async => _client.post(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<dynamic> get(String path, {bool authenticated = true}) async {
    final response = await _send(
      () async => _client.get(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
      ),
    );
    return _decode(response);
  }

  Future<dynamic> patch(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    final response = await _send(
      () async => _client.patch(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<void> delete(String path, {bool authenticated = true}) async {
    final response = await _send(
      () async => _client.delete(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
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
