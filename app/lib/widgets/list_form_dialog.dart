import 'package:flutter/material.dart';

const listCategories = <Map<String, String>>[
  {'id': 'groceries', 'label': 'Groceries'},
  {'id': 'clothing', 'label': 'Clothing'},
  {'id': 'wishlist', 'label': 'Wishlist'},
  {'id': 'event', 'label': 'Event'},
  {'id': 'ingredients', 'label': 'Ingredients'},
  {'id': 'custom', 'label': 'Custom'},
];

Future<Map<String, dynamic>?> showListFormDialog(
  BuildContext context, {
  String? initialTitle,
  String initialCategory = 'custom',
  bool initialRecurring = false,
  String title = 'New list',
}) async {
  final titleController = TextEditingController(text: initialTitle ?? '');
  var category = initialCategory;
  var recurring = initialRecurring;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: listCategories
                    .map((e) => DropdownMenuItem(
                          value: e['id'],
                          child: Text(e['label']!),
                        ))
                    .toList(),
                onChanged: (v) => setLocal(() => category = v ?? category),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Recurring'),
                value: recurring,
                onChanged: (v) => setLocal(() => recurring = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = titleController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx, {
                'title': name,
                'category': category,
                'is_recurring': recurring,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}