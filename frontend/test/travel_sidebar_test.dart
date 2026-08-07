import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:travelai/services/auth_service.dart';
import 'package:travelai/services/http_client.dart';
import 'package:travelai/widgets/travel_sidebar.dart';

import 'test_helpers/in_memory_token_storage.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

Map<String, dynamic> _savedTravelResponse({
  required String id,
  String destinationCity = 'Lisbon',
  String departureCity = 'Boston',
}) {
  return {
    'id': id,
    'destinationCity': destinationCity,
    'departureCity': departureCity,
    'startDate': '2026-10-01',
    'endDate': '2026-10-08',
    'savedAt': '2026-07-19T12:00:00.000Z',
    'travelPlan': {
      'planSummary': {'destinationCity': destinationCity, 'departureCity': departureCity},
    },
  };
}

void main() {
  testWidgets('shows a sign-in prompt when the user is logged out', (WidgetTester tester) async {
    AuthService.debugOverrideStorage(InMemoryTokenStorage()); // no tokens
    AppHttpClient.debugOverride(MockClient((request) async {
      fail('should not call the network while logged out');
    }));

    await tester.pumpWidget(_wrap(const TravelSidebar()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sign in to see your saved travels'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  group('when logged in', () {
    setUp(() async {
      final storage = InMemoryTokenStorage();
      AuthService.debugOverrideStorage(storage);
      await storage.write('access_token', 'test-access-token');
      await storage.write('refresh_token', 'test-refresh-token');
    });

    testWidgets('shows an empty-state message when there are no saved travels',
        (WidgetTester tester) async {
      AppHttpClient.debugOverride(MockClient((request) async {
        return http.Response(json.encode(<dynamic>[]), 200);
      }));

      await tester.pumpWidget(_wrap(const TravelSidebar()));
      await tester.pumpAndSettle();

      expect(find.textContaining('No saved travels yet'), findsOneWidget);
    });

    testWidgets('lists a saved travel with its destination city', (WidgetTester tester) async {
      AppHttpClient.debugOverride(MockClient((request) async {
        return http.Response(json.encode([_savedTravelResponse(id: '1')]), 200);
      }));

      await tester.pumpWidget(_wrap(const TravelSidebar()));
      await tester.pumpAndSettle();

      expect(find.text('Lisbon'), findsOneWidget);
      expect(find.textContaining('From Boston'), findsOneWidget);
    });

    testWidgets('tapping delete removes the travel from the list', (WidgetTester tester) async {
      var deleted = false;
      AppHttpClient.debugOverride(MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted = true;
          return http.Response('', 204);
        }
        return http.Response(
          json.encode(deleted ? <dynamic>[] : [_savedTravelResponse(id: '1')]),
          200,
        );
      }));

      await tester.pumpWidget(_wrap(const TravelSidebar()));
      await tester.pumpAndSettle();

      expect(find.text('Lisbon'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Lisbon'), findsNothing);
      expect(find.textContaining('No saved travels yet'), findsOneWidget);
    });
  });
}
