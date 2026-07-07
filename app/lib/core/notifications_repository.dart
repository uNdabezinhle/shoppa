/// In-app notification feed (TC-5.5 / FR-5.4).
import 'api_client.dart';

class ShoppaNotification {
  ShoppaNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.payload = const {},
  });

  factory ShoppaNotification.fromJson(Map<String, dynamic> json) =>
      ShoppaNotification(
        id: json['id'] as String,
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        isRead: json['is_read'] as bool? ?? false,
        createdAt: json['created_at'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );

  final String id;
  final String kind;
  final String title;
  final String body;
  final bool isRead;
  final String createdAt;
  final Map<String, dynamic> payload;
}

class NotificationsRepository {
  NotificationsRepository(this._client);

  final ApiClient _client;

  Future<List<ShoppaNotification>> fetchNotifications() async {
    final json = await _client.get('/notifications') as Map<String, dynamic>;
    final results = json['results'] as List;
    return results
        .map((e) => ShoppaNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ShoppaNotification> markRead(String notificationId) async {
    final json = await _client.patch('/notifications/$notificationId/read', {})
        as Map<String, dynamic>;
    return ShoppaNotification.fromJson(json);
  }

  Future<int> unreadCount() async {
    final notes = await fetchNotifications();
    return notes.where((n) => !n.isRead).length;
  }
}