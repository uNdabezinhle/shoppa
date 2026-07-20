/// Push device registration (M8 / POST /v1/devices).
import 'api_client.dart';

class DevicesRepository {
  DevicesRepository(this._client);

  final ApiClient _client;

  /// Registers an FCM (or stub) token for the current user.
  /// Safe to call on web with a stub token when real FCM is unavailable.
  Future<void> registerDevice({
    required String token,
    String platform = 'web',
  }) async {
    if (token.isEmpty) return;
    await _client.post('/devices', {
      'token': token,
      'platform': platform,
    });
  }
}
