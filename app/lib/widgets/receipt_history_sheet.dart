import 'package:flutter/material.dart';

import '../core/list_shop_helpers.dart';
import '../core/receipt_history_store.dart';
import '../theme/shoppa_theme.dart';

/// Shows device-local logged receipts for a list, multi-list trip, or all.
///
/// When [scopeId] is null, shows recent receipts across every list/trip.
Future<void> showReceiptHistorySheet(
  BuildContext context, {
  required ReceiptHistoryStore store,
  String? scopeId,
  String title = 'Receipt history',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ReceiptHistorySheet(
      store: store,
      scopeId: scopeId,
      title: title,
    ),
  );
}

class _ReceiptHistorySheet extends StatefulWidget {
  const _ReceiptHistorySheet({
    required this.store,
    required this.scopeId,
    required this.title,
  });

  final ReceiptHistoryStore store;
  final String? scopeId;
  final String title;

  @override
  State<_ReceiptHistorySheet> createState() => _ReceiptHistorySheetState();
}

class _ReceiptHistorySheetState extends State<_ReceiptHistorySheet> {
  late Future<List<LoggedReceipt>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<LoggedReceipt>> _load() {
    final scope = widget.scopeId;
    if (scope == null || scope.isEmpty) {
      return widget.store.recent(limit: 50);
    }
    return widget.store.forScope(scope);
  }

  Future<void> _clear() async {
    final scope = widget.scopeId;
    if (scope == null || scope.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear receipt history?'),
        content: const Text(
          'This only clears logs saved on this device for this list/trip. '
          'Item prices are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ShoppaColors.rose),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.clearScope(scope);
    if (!mounted) return;
    _reloadFuture();
  }

  void _reloadFuture() {
    final future = _load();
    setState(() {
      _future = future;
    });
  }

  Future<void> _removeReceipt(LoggedReceipt receipt) async {
    await widget.store.removeById(receipt.id);
    if (!mounted) return;
    _reloadFuture();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${receipt.formattedTotal}'),
        backgroundColor: ShoppaColors.panel2,
        action: SnackBarAction(
          label: 'Undo',
          textColor: ShoppaColors.amber,
          onPressed: () async {
            await widget.store.add(receipt);
            if (!mounted) return;
            _reloadFuture();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canClear = widget.scopeId != null && widget.scopeId!.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ShoppaColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: ShoppaColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (canClear)
                  TextButton(
                    onPressed: _clear,
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              canClear
                  ? 'Saved on this device after you log a till total'
                  : 'All till totals saved on this device',
              style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<LoggedReceipt>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final rows = snapshot.data ?? const <LoggedReceipt>[];
                  if (rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'No receipts logged yet.\nUse Log receipt after a shop.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    );
                  }
                  final insights = ReceiptSpendInsights.from(rows);
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      _InsightsBanner(insights: insights),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      ...List.generate(rows.length, (index) {
                        final r = rows[index];
                        final when = formatRelativeTime(r.createdAt);
                        final store = r.storeName.isNotEmpty
                            ? r.storeName
                            : 'Store not set';
                        final filled = r.pricesFilled > 0
                            ? 'filled ${r.pricesFilled} prices'
                            : '';
                        final titles = r.listTitles.isNotEmpty
                            ? r.listTitles.join(' · ')
                            : null;
                        final vs = r.tillVsBasket;
                        final delta = vs != null && vs.hasComparison
                            ? vs.variancePhrase
                            : '';
                        final titleLine = delta.isNotEmpty
                            ? '${r.formattedTotal} · $delta'
                            : r.formattedTotal;
                        final titleColor = vs == null || !vs.hasComparison
                            ? ShoppaColors.ink
                            : (vs.matches
                                ? ShoppaColors.green
                                : (vs.over
                                    ? ShoppaColors.amber
                                    : ShoppaColors.ink));
                        return Column(
                          children: [
                            if (index > 0) const Divider(height: 1),
                            Dismissible(
                              key: ValueKey(r.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                color: ShoppaColors.rose.withOpacity(0.2),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: ShoppaColors.rose,
                                ),
                              ),
                              onDismissed: (_) => _removeReceipt(r),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.receipt_long_outlined,
                                  color: ShoppaColors.amber,
                                ),
                                title: Text(
                                  titleLine,
                                  style: TextStyle(
                                    color: titleColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    store,
                                    if (when.isNotEmpty) when,
                                    r.source.name,
                                    if (filled.isNotEmpty) filled,
                                    if (titles != null) titles,
                                    if (r.notes.isNotEmpty) r.notes,
                                  ].join(' · '),
                                  style: const TextStyle(
                                    color: ShoppaColors.mist,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: ShoppaColors.mist,
                                  ),
                                  onPressed: () => _removeReceipt(r),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsBanner extends StatelessWidget {
  const _InsightsBanner({required this.insights});

  final ReceiptSpendInsights insights;

  @override
  Widget build(BuildContext context) {
    final variance = insights.varianceLine;
    final varianceColor = insights.withBasketCount == 0
        ? ShoppaColors.mist
        : (insights.netDeltaCents == 0
            ? ShoppaColors.green
            : (insights.netDeltaCents > 0
                ? ShoppaColors.amber
                : ShoppaColors.mist));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShoppaColors.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ShoppaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spend insights',
            style: TextStyle(
              color: ShoppaColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            insights.summaryLine,
            style: const TextStyle(
              color: ShoppaColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (variance != null) ...[
            const SizedBox(height: 4),
            Text(
              variance,
              style: TextStyle(
                color: varianceColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
