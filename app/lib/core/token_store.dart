/// Holds the JWT access/refresh pair for the current session.
///
/// This in-memory implementation is a placeholder for the vertical slice:
/// it proves the register -> login -> authenticated-request chain works.
/// Before Phase 1 exits it should be swapped for persistent, encrypted
/// storage (e.g. flutter_secure_storage) so sessions survive an app
/// restart — see the Implementation Plan §6.1 offline/security notes.
abstract class TokenStore {
  Future<void> save({required String access, required String refresh});
  Future<String?> get accessToken;
  Future<String?> get refreshToken;
  Future<void> clear();
}

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
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}
