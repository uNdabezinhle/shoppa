import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth_repository.dart';
import '../core/auth_state.dart';
import '../core/notifications_repository.dart';
import '../theme/shoppa_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.authRepository,
    required this.authState,
    required this.notificationsRepository,
    required this.user,
  });

  final AuthRepository authRepository;
  final AuthState authState;
  final NotificationsRepository notificationsRepository;
  final ShoppaUser user;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;
  String? _message;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await widget.notificationsRepository.unreadCount();
      if (mounted) setState(() => _unreadNotifications = count);
    } catch (_) {}
  }

  Future<void> _upgrade() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final updated = await widget.authRepository.upgradeToProfessional();
      widget.authState.updateUser(updated);
      setState(() => _message = 'Upgraded to Professional.');
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authState.user ?? widget.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            tileColor: ShoppaColors.panel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(user.email, style: const TextStyle(color: ShoppaColors.ink)),
            subtitle: Text(
              '${user.accountType.toUpperCase()} · ${user.region}',
              style: const TextStyle(color: ShoppaColors.mist),
            ),
          ),
          const SizedBox(height: 16),
          if (user.accountType == 'personal')
            FilledButton(
              onPressed: _busy ? null : _upgrade,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Upgrade to Professional'),
            ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: ShoppaColors.panel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.workspace_premium_outlined, color: ShoppaColors.amber),
            title: const Text('Plans & Billing', style: TextStyle(color: ShoppaColors.ink)),
            subtitle: const Text(
              'Subscriptions and upgrades',
              style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: ShoppaColors.mist),
            onTap: () => context.push('/subscriptions'),
          ),
          if (user.accountType == 'admin') ...[
            const SizedBox(height: 12),
            ListTile(
              tileColor: ShoppaColors.panel,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const Icon(Icons.admin_panel_settings_outlined, color: ShoppaColors.amber),
              title: const Text('Admin Console', style: TextStyle(color: ShoppaColors.ink)),
              subtitle: const Text(
                'Overview and moderation queue',
                style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: ShoppaColors.mist),
              onTap: () => context.push('/admin'),
            ),
          ],
          const SizedBox(height: 12),
          ListTile(
            tileColor: ShoppaColors.panel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.notifications_outlined, color: ShoppaColors.amber),
            title: const Text('Notifications', style: TextStyle(color: ShoppaColors.ink)),
            subtitle: Text(
              _unreadNotifications > 0
                  ? '$_unreadNotifications unread price alert${_unreadNotifications == 1 ? '' : 's'}'
                  : 'Price drops on your list items',
              style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_unreadNotifications > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: ShoppaColors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_unreadNotifications',
                      style: const TextStyle(
                        color: ShoppaColors.amber,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const Icon(Icons.chevron_right, color: ShoppaColors.mist),
              ],
            ),
            onTap: () async {
              await context.push('/notifications');
              _loadUnreadCount();
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: ShoppaColors.panel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.local_offer_outlined, color: ShoppaColors.amber),
            title: const Text('Promotions', style: TextStyle(color: ShoppaColors.ink)),
            subtitle: const Text(
              'Deals matched to your lists',
              style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: ShoppaColors.mist),
            onTap: () => context.push('/promotions'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => widget.authState.logout(),
            child: const Text('Log out'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(color: ShoppaColors.mist)),
          ],
        ],
      ),
    );
  }
}