import 'auth_repository.dart';
import 'auth_state.dart';
import 'catalogue_repository.dart';
import 'list_chat_client.dart';
import 'list_realtime_client.dart';
import 'lists_repository.dart';
import 'notifications_repository.dart';

/// Shared dependencies wired once in [main] and passed into the router.
class AppDeps {
  AppDeps({
    required this.authRepository,
    required this.catalogueRepository,
    required this.listsRepository,
    required this.notificationsRepository,
    required this.realtimeClient,
    required this.chatClient,
    required this.authState,
  });

  final AuthRepository authRepository;
  final CatalogueRepository catalogueRepository;
  final ListsRepository listsRepository;
  final NotificationsRepository notificationsRepository;
  final ListRealtimeClient realtimeClient;
  final ListChatClient chatClient;
  final AuthState authState;
}