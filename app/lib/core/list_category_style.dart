// Visual style for shopping-list categories (My Lists accents, chips).
import 'package:flutter/material.dart';

import '../theme/shoppa_theme.dart';
import '../widgets/list_form_dialog.dart';

/// Color + icon for a list [category] id (e.g. `groceries`).
class ListCategoryStyle {
  const ListCategoryStyle({
    required this.id,
    required this.label,
    required this.color,
    required this.icon,
  });

  final String id;
  final String label;
  final Color color;
  final IconData icon;
}

const _styles = <String, ListCategoryStyle>{
  'groceries': ListCategoryStyle(
    id: 'groceries',
    label: 'Groceries',
    color: ShoppaColors.green,
    icon: Icons.local_grocery_store_outlined,
  ),
  'clothing': ListCategoryStyle(
    id: 'clothing',
    label: 'Clothing',
    color: ShoppaColors.violet,
    icon: Icons.checkroom_outlined,
  ),
  'wishlist': ListCategoryStyle(
    id: 'wishlist',
    label: 'Wishlist',
    color: ShoppaColors.rose,
    icon: Icons.favorite_outline,
  ),
  'event': ListCategoryStyle(
    id: 'event',
    label: 'Event',
    color: ShoppaColors.amber,
    icon: Icons.celebration_outlined,
  ),
  'ingredients': ListCategoryStyle(
    id: 'ingredients',
    label: 'Ingredients',
    color: ShoppaColors.blue,
    icon: Icons.restaurant_outlined,
  ),
  'custom': ListCategoryStyle(
    id: 'custom',
    label: 'Custom',
    color: ShoppaColors.mist,
    icon: Icons.list_alt_outlined,
  ),
};

/// Known category ids from [listCategories].
List<String> get knownListCategoryIds =>
    listCategories.map((c) => c['id']!).toList(growable: false);

/// Style for [categoryId]; unknown ids fall back to a mist “Other” style.
ListCategoryStyle listCategoryStyle(String? categoryId) {
  final id = (categoryId ?? '').trim().toLowerCase();
  if (id.isEmpty) return _styles['custom']!;
  final known = _styles[id];
  if (known != null) return known;
  // Title-case free-text categories from older data.
  final label = id
      .split(RegExp(r'[_\s]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
  return ListCategoryStyle(
    id: id,
    label: label.isEmpty ? 'Custom' : label,
    color: ShoppaColors.mist,
    icon: Icons.category_outlined,
  );
}

/// Human label for chips / subtitles.
String listCategoryLabel(String? categoryId) =>
    listCategoryStyle(categoryId).label;
