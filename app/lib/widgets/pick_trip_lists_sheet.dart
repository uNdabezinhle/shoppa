import 'package:flutter/material.dart';

import '../core/list_category_style.dart';
import '../core/lists_repository.dart';
import '../core/multi_list_trip.dart';
import '../theme/shoppa_theme.dart';

/// Multi-select incomplete lists to shop in one combined trip.
///
/// [initialSelectedIds] pre-checks matching eligible lists (e.g. last trip).
/// When null or empty after filtering, all eligible lists start selected.
Future<List<String>?> showPickTripListsSheet(
  BuildContext context, {
  required List<ShoppaList> lists,
  Iterable<String>? initialSelectedIds,
}) {
  final eligible = lists.where(listEligibleForTrip).toList();
  if (eligible.isEmpty) {
    return Future.value(null);
  }
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _PickTripListsSheet(
      lists: eligible,
      initialSelectedIds: initialSelectedIds,
    ),
  );
}

class _PickTripListsSheet extends StatefulWidget {
  const _PickTripListsSheet({
    required this.lists,
    this.initialSelectedIds,
  });

  final List<ShoppaList> lists;
  final Iterable<String>? initialSelectedIds;

  @override
  State<_PickTripListsSheet> createState() => _PickTripListsSheetState();
}

class _PickTripListsSheetState extends State<_PickTripListsSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    final eligibleIds = widget.lists.map((l) => l.id).toSet();
    final remembered = <String>{};
    for (final raw in widget.initialSelectedIds ?? const <String>[]) {
      final id = raw.trim();
      if (eligibleIds.contains(id)) remembered.add(id);
    }
    _selected = remembered.isNotEmpty
        ? remembered
        : Set<String>.from(eligibleIds);
  }

  int get _remainingTotal {
    var n = 0;
    for (final list in widget.lists) {
      if (_selected.contains(list.id)) {
        n += remainingItemCount(list);
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final usingRemembered = widget.initialSelectedIds != null &&
        widget.initialSelectedIds!.any(
          (id) => widget.lists.any((l) => l.id == id.trim()),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
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
              const Text(
                'Today’s trip',
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                usingRemembered
                    ? 'Last trip’s lists pre-selected — adjust if needed'
                    : 'Combine remaining items from several lists into one shop',
                style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(
                      () => _selected
                        ..clear()
                        ..addAll(widget.lists.map((l) => l.id)),
                    ),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              ...widget.lists.map((list) {
                final cat = listCategoryStyle(list.category);
                final left = remainingItemCount(list);
                final selected = _selected.contains(list.id);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: selected,
                  activeColor: ShoppaColors.amber,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(list.id);
                      } else {
                        _selected.remove(list.id);
                      }
                    });
                  },
                  secondary: Icon(cat.icon, color: cat.color, size: 22),
                  title: Text(
                    list.title,
                    style: const TextStyle(color: ShoppaColors.ink),
                  ),
                  subtitle: Text(
                    '$left left · ${cat.label}',
                    style: const TextStyle(
                      color: ShoppaColors.mist,
                      fontSize: 12,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected.toList()),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: Text(
                  _selected.isEmpty
                      ? 'Select at least one list'
                      : 'Start trip · $_remainingTotal items',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
