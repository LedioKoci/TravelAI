import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:travelai/services/travel_storage_service.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    test('getAll returns an empty list when nothing has been saved', () async {
      final travels = await TravelStorageService.getAll();
      expect(travels, isEmpty);
    });

    test('save persists a travel plan and getAll returns it back', () async {
      final saved = await TravelStorageService.save(_samplePlan());

      expect(saved.destinationCity, 'Paris');
      expect(saved.departureCity, 'New York');

      final all = await TravelStorageService.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, saved.id);
      expect(all.first.destinationCity, 'Paris');
    });

    test('save falls back to defaults when planSummary is missing', () async {
      final saved = await TravelStorageService.save({'flights': []});

      expect(saved.destinationCity, 'Unknown City');
      expect(saved.departureCity, '');
      expect(saved.startDate, 'flexible');
      expect(saved.endDate, 'flexible');
    });

    test('getAll sorts travels newest-first by savedAt', () async {
      await TravelStorageService.save(_samplePlan(destinationCity: 'Older'));
      await Future.delayed(const Duration(milliseconds: 5));
      await TravelStorageService.save(_samplePlan(destinationCity: 'Newer'));

      final all = await TravelStorageService.getAll();
      expect(all.first.destinationCity, 'Newer');
      expect(all.last.destinationCity, 'Older');
    });

    test('getAll silently skips entries that fail to parse', () async {
      SharedPreferences.setMockInitialValues({
        'saved_travels': ['not valid json', '{"also": "not a saved travel"}'],
      });

      final all = await TravelStorageService.getAll();
      expect(all, isEmpty);
    });

    test('delete removes only the matching travel by id', () async {
      final first = await TravelStorageService.save(
        _samplePlan(destinationCity: 'Rome'),
      );
      await Future.delayed(const Duration(milliseconds: 5));
      final second = await TravelStorageService.save(
        _samplePlan(destinationCity: 'Berlin'),
      );

      await TravelStorageService.delete(first.id);

      final remaining = await TravelStorageService.getAll();
      expect(remaining, hasLength(1));
      expect(remaining.first.id, second.id);
    });

    test('delete is a no-op when the id does not exist', () async {
      await TravelStorageService.save(_samplePlan());
      await TravelStorageService.delete('nonexistent-id');

      final all = await TravelStorageService.getAll();
      expect(all, hasLength(1));
    });
  });
}
