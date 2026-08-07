import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over secure token persistence, so AuthService can be exercised in
/// widget/unit tests without hitting the real platform secure-storage channel
/// (which has no handler registered under plain `flutter test`).
abstract class TokenStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Production implementation: OS-level encrypted storage (Keychain on iOS,
/// EncryptedSharedPreferences on Android, etc.) via flutter_secure_storage.
class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
