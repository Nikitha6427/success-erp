import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Somewhere to keep the OAuth refresh token.
///
/// Behind an interface because it is the thing that makes a session survive a
/// restart — the exact behaviour AGENTS.md §9 says must be provable rather than
/// eyeballed. A test can supply an in-memory implementation and replay cold
/// starts; the plugin cannot be driven that way.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production implementation: Android Keystore / iOS Keychain.
class SecureSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;

  const SecureSecretStore([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
