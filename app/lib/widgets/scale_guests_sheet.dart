import 'package:flutter/material.dart';

import '../theme/shoppa_theme.dart';

/// FR-8.1 — scale a list by guest count or arbitrary factor (Professional).
/// Returns either `{'guests': n}` or `{'factor': n}`.
Future<Map<String, num>?> showScaleGuestsSheet(BuildContext context) {
  final controller = TextEditingController(text: '10');
  var mode = 'guests'; // guests | factor

  return showModalBottomSheet<Map<String, num>>(
    context: context,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => Padding(
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
              'Scale list',
              style: TextStyle(
                color: ShoppaColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mode == 'guests'
                  ? 'Multiply every item quantity by the number of guests.'
                  : 'Multiply every item quantity by a custom factor.',
              style: const TextStyle(color: ShoppaColors.mist, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'guests', label: Text('Guests')),
                ButtonSegment(value: 'factor', label: Text('Factor')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setLocal(() => mode = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: mode == 'guests' ? 'Guest count' : 'Factor',
                hintText: mode == 'guests' ? 'e.g. 25' : 'e.g. 1.5',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim();
                if (mode == 'guests') {
                  final guests = int.tryParse(raw);
                  if (guests == null || guests <= 0) return;
                  Navigator.pop(context, <String, num>{'guests': guests});
                } else {
                  final factor = num.tryParse(raw);
                  if (factor == null || factor <= 0) return;
                  Navigator.pop(context, <String, num>{'factor': factor});
                }
              },
              child: const Text('Scale list'),
            ),
          ],
        ),
      ),
    ),
  );
}
