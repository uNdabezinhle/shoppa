import 'package:flutter/material.dart';

import '../theme/shoppa_theme.dart';

/// FR-8.1 — scale a list by guest count (Professional).
Future<int?> showScaleGuestsSheet(BuildContext context) {
  final controller = TextEditingController(text: '10');
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Scale for guests',
            style: TextStyle(
              color: ShoppaColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Multiply every item quantity by the number of guests.',
            style: TextStyle(color: ShoppaColors.mist, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Guest count',
              hintText: 'e.g. 25',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final guests = int.tryParse(controller.text.trim());
              if (guests == null || guests <= 0) return;
              Navigator.pop(context, guests);
            },
            child: const Text('Scale list'),
          ),
        ],
      ),
    ),
  );
}