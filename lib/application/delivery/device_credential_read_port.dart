import '../../domain/delivery/delivery_configuration.dart';

/// E4-only capability for consuming the complete device credential (design
/// E4.4).
///
/// E3 widgets, controllers, and state depend exclusively on
/// `DeviceCredentialStatusPort`. Only the E4 delivery boundary may receive this
/// narrow port.
abstract interface class DeviceCredentialReadPort {
  /// Reads the stored credential for one delivery attempt.
  ///
  /// Never throws for storage problems. The result is [CredentialAvailable]
  /// (wrapped in a non-printable secret), [CredentialMissing],
  /// [CredentialInvalidFormat] (not `prefix.secret`), or
  /// [CredentialStorageUnavailable]. No variant carries the raw value or a raw
  /// exception.
  Future<CredentialReadResult> readForDelivery();
}
