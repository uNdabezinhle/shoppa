import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_repository.dart';
import 'core/list_realtime_client.dart';
import 'core/lists_repository.dart';
import 'core/offline_store.dart';
import 'core/token_store.dart';
import 'screens/login_screen.dart';
import 'theme/shoppa_theme.dart';

/// API base URL is overridable at build time, e.g.:
///   flutter run --dart-define=API_BASE_URL=https://api.shoppa.app/v1
const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000/v1',
);

/// Real-time (WebSocket) endpoints live at the ASGI root, not under the
/// versioned REST path -- derived from _apiBaseUrl by dropping the /v1
/// suffix and swapping the scheme (http -> ws, https -> wss).
String _deriveWsBaseUrl(String apiBaseUrl) {
  final withoutSuffix = apiBaseUrl.endsWith('/v1')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 3)
      : apiBaseUrl;
  if (withoutSuffix.startsWith('https://')) {
    return 'wss://${withoutSuffix.substring('https://'.length)}';
  }
  if (withoutSuffix.startsWith('http://')) {
    return 'ws://${withoutSuffix.substring('http://'.length)}';
  }
  return withoutSuffix;
}

void main() {
  final tokenStore = InMemoryTokenStore();
  final apiClient = ApiClient(baseUrl: _apiBaseUrl, tokenStore: tokenStore);
  final authRepository = AuthRepository(apiClient);
  final listsRepository = ListsRepository(
    apiClient,
    offlineStore: SharedPreferencesOfflineStore(),
  );
  final realtimeClient = ListRealtimeClient(
    wsBaseUrl: _deriveWsBaseUrl(_apiBaseUrl),
    tokenStore: tokenStore,
  );

  runApp(ShoppaApp(
    authRepository: authRepository,
    listsRepository: listsRepository,
    realtimeClient: realtimeClient,
  ));
}

class ShoppaApp extends StatelessWidget {
  const ShoppaApp({
    super.key,
    required this.authRepository,
    required this.listsRepository,
    required this.realtimeClient,
  });

  final AuthRepository authRepository;
  final ListsRepository listsRepository;
  final ListRealtimeClient realtimeClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shoppa',
      debugShowCheckedModeBanner: false,
      theme: ShoppaTheme.dark,
      home: LoginScreen(
        authRepository: authRepository,
        listsRepository: listsRepository,
        realtimeClient: realtimeClient,
      ),
    );
  }
}
