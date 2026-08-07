import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travelai/main.dart';
import 'package:travelai/services/auth_service.dart';

import 'test_helpers/in_memory_token_storage.dart';

void main() {
  setUp(() {
    // Logged out by default: main.dart's account-context/toggle logic and the
    // saved-travels sidebar both read AuthService on launch, so they must never
    // touch the real (unmocked, platform-channel-backed) secure storage in tests.
    AuthService.debugOverrideStorage(InMemoryTokenStorage());
  });

  testWidgets('renders the TravelAI title and search field on launch',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TravelAIApp());

    expect(find.text('TravelAI'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Weekend in Rome'), findsOneWidget);
  });

  testWidgets('shows a warning snackbar when searching with an empty query',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TravelAIApp());

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    expect(find.text('Please enter your travel idea'), findsOneWidget);
  });

  testWidgets('tapping a suggestion chip fills in the search field',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TravelAIApp());

    // The "Departing from home?" toggle pushes the suggestion chips further
    // down the page, past the default test viewport — scroll it into view
    // before tapping, same as a real device would on a shorter screen.
    final chip = find.text('Tokyo for 7 days');
    await tester.ensureVisible(chip);
    await tester.pump();

    await tester.tap(chip);
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, 'Tokyo for 7 days');
  });
}
