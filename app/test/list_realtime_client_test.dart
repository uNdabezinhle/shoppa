import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/list_realtime_client.dart';

void main() {
  group('ListRealtimeEvent.tryParse', () {
    test('parses a well-formed item.added frame', () {
      final event = ListRealtimeEvent.tryParse(
        '{"event": "item.added", "payload": {"id": "i-1", "name": "Milk"}}',
      );

      expect(event, isNotNull);
      expect(event!.event, 'item.added');
      expect(event.payload['name'], 'Milk');
    });

    test('parses item.checked with a boolean payload field', () {
      final event = ListRealtimeEvent.tryParse(
        '{"event": "item.checked", "payload": {"id": "i-1", "checked": true}}',
      );

      expect(event!.event, 'item.checked');
      expect(event.payload['checked'], true);
    });

    test('defaults to an empty payload map when payload is omitted', () {
      final event = ListRealtimeEvent.tryParse(
        '{"event": "collaborator.joined"}',
      );

      expect(event!.event, 'collaborator.joined');
      expect(event.payload, isEmpty);
    });

    test('returns null for malformed JSON', () {
      expect(ListRealtimeEvent.tryParse('not json'), isNull);
    });

    test('returns null when the event field is missing', () {
      expect(
        ListRealtimeEvent.tryParse('{"payload": {"id": "i-1"}}'),
        isNull,
      );
    });

    test('returns null for a JSON array instead of an object', () {
      expect(ListRealtimeEvent.tryParse('[1, 2, 3]'), isNull);
    });

    test('parses presence.joined with email and initials', () {
      final event = ListRealtimeEvent.tryParse(
        '{"event": "presence.joined", "payload": {"user_id": "u-2", "email": "friend@example.com", "initials": "FR"}}',
      );

      expect(event!.event, 'presence.joined');
      expect(event.payload['email'], 'friend@example.com');
      expect(event.payload['initials'], 'FR');
    });
  });
}
