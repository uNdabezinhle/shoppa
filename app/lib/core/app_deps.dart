import 'admin_repository.dart';
import 'ads_repository.dart';
import 'auth_repository.dart';
import 'auth_state.dart';
import 'catalogue_repository.dart';
import 'delivery_realtime_client.dart';
import 'delivery_repository.dart';
import 'list_chat_client.dart';
import 'list_realtime_client.dart';
import 'lists_repository.dart';
import 'notifications_repository.dart';
import 'subscriptions_repository.dart';
import 'verify_repository.dart';

/// Shared dependencies wired once in [main] and passed into the router.
class AppDeps {
  AppDeps({
    required this.adminRepository,
    required this.adsRepository,
    required this.authRepository,
    required this.catalogueRepository,
    required this.deliveryRepository,
    required this.deliveryRealtimeClient,
    required this.listsRepository,
    required this.notificationsRepository,
    required this.subscriptionsRepository,
    required this.verifyRepository,
    required this.realtimeClient,
    required this.chatClient,
    required this.authState,
  });

  final AdminRepository adminRepository;
  final AdsRepository adsRepository;
  final AuthRepository authRepository;
  final CatalogueRepository catalogueRepository;
  final DeliveryRepository deliveryRepository;
  final DeliveryRealtimeClient deliveryRealtimeClient;
  final ListsRepository listsRepository;
  final NotificationsRepository notificationsRepository;
  final SubscriptionsRepository subscriptionsRepository;
  final VerifyRepository verifyRepository;
  final ListRealtimeClient realtimeClient;
  final ListChatClient chatClient;
  final AuthState authState;
}