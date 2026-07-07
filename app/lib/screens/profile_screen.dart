import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth_repository.dart';
import '../core/auth_state.dart';
import '../theme/shoppa_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.authRepository,
    required this.authState,
    required this.user,
  });

  final AuthRepository authRepository;
  final AuthState authState;
  final ShoppaUser user;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;
  String? _message;

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