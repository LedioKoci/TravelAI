import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:travelai/services/auth_service.dart';
import 'package:travelai/services/http_client.dart';

import 'test_helpers/in_memory_token_storage.dart';

void main() {
  late InMemoryTokenStorage storage;

  setUp(() {
    storage = InMemoryTokenStorage();
    AuthService.debugOverrideStorage(storage);
  });

  group('isLoggedIn', () {
    test('is false with no session on file', () async {
      expect(await AuthService.isLoggedIn(), isFalse);
    });

    test('is true once a refresh token is stored', () async {
      await storage.write('refresh_token', 'some-refresh-token');
      expect(await AuthService.isLoggedIn(), isTrue);
    });
  });

  group('signup', () {
    test('stores the returned tokens and email on success', () async {
      AppHttpClient.debugOverride(MockClient((request) async {
        expect(request.url.path, '/api/auth/signup');
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['email'], 'a@b.com');
        expect(body['displayName'], 'Ada');
        return http.Response(
          json.encode({
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'user': {'id': 'user-1', 'email': 'a@b.com'},
          }),
          201,
        );
      }));

      await AuthService.signup(email: 'a@b.com', password: 'longenough1', displayName: 'Ada');

      expect(await AuthService.accessToken, 'access-1');
      expect(await AuthService.refreshToken, 'refresh-1');
      expect(await AuthService.email, 'a@b.com');
    });

    test('surfaces the backend error message on failure', () async {
      AppHttpClient.debugOverride(MockClient((request) async {
        return http.Response(json.encode({'error': 'An account with this email already exists'}), 409);
      }));

      expect(
        () => AuthService.signup(email: 'a@b.com', password: 'longenough1'),
        throwsA(predicate((e) => e.toString().contains('already exists'))),
      );
    });
  });

  group('login', () {
    test('stores the returned tokens on success', () async {
      AppHttpClient.debugOverride(MockClient((request) async {
        expect(request.url.path, '/api/auth/login');
        return http.Response(
          json.encode({
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
            'user': {'id': 'user-2', 'email': 'b@b.com'},
          }),
          200,
        );
      }));

      await AuthService.login(email: 'b@b.com', password: 'correctpass1');

      expect(await AuthService.accessToken, 'access-2');
      expect(await AuthService.refreshToken, 'refresh-2');
    });

    test('throws on invalid credentials and stores nothing', () async {
      AppHttpClient.debugOverride(MockClient((request) async {
        return http.Response(json.encode({'error': 'Invalid email or password'}), 401);
      }));

      await expectLater(
        AuthService.login(email: 'b@b.com', password: 'wrongpass'),
        throwsA(predicate((e) => e.toString().contains('Invalid email or password'))),
      );

      expect(await AuthService.accessToken, isNull);
    });
  });

  group('refreshAccessToken', () {
    test('returns null immediately when there is no refresh token', () async {
      expect(await AuthService.refreshAccessToken(), isNull);
    });

    test('rotates to a new pair and persists it on success', () async {
      await storage.write('access_token', 'old-access');
      await storage.write('refresh_token', 'old-refresh');

      AppHttpClient.debugOverride(MockClient((request) async {
        expect(request.url.path, '/api/auth/refresh');
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['refreshToken'], 'old-refresh');
        return http.Response(
          json.encode({'accessToken': 'new-access', 'refreshToken': 'new-refresh'}),
          200,
        );
      }));

      final newToken = await AuthService.refreshAccessToken();

      expect(newToken, 'new-access');
      expect(await AuthService.accessToken, 'new-access');
      expect(await AuthService.refreshToken, 'new-refresh');
    });

    test('clears the local session when the refresh token is rejected', () async {
      await storage.write('access_token', 'old-access');
      await storage.write('refresh_token', 'dead-refresh');

      AppHttpClient.debugOverride(MockClient((request) async {
        return http.Response(json.encode({'error': 'invalid'}), 401);
      }));

      final newToken = await AuthService.refreshAccessToken();

      expect(newToken, isNull);
      expect(await AuthService.accessToken, isNull);
      expect(await AuthService.refreshToken, isNull);
    });
  });

  group('logout', () {
    test('revokes server-side and clears local storage', () async {
      await storage.write('access_token', 'access');
      await storage.write('refresh_token', 'refresh');

      String? calledPath;
      AppHttpClient.debugOverride(MockClient((request) async {
        calledPath = request.url.path;
        return http.Response('', 204);
      }));

      await AuthService.logout();

      expect(calledPath, '/api/auth/logout');
      expect(await AuthService.accessToken, isNull);
      expect(await AuthService.refreshToken, isNull);
    });

    test('still clears local storage even if the network call fails', () async {
      await storage.write('access_token', 'access');
      await storage.write('refresh_token', 'refresh');

      AppHttpClient.debugOverride(MockClient((request) async {
        throw Exception('network down');
      }));

      await AuthService.logout();

      expect(await AuthService.accessToken, isNull);
      expect(await AuthService.refreshToken, isNull);
    });

    test('is a no-op network-wise when there is nothing to revoke', () async {
      var called = false;
      AppHttpClient.debugOverride(MockClient((request) async {
        called = true;
        return http.Response('', 204);
      }));

      await AuthService.logout();

      expect(called, isFalse);
    });
  });
}
