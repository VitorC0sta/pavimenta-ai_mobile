import '../../domain/delivery/delivery_configuration.dart';

/// Consistent view of destination and credential for delivery (design E4.4).
///
/// Starting an attempt and mutating the destination or the credential are
/// mutually exclusive within the process. Every snapshot carries a monotonic,
/// process-local revision, so an attempt uses entirely the old pair or entirely
/// the new pair, never a mix.
abstract interface class DeliveryConfigurationSnapshotPort {
  /// Reads destination and credential as one consistent snapshot.
  ///
  /// The destination is revalidated against the E3 `BASE_URL` rules and the
  /// credential against the minimum `prefix.secret` shape as part of this
  /// read. Absence or invalidity, and a secure storage failure, are typed
  /// results that must not lead to opening the image or a socket.
  ///
  /// Only [DeliveryConfigurationAvailable] may reach the transport. No result
  /// carries a raw exception, and the credential is wrapped so that it cannot
  /// be printed.
  Future<DeliveryConfigurationResult> readForAttempt();

  /// Runs [action], which writes the destination or the credential, under the
  /// same exclusion used by [readForAttempt].
  ///
  /// The revision advances once [action] has changed the configuration, so
  /// every earlier snapshot stops being current.
  Future<T> runConfigurationMutation<T>(Future<T> Function() action);

  /// Whether [revision] is still the current configuration revision.
  ///
  /// The coordinator checks this immediately before opening a socket.
  bool isCurrent(int revision);
}
