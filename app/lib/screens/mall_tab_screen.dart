import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/ads_repository.dart';
import '../core/auth_repository.dart';
import '../core/list_shop_helpers.dart';
import '../core/lists_repository.dart';
import '../core/multi_list_trip.dart';
import '../core/notifications_repository.dart';
import '../core/receipt_capture.dart';
import '../core/receipt_history_store.dart';
import '../theme/shoppa_theme.dart';
import '../widgets/ad_banner.dart';
import '../widgets/pick_trip_lists_sheet.dart';
import '../widgets/receipt_history_sheet.dart';

/// Mall tab — greeting, savings hero, quick list preview (Phase 1 M1).
class MallTabScreen extends StatefulWidget {
  const MallTabScreen({
    super.key,
    required this.authRepository,
    required this.adsRepository,
    required this.listsRepository,
    required this.notificationsRepository,
    required this.user,
  });

  final AuthRepository authRepository;
  final AdsRepository adsRepository;
  final ListsRepository listsRepository;
  final NotificationsRepository notificationsRepository;
  final ShoppaUser user;

  @override
  State<MallTabScreen> createState() => _MallTabScreenState();
}

class _MallTabScreenState extends State<MallTabScreen> {
  late Future<_MallData> _data;
  final ReceiptHistoryStore _receiptHistory =
      SharedPreferencesReceiptHistoryStore();

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_MallData> _load() async {
    final lists = await widget.listsRepository.fetchLists();
    LoggedReceipt? lastReceipt;
    ReceiptSpendInsights? receiptInsights;
    try {
      final recent = await _receiptHistory.recent(limit: 30);
      if (recent.isNotEmpty) {
        lastReceipt = recent.first;
        receiptInsights = ReceiptSpendInsights.from(recent);
      }
    } catch (_) {}
    AdPlacement? homeBanner;
    try {
      final ads = await widget.adsRepository.fetchPlacements(
        surface: 'home',
        adFormat: 'banner',
      );
      if (ads.placements.isNotEmpty) homeBanner = ads.placements.first;
    } catch (_) {}
    ShoppaComparison? comparison;
    String? savingsListTitle;
    var promotionCount = 0;
    var unreadNotifications = 0;
    // Pick the list with the largest potential savings (not just the first).
    if (lists.isNotEmpty) {
      final sample = lists.take(5).toList();
      final results = await Future.wait(
        sample.map((list) async {
          try {
            final c = await widget.listsRepository.fetchComparison(list.id);
            return (list: list, comparison: c);
          } catch (_) {
            return null;
          }
        }),
      );
      var bestSaves = -1;
      for (final row in results) {
        if (row == null) continue;
        final saves = row.comparison.bestSaves ?? 0;
        if (saves > bestSaves) {
          bestSaves = saves;
          comparison = row.comparison;
          savingsListTitle = row.list.title;
        }
      }
      // Fall back to first list comparison shape if nothing priced yet.
      if (comparison == null) {
        for (final row in results) {
          if (row != null) {
            comparison = row.comparison;
            savingsListTitle = row.list.title;
            break;
          }
        }
      }
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
      savingsListTitle: savingsListTitle,
      promotionCount: promotionCount,
      unreadNotifications: unreadNotifications,
      homeBanner: homeBanner,
      lastReceipt: lastReceipt,
      receiptInsights: receiptInsights,
    );
  }

  Future<void> _refresh() async {
    setState(() => _data = _load());
  }

  Future<void> _startTodaysTrip(List<ShoppaList> all) async {
    final incomplete = all.where(listEligibleForTrip).toList();
    if (incomplete.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No lists with items left to shop'),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
      return;
    }
    if (incomplete.length == 1) {
      final list = incomplete.first;
      context.push(
        listDetailPath(list.id, title: list.title, shop: true),
      );
      return;
    }
    final selected = await showPickTripListsSheet(context, lists: incomplete);
    if (selected == null || selected.isEmpty || !mounted) return;
    if (selected.length == 1) {
      final list = incomplete.firstWhere((l) => l.id == selected.first);
      context.push(
        listDetailPath(list.id, title: list.title, shop: true),
      );
      return;
    }
    context.push(multiListTripPath(selected));
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
                return ListView(
                  children: const [
                    SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                  ],
                );
              }
              final data = snapshot.data!;
              final incomplete =
                  data.lists.where(listEligibleForTrip).toList();
              final remainingItems = incomplete.fold<int>(
                0,
                (n, list) => n + remainingItemCount(list),
              );
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
                  _SavingsHero(
                    comparison: data.comparison,
                    listTitle: data.savingsListTitle,
                  ),
                  if (incomplete.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: ShoppaColors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _startTodaysTrip(data.lists),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: ShoppaColors.amber.withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: ShoppaColors.amber.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.shopping_bag_outlined,
                                  color: ShoppaColors.amber,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Today’s trip',
                                      style: TextStyle(
                                        color: ShoppaColors.ink,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      incomplete.length == 1
                                          ? '$remainingItems left on ${incomplete.first.title}'
                                          : '$remainingItems items · ${incomplete.length} lists ready',
                                      style: const TextStyle(
                                        color: ShoppaColors.mist,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: ShoppaColors.amber,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (data.lastReceipt != null) ...[
                    const SizedBox(height: 12),
                    _LastReceiptCard(
                      receipt: data.lastReceipt!,
                      insights: data.receiptInsights,
                      onTap: () async {
                        await showReceiptHistorySheet(
                          context,
                          store: _receiptHistory,
                          title: 'Receipt history',
                        );
                        if (mounted) await _refresh();
                      },
                    ),
                  ],
                  if (data.homeBanner != null) ...[
                    const SizedBox(height: 12),
                    AdBanner(
                      placement: data.homeBanner!,
                      adsRepository: widget.adsRepository,
                    ),
                  ],
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
                  if (widget.user.accountType == 'personal') ...[
                    const SizedBox(height: 16),
                    ListTile(
                      tileColor: ShoppaColors.panel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: ShoppaColors.amber.withOpacity(0.3)),
                      ),
                      leading: const Icon(Icons.restaurant_menu, color: ShoppaColors.amber),
                      title: const Text(
                        'Cooking for a crowd?',
                        style: TextStyle(
                          color: ShoppaColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        'Scale any list by guests with Shoppa Pro',
                        style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: ShoppaColors.mist),
                      onTap: () => context.push('/subscriptions'),
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
                            listIsIncompleteTrip(list)
                                ? '${remainingItemCount(list)} left · ${list.itemCount} items'
                                : (list.itemCount == 0
                                    ? 'Empty'
                                    : '${list.itemCount} items · all done'),
                            style: const TextStyle(
                              color: ShoppaColors.mist,
                              fontSize: 12,
                            ),
                          ),
                          trailing: list.itemCount > 0
                              ? IconButton(
                                  tooltip: listIsIncompleteTrip(list)
                                      ? 'Start shopping'
                                      : 'Shop again',
                                  icon: Icon(
                                    listIsIncompleteTrip(list)
                                        ? Icons.shopping_cart_outlined
                                        : Icons.replay_outlined,
                                    color: listIsIncompleteTrip(list)
                                        ? ShoppaColors.amber
                                        : ShoppaColors.mist,
                                  ),
                                  onPressed: () => context.push(
                                    listDetailPath(
                                      list.id,
                                      title: list.title,
                                      shop: true,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () => context.push(
                            listDetailPath(list.id, title: list.title),
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
    this.savingsListTitle,
    this.promotionCount = 0,
    this.unreadNotifications = 0,
    this.homeBanner,
    this.lastReceipt,
    this.receiptInsights,
  });
  final List<ShoppaList> lists;
  final ShoppaComparison? comparison;
  final String? savingsListTitle;
  final int promotionCount;
  final int unreadNotifications;
  final AdPlacement? homeBanner;
  final LoggedReceipt? lastReceipt;
  final ReceiptSpendInsights? receiptInsights;
}

class _LastReceiptCard extends StatelessWidget {
  const _LastReceiptCard({
    required this.receipt,
    required this.onTap,
    this.insights,
  });

  final LoggedReceipt receipt;
  final ReceiptSpendInsights? insights;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = receipt.tillVsBasket;
    final when = formatRelativeTime(receipt.createdAt);
    final store = receipt.storeName.isNotEmpty
        ? receipt.storeName
        : (receipt.listTitles.isNotEmpty
            ? receipt.listTitles.join(' · ')
            : 'Last till total');
    final multi = insights != null && insights!.receiptCount > 1;
    final subtitle = multi
        ? [
            insights!.compactLine,
            if (when.isNotEmpty) 'last $when',
          ].join(' · ')
        : [
            if (vs != null && vs.hasComparison) vs.variancePhrase,
            if (when.isNotEmpty) when,
          ].join(' · ');
    final accent = multi
        ? (insights!.withBasketCount > 0 && insights!.netDeltaCents > 0
            ? ShoppaColors.amber
            : (insights!.withBasketCount > 0 && insights!.netDeltaCents == 0
                ? ShoppaColors.green
                : ShoppaColors.mist))
        : (vs == null || !vs.hasComparison
            ? ShoppaColors.mist
            : (vs.matches
                ? ShoppaColors.green
                : (vs.over ? ShoppaColors.amber : ShoppaColors.mist)));

    final headline = multi
        ? 'Receipts · ${insights!.formattedTotal} total'
        : 'Last receipt · ${receipt.formattedTotal}';

    return Material(
      color: ShoppaColors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ShoppaColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.receipt_long_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        color: ShoppaColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isNotEmpty ? '$store · $subtitle' : store,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: ShoppaColors.mist,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingsHero extends StatelessWidget {
  const _SavingsHero({this.comparison, this.listTitle});

  final ShoppaComparison? comparison;
  final String? listTitle;

  String _formatZar(int cents) =>
      'R${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final saves = comparison?.bestSaves;
    final hasSavings = saves != null && saves > 0;
    final String headline;
    if (saves != null && saves > 0) {
      headline = 'You could save up to ${_formatZar(saves)}'
          '${listTitle != null ? ' on $listTitle' : ''}';
    } else {
      headline =
          'Compare prices across stores once your lists have catalogue items';
    }
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
            headline,
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