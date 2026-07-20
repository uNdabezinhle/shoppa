import 'package:flutter/material.dart';

import '../core/bulk_item_parse.dart';
import '../theme/shoppa_theme.dart';

/// Paste multi-line items or rough receipt text; returns parsed lines to add.
Future<List<ParsedListLine>?> showBulkAddSheet(
  BuildContext context, {
  String title = 'Paste items',
  String hint =
      'One item per line.\nExamples:\nMilk\n2x Bread\n1.5 kg Rice\nApples R 29.99',
}) {
  final controller = TextEditingController();
  return showModalBottomSheet<List<ParsedListLine>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: ShoppaColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Paste a shopping list or type lines from a receipt. '
              'Prices and totals are ignored.',
              style: TextStyle(color: ShoppaColors.mist, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 10,
              minLines: 6,
              autofocus: true,
              decoration: InputDecoration(
                hintText: hint,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final parsed = parseBulkItemLines(controller.text);
                if (parsed.isEmpty) return;
                Navigator.pop(ctx, parsed);
              },
              child: const Text('Add items'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    },
  );
}
