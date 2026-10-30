import 'dart:async';

import '../../domain/configuration_validators.dart';
import '../../domain/delivery/delivery_configuration.dart';
import '../../domain/delivery/delivery_configuration_revalidation.dart';
import '../e3_storage_ports.dart';
import 'delivery_configuration_snapshot_port.dart';
import 'device_credential_read_port.dart';

/// Process-local implementation of [DeliveryConfigurationSnapshotPort]
/// (design E4.4).
///
/// A single first-in-first-out exclusion serializes [readForAttempt] and
/// [runConfigurationMutation]. While a mutation holds the exclusion, no
/// snapshot can observe a half-written pair, and while a snapshot is being
/// acquired, no mutation can change one half of it. A snapshot therefore
/// contains the destination and the credential of one revision only.
///
/// The revision is a monotonic in-memory counter. It does not survive the
/// process: after a restart there is no earlier request, and the next snapshot
/// reads both stores again. The credential is read only through the E4-only
/// [DeviceCredentialReadPort], only after a destination exists and passes the
/// E3 `BASE_URL` rules again, and only inside the exclusion. The credential's
/// `prefix.secret` shape is checked again too. Any failure yields a typed,
/// secret-free result (missing, invalid destination, invalid format, or secure
/// storage unavailable), so the caller never opens an image or a socket for
/// it. The credential is wrapped by the domain secret type and is never
/// cached, formatted, or logged here.
///
/// A mutation action must not call [readForAttempt] or
/// [runConfigurationMutation] on the same instance: the exclusion is not
/// re-entrant and doing so would wait for itself forever.
final class ExclusiveDeliveryConfigurationSnapshot
    implements DeliveryConfigurationSnapshotPort {
  ExclusiveDeliveryConfigurationSnapshot({
    required OperationalConfigurationRepository configurationRepository,
    required DeviceCredentialReadPort credentialReader,
    required ConfigurationBuildVariant buildVariant,
  })  : _configurationRepository = configurationRepository,
        _credentialReader = credentialReader,
        _buildVariant = buildVariant;

  final OperationalConfigurationRepository _configurationRepository;
  final DeviceCredentialReadPort _credentialReader;
  final ConfigurationBuildVariant _buildVariant;

  Future<void> _tail = Future<void>.value();
  int _revision = 0;
  bool _mutationRunning = false;

  /// The current local revision; it only grows.
  int get revision => _revision;

  @override
  Future<DeliveryConfigurationResult> readForAttempt() =>
      _exclusively(_acquireSnapshot);

  @override
  Future<T> runConfigurationMutation<T>(Future<T> Function() action) {
    return _exclusively(() async {
      _mutationRunning = true;
      try {
        return await action();
      } finally {
        // Advance even when the action fails: a partial write may have
        // happened, so every earlier snapshot must stop being current.
        _revision++;
        _mutationRunning = false;
      }
    });
  }

  /// A snapshot is current only while its revision is the latest and no
  /// mutation is writing, so a socket is never opened for a pair that is being
  /// replaced.
  @override
  bool isCurrent(int revision) => !_mutationRunning && revision == _revision;

  Future<DeliveryConfigurationResult> _acquireSnapshot() async {
    final Uri? storedUrl;
    try {
      storedUrl = (await _configurationRepository.load()).baseUrl;
    } on Object {
      // The caught object is discarded; the destination is unusable.
      return const DeliveryConfigurationMissing();
    }
    if (storedUrl == null) {
      return const DeliveryConfigurationMissing();
    }

    // Revalidate with the E3 rules before anything else is touched: an invalid
    // destination never causes a credential read, an image read, or a socket.
    final baseUrl = DeliveryConfigurationRevalidation.validatedDestination(
      storedUrl,
      buildVariant: _buildVariant,
    );
    if (baseUrl == null) {
      return const DeliveryDestinationInvalid();
    }

    final CredentialReadResult credential;
    try {
      credential = await _credentialReader.readForDelivery();
    } on Object {
      return const DeliverySecureStorageUnavailable();
    }

    return switch (credential) {
      // The reader already classifies the shape; checking again here keeps the
      // guarantee independent of any particular reader implementation.
      CredentialAvailable(:final secret)
          when !DeliveryConfigurationRevalidation.hasValidCredentialShape(
            secret,
          ) =>
        const DeliveryCredentialInvalidFormat(),
      CredentialAvailable(:final secret) => DeliveryConfigurationAvailable(
          DeliveryConfiguration(
            revision: _revision,
            baseUrl: baseUrl,
            credential: secret,
          ),
        ),
      CredentialMissing() => const DeliveryConfigurationMissing(),
      CredentialInvalidFormat() => const DeliveryCredentialInvalidFormat(),
      CredentialStorageUnavailable() =>
        const DeliverySecureStorageUnavailable(),
    };
  }

  /// Runs [body] after every earlier exclusive section has finished. A failure
  /// is reported to its own caller only and never blocks later sections.
  Future<T> _exclusively<T>(Future<T> Function() body) {
    final previous = _tail;
    final result = Completer<T>();
    _tail = result.future.then<void>((_) {}, onError: (Object _) {});
    previous.then<void>((_) async {
      try {
        result.complete(await body());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
