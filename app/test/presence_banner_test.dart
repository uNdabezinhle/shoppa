import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/widgets/presence_banner.dart';

void main() {
  testWidgets('PresenceBanner shows editor name when someone is editing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PresenceBanner(
            editorEmails: ['friend@example.com'],
            connected: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('Friend is editing this list now'), findsOneWidget);
  });

  testWidgets('PresenceBanner shows reconnecting message when disconnected', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PresenceBanner(editorEmails: [], connected: false),
        ),
      ),
    );

    expect(find.text('Reconnecting to live updates…'), findsOneWidget);
  });
}