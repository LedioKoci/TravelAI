import 'package:http/http.dart' as http;

/// A single, shared, overridable HTTP client used by every network-facing
/// service (AuthService, ApiClient, and the generate-plan call in main.dart).
/// Having one seam lets tests stub the entire backend surface — auth included —
/// with a single `http.testing.MockClient`, instead of each service needing its
/// own override mechanism.
class AppHttpClient {
  AppHttpClient._();

  static http.Client instance = http.Client();

  /// Test-only: swap the real client for a fake/mock one.
  static void debugOverride(http.Client client) {
    instance = client;
  }
}
