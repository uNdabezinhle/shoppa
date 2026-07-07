import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/delivery_realtime_client.dart';

void main() {
  group('DeliveryRealtimeEvent', () {
    test('tryParse decodes quote.updated payload', () {
      final event = DeliveryRealtimeEvent.tryParse(
        '{"event":"quote.updated","payload":{"currency_code":"ZAR","quotes":[]}}',
      );
      expect(event, isNotNull);
      expect(event!.event, 'quote.updated');
      expect(event.payload['currency_code'], 'ZAR');
    });

    test('tryParse returns null for invalid JSON', () {
      expect(DeliveryRealtimeEvent.tryParse('not-json'), isNull);
    });
  });
}