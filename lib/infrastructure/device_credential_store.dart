import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/e3_storage_ports.dart';

/// Minimal backend seam for the Android secure-storage plugin.
///
/// It exposes status, write, and deletion to E3. Complete-value reads are
/// available solely through the E4-only credential-consumption port.
abstract interface class SecureCredentialBackend {
  Future<bool> containsKey(String key);

  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Android implementation of [SecureCredentialBackend].
///
/// The non-secret storage name and key are stable so task 54.4 can exclude the
/// real plugin artifact from backup and data extraction without affecting E2.
final class FlutterSecureCredentialBackend implements SecureCredentialBackend {
  FlutterSecureCredentialBackend({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                sharedPreferencesName: storageName,
                preferencesKeyPrefix: storageKeyPrefix,
              ),
            );

  static const storageName = 'pavimenta_ai_mobile_secure_storage';
  static const storageKeyPrefix = 'pavimenta_ai.';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Secure credential adapter exposed to E3 and the future E4 consumer.
///
/// E3 code receives [DeviceCredentialStatusPort] only. The complete value
/// crosses [saveCredential] into the secure backend or the E4-only
/// [DeviceCredentialReadPort]; it is never cached, formatted, or logged.
final class DeviceCredentialStore
    implements DeviceCredentialStatusPort, DeviceCredentialReadPort {
  DeviceCredentialStore({SecureCredentialBackend? backend})
      : _backend = backend ?? FlutterSecureCredentialBackend();

  static const credentialKey = 'device_api_key_v1';

  final SecureCredentialBackend _backend;

  @override
  Future<bool> hasCredential() => _backend.containsKey(credentialKey);

  @override
  Future<String?> readCredential() => _backend.read(credentialKey);

  @override
  Future<void> removeCredential() => _backend.delete(credentialKey);

  @override
  Future<void> saveCredential(String credential) =>
      _backend.write(credentialKey, credential);
}
