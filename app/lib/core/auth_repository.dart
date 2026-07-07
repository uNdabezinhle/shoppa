/// Wraps the Accounts & Authentication endpoints (API Specification §4)
/// for use by the login/register screens.
import 'api_client.dart';

class ShoppaUser {
  ShoppaUser({
    required this.id,
    required this.email,
    required this.accountType,
    required this.region,
  });

  factory ShoppaUser.fromJson(Map<String, dynamic> json) => ShoppaUser(
        id: json['id'] as String,
        email: json['email'] as String,
        accountType: json['account_type'] as String,
        region: json['region'] as String? ?? 'ZA',
      );

  final String id;
  final String email;
  final String accountType;
  final String region;
}

class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<ShoppaUser> register({
    required String email,
    required String password,
    String accountType = 'personal',
    String region = 'ZA',
  }) async {
    final json = await _client.post('/auth/register', {
      'email': email,
      'password': password,
      'account_type': accountType,
      'region': region,
    });
    return ShoppaUser.fromJson(json);
  }

  Future<ShoppaUser> login({
    required String email,
    required String password,
  }) async {
    final json = await _client.post('/auth/login', {
      'email': email,
      'password': password,
    });
    await _client.tokenStore.save(
      access: json['access'] as String,
      refresh: json['refresh'] as String,
    );
    return ShoppaUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<ShoppaUser> fetchMe() async {
    final json = await _client.get('/users/me');
    return ShoppaUser.fromJson(json);
  }
}
