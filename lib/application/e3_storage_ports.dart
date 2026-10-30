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
/// port. The restricted E4 consumption boundary is `DeviceCredentialReadPort`
/// in `application/delivery/`.
abstract interface class DeviceCredentialStatusPort {
  Future<bool> hasCredential();

  Future<void> saveCredential(String credential);

  Future<void> removeCredential();
}

/// E3 boundary through which a configuration write is applied as a change
/// that other stages may need to observe.
///
/// E3 declares the capability and E4 implements it (design E4.4, E4.6), so
/// the E3 use cases never depend on delivery. Each method runs the supplied
/// callback, which performs the actual write; the guard never receives,
/// keeps, or formats a URL or a credential. A failed callback is rethrown to
/// the caller.
abstract interface class ConfigurationChangeGuard {
  /// Runs [write], which saves the whole non-secret configuration document.
  ///
  /// [readCurrentBaseUrl] returns the destination stored now and [newBaseUrl]
  /// the one [write] will store. When both are equal the write is an
  /// operational-only edit and is not treated as a change. When the current
  /// destination cannot be read, the write is handled as a change. A
  /// [newBaseUrl] of `null` is a removal, not a correction.
  Future<T> saveOperationalConfiguration<T>({
    required Future<Uri?> Function() readCurrentBaseUrl,
    required Uri? newBaseUrl,
    required Future<T> Function() write,
  });

  /// Runs [write], which saves or replaces the credential or the destination,
  /// as a configuration change that may correct a previous problem.
  Future<T> replaceDestinationOrCredential<T>(Future<T> Function() write);

  /// Runs [remove], which deletes the stored credential, as a configuration
  /// change that never corrects anything.
  Future<T> removeCredential<T>(Future<T> Function() remove);
}
