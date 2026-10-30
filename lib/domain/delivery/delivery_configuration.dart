import 'non_printable_secret.dart';

/// Outcome of reading the complete device credential for one attempt.
///
/// Only [CredentialAvailable] can reach the transport. No variant carries a
/// raw exception.
sealed class CredentialReadResult {
  const CredentialReadResult();
}

final class CredentialAvailable extends CredentialReadResult {
  const CredentialAvailable(this.secret);

  final NonPrintableSecret secret;

  @override
  String toString() => 'CredentialAvailable(<redacted>)';
}

/// No credential is stored.
final class CredentialMissing extends CredentialReadResult {
  const CredentialMissing();

  @override
  String toString() => 'CredentialMissing()';
}

/// A credential exists but violates the minimum E3 shape.
final class CredentialInvalidFormat extends CredentialReadResult {
  const CredentialInvalidFormat();

  @override
  String toString() => 'CredentialInvalidFormat()';
}

/// The secure storage could not be read.
final class CredentialStorageUnavailable extends CredentialReadResult {
  const CredentialStorageUnavailable();

  @override
  String toString() => 'CredentialStorageUnavailable()';
}

/// Consistent destination and credential pair for exactly one attempt.
///
/// [revision] is a process-local, monotonic number. It lets the coordinator
/// confirm, right before opening a socket, that neither value changed since
/// this snapshot was taken. [baseUrl] is the destination already validated by
/// the E3 rules (no occurrence suffix); the transport adapter derives the final
/// address from it.
final class DeliveryConfiguration {
  DeliveryConfiguration({
    required this.revision,
    required this.baseUrl,
    required this.credential,
  }) {
    if (revision < 0) {
      throw ArgumentError('A configuration revision must not be negative.');
    }
  }

  final int revision;
  final Uri baseUrl;
  final NonPrintableSecret credential;

  /// Never renders the destination or the credential.
  @override
  String toString() => 'DeliveryConfiguration(revision: $revision)';
}

/// Result of acquiring a configuration snapshot for one delivery attempt.
sealed class DeliveryConfigurationResult {
  const DeliveryConfigurationResult();
}

final class DeliveryConfigurationAvailable extends DeliveryConfigurationResult {
  const DeliveryConfigurationAvailable(this.configuration);

  final DeliveryConfiguration configuration;

  @override
  String toString() => 'DeliveryConfigurationAvailable(<redacted>)';
}

/// The destination or the credential is not configured.
final class DeliveryConfigurationMissing extends DeliveryConfigurationResult {
  const DeliveryConfigurationMissing();

  @override
  String toString() => 'DeliveryConfigurationMissing()';
}

/// The stored destination no longer satisfies the E3 `BASE_URL` rules.
final class DeliveryDestinationInvalid extends DeliveryConfigurationResult {
  const DeliveryDestinationInvalid();

  @override
  String toString() => 'DeliveryDestinationInvalid()';
}

/// The stored credential is malformed.
final class DeliveryCredentialInvalidFormat
    extends DeliveryConfigurationResult {
  const DeliveryCredentialInvalidFormat();

  @override
  String toString() => 'DeliveryCredentialInvalidFormat()';
}

/// The secure storage was unavailable while taking the snapshot.
final class DeliverySecureStorageUnavailable
    extends DeliveryConfigurationResult {
  const DeliverySecureStorageUnavailable();

  @override
  String toString() => 'DeliverySecureStorageUnavailable()';
}
