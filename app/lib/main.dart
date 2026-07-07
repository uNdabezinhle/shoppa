import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/api_client.dart';
import 'core/app_deps.dart';
import 'core/app_router.dart';
import 'core/auth_repository.dart';
import 'core/auth_state.dart';
import 'core/list_chat_client.dart';
import 'core/list_realtime_client.dart';
import 'core/lists_repository.dart';
import 'core/offline_store.dart';
import 'core/token_store.dart';
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
  WidgetsFlutterBinding.ensureInitialized();

  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(baseUrl: _apiBaseUrl, tokenStore: tokenStore);
  final authRepository = AuthRepository(apiClient);
  final listsRepository = ListsRepository(
    apiClient,
    offlineStore: SharedPreferencesOfflineStore(),
  );
  final wsBaseUrl = _deriveWsBaseUrl(_apiBaseUrl);
  final realtimeClient = ListRealtimeClient(
    wsBaseUrl: wsBaseUrl,
    tokenStore: tokenStore,
  );
  final chatClient = ListChatClient(
    wsBaseUrl: wsBaseUrl,
    tokenStore: tokenStore,
  );
  final authState = AuthState(authRepository);
  final deps = AppDeps(
    authRepository: authRepository,
    listsRepository: listsRepository,
    realtimeClient: realtimeClient,
    chatClient: chatClient,
    authState: authState,
  );
  final router = createAppRouter(deps);

  runApp(ShoppaApp(router: router, authState: authState));
}

class ShoppaApp extends StatefulWidget {
  const ShoppaApp({
    super.key,
    required this.router,
    required this.authState,
  });

  final GoRouter router;
  final AuthState authState;

  @override
  State<ShoppaApp> createState() => _ShoppaAppState();
}

class _ShoppaAppState extends State<ShoppaApp> {
  @override
  void initState() {
    super.initState();
    widget.authState.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Shoppa',
      debugShowCheckedModeBanner: false,
      theme: ShoppaTheme.dark,
      routerConfig: widget.router,
    );
  }
}