import 'dart:convert';

import 'api_client.dart';

/// A travel plan the user has explicitly chosen to save, so it can be
/// reopened later without re-calling the Gemini-backed generate-plan API.
///
/// Backed by the cloud (`GET/POST/DELETE /api/travels`) rather than on-device
/// storage — see docs/supabase-schema-design.md §8 ("Login required to save").
/// The shape here matches the backend's response 1:1, so toJson/fromJson stay
/// simple, direct mirrors of the wire format.
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
  /// Throws [AuthRequiredException] (via ApiClient) when the user isn't signed in.
  static Future<List<SavedTravel>> getAll() async {
    final response = await ApiClient.get('/api/travels');
    if (response.statusCode != 200) {
      throw Exception('Failed to load saved travels (${response.statusCode})');
    }

    final List<dynamic> raw = json.decode(response.body) as List<dynamic>;
    return raw.map((entry) => SavedTravel.fromJson(entry as Map<String, dynamic>)).toList();
  }

  /// Saves [travelPlan] as a new entry and returns it. Throws
  /// [AuthRequiredException] (via ApiClient) when the user isn't signed in —
  /// callers (see results_screen.dart) should prompt sign-in before calling this
  /// rather than relying solely on the exception, so the user isn't surprised.
  static Future<SavedTravel> save(Map<String, dynamic> travelPlan) async {
    final response = await ApiClient.post('/api/travels', body: {'travelPlan': travelPlan});
    if (response.statusCode != 201) {
      throw Exception('Failed to save travel (${response.statusCode})');
    }
    return SavedTravel.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }

  static Future<void> delete(String id) async {
    final response = await ApiClient.delete('/api/travels/$id');
    // A 404 here means it's already gone (e.g. deleted from another device) —
    // treat that the same as a successful delete rather than surfacing an error.
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw Exception('Failed to delete travel (${response.statusCode})');
    }
  }
}
