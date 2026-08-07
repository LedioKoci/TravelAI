import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'http_client.dart';
import 'token_storage.dart';

/// Thrown by any call that requires a logged-in user when there's no valid
/// session — either no refresh token stored locally, or the refresh token was
/// itself rejected (expired/revoked/already rotated away). Callers should catch
/// this and prompt the user to sign in; see AuthScreen and AccountSheet.
class AuthRequiredException implements Exception {
  const AuthRequiredException();

  @override
  String toString() => 'AuthRequiredException: the user needs to sign in';
}

/// Talks to the backend's /api/auth/* endpoints and holds the resulting
/// access/refresh token pair in secure storage. See
/// docs/supabase-schema-design.md §4 for the full session design this mirrors:
/// a 15-minute access token plus a rotating refresh token.
class AuthService {
  AuthService._();

  static TokenStorage _storage = const SecureTokenStorage();

  /// Test-only: swap the real secure storage for an in-memory fake.
  static void debugOverrideStorage(TokenStorage storage) {
    _storage = storage;
  }

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _emailKey = 'user_email';

  static Future<String?> get accessToken => _storage.read(_accessTokenKey);
  static Future<String?> get refreshToken => _storage.read(_refreshTokenKey);
  static Future<String?> get email => _storage.read(_emailKey);

  /// A refresh token on file means the user has an account session, even if the
  /// short-lived access token has since expired — that expiry is recovered
  /// transparently by ApiClient's refresh-and-retry, not by this check.
  static Future<bool> isLoggedIn() async => (await refreshToken) != null;

  static Future<void> signup({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await AppHttpClient.instance.post(
      Uri.parse('$kApiBaseUrl/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception(_extractError(response) ?? 'Could not create account');
    }
    await _storeSession(json.decode(response.body) as Map<String, dynamic>);
  }

  static Future<void> login({required String email, required String password}) async {
    final response = await AppHttpClient.instance.post(
      Uri.parse('$kApiBaseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode != 200) {
      throw Exception(_extractError(response) ?? 'Invalid email or password');
    }
    await _storeSession(json.decode(response.body) as Map<String, dynamic>);
  }

  /// Revokes the refresh token server-side (best-effort — a network failure here
  /// shouldn't block the user from logging out locally), then clears local storage.
  static Future<void> logout() async {
    final token = await refreshToken;
    if (token != null) {
      try {
        await AppHttpClient.instance.post(
          Uri.parse('$kApiBaseUrl/api/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'refreshToken': token}),
        );
      } catch (_) {
        // Best-effort: still clear the local session even if the network call fails.
      }
    }
    await _storage.deleteAll();
  }

  /// Exchanges the stored refresh token for a new access/refresh pair (rotation —
  /// the old refresh token can never be used again, see docs §4.4). On success,
  /// persists and returns the new access token. On failure, clears the local
  /// session so the rest of the app treats the user as logged out.
  static Future<String?> refreshAccessToken() async {
    final token = await refreshToken;
    if (token == null) return null;

    final response = await AppHttpClient.instance.post(
      Uri.parse('$kApiBaseUrl/api/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'refreshToken': token}),
    );

    if (response.statusCode != 200) {
      await _storage.deleteAll();
      return null;
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    await _storage.write(_accessTokenKey, body['accessToken'] as String);
    await _storage.write(_refreshTokenKey, body['refreshToken'] as String);
    return body['accessToken'] as String;
  }

  static Future<void> _storeSession(Map<String, dynamic> body) async {
    await _storage.write(_accessTokenKey, body['accessToken'] as String);
    await _storage.write(_refreshTokenKey, body['refreshToken'] as String);
    final user = body['user'] as Map<String, dynamic>?;
    if (user != null && user['email'] != null) {
      await _storage.write(_emailKey, user['email'].toString());
    }
  }

  static String? _extractError(http.Response response) {
    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic>) return body['error']?.toString();
    } catch (_) {
      // Response body wasn't JSON (or wasn't shaped as expected) — fall through
      // to the caller's generic default message.
    }
    return null;
  }
}
