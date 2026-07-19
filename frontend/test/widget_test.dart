import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:travelai/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

    await tester.tap(find.text('Tokyo for 7 days'));
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, 'Tokyo for 7 days');
  });
}
