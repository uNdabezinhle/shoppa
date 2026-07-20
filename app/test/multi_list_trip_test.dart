import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/lists_repository.dart';
import 'package:shoppa_app/core/aisle_sort.dart';
import 'package:shoppa_app/core/multi_list_trip.dart';

ShoppaListItem _item(
  String id, {
  required String name,
  bool checked = false,
}) =>
    ShoppaListItem(
      id: id,
      name: name,
      quantity: 1,
      unit: 'ea',
      note: '',
      checked: checked,
    );

ShoppaList _list(
  String id,
  String title,
  List<ShoppaListItem> items,
) =>
    ShoppaList(
      id: id,
      title: title,
      category: 'groceries',
      isRecurring: false,
      itemCount: items.length,
      checkedCount: items.where((i) => i.checked).length,
      items: items,
    );

void main() {
  group('multiListTripPath / parseTripListIds', () {
    test('round-trips list ids', () {
      expect(multiListTripPath([]), '/trip');
      expect(multiListTripPath(['b', 'a', 'a']), '/trip?lists=a,b');
      expect(parseTripListIds('a,b'), ['a', 'b']);
      expect(parseTripListIds('a,,b,a'), ['a', 'b']);
      expect(parseTripListIds(null), isEmpty);
    });
  });

  group('buildTripLines', () {
    test('includes only remaining items by default', () {
      final lists = [
        _list('l1', 'Home', [
          _item('1', name: 'Milk'),
          _item('2', name: 'Bread', checked: true),
        ]),
        _list('l2', 'Party', [
          _item('3', name: 'Chips'),
        ]),
      ];
      final lines = buildTripLines(lists);
      expect(lines.map((l) => l.item.name), ['Milk', 'Chips']);
      expect(lines.map((l) => l.listTitle), ['Home', 'Party']);
    });

    test('can include checked when asked', () {
      final lists = [
        _list('l1', 'Home', [
          _item('1', name: 'Milk', checked: true),
        ]),
      ];
      expect(buildTripLines(lists, includeChecked: true).length, 1);
    });
  });

  group('tripAisleSections', () {
    test('groups by aisle and puts checked at end', () {
      final lines = [
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('1', name: 'Apples'),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('2', name: 'Milk', checked: true),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('3', name: 'Bread'),
        ),
      ];
      final sections = tripAisleSections(lines, includeChecked: true);
      expect(sections.map((s) => s.aisle.id).toList(), [
        'produce',
        'bakery',
        'checked',
      ]);
      expect(sections.last.lines.single.item.name, 'Milk');
    });
  });

  group('cross-list duplicates', () {
    test('indexes open items on 2+ lists and formats hints', () {
      final lines = [
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('1', name: 'Milk'),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('2', name: 'milk'),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('3', name: 'Bread'),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('4', name: 'Chips', checked: true),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('5', name: 'Chips'),
        ),
      ];
      final index = indexCrossListDuplicates(lines);
      expect(crossListDuplicateGroupCount(index), 1);
      expect(index.keys.single, 'milk|ea');
      final milkHome = lines.first;
      expect(
        otherListsWithSameItem(milkHome, index),
        ['Party'],
      );
      expect(
        formatCrossListDuplicateHint(otherListsWithSameItem(milkHome, index)),
        'Also on Party',
      );
      // Chips only open on Home (Party checked) → not a cross-list dup.
      expect(
        otherListsWithSameItem(lines.last, index),
        isEmpty,
      );
      expect(matchingOpenTripLines(milkHome, lines).length, 2);
      expect(
        matchingOpenTripLines(milkHome, lines).map((l) => l.listId).toSet(),
        {'l1', 'l2'},
      );
    });

    test('filterCrossListDuplicates keeps only multi-list open matches', () {
      final lines = [
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('1', name: 'Milk'),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('2', name: 'milk'),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('3', name: 'Bread'),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('4', name: 'Bread', checked: true),
        ),
      ];
      final index = indexCrossListDuplicates(lines);
      expect(filterCrossListDuplicates(lines, enabled: false), lines);
      final filtered = filterCrossListDuplicates(
        lines,
        enabled: true,
        index: index,
      );
      expect(filtered.map((l) => l.item.id).toList(), ['1', '2']);
      expect(
        filterCrossListDuplicates(const [], enabled: true),
        isEmpty,
      );
      // Only unique open names → empty filter result.
      final uniques = [
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('1', name: 'Milk'),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('2', name: 'Bread'),
        ),
      ];
      expect(
        filterCrossListDuplicates(uniques, enabled: true),
        isEmpty,
      );
    });
  });

  group('tripItemsForList / formatTripQuickAddResult', () {
    test('filters open items for one list', () {
      final lines = [
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('1', name: 'Milk'),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('2', name: 'Chips'),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('3', name: 'Bread'),
        ),
      ];
      expect(
        tripItemsForList(lines, 'l1').map((i) => i.name).toList(),
        ['Milk', 'Bread'],
      );
    });

    test('formats create vs merge snack lines', () {
      expect(
        formatTripQuickAddResult(
          listTitle: 'Home',
          createdCount: 1,
          mergedCount: 0,
          singleName: 'Milk',
        ),
        'Added Milk to Home',
      );
      expect(
        formatTripQuickAddResult(
          listTitle: 'Home',
          createdCount: 0,
          mergedCount: 1,
          singleName: 'Milk',
          singleQty: 3,
        ),
        'Updated “Milk”: qty 3',
      );
      expect(
        formatTripQuickAddResult(
          listTitle: 'Home',
          createdCount: 2,
          mergedCount: 1,
        ),
        'Added 2 · merged 1 on Home',
      );
    });
  });

  group('resolveTripAddTarget', () {
    test('prefers preferred editable list, else first editable', () {
      final viewOnly = ShoppaList(
        id: 'l2',
        title: 'Shared',
        category: 'groceries',
        isRecurring: false,
        itemCount: 1,
        checkedCount: 0,
        role: 'view',
        items: [_item('2', name: 'Chips')],
      );
      final editShared = ShoppaList(
        id: 'l3',
        title: 'Party',
        category: 'groceries',
        isRecurring: false,
        itemCount: 0,
        checkedCount: 0,
        role: 'edit',
        items: const [],
      );
      final owned = ShoppaList(
        id: 'l1',
        title: 'Home',
        category: 'groceries',
        isRecurring: false,
        itemCount: 1,
        checkedCount: 0,
        role: 'owner',
        items: [_item('1', name: 'Milk')],
      );
      final lists = [viewOnly, owned, editShared];
      expect(tripEditableLists(lists).map((l) => l.id).toList(), ['l1', 'l3']);
      expect(resolveTripAddTarget(lists)?.id, 'l1');
      expect(resolveTripAddTarget(lists, preferredListId: 'l3')?.id, 'l3');
      expect(resolveTripAddTarget(lists, preferredListId: 'l2')?.id, 'l1');
      expect(resolveTripAddTarget([viewOnly]), isNull);
    });
  });

  group('openTripLinesInAisle / formatAisleCheckOffMessage', () {
    test('finds open lines in an aisle and formats confirm copy', () {
      final lines = [
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('1', name: 'Apples'),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('2', name: 'Bananas'),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('3', name: 'Milk'),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('4', name: 'Oranges', checked: true),
        ),
      ];
      final produce = openTripLinesInAisle(lines, 'produce');
      expect(produce.map((l) => l.item.name).toList(), ['Apples', 'Bananas']);
      expect(openTripLinesInAisle(lines, 'checked'), isEmpty);
      expect(openTripLinesInAisle(lines, 'dairy').map((l) => l.item.name), [
        'Milk',
      ]);
      expect(
        formatAisleCheckOffMessage(aisleLabel: 'Fruit & veg', count: 2),
        'Check off 2 items in Fruit & veg?',
      );
      expect(
        formatAisleCheckOffMessage(aisleLabel: 'Dairy', count: 1),
        'Check off 1 item in Dairy?',
      );
    });
  });

  group('filterTripLinesByListId / tripListFilterOptions', () {
    test('filters by list and builds chip options with open counts', () {
      final lines = [
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('1', name: 'Milk'),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('2', name: 'Chips'),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('3', name: 'Bread', checked: true),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: _item('4', name: 'Soda'),
        ),
      ];
      expect(filterTripLinesByListId(lines, null).length, 4);
      expect(
        filterTripLinesByListId(lines, 'l1').map((l) => l.item.id).toList(),
        ['1', '3'],
      );
      expect(tripOpenCountByListId(lines), {'l1': 1, 'l2': 2});
      final opts = tripListFilterOptions(
        lines,
        sourceLists: [
          _list('l2', 'Party', []),
          _list('l1', 'Home', []),
        ],
      );
      expect(opts.map((o) => o.id).toList(), ['l2', 'l1']);
      expect(opts.first.open, 2);
      expect(opts.last.open, 1);
    });
  });

  group('filterTripLines', () {
    test('matches name, list title, and note; empty query is no-op', () {
      final lines = [
        TripLine(
          listId: 'l1',
          listTitle: 'Weekly',
          item: ShoppaListItem(
            id: 'i1',
            name: 'Milk',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: false,
          ),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: ShoppaListItem(
            id: 'i2',
            name: 'Chips',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: false,
          ),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Weekly',
          item: ShoppaListItem(
            id: 'i3',
            name: 'Yogurt',
            quantity: 1,
            unit: 'ea',
            note: 'Greek plain',
            checked: false,
          ),
        ),
      ];
      expect(filterTripLines(lines, '  ').length, 3);
      expect(filterTripLines(lines, 'milk').map((l) => l.item.id), ['i1']);
      expect(
        filterTripLines(lines, 'party').map((l) => l.listId).toSet(),
        {'l2'},
      );
      expect(filterTripLines(lines, 'greek').map((l) => l.item.id), ['i3']);
      expect(filterTripLines(lines, 'zzzz'), isEmpty);
    });
  });

  group('remainingItemCount', () {
    test('uses items when present else summary counts', () {
      final withItems = _list('a', 'A', [
        _item('1', name: 'x'),
        _item('2', name: 'y', checked: true),
      ]);
      expect(remainingItemCount(withItems), 1);

      final summary = ShoppaList(
        id: 'b',
        title: 'B',
        category: 'custom',
        isRecurring: false,
        itemCount: 5,
        checkedCount: 2,
      );
      expect(remainingItemCount(summary), 3);
    });
  });

  group('formatTripAsText / tripSpendFromLines', () {
    test('recap groups by list and includes prices', () {
      final lines = [
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: ShoppaListItem(
            id: '1',
            name: 'Milk',
            quantity: 1,
            unit: 'ea',
            note: '',
            checked: true,
            paidPrice: 2599,
          ),
        ),
        TripLine(
          listId: 'l2',
          listTitle: 'Party',
          item: ShoppaListItem(
            id: '2',
            name: 'Chips',
            quantity: 2,
            unit: 'ea',
            note: '',
            checked: true,
            paidPrice: 1500,
          ),
        ),
        TripLine(
          listId: 'l1',
          listTitle: 'Home',
          item: _item('3', name: 'Bread'),
        ),
      ];
      final spend = tripSpendFromLines(lines);
      expect(spend.spentCents, 4099);
      expect(spend.checkedCount, 2);

      final recap = formatTripAsText(
        lines,
        listTitles: const ['Home', 'Party'],
        mode: TripTextMode.checked,
      );
      expect(recap, contains('Today’s trip'));
      expect(recap, contains('HOME'));
      expect(recap, contains('PARTY'));
      expect(recap, contains('R25.99'));
      expect(recap, contains('R15.00'));
      expect(recap, isNot(contains('Bread')));

      final left = formatTripAsText(lines, mode: TripTextMode.remaining);
      expect(left, contains('Bread'));
      expect(left, isNot(contains('Milk')));

      final withTill = formatTripAsText(
        lines,
        mode: TripTextMode.checked,
        tillCents: 4500,
        basketCents: 4099,
      );
      expect(withTill, contains('Till R45.00'));
      expect(withTill, contains('over basket'));
    });
  });
}
