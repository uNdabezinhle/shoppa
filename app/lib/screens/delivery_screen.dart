import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/delivery_repository.dart';
import '../theme/shoppa_theme.dart';

/// SRS FR-6.2 / prototype DeliveryScreen — ETA, fee, stock, affiliate order.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({
    super.key,
    required this.deliveryRepository,
    required this.listId,
    required this.listTitle,
    this.regionLabel = 'South Africa',
  });

  final DeliveryRepository deliveryRepository;
  final String listId;
  final String listTitle;
  final String regionLabel;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  late Future<ShoppaDeliveryQuotes> _quotes;

  @override
  void initState() {
    super.initState();
    _quotes = widget.deliveryRepository.fetchDeliveryQuotes(widget.listId);
  }

  void _reload() {
    setState(() {
      _quotes = widget.deliveryRepository.fetchDeliveryQuotes(widget.listId);
    });
  }

  String _formatZar(int cents) => 'R${(cents / 100).toStringAsFixed(2)}';

  void _showOrderHandoff(ShoppaDeliveryQuote quote) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ShoppaColors.panel,
        title: Text('Order via ${quote.displayName}',
            style: const TextStyle(color: ShoppaColors.ink)),
        content: Text(
          'Affiliate link copied. Complete your order in the retailer app or browser.\n\n${quote.orderUrl}',
          style: const TextStyle(color: ShoppaColors.mist, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    Clipboard.setData(ClipboardData(text: quote.orderUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Order link copied for ${quote.displayName}'),
        backgroundColor: ShoppaColors.panel2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Same-Day Delivery'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<ShoppaDeliveryQuotes>(
          future: _quotes,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load delivery quotes: ${snapshot.error}',
                  style: const TextStyle(color: ShoppaColors.rose),
                ),
              );
            }
            final payload = snapshot.data!;
            if (payload.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Add catalogue-linked items to compare delivery options.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ShoppaColors.mist),
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.listTitle,
                  style: const TextStyle(
                    color: ShoppaColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: ShoppaColors.mist),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.regionLabel} · ${payload.quotes.length} platforms',
                      style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...payload.quotes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final quote = entry.value;
                  final isCheapest = index == 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DeliveryQuoteCard(
                      quote: quote,
                      isCheapest: isCheapest,
                      formatZar: _formatZar,
                      onOrder: () => _showOrderHandoff(quote),
                    ),
                  );
                }),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Prices include affiliate links · Shoppa earns a small commission at no cost to you',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ShoppaColors.faint, fontSize: 11),
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

class _DeliveryQuoteCard extends StatelessWidget {
  const _DeliveryQuoteCard({
    required this.quote,
    required this.isCheapest,
    required this.formatZar,
    required this.onOrder,
  });

  final ShoppaDeliveryQuote quote;
  final bool isCheapest;
  final String Function(int cents) formatZar;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final stockColor =
        quote.isFullyAvailable ? ShoppaColors.ink : ShoppaColors.rose;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ShoppaColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCheapest
              ? ShoppaColors.amber.withOpacity(0.35)
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
                quote.displayName,
                style: const TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (isCheapest)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ShoppaColors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Cheapest',
                    style: TextStyle(
                      color: ShoppaColors.amber,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetaChip(
                icon: Icons.schedule,
                label: '${quote.etaMinutes} min',
              ),
              const SizedBox(width: 16),
              _MetaChip(
                icon: Icons.inventory_2_outlined,
                label: '${quote.availableItems}/${quote.totalItems} in stock',
                color: stockColor,
              ),
              const SizedBox(width: 16),
              _MetaChip(
                icon: Icons.local_shipping_outlined,
                label: quote.deliveryFee == 0
                    ? 'Free delivery'
                    : '${formatZar(quote.deliveryFee)} fee',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatZar(quote.total),
                style: TextStyle(
                  color: isCheapest ? ShoppaColors.amber : ShoppaColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              FilledButton(
                onPressed: onOrder,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Order'),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.color = ShoppaColors.ink,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: ShoppaColors.mist),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}