import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth_repository.dart';
import '../core/lists_repository.dart';
import '../core/notifications_repository.dart';
import '../theme/shoppa_theme.dart';

/// Mall tab — greeting, savings hero, quick list preview (Phase 1 M1).
class MallTabScreen extends StatefulWidget {
  const MallTabScreen({
    super.key,
    required this.authRepository,
    required this.listsRepository,
    required this.notificationsRepository,
    required this.user,
  });

  final AuthRepository authRepository;
  final ListsRepository listsRepository;
  final NotificationsRepository notificationsRepository;
  final ShoppaUser user;

  @override
  State<MallTabScreen> createState() => _MallTabScreenState();
}

class _MallTabScreenState extends State<MallTabScreen> {
  late Future<_MallData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_MallData> _load() async {
    final lists = await widget.listsRepository.fetchLists();
    ShoppaComparison? comparison;
    var promotionCount = 0;
    var unreadNotifications = 0;
    if (lists.isNotEmpty) {
      try {
        comparison = await widget.listsRepository.fetchComparison(lists.first.id);
      } catch (_) {}
    }
    try {
      promotionCount = (await widget.listsRepository.fetchPromotions()).length;
    } catch (_) {}
    try {
      unreadNotifications = await widget.notificationsRepository.unreadCount();
    } catch (_) {}
    return _MallData(
      lists: lists,
      comparison: comparison,
      promotionCount: promotionCount,
      unreadNotifications: unreadNotifications,
    );
  }

  Future<void> _refresh() async {
    setState(() => _data = _load());
  }

  String get _greetingName => widget.user.email.split('@').first;

  static const _categoryIcons = {
    'groceries': '🛒',
    'clothing': '👕',
    'wishlist': '🎁',
    'event': '🔥',
    'ingredients': '🍲',
    'custom': '📋',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<_MallData>(
            future: _data,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const ListView(
                  children: [
                    SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                  ],
                );
              }
              final data = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Sawubona, $_greetingName 👋',
                    style: const TextStyle(color: ShoppaColors.mist, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your Mall',
                    style: TextStyle(
                      color: ShoppaColors.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SavingsHero(comparison: data.comparison),
                  if (data.unreadNotifications > 0) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      tileColor: ShoppaColors.panel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: ShoppaColors.amber.withOpacity(0.35)),
                      ),
                      leading: const Icon(Icons.notifications_active, color: ShoppaColors.amber),
                      title: Text(
                        '${data.unreadNotifications} price alert${data.unreadNotifications == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: ShoppaColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: ShoppaColors.mist),
                      onTap: () => context.push('/notifications'),
                    ),
                  ],
                  if (data.promotionCount > 0) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      tileColor: ShoppaColors.panel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: ShoppaColors.amber.withOpacity(0.35)),
                      ),
                      leading: const Icon(Icons.local_offer, color: ShoppaColors.amber),
                      title: Text(
                        '${data.promotionCount} promotion${data.promotionCount == 1 ? '' : 's'} for your lists',
                        style: const TextStyle(
                          color: ShoppaColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: ShoppaColors.mist),
                      onTap: () => context.push('/promotions'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Recent Lists',
                    style: TextStyle(
                      color: ShoppaColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (data.lists.isEmpty)
                    const Text(
                      'No lists yet — tap Lists to create one.',
                      style: TextStyle(color: ShoppaColors.mist),
                    )
                  else
                    ...data.lists.take(3).map((list) {
                      final icon = _categoryIcons[list.category] ?? '📋';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          tileColor: ShoppaColors.panel,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: ShoppaColors.line),
                          ),
                          leading: Text(icon, style: const TextStyle(fontSize: 22)),
                          title: Text(list.title,
                              style: const TextStyle(color: ShoppaColors.ink)),
                          subtitle: Text(
                            '${list.itemCount} items',
                            style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                          ),
                          onTap: () => context.push(
                            '/lists/${list.id}?title=${Uri.encodeComponent(list.title)}',
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MallData {
  _MallData({
    required this.lists,
    this.comparison,
    this.promotionCount = 0,
    this.unreadNotifications = 0,
  });
  final List<ShoppaList> lists;
  final ShoppaComparison? comparison;
  final int promotionCount;
  final int unreadNotifications;
}

class _SavingsHero extends StatelessWidget {
  const _SavingsHero({this.comparison});

  final ShoppaComparison? comparison;

  String _formatZar(int cents) =>
      'R${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final saves = comparison?.bestSaves;
    final hasSavings = saves != null && saves > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ShoppaColors.amber.withOpacity(0.25),
            ShoppaColors.panel2,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShoppaColors.amber.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart Savings',
            style: TextStyle(
              color: ShoppaColors.amber,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasSavings
                ? 'You could save up to ${_formatZar(saves!)} on your latest list'
                : 'Compare prices across stores once your lists have catalogue items',
            style: const TextStyle(color: ShoppaColors.ink, fontSize: 15),
          ),
          if (hasSavings) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.go('/compare'),
              child: const Text('See full comparison'),
            ),
          ],
        ],
      ),
    );
  }
}