import 'package:flutter/material.dart';

import '../core/aisle_sort.dart';
import '../theme/shoppa_theme.dart';

/// Pick a free-text store for aisle walk order (no receipt or catalogue id).
///
/// Returns the chosen name, `''` to clear, or `null` if dismissed.
Future<String?> showShoppingAtStoreSheet(
  BuildContext context, {
  String? currentStoreName,
  List<String> suggestedStores = const [],
  String subtitle =
      'Sets aisle walk order from the store name. No receipt needed.',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ShoppingAtStoreSheet(
      currentStoreName: currentStoreName,
      suggestedStores: tripStoreSuggestions(frequent: suggestedStores),
      subtitle: subtitle,
    ),
  );
}

class _ShoppingAtStoreSheet extends StatefulWidget {
  const _ShoppingAtStoreSheet({
    required this.currentStoreName,
    required this.suggestedStores,
    required this.subtitle,
  });

  final String? currentStoreName;
  final List<String> suggestedStores;
  final String subtitle;

  @override
  State<_ShoppingAtStoreSheet> createState() => _ShoppingAtStoreSheetState();
}

class _ShoppingAtStoreSheetState extends State<_ShoppingAtStoreSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentStoreName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final current = widget.currentStoreName;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ShoppaColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Shopping at',
            style: TextStyle(
              color: ShoppaColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Store name',
              filled: true,
              fillColor: ShoppaColors.panel2.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: ShoppaColors.line),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('Use this store'),
          ),
          if (current != null && current.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Clear store'),
            ),
          ],
          if (widget.suggestedStores.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Suggestions',
              style: TextStyle(
                color: ShoppaColors.mist,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in widget.suggestedStores)
                  ActionChip(
                    label: Text(name),
                    onPressed: () => Navigator.pop(context, name),
                    backgroundColor: ShoppaColors.panel2.withOpacity(0.6),
                    side: BorderSide(
                      color: (current ?? '').toLowerCase() == name.toLowerCase()
                          ? ShoppaColors.green
                          : ShoppaColors.line,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
