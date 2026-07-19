import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:travelai/services/travel_storage_service.dart';
import 'package:travelai/widgets/travel_sidebar.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows an empty-state message when there are no saved travels',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const TravelSidebar()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No saved travels yet'),
      findsOneWidget,
    );
  });

  testWidgets('lists a saved travel with its destination city',
      (WidgetTester tester) async {
    await TravelStorageService.save({
      'planSummary': {
        'destinationCity': 'Lisbon',
        'departureCity': 'Boston',
        'startDate': '2026-10-01',
        'endDate': '2026-10-08',
      },
    });

    await tester.pumpWidget(_wrap(const TravelSidebar()));
    await tester.pumpAndSettle();

    expect(find.text('Lisbon'), findsOneWidget);
    expect(find.textContaining('From Boston'), findsOneWidget);
  });

  testWidgets('tapping delete removes the travel from the list',
      (WidgetTester tester) async {
    await TravelStorageService.save({
      'planSummary': {
        'destinationCity': 'Lisbon',
        'departureCity': 'Boston',
      },
    });

    await tester.pumpWidget(_wrap(const TravelSidebar()));
    await tester.pumpAndSettle();

    expect(find.text('Lisbon'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Lisbon'), findsNothing);
    expect(find.textContaining('No saved travels yet'), findsOneWidget);
  });
}
