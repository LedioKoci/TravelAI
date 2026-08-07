import 'dart:convert';

import 'api_client.dart';

/// Talks to /api/profile. `homeCity` is what powers the "Departing from home?"
/// search toggle — see docs/supabase-schema-design.md §3.1 for why the backend
/// applies it as a deterministic post-processing fallback rather than feeding it
/// into the Gemini prompt.
class ProfileService {
  ProfileService._();

  static Future<Map<String, dynamic>> getProfile() async {
    final response = await ApiClient.get('/api/profile');
    if (response.statusCode != 200) {
      throw Exception('Failed to load profile (${response.statusCode})');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Pass null (or an empty string) to clear the home city.
  static Future<Map<String, dynamic>> updateHomeCity(String? homeCity) async {
    final response = await ApiClient.patch('/api/profile', body: {'homeCity': homeCity});
    if (response.statusCode != 200) {
      throw Exception('Failed to update home city (${response.statusCode})');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }
}
