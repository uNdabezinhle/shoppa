import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_deps.dart';
import 'auth_state.dart';
import '../screens/home_screen.dart';
import '../screens/list_screen.dart';
import '../screens/login_screen.dart';
import '../screens/promotions_screen.dart';
import '../screens/register_screen.dart';

GoRouter createAppRouter(AppDeps deps) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: deps.authState,
    redirect: (context, state) => resolveAuthRedirect(
      bootstrapping: deps.authState.bootstrapping,
      isAuthenticated: deps.authState.isAuthenticated,
      matchedLocation: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          authRepository: deps.authRepository,
          authState: deps.authState,
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => RegisterScreen(
          authRepository: deps.authRepository,
          authState: deps.authState,
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          final user = deps.authState.user!;
          return HomeScreen(
            authRepository: deps.authRepository,
            listsRepository: deps.listsRepository,
            realtimeClient: deps.realtimeClient,
            authState: deps.authState,
            user: user,
          );
        },
      ),
      GoRoute(
        path: '/promotions',
        builder: (context, state) => PromotionsScreen(
          listsRepository: deps.listsRepository,
        ),
      ),
      GoRoute(
        path: '/lists/:listId',
        builder: (context, state) {
          final listId = state.pathParameters['listId']!;
          final title = state.uri.queryParameters['title'] ?? 'List';
          return ListScreen(
            listsRepository: deps.listsRepository,
            realtimeClient: deps.realtimeClient,
            listId: listId,
            title: title,
          );
        },
      ),
    ],
  );
}