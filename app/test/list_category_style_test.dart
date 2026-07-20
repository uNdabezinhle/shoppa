import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/list_category_style.dart';
import 'package:shoppa_app/theme/shoppa_theme.dart';
import 'package:shoppa_app/widgets/list_form_dialog.dart';

void main() {
  group('listCategoryStyle', () {
    test('maps known categories to colors and icons', () {
      expect(listCategoryStyle('groceries').color, ShoppaColors.green);
      expect(listCategoryStyle('clothing').color, ShoppaColors.violet);
      expect(listCategoryStyle('wishlist').color, ShoppaColors.rose);
      expect(listCategoryStyle('event').color, ShoppaColors.amber);
      expect(listCategoryStyle('ingredients').color, ShoppaColors.blue);
      expect(listCategoryStyle('custom').color, ShoppaColors.mist);
      expect(
        listCategoryStyle('groceries').icon,
        Icons.local_grocery_store_outlined,
      );
    });

    test('is case-insensitive and trims', () {
      expect(listCategoryStyle('  GROCERIES ').id, 'groceries');
      expect(listCategoryStyle('Event').label, 'Event');
    });

    test('unknown and empty fall back gracefully', () {
      expect(listCategoryStyle(null).id, 'custom');
      expect(listCategoryStyle('').id, 'custom');
      final other = listCategoryStyle('party_supplies');
      expect(other.label, 'Party Supplies');
      expect(other.color, ShoppaColors.mist);
    });

    test('covers every form-dialog category id', () {
      for (final row in listCategories) {
        final id = row['id']!;
        final style = listCategoryStyle(id);
        expect(style.id, id);
        expect(style.label, isNotEmpty);
      }
    });
  });

  group('listCategoryLabel', () {
    test('returns display labels', () {
      expect(listCategoryLabel('groceries'), 'Groceries');
      expect(listCategoryLabel('wishlist'), 'Wishlist');
    });
  });
}
