import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_deps.dart';
import 'auth_state.dart';
import '../screens/app_shell.dart';
import '../screens/compare_tab_screen.dart';
import '../screens/delivery_screen.dart';
import '../screens/list_screen.dart';
import '../screens/login_screen.dart';
import '../screens/mall_tab_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/my_lists_tab_screen.dart';
import '../screens/discover_lists_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/promotions_screen.dart';
import '../screens/subscription_screen.dart';
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
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => MallTabScreen(
              authRepository: deps.authRepository,
              listsRepository: deps.listsRepository,
              notificationsRepository: deps.notificationsRepository,
              user: deps.authState.user!,
            ),
          ),
          GoRoute(
            path: '/compare',
            builder: (context, state) => CompareTabScreen(
              listsRepository: deps.listsRepository,
            ),
          ),
          GoRoute(
            path: '/my-lists',
            builder: (context, state) => MyListsTabScreen(
              listsRepository: deps.listsRepository,
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => ProfileScreen(
              authRepository: deps.authRepository,
              authState: deps.authState,
              notificationsRepository: deps.notificationsRepository,
              user: deps.authState.user!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/promotions',
        builder: (context, state) => PromotionsScreen(
          listsRepository: deps.listsRepository,
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => NotificationsScreen(
          notificationsRepository: deps.notificationsRepository,
        ),
      ),
      GoRoute(
        path: '/subscriptions',
        builder: (context, state) => SubscriptionScreen(
          subscriptionsRepository: deps.subscriptionsRepository,
        ),
      ),
      GoRoute(
        path: '/discover-lists',
        builder: (context, state) => DiscoverListsScreen(
          listsRepository: deps.listsRepository,
        ),
      ),
      GoRoute(
        path: '/delivery',
        builder: (context, state) {
          final listId = state.uri.queryParameters['listId'] ?? '';
          final title = state.uri.queryParameters['title'] ?? 'List';
          return DeliveryScreen(
            deliveryRepository: deps.deliveryRepository,
            deliveryRealtimeClient: deps.deliveryRealtimeClient,
            listId: listId,
            listTitle: title,
          );
        },
      ),
      GoRoute(
        path: '/lists/:listId',
        builder: (context, state) {
          final listId = state.pathParameters['listId']!;
          final title = state.uri.queryParameters['title'] ?? 'List';
          return ListScreen(
            listsRepository: deps.listsRepository,
            catalogueRepository: deps.catalogueRepository,
            realtimeClient: deps.realtimeClient,
            chatClient: deps.chatClient,
            currentUserEmail: deps.authState.user?.email,
            accountType: deps.authState.user?.accountType ?? 'personal',
            listId: listId,
            title: title,
          );
        },
      ),
    ],
  );
}