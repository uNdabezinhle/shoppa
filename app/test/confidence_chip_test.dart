import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/widgets/confidence_chip.dart';

void main() {
  testWidgets('renders high confidence chip', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ConfidenceChip(confidence: 'high')),
      ),
    );
    expect(find.text('Confidence · High'), findsOneWidget);
  });

  test('label and color helpers normalize casing', () {
    expect(ConfidenceChip.labelFor('HIGH'), 'High');
    expect(ConfidenceChip.labelFor('medium'), 'Medium');
    expect(ConfidenceChip.legendHint('low'), 'Limited data');
  });
}
