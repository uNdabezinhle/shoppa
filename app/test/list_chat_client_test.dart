import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/list_chat_client.dart';

void main() {
  group('ListChatEvent.tryParse', () {
    test('parses message.created', () {
      final event = ListChatEvent.tryParse(
        '{"event": "message.created", "payload": {"id": "m-1", "body": "Hello"}}',
      );

      expect(event, isNotNull);
      expect(event!.event, 'message.created');
      expect(event.payload['body'], 'Hello');
    });

    test('returns null for malformed JSON', () {
      expect(ListChatEvent.tryParse('not json'), isNull);
    });
  });
}