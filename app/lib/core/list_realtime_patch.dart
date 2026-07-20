// Applies list WebSocket item events to an in-memory ShoppaList without a
// full REST refetch (SRS FR-3.2). Returns a new list when the event can be
// applied safely; null means the caller should fall back to a full detail
// reload (collaborator role changes, unknown events, or missing item data).
import 'list_realtime_client.dart';
import 'lists_repository.dart';

ShoppaList? applyListRealtimeEvent(ShoppaList list, ListRealtimeEvent event) {
  switch (event.event) {
    case 'item.added':
    case 'item.updated':
    case 'item.checked':
      return _upsertItem(list, event.payload);
    case 'item.removed':
      return _removeItem(list, event.payload);
    case 'list.scaled':
      return _replaceAllItems(list, event.payload);
    // Presence is handled by the screen banner, not list data.
    case 'presence.joined':
    case 'presence.left':
      return list;
    // Collaborator previews / role can change — keep REST as source of truth.
    case 'collaborator.joined':
    case 'collaborator.removed':
    case 'collaborator.updated':
      return null;
    default:
      return null;
  }
}

ShoppaList? _upsertItem(ShoppaList list, Map<String, dynamic> payload) {
  final items = list.items;
  if (items == null) return null;
  final id = payload['id'] as String?;
  if (id == null || payload['name'] == null) return null;

  ShoppaListItem incoming;
  try {
    incoming = ShoppaListItem.fromJson(payload);
  } catch (_) {
    return null;
  }

  final next = List<ShoppaListItem>.from(items);
  final index = next.indexWhere((i) => i.id == id);
  if (index >= 0) {
    next[index] = incoming;
  } else {
    next.add(incoming);
  }
  next.sort((a, b) {
    final byPos = a.position.compareTo(b.position);
    if (byPos != 0) return byPos;
    return a.id.compareTo(b.id);
  });
  return _withItems(list, next);
}

ShoppaList? _removeItem(ShoppaList list, Map<String, dynamic> payload) {
  final items = list.items;
  if (items == null) return null;
  final id = payload['id'] as String?;
  if (id == null) return null;
  final next = items.where((i) => i.id != id).toList();
  if (next.length == items.length) return list;
  return _withItems(list, next);
}

ShoppaList? _replaceAllItems(ShoppaList list, Map<String, dynamic> payload) {
  final raw = payload['items'];
  if (raw is! List) return null;
  try {
    final next = raw
        .map((e) => ShoppaListItem.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        final byPos = a.position.compareTo(b.position);
        if (byPos != 0) return byPos;
        return a.id.compareTo(b.id);
      });
    return _withItems(list, next);
  } catch (_) {
    return null;
  }
}

ShoppaList _withItems(ShoppaList list, List<ShoppaListItem> items) {
  return ShoppaList(
    id: list.id,
    title: list.title,
    category: list.category,
    isRecurring: list.isRecurring,
    itemCount: items.length,
    checkedCount: items.where((i) => i.checked).length,
    isPublic: list.isPublic,
    eventName: list.eventName,
    eventDate: list.eventDate,
    updatedAt: list.updatedAt,
    role: list.role,
    collaborators: list.collaborators,
    items: items,
    fromCache: list.fromCache,
  );
}
