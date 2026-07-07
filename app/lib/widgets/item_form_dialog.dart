import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showItemFormDialog(
  BuildContext context, {
  String? initialName,
  num initialQuantity = 1,
  String initialUnit = 'ea',
  String initialNote = '',
  String title = 'Add item',
}) async {
  final nameController = TextEditingController(text: initialName ?? '');
  final qtyController =
      TextEditingController(text: initialQuantity.toString());
  final unitController = TextEditingController(text: initialUnit);
  final noteController = TextEditingController(text: initialNote);

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qty'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: unitController,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = nameController.text.trim();
            if (name.isEmpty) return;
            final qty = num.tryParse(qtyController.text.trim()) ?? 1;
            Navigator.pop(ctx, {
              'name': name,
              'quantity': qty,
              'unit': unitController.text.trim().isEmpty
                  ? 'ea'
                  : unitController.text.trim(),
              'note': noteController.text.trim(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}