// Shop-mode aisle grouping (heuristic store-walk order from item names).
// Store layouts reorder the same aisle buckets; no per-SKU floor plan yet.
import 'lists_repository.dart';

class AisleGroup {
  const AisleGroup({required this.id, required this.label, required this.order});

  final String id;
  final String label;
  final int order;
}

/// Typical grocery walk order (ZA-oriented labels; works as a general guide).
const aisleGroups = <AisleGroup>[
  AisleGroup(id: 'produce', label: 'Fruit & veg', order: 0),
  AisleGroup(id: 'bakery', label: 'Bakery', order: 1),
  AisleGroup(id: 'meat', label: 'Meat & deli', order: 2),
  AisleGroup(id: 'dairy', label: 'Dairy & eggs', order: 3),
  AisleGroup(id: 'frozen', label: 'Frozen', order: 4),
  AisleGroup(id: 'pantry', label: 'Pantry', order: 5),
  AisleGroup(id: 'snacks', label: 'Snacks', order: 6),
  AisleGroup(id: 'drinks', label: 'Drinks', order: 7),
  AisleGroup(id: 'household', label: 'Household', order: 8),
  AisleGroup(id: 'personal', label: 'Personal care', order: 9),
  AisleGroup(id: 'baby', label: 'Baby', order: 10),
  AisleGroup(id: 'pet', label: 'Pet', order: 11),
  AisleGroup(id: 'other', label: 'Other', order: 12),
];

final _aisleById = {for (final a in aisleGroups) a.id: a};

/// Named walk-order profile for a store chain (heuristic, not a floor map).
class StoreAisleLayout {
  const StoreAisleLayout({
    required this.id,
    required this.label,
    required this.aisleIds,
  });

  final String id;
  final String label;
  /// Aisle group ids in walk order (must cover known aisles).
  final List<String> aisleIds;
}

const _defaultAisleIds = <String>[
  'produce',
  'bakery',
  'meat',
  'dairy',
  'frozen',
  'pantry',
  'snacks',
  'drinks',
  'household',
  'personal',
  'baby',
  'pet',
  'other',
];

/// Built-in ZA-oriented layouts (approximate walk order by chain).
const storeAisleLayouts = <StoreAisleLayout>[
  StoreAisleLayout(
    id: 'default',
    label: 'General grocery',
    aisleIds: _defaultAisleIds,
  ),
  StoreAisleLayout(
    id: 'checkers',
    label: 'Checkers / Shoprite',
    aisleIds: [
      'produce',
      'bakery',
      'meat',
      'dairy',
      'frozen',
      'pantry',
      'snacks',
      'drinks',
      'household',
      'personal',
      'baby',
      'pet',
      'other',
    ],
  ),
  StoreAisleLayout(
    id: 'picknpay',
    label: 'Pick n Pay',
    // Dairy often sits earlier after produce/bakery in PnP stores.
    aisleIds: [
      'produce',
      'bakery',
      'dairy',
      'meat',
      'frozen',
      'pantry',
      'snacks',
      'drinks',
      'household',
      'personal',
      'baby',
      'pet',
      'other',
    ],
  ),
  StoreAisleLayout(
    id: 'woolworths',
    label: 'Woolworths',
    aisleIds: [
      'produce',
      'bakery',
      'meat',
      'dairy',
      'frozen',
      'pantry',
      'drinks',
      'snacks',
      'household',
      'personal',
      'baby',
      'pet',
      'other',
    ],
  ),
  StoreAisleLayout(
    id: 'spar',
    label: 'SPAR',
    aisleIds: [
      'produce',
      'bakery',
      'meat',
      'dairy',
      'drinks',
      'snacks',
      'pantry',
      'frozen',
      'household',
      'personal',
      'baby',
      'pet',
      'other',
    ],
  ),
  StoreAisleLayout(
    id: 'pharmacy',
    label: 'Dis-Chem / Clicks',
    aisleIds: [
      'personal',
      'baby',
      'household',
      'drinks',
      'snacks',
      'pantry',
      'dairy',
      'frozen',
      'produce',
      'bakery',
      'meat',
      'pet',
      'other',
    ],
  ),
];

final _layoutById = {for (final l in storeAisleLayouts) l.id: l};

StoreAisleLayout storeAisleLayoutById(String? id) {
  if (id == null || id.isEmpty) return storeAisleLayouts.first;
  return _layoutById[id] ?? storeAisleLayouts.first;
}

/// Guess a layout from a free-text store name (receipts, shopping-at).
StoreAisleLayout storeAisleLayoutForName(String? storeName) {
  final n = (storeName ?? '').toLowerCase().trim();
  if (n.isEmpty) return storeAisleLayoutById('default');
  if (n.contains('dis-chem') ||
      n.contains('dischem') ||
      n.contains('clicks')) {
    return storeAisleLayoutById('pharmacy');
  }
  if (n.contains('woolworth') || n.contains('woolies')) {
    return storeAisleLayoutById('woolworths');
  }
  if (n.contains('pick n') ||
      n.contains("pick 'n") ||
      n.contains('pickn') ||
      n.contains('pnp') ||
      n.contains('pick-n')) {
    return storeAisleLayoutById('picknpay');
  }
  if (n.contains('spar')) {
    return storeAisleLayoutById('spar');
  }
  if (n.contains('checker') ||
      n.contains('shoprite') ||
      n.contains('usave') ||
      n.contains('u-save')) {
    return storeAisleLayoutById('checkers');
  }
  if (n.contains('food lover')) {
    // Similar perimeter walk to Checkers-style hypermarkets.
    return storeAisleLayoutById('checkers');
  }
  return storeAisleLayoutById('default');
}

/// Prefer an explicit layout id; otherwise infer from [storeName].
StoreAisleLayout resolveStoreAisleLayout({
  String? storeName,
  String? layoutId,
}) {
  if (layoutId != null &&
      layoutId.isNotEmpty &&
      _layoutById.containsKey(layoutId)) {
    return _layoutById[layoutId]!;
  }
  return storeAisleLayoutForName(storeName);
}

/// Common ZA chain labels for “shopping at” pickers (no catalogue id needed).
const kKnownStoreNameSuggestions = <String>[
  'Checkers',
  'Shoprite',
  'Pick n Pay',
  'Woolworths',
  'SPAR',
  'Dis-Chem',
  'Clicks',
  "Food Lover's Market",
];

/// Merge recent receipt stores with known chains (deduped, frequent first).
List<String> tripStoreSuggestions({
  Iterable<String> frequent = const [],
  Iterable<String> known = kKnownStoreNameSuggestions,
  int limit = 12,
}) {
  final seen = <String>{};
  final out = <String>[];
  void add(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return;
    final key = name.toLowerCase();
    if (seen.contains(key)) return;
    seen.add(key);
    out.add(name);
  }

  for (final f in frequent) {
    add(f);
  }
  for (final k in known) {
    add(k);
  }
  if (out.length <= limit) return out;
  return out.take(limit).toList(growable: false);
}

/// Synthetic session id when the shopper picks a free-text store (no catalogue).
String tripStoreSessionId(String storeName) {
  final key = storeName.trim().toLowerCase();
  return 'name:$key';
}

/// True when [storeId] is a real catalogue store (not a free-text session id).
bool isCatalogueStoreId(String? storeId) {
  if (storeId == null || storeId.isEmpty) return false;
  return !storeId.startsWith('name:');
}

/// Open (unchecked) list items that belong to [aisleId] (not the checked bucket).
List<ShoppaListItem> openListItemsInAisle(
  List<ShoppaListItem> items,
  String aisleId,
) {
  if (aisleId.isEmpty || aisleId == 'checked') return const [];
  return items
      .where((i) => !i.checked && aisleForItem(i).id == aisleId)
      .toList(growable: false);
}

/// Snack / confirm copy for bulk aisle check-off.
String formatAisleCheckOffMessage({
  required String aisleLabel,
  required int count,
}) {
  final n = count < 0 ? 0 : count;
  final aisle = aisleLabel.trim().isEmpty ? 'this aisle' : aisleLabel.trim();
  if (n == 1) return 'Check off 1 item in $aisle?';
  return 'Check off $n items in $aisle?';
}

/// Next aisle still holding open items, after [afterAisleId] in walk order.
///
/// When [afterAisleId] is null, returns the first open aisle. Returns null when
/// nothing remains (or only the synthetic checked bucket would apply).
AisleGroup? nextOpenAisleGroup(
  List<ShoppaListItem> items, {
  StoreAisleLayout? layout,
  String? afterAisleId,
}) {
  final resolved = layout ?? storeAisleLayoutById('default');
  final sections = shopAisleSections(
    items,
    separateChecked: true,
    includeChecked: false,
    layout: resolved,
  );
  if (sections.isEmpty) return null;

  final after = afterAisleId?.trim() ?? '';
  if (after.isEmpty || after == 'checked') {
    return sections.first.aisle;
  }

  final openById = {for (final s in sections) s.aisle.id: s.aisle};
  var seenAfter = false;
  for (final g in aisleGroupsForLayout(resolved)) {
    if (g.id == after) {
      seenAfter = true;
      continue;
    }
    if (seenAfter && openById.containsKey(g.id)) {
      return openById[g.id];
    }
  }
  // Finished aisle was not in the walk (or was last). If it still has opens,
  // there is no “next”; otherwise jump to the first remaining open aisle.
  if (openById.containsKey(after)) return null;
  return sections.first.aisle;
}

/// Short walk hint, e.g. `Next up: Dairy & eggs`.
String formatNextAisleHint(AisleGroup? next) {
  if (next == null) return 'No more aisles left';
  return 'Next up: ${next.label}';
}

/// Aisle groups in walk order for [layout], with any missing ids appended.
List<AisleGroup> aisleGroupsForLayout(StoreAisleLayout layout) {
  final seen = <String>{};
  final out = <AisleGroup>[];
  for (final id in layout.aisleIds) {
    final g = _aisleById[id];
    if (g == null || seen.contains(id)) continue;
    seen.add(id);
    out.add(g);
  }
  for (final g in aisleGroups) {
    if (seen.contains(g.id)) continue;
    out.add(g);
  }
  return out;
}

/// Keyword → aisle id. First match wins (more specific lists first).
const _keywordAisles = <String, List<String>>{
  'produce': [
    'apple', 'banana', 'orange', 'lemon', 'lime', 'grape', 'berry', 'mango',
    'avocado', 'tomato', 'onion', 'potato', 'carrot', 'lettuce', 'spinach',
    'cabbage', 'broccoli', 'cucumber', 'pepper', 'chilli', 'garlic', 'ginger',
    'herb', 'coriander', 'parsley', 'mint', 'fruit', 'veg', 'salad', 'mushroom',
    'pumpkin', 'sweet potato', 'butternut', 'mielie', 'corn', 'beans green',
  ],
  'bakery': [
    'bread', 'roll', 'bun', 'bagel', 'croissant', 'muffin', 'cake', 'pastry',
    'wrap', 'pita', 'tortilla', 'bake',
  ],
  'meat': [
    'chicken', 'beef', 'mince', 'pork', 'lamb', 'bacon', 'sausage', 'boerewors',
    'ham', 'turkey', 'fish', 'salmon', 'tuna', 'prawn', 'shrimp', 'meat',
    'steak', 'chop', 'ribs', 'wors', 'polony', 'deli',
  ],
  'dairy': [
    'milk', 'cheese', 'butter', 'yoghurt', 'yogurt', 'cream', 'egg', 'ghee',
    'maas', 'amasi', 'cottage', 'feta', 'cheddar',
  ],
  'frozen': [
    'frozen', 'ice cream', 'icecream', 'pizza frozen', 'chips frozen',
  ],
  'pantry': [
    'rice', 'pasta', 'noodle', 'flour', 'sugar', 'salt', 'oil', 'vinegar',
    'sauce', 'spice', 'stock', 'soup', 'bean', 'lentil', 'chickpea', 'cereal',
    'oats', 'mielie meal', 'maize', 'pap', 'tinned', 'canned', 'jam', 'peanut',
    'tin of',
    'honey', 'baking', 'yeast', 'mayo', 'mustard', 'ketchup', 'tomato sauce',
  ],
  'snacks': [
    'chip', 'crisp', 'biscuit', 'cookie', 'chocolate', 'sweet', 'candy',
    'popcorn', 'nut', 'snack', 'bar', 'cracker',
  ],
  'drinks': [
    'water', 'juice', 'soda', 'coke', 'colddrink', 'cool drink', 'beer',
    'wine', 'coffee', 'tea', 'energy drink', 'smoothie', 'cordial', 'drink',
  ],
  'household': [
    'detergent', 'soap dish', 'bleach', 'cleaner', 'wipe', 'bin bag',
    'garbage', 'foil', 'wrap cling', 'tissue', 'toilet paper', 'paper towel',
    'sponge', 'dishwash', 'laundry', 'fabric softener',
  ],
  'personal': [
    'shampoo', 'conditioner', 'toothpaste', 'toothbrush', 'deodorant',
    'lotion', 'sunscreen', 'razor', 'sanitary', 'pad', 'tampon', 'body wash',
    'soap', 'face wash', 'moisturizer',
  ],
  'baby': [
    'nappy', 'diaper', 'formula', 'baby', 'wipe baby', 'dummy', 'pacifier',
  ],
  'pet': [
    'dog', 'cat', 'pet', 'kibble', 'litter',
  ],
};

bool _nameMatchesKeyword(String lowerName, String keyword) {
  final k = keyword.trim().toLowerCase();
  if (k.isEmpty) return false;
  if (k.contains(' ')) return lowerName.contains(k);
  // Short tokens need word boundaries ("pap" ≠ "paper"); longer stems
  // allow plurals ("banana" matches "bananas", "milk" matches "milk").
  if (k.length <= 3) {
    final pattern =
        RegExp('(?:^|[^a-z0-9])${RegExp.escape(k)}(?:[^a-z0-9]|\$)');
    return pattern.hasMatch(lowerName);
  }
  return lowerName.contains(k);
}

AisleGroup aisleForName(String name) {
  final lower = name.toLowerCase();
  for (final entry in _keywordAisles.entries) {
    for (final keyword in entry.value) {
      if (_nameMatchesKeyword(lower, keyword)) {
        return _aisleById[entry.key]!;
      }
    }
  }
  return _aisleById['other']!;
}

AisleGroup aisleForItem(ShoppaListItem item) => aisleForName(item.name);

/// A row in the shop list: either a section header or an item.
sealed class ShopListRow {
  const ShopListRow();
}

class ShopSectionRow extends ShopListRow {
  const ShopSectionRow(this.aisle);
  final AisleGroup aisle;
}

class ShopItemRow extends ShopListRow {
  const ShopItemRow(this.item);
  final ShoppaListItem item;
}

/// One aisle (or "Checked off") with its items — used for sticky headers.
class AisleSection {
  const AisleSection({required this.aisle, required this.items});

  final AisleGroup aisle;
  final List<ShoppaListItem> items;
}

/// Shop mode aisle groups for sticky section headers / walk order.
List<AisleSection> shopAisleSections(
  List<ShoppaListItem> items, {
  bool separateChecked = true,
  bool includeChecked = true,
  StoreAisleLayout? layout,
}) {
  if (items.isEmpty) return const [];

  final open = <ShoppaListItem>[];
  final done = <ShoppaListItem>[];
  for (final item in items) {
    if (separateChecked && item.checked) {
      if (includeChecked) done.add(item);
    } else if (!item.checked || !separateChecked) {
      open.add(item);
    }
  }

  final byAisle = <String, List<ShoppaListItem>>{};
  for (final item in open) {
    final aisle = aisleForItem(item);
    byAisle.putIfAbsent(aisle.id, () => []).add(item);
  }

  final walk = aisleGroupsForLayout(layout ?? storeAisleLayoutById('default'));
  final sections = <AisleSection>[];
  for (final group in walk) {
    final groupItems = byAisle[group.id];
    if (groupItems == null || groupItems.isEmpty) continue;
    sections.add(AisleSection(aisle: group, items: groupItems));
  }

  if (done.isNotEmpty) {
    sections.add(
      AisleSection(
        aisle: const AisleGroup(id: 'checked', label: 'Checked off', order: 99),
        items: done,
      ),
    );
  }
  return sections;
}

/// Flat rows (header + items). Prefer [shopAisleSections] for sticky UIs.
List<ShopListRow> shopRowsByAisle(
  List<ShoppaListItem> items, {
  bool separateChecked = true,
  bool includeChecked = true,
  StoreAisleLayout? layout,
}) {
  final rows = <ShopListRow>[];
  for (final section in shopAisleSections(
    items,
    separateChecked: separateChecked,
    includeChecked: includeChecked,
    layout: layout,
  )) {
    rows.add(ShopSectionRow(section.aisle));
    rows.addAll(section.items.map(ShopItemRow.new));
  }
  return rows;
}
