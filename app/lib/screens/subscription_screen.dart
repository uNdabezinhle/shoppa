import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/subscriptions_repository.dart';
import '../theme/shoppa_theme.dart';

/// SRS FR-9.1 / FR-9.2 — browse plans and start Stripe checkout.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.subscriptionsRepository});

  final SubscriptionsRepository subscriptionsRepository;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<_PlansPayload> _data;
  String? _error;
  String? _busyPlan;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _data = _load();
      _error = null;
    });
  }

  Future<_PlansPayload> _load() async {
    final plans = await widget.subscriptionsRepository.fetchPlans();
    final subscription = await widget.subscriptionsRepository.fetchMySubscription();
    return _PlansPayload(plans: plans, subscription: subscription);
  }

  String _formatPrice(ShoppaPlan plan) {
    if (plan.isFree) return 'Free';
    return 'R${(plan.priceMonthly / 100).toStringAsFixed(2)}/mo';
  }

  Future<void> _subscribe(ShoppaPlan plan) async {
    if (plan.isFree) return;
    setState(() => _busyPlan = plan.slug);
    try {
      final session = await widget.subscriptionsRepository.startCheckout(plan.slug);
      await Clipboard.setData(ClipboardData(text: session.checkoutUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            session.devMode
                ? 'Dev checkout link copied — complete via webhook smoke or Stripe test mode'
                : 'Checkout link copied — open in browser to pay',
          ),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plans & Billing')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<_PlansPayload>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load plans: ${snapshot.error}',
                  style: const TextStyle(color: ShoppaColors.rose),
                ),
              );
            }
            final payload = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ShoppaColors.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ShoppaColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current plan',
                        style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        payload.subscription.plan.name,
                        style: const TextStyle(
                          color: ShoppaColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (payload.subscription.plan.maxOwnedLists != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Up to ${payload.subscription.plan.maxOwnedLists} owned lists',
                          style: const TextStyle(color: ShoppaColors.mist, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Upgrade',
                  style: TextStyle(
                    color: ShoppaColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...payload.plans.map(
                  (plan) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PlanCard(
                      plan: plan,
                      isCurrent: plan.slug == payload.subscription.plan.slug,
                      priceLabel: _formatPrice(plan),
                      busy: _busyPlan == plan.slug,
                      onSubscribe: () => _subscribe(plan),
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

class _PlansPayload {
  const _PlansPayload({required this.plans, required this.subscription});

  final List<ShoppaPlan> plans;
  final ShoppaSubscription subscription;
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.priceLabel,
    required this.busy,
    required this.onSubscribe,
  });

  final ShoppaPlan plan;
  final bool isCurrent;
  final String priceLabel;
  final bool busy;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShoppaColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? ShoppaColors.amber.withOpacity(0.4)
              : ShoppaColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                plan.name,
                style: const TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                priceLabel,
                style: const TextStyle(
                  color: ShoppaColors.amber,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (plan.features.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: plan.features.map((feature) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ShoppaColors.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    feature.replaceAll('_', ' '),
                    style: const TextStyle(color: ShoppaColors.mist, fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ],
          if (!plan.isFree && !isCurrent) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: busy ? null : onSubscribe,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Subscribe'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}