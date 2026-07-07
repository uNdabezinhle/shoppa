import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth_repository.dart';
import '../core/auth_state.dart';
import '../core/list_realtime_client.dart';
import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';

/// "Mall" home screen: greets the user (proving GET /v1/users/me works)
/// and shows their shopping lists (proving GET /v1/lists works). Matches
/// the prototype's HomeScreen, minus the savings hero card and quick
/// stats, which land once price_intelligence (Phase 3) has real data.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.authRepository,
    required this.listsRepository,
    required this.realtimeClient,
    required this.authState,
    required this.user,
  });

  final AuthRepository authRepository;
  final ListsRepository listsRepository;
  final ListRealtimeClient realtimeClient;
  final AuthState authState;
  final ShoppaUser user;

  String get _greetingName => user.email.split('@').first;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<ShoppaList>> _lists;

  @override
  void initState() {
    super.initState();
    _lists = widget.listsRepository.fetchLists();
  }

  Future<void> _refresh() async {
    setState(() {
      _lists = widget.listsRepository.fetchLists();
    });
  }

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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            tooltip: 'Promotions',
            icon: const Icon(Icons.local_offer_outlined),
            onPressed: () => context.push('/promotions'),
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => widget.authState.logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Sawubona, ${widget._greetingName} 👋',
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
              const SizedBox(height: 20),
              const Text(
                'My Lists',
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<ShoppaList>>(
                future: _lists,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'Could not load lists: ${snapshot.error}',
                      style: const TextStyle(color: ShoppaColors.rose),
                    );
                  }
                  final lists = snapshot.data!;
                  if (lists.isEmpty) {
                    return const Text(
                      'No lists yet — create one to get started.',
                      style: TextStyle(color: ShoppaColors.mist),
                    );
                  }
                  return Column(
                    children: lists
                        .map((list) => Padding(
                              padding: const EdgeInsets.only(bottom: 11),
                              child: _ListCard(
                                list: list,
                                onTap: () => context.push(
                                  '/lists/${list.id}?title=${Uri.encodeComponent(list.title)}',
                                ),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.list, required this.onTap});

  final ShoppaList list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = _HomeScreenState._categoryIcons[list.category] ?? '📋';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: ShoppaColors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ShoppaColors.line),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        list.title,
                        style: const TextStyle(
                          color: ShoppaColors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (list.isRecurring) ...[
                        const SizedBox(width: 8),
                        const _Pill(text: 'MONTHLY', color: ShoppaColors.green),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${list.itemCount} item${list.itemCount == 1 ? '' : 's'}',
                    style: const TextStyle(color: ShoppaColors.mist, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
