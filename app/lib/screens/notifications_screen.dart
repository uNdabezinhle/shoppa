import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/notifications_repository.dart';
import '../theme/shoppa_theme.dart';

/// SRS FR-5.4 / TC-5.5: in-app price-drop feed (GET /notifications).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.notificationsRepository});

  final NotificationsRepository notificationsRepository;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<ShoppaNotification>> _notifications;
  String? _error;

  @override
  void initState() {
    super.initState();
    _notifications = widget.notificationsRepository.fetchNotifications();
  }

  void _reload() {
    setState(() {
      _notifications = widget.notificationsRepository.fetchNotifications();
      _error = null;
    });
  }

  Future<void> _markRead(ShoppaNotification note) async {
    if (note.isRead) return;
    try {
      await widget.notificationsRepository.markRead(note.id);
      _reload();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<ShoppaNotification>>(
          future: _notifications,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load notifications: ${snapshot.error}',
                  style: const TextStyle(color: ShoppaColors.rose),
                ),
              );
            }
            final notifications = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
                  const SizedBox(height: 12),
                ],
                if (notifications.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No notifications yet — price drops on your list items will show here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    ),
                  )
                else
                  ...notifications.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _NotificationCard(
                        notification: note,
                        onTap: () => _markRead(note),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  final ShoppaNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: unread
                ? ShoppaColors.panel2
                : ShoppaColors.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: unread
                  ? ShoppaColors.amber.withOpacity(0.4)
                  : ShoppaColors.line,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                notification.kind == 'price_drop'
                    ? Icons.trending_down
                    : Icons.notifications_outlined,
                color: unread ? ShoppaColors.amber : ShoppaColors.mist,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        color: ShoppaColors.ink,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        color: ShoppaColors.mist,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, left: 8),
                  decoration: const BoxDecoration(
                    color: ShoppaColors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}