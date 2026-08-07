import 'package:travelai/services/token_storage.dart';

/// A [TokenStorage] test double backed by a plain in-memory map, so tests never
/// touch the real platform secure-storage channel (which has no handler
/// registered under plain `flutter test`).
class InMemoryTokenStorage implements TokenStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}
