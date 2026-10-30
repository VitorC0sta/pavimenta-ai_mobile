import '../../domain/delivery/delivery_decision.dart';
import '../e3_storage_ports.dart';
import 'delivery_configuration_change_port.dart';
import 'delivery_configuration_snapshot_port.dart';
import 'occurrence_delivery_queue_port.dart';

/// Pauses that a corrected destination or credential may resolve.
///
/// `localFailure` is deliberately absent: a local problem (image, storage,
/// keystore) is not fixed by a new URL or key, so that pause stays until an
/// explicit resume.
const Set<DeliveryPauseReason> configurationClearablePauses =
    <DeliveryPauseReason>{
  DeliveryPauseReason.authentication,
  DeliveryPauseReason.access,
  DeliveryPauseReason.unexpectedResponse,
};

/// Applies a save or replacement of `BASE_URL` or of the device credential
/// without letting an old attempt mix with the new value (design E4.4, E4.6).
///
/// For every change that is written, in this order:
///
/// 1. the old attempt is cancelled or suspended through
///    [DeliveryConfigurationChangePort], before anything is written;
/// 2. the write runs under the exclusion of
///    [DeliveryConfigurationSnapshotPort], so no snapshot can observe half of
///    the new pair;
/// 3. once the write is confirmed, and still under the exclusion, only the
///    `authentication`, `access` and `unexpectedResponse` pauses are cleared
///    in the persisted control, so the correction survives a restart;
/// 4. the exclusion is released and exactly one immediate evaluation is
///    requested.
///
/// A failed write clears nothing, rethrows to the caller, and still ends the
/// suspension with that single evaluation request. Failures of the clearing
/// or of the evaluation request never turn a confirmed write into a failure:
/// the operator can still resume manually.
///
/// This type never receives, keeps, or formats a URL or a credential: the
/// value is written by the callback its caller supplies.
///
/// It is the E4 implementation of the E3 [ConfigurationChangeGuard] port, so
/// the E3 use cases depend only on their own port and never on delivery.
final class DeliveryConfigurationChangeService
    implements ConfigurationChangeGuard {
  DeliveryConfigurationChangeService({
    required DeliveryConfigurationSnapshotPort snapshot,
    required OccurrenceDeliveryQueuePort queue,
    required DeliveryConfigurationChangePort delivery,
  })  : _snapshot = snapshot,
        _queue = queue,
        _delivery = delivery;

  final DeliveryConfigurationSnapshotPort _snapshot;
  final OccurrenceDeliveryQueuePort _queue;
  final DeliveryConfigurationChangePort _delivery;

  /// Runs [write], which saves or replaces the credential or the destination,
  /// as a configuration change.
  @override
  Future<T> replaceDestinationOrCredential<T>(Future<T> Function() write) {
    return _applyChange<T>(write, clearsPauses: true);
  }

  /// Runs [remove], which deletes the stored credential, as a configuration
  /// change that never corrects anything.
  ///
  /// The attempt that uses the old credential is suspended before the removal
  /// and one evaluation is requested afterwards, so the coordinator can
  /// publish `configurationRequired`. No pause is cleared: removing a value
  /// does not fix an authentication, access or unexpected-response pause. The
  /// removal itself opens no connection (design E4.10).
  @override
  Future<T> removeCredential<T>(Future<T> Function() remove) {
    return _applyChange<T>(remove, clearsPauses: false);
  }

  /// Runs [write], which saves the whole non-secret configuration document,
  /// and treats it as a configuration change only when the destination moves.
  ///
  /// [readCurrentBaseUrl] returns the destination stored now and [newBaseUrl]
  /// the one [write] will store. When both are equal the write is an
  /// operational-only edit (cooldown, distance, confidence, FPS): it neither
  /// touches a running attempt, nor clears a pause, nor requests an
  /// evaluation. When the current destination cannot be read, the write is
  /// handled as a change.
  ///
  /// A new destination of `null` is a removal, not a correction: the attempt
  /// is still suspended before the write and an evaluation is requested
  /// afterwards, but no pause is cleared.
  @override
  Future<T> saveOperationalConfiguration<T>({
    required Future<Uri?> Function() readCurrentBaseUrl,
    required Uri? newBaseUrl,
    required Future<T> Function() write,
  }) async {
    var destinationMoves = true;
    try {
      destinationMoves = (await readCurrentBaseUrl()) != newBaseUrl;
    } on Object {
      // The caught object is discarded; the safe reading is "changed".
    }
    if (!destinationMoves) {
      return write();
    }
    return _applyChange<T>(write, clearsPauses: newBaseUrl != null);
  }

  Future<T> _applyChange<T>(
    Future<T> Function() write, {
    required bool clearsPauses,
  }) async {
    try {
      await _delivery.suspendForConfigurationChange();
      return await _snapshot.runConfigurationMutation<T>(() async {
        final result = await write();
        if (clearsPauses) {
          await _clearApplicablePauses();
        }
        return result;
      });
    } finally {
      _requestEvaluation();
    }
  }

  /// Clears the persisted pause only when its reason is one that a corrected
  /// configuration can resolve. Any failure leaves the pause as it was.
  Future<void> _clearApplicablePauses() async {
    try {
      final control = await _queue.readControl();
      if (control is DeliveryControlPaused &&
          configurationClearablePauses.contains(control.reason)) {
        await _queue.resume();
      }
    } on Object {
      // The caught object is discarded; the pause simply stays.
    }
  }

  void _requestEvaluation() {
    try {
      _delivery.onConfigurationChanged();
    } on Object {
      // The caught object is discarded; the next trigger evaluates anyway.
    }
  }
}
