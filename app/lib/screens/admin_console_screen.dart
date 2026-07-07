import 'package:flutter/material.dart';

import '../core/admin_repository.dart';
import '../core/api_client.dart';
import '../theme/shoppa_theme.dart';

/// Phase 5 admin console — platform overview and moderation queue.
class AdminConsoleScreen extends StatefulWidget {
  const AdminConsoleScreen({super.key, required this.adminRepository});

  final AdminRepository adminRepository;

  @override
  State<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends State<AdminConsoleScreen> {
  late Future<(_AdminPayload)> _data;
  String? _error;
  String? _busyId;

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

  Future<(_AdminPayload)> _load() async {
    final overview = await widget.adminRepository.fetchOverview();
    final queue = await widget.adminRepository.fetchQuarantineQueue();
    return (overview: overview, queue: queue);
  }

  Future<void> _moderate(String id, String action) async {
    setState(() => _busyId = id);
    try {
      await widget.adminRepository.moderateObservation(id, action: action);
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Observation ${action}d'),
          backgroundColor: ShoppaColors.panel2,
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Console')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<(_AdminPayload)>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load admin data: ${snapshot.error}',
                  style: const TextStyle(color: ShoppaColors.rose),
                ),
              );
            }
            final payload = snapshot.data!;
            final overview = payload.overview;
            final queue = payload.queue;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Platform overview',
                  style: TextStyle(
                    color: ShoppaColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(label: 'Users', value: '${overview.users}'),
                    _StatCard(label: 'Lists', value: '${overview.lists}'),
                    _StatCard(
                      label: 'Quarantined',
                      value: '${overview.quarantinedObservations}',
                    ),
                    _StatCard(label: 'Stores', value: '${overview.stores}'),
                    _StatCard(
                      label: 'Active promos',
                      value: '${overview.activePromotions}',
                    ),
                  ],
                ),
                if (overview.subscriptionsByPlan.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Subscriptions: ${overview.subscriptionsByPlan.entries.map((e) => '${e.key} (${e.value})').join(', ')}',
                    style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text(
                      'Moderation queue',
                      style: TextStyle(
                        color: ShoppaColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (queue.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: ShoppaColors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${queue.length}',
                          style: const TextStyle(
                            color: ShoppaColors.amber,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (queue.isEmpty)
                  const Text(
                    'No quarantined price observations.',
                    style: TextStyle(color: ShoppaColors.mist),
                  )
                else
                  ...queue.map(
                    (item) => Card(
                      color: ShoppaColors.panel,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(
                          item.productName,
                          style: const TextStyle(color: ShoppaColors.ink),
                        ),
                        subtitle: Text(
                          '${item.storeName} · R${(item.price / 100).toStringAsFixed(2)} · ${item.source}',
                          style: const TextStyle(
                            color: ShoppaColors.mist,
                            fontSize: 12,
                          ),
                        ),
                        trailing: _busyId == item.id
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Approve',
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                      color: ShoppaColors.green,
                                    ),
                                    onPressed: () =>
                                        _moderate(item.id, 'approve'),
                                  ),
                                  IconButton(
                                    tooltip: 'Reject',
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      color: ShoppaColors.rose,
                                    ),
                                    onPressed: () =>
                                        _moderate(item.id, 'reject'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShoppaColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: ShoppaColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

typedef _AdminPayload = ({AdminOverview overview, List<QuarantineItem> queue});