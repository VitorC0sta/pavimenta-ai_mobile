import '../domain/operational_configuration.dart';

/// Minimal key-value boundary for non-secret E3 configuration data.
///
/// This port deliberately contains no configuration schema. Task 56 owns the
/// versioned configuration repository built on top of it.
abstract interface class PreferencesStore {
  Future<String?> getString(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

/// Persistence boundary for the versioned, non-secret E3 configuration.
///
/// The configuration document deliberately excludes the device API key. Its
/// separate secure-store boundary is defined below.
abstract interface class OperationalConfigurationRepository {
  Future<OperationalConfiguration> load();

  Future<void> save(OperationalConfiguration configuration);
}

/// Presentation-safe credential capability for E3.
///
/// A caller can determine whether a credential exists, submit a replacement,
/// or remove it. It cannot read the complete credential back through this
/// port. E4 will introduce its own restricted consumption boundary when an
/// authenticated occurrence client actually exists.
abstract interface class DeviceCredentialStatusPort {
  Future<bool> hasCredential();

  Future<void> saveCredential(String credential);

  Future<void> removeCredential();
}

/// E4-only capability for consuming the complete device credential.
///
/// E3 widgets, controllers, and state must depend exclusively on
/// [DeviceCredentialStatusPort]. The future occurrence client may receive this
/// narrow port when E4 introduces authenticated transport.
abstract interface class DeviceCredentialReadPort {
  Future<String?> readCredential();
}
