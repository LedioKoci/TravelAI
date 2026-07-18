import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A travel plan the user has explicitly chosen to save, so it can be
/// reopened later without re-calling the Gemini-backed generate-plan API.
class SavedTravel {
  final String id;
  final String destinationCity;
  final String departureCity;
  final String startDate;
  final String endDate;
  final DateTime savedAt;
  final Map<String, dynamic> travelPlan;

  SavedTravel({
    required this.id,
    required this.destinationCity,
    required this.departureCity,
    required this.startDate,
    required this.endDate,
    required this.savedAt,
    required this.travelPlan,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'destinationCity': destinationCity,
        'departureCity': departureCity,
        'startDate': startDate,
        'endDate': endDate,
        'savedAt': savedAt.toIso8601String(),
        'travelPlan': travelPlan,
      };

  factory SavedTravel.fromJson(Map<String, dynamic> json) {
    return SavedTravel(
      id: json['id'] as String,
      destinationCity: json['destinationCity']?.toString() ?? 'Unknown City',
      departureCity: json['departureCity']?.toString() ?? '',
      startDate: json['startDate']?.toString() ?? 'flexible',
      endDate: json['endDate']?.toString() ?? 'flexible',
      savedAt: DateTime.tryParse(json['savedAt']?.toString() ?? '') ?? DateTime.now(),
      travelPlan: Map<String, dynamic>.from(json['travelPlan'] as Map),
    );
  }
}

class TravelStorageService {
  static const String _storageKey = 'saved_travels';

  static Future<List<SavedTravel>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];

    final travels = raw
        .map((entry) {
          try {
            return SavedTravel.fromJson(
                json.decode(entry) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<SavedTravel>()
        .toList();

    travels.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return travels;
  }

  /// Saves [travelPlan] as a new entry and returns it.
  static Future<SavedTravel> save(Map<String, dynamic> travelPlan) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];

    final planSummary =
        travelPlan['planSummary'] as Map<String, dynamic>? ?? {};

    final saved = SavedTravel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      destinationCity:
          planSummary['destinationCity']?.toString() ?? 'Unknown City',
      departureCity: planSummary['departureCity']?.toString() ?? '',
      startDate: planSummary['startDate']?.toString() ?? 'flexible',
      endDate: planSummary['endDate']?.toString() ?? 'flexible',
      savedAt: DateTime.now(),
      travelPlan: travelPlan,
    );

    raw.add(json.encode(saved.toJson()));
    await prefs.setStringList(_storageKey, raw);
    return saved;
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];

    raw.removeWhere((entry) {
      try {
        return (json.decode(entry) as Map<String, dynamic>)['id'] == id;
      } catch (_) {
        return false;
      }
    });

    await prefs.setStringList(_storageKey, raw);
  }
}
