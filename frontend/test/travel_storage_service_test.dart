import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:travelai/services/auth_service.dart';
import 'package:travelai/services/http_client.dart';
import 'package:travelai/services/travel_storage_service.dart';

import 'test_helpers/in_memory_token_storage.dart';

Map<String, dynamic> _samplePlan({
  String destinationCity = 'Paris',
  String departureCity = 'New York',
  String startDate = '2026-08-01',
  String endDate = '2026-08-07',
}) {
  return {
    'planSummary': {
      'destinationCity': destinationCity,
      'departureCity': departureCity,
      'startDate': startDate,
      'endDate': endDate,
    },
    'flights': [],
  };
}

Map<String, dynamic> _savedTravelResponse({
  required String id,
  String destinationCity = 'Paris',
  String departureCity = 'New York',
  String startDate = '2026-08-01',
  String endDate = '2026-08-07',
  String savedAt = '2026-07-19T12:00:00.000Z',
}) {
  return {
    'id': id,
    'destinationCity': destinationCity,
    'departureCity': departureCity,
    'startDate': startDate,
    'endDate': endDate,
    'savedAt': savedAt,
    'travelPlan': _samplePlan(
      destinationCity: destinationCity,
      departureCity: departureCity,
      startDate: startDate,
      endDate: endDate,
    ),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final storage = InMemoryTokenStorage();
    AuthService.debugOverrideStorage(storage);
    await storage.write('access_token', 'test-access-token');
    await storage.write('refresh_token', 'test-refresh-token');
  });

  group('SavedTravel.fromJson', () {
    test('round-trips through toJson/fromJson', () {
      final original = SavedTravel(
        id: '123',
        destinationCity: 'Tokyo',
        departureCity: 'London',
        startDate: '2026-09-01',
        endDate: '2026-09-10',
        savedAt: DateTime.utc(2026, 7, 19, 12, 30),
        travelPlan: {'foo': 'bar'},
      );

      final roundTripped = SavedTravel.fromJson(original.toJson());

      expect(roundTripped.id, '123');
      expect(roundTripped.destinationCity, 'Tokyo');
      expect(roundTripped.departureCity, 'London');
      expect(roundTripped.startDate, '2026-09-01');
      expect(roundTripped.endDate, '2026-09-10');
      expect(roundTripped.savedAt, DateTime.utc(2026, 7, 19, 12, 30));
      expect(roundTripped.travelPlan, {'foo': 'bar'});
    });

    test('falls back to defaults when optional fields are missing', () {
      final travel = SavedTravel.fromJson({
        'id': '1',
        'travelPlan': <String, dynamic>{},
      });

      expect(travel.destinationCity, 'Unknown City');
      expect(travel.departureCity, '');
      expect(travel.startDate, 'flexible');
      expect(travel.endDate, 'flexible');
      expect(travel.savedAt, isA<DateTime>());
    });

    test('falls back to DateTime.now() when savedAt is unparseable', () {
      final before = DateTime.now();
      final travel = SavedTravel.fromJson({
        'id': '1',
        'savedAt': 'not-a-date',
        'travelPlan': <String, dynamic>{},
      });
      final after = DateTime.now();

      expect(
        travel.savedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        travel.savedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('TravelStorageService', () {
    test('getAll returns whatever the backend responds with', () async {
      AppHttpClient.debugOverride(MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/travels');
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        return http.Response(json.encode([_savedTravelResponse(id: '1')]), 200);
      }));

      final travels = await TravelStorageService.getAll();
      expect(travels, hasLength(1));
      expect(travels.first.destinationCity, 'Paris');
      expect(travels.first.departureCity, 'New York');
    });

    test('getAll throws AuthRequiredException when logged out', () {
      AuthService.debugOverrideStorage(InMemoryTokenStorage()); // no tokens stored

      expect(TravelStorageService.getAll(), throwsA(isA<AuthRequiredException>()));
    });

    test('save POSTs the plan and returns the created SavedTravel', () async {
      AppHttpClient.debugOverride(MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/travels');
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['travelPlan']['planSummary']['destinationCity'], 'Paris');
        return http.Response(json.encode(_savedTravelResponse(id: 'new-1')), 201);
      }));

      final saved = await TravelStorageService.save(_samplePlan());
      expect(saved.id, 'new-1');
      expect(saved.destinationCity, 'Paris');
    });

    test('delete calls DELETE on the right id', () async {
      String? deletedPath;
      AppHttpClient.debugOverride(MockClient((request) async {
        deletedPath = request.url.path;
        expect(request.method, 'DELETE');
        return http.Response('', 204);
      }));

      await TravelStorageService.delete('abc123');
      expect(deletedPath, '/api/travels/abc123');
    });

    test('delete treats a 404 (already gone) as success, not an error', () async {
      AppHttpClient.debugOverride(MockClient((request) async {
        return http.Response('', 404);
      }));

      await expectLater(TravelStorageService.delete('already-gone'), completes);
    });

    test('an expired access token is silently refreshed, then the call retried', () async {
      var attempt = 0;
      AppHttpClient.debugOverride(MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          return http.Response(
            json.encode({'accessToken': 'new-access-token', 'refreshToken': 'new-refresh-token'}),
            200,
          );
        }

        attempt++;
        if (attempt == 1) {
          expect(request.headers['Authorization'], 'Bearer test-access-token');
          return http.Response(json.encode({'error': 'Access token expired or invalid'}), 401);
        }
        expect(request.headers['Authorization'], 'Bearer new-access-token');
        return http.Response(json.encode(<dynamic>[]), 200);
      }));

      final travels = await TravelStorageService.getAll();
      expect(travels, isEmpty);
      expect(attempt, 2);
    });

    test('throws AuthRequiredException when the refresh token is also rejected', () async {
      AppHttpClient.debugOverride(MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          return http.Response(json.encode({'error': 'invalid'}), 401);
        }
        return http.Response(json.encode({'error': 'expired'}), 401);
      }));

      expect(TravelStorageService.getAll(), throwsA(isA<AuthRequiredException>()));
    });
  });
}
