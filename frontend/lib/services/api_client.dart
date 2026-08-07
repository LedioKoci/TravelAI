import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_service.dart';
import 'http_client.dart';

/// Thin authenticated HTTP layer for the backend's protected endpoints
/// (/api/travels, /api/profile). Attaches the access token, and on a 401
/// transparently refreshes it and retries the request exactly once — the caller
/// only ever sees the eventual success or an [AuthRequiredException], never the
/// intermediate expiry. Pair calls to this with a loading state in the UI, per
/// docs/supabase-schema-design.md §4.3 ("the user only sees a loading page").
///
/// Not used for /api/generate-plan, which never requires auth (see
/// applyDepartingFromHomeFallback on the backend) — that call stays a plain,
/// unauthenticated POST in main.dart, optionally carrying the access token.
class ApiClient {
  ApiClient._();

  static Future<http.Response> get(String path) => _send('GET', path);

  static Future<http.Response> post(String path, {Object? body}) => _send('POST', path, body: body);

  static Future<http.Response> patch(String path, {Object? body}) => _send('PATCH', path, body: body);

  static Future<http.Response> delete(String path) => _send('DELETE', path);

  static Future<http.Response> _send(String method, String path, {Object? body}) async {
    final token = await AuthService.accessToken;
    if (token == null) {
      throw const AuthRequiredException();
    }

    var response = await _request(method, path, token, body);

    if (response.statusCode == 401) {
      final newToken = await AuthService.refreshAccessToken();
      if (newToken == null) {
        throw const AuthRequiredException();
      }
      response = await _request(method, path, newToken, body);
      if (response.statusCode == 401) {
        // The brand-new access token was rejected too — something's wrong beyond
        // a simple expiry. Treat it the same as "needs to log in again" rather
        // than looping.
        throw const AuthRequiredException();
      }
    }

    return response;
  }

  static Future<http.Response> _request(String method, String path, String token, Object? body) {
    final uri = Uri.parse('$kApiBaseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final encodedBody = body != null ? json.encode(body) : null;

    switch (method) {
      case 'GET':
        return AppHttpClient.instance.get(uri, headers: headers);
      case 'POST':
        return AppHttpClient.instance.post(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        return AppHttpClient.instance.patch(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return AppHttpClient.instance.delete(uri, headers: headers);
      default:
        throw ArgumentError('Unsupported method: $method');
    }
  }
}
