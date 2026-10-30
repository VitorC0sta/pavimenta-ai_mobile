import '../../domain/delivery/delivery_decision.dart';
import '../../domain/delivery/delivery_queue_head.dart';
import '../../domain/persistent_occurrence.dart';
import '../e2_persistence_ports.dart';

/// Aggregate-only queue summary published to observers.
///
/// It is the E2 snapshot: health and counts, never records, identifiers,
/// paths, digests, coordinates, or timestamps.
typedef DeliveryQueueSummary = QueueSnapshot;

/// Outcome of a delivery-state mutation in the queue.
enum DeliveryMutationResult {
  /// The change was durably applied.
  applied,

  /// The item no longer exists (for example it was already removed).
  notFound,

  /// The change could not be persisted; nothing was changed.
  storageFailure,
}

/// Persisted pause control of the delivery.
///
/// Carries only closed values. [DeliveryControlPaused.unexpectedStatusCode]
/// exists solely for technical diagnosis of an unexpected response.
sealed class DeliveryControl {
  const DeliveryControl();
}

/// Automatic delivery is allowed.
final class DeliveryControlRunning extends DeliveryControl {
  const DeliveryControlRunning();

  @override
  String toString() => 'DeliveryControlRunning()';
}

/// Automatic delivery is stopped until an explicit resume.
final class DeliveryControlPaused extends DeliveryControl {
  /// [unexpectedStatusCode] is allowed only for
  /// [DeliveryPauseReason.unexpectedResponse].
  DeliveryControlPaused(this.reason, {this.unexpectedStatusCode}) {
    if ((unexpectedStatusCode != null) !=
        (reason == DeliveryPauseReason.unexpectedResponse)) {
      throw ArgumentError(
        'A status code is required for, and only for, an unexpected response.',
      );
    }
  }

  final DeliveryPauseReason reason;
  final int? unexpectedStatusCode;

  @override
  String toString() => unexpectedStatusCode == null
      ? 'DeliveryControlPaused(${reason.name})'
      : 'DeliveryControlPaused(${reason.name}, $unexpectedStatusCode)';
}

/// The persisted control could not be read.
final class DeliveryControlUnavailable extends DeliveryControl {
  const DeliveryControlUnavailable();

  @override
  String toString() => 'DeliveryControlUnavailable()';
}

/// Delivery view of the persistent FIFO queue (design E4.4).
///
/// Implementations serialize every operation with the existing queue
/// coordination and never keep that serial region locked while the network is
/// in use: [nextHead] returns an immutable projection. Only the delivery
/// coordinator concludes the selected item.
///
/// No method accepts or returns a path, digest, or raw image buffer. Failures
/// are reported through the typed results below, never through exception text
/// that callers would forward to logs or presentation.
abstract interface class OccurrenceDeliveryQueuePort {
  /// Selects the FIFO head as of [now].
  ///
  /// The queue, not the caller, decides whether the head is eligible, in
  /// backoff, pending local cleanup, or inconsistent. Later items never
  /// overtake the head.
  Future<DeliveryHeadResult> nextHead(DateTime now);

  /// Opens a single-subscription stream of the JPEG bytes of [head].
  ///
  /// The total length equals `head.payload.image.byteLength`. A read failure
  /// is delivered as a stream error and handled as a local failure.
  Stream<List<int>> openImage(DeliveryHeadEligible head);

  /// Records one more consecutive recoverable failure for [idempotencyKey]
  /// with the instant the backoff was computed and the next allowed attempt.
  Future<DeliveryMutationResult> recordRecoverableFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextAttemptAt,
  );

  /// Durably records the definitive remote [disposition] before any local
  /// removal starts, so a restart finishes the removal without resending.
  Future<DeliveryMutationResult> recordDefinitiveDecision(
    String idempotencyKey,
    DeliveryDisposition disposition,
  );

  /// Removes the row and JPEG of an item whose definitive decision was
  /// recorded. Idempotent; never touches the network.
  Future<QueueRemovalResult> completePendingLocalRemoval(String idempotencyKey);

  /// Records a failed local cleanup and the next allowed cleanup instant.
  Future<DeliveryMutationResult> recordCleanupFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextCleanupAt,
  );

  /// Reads the persisted global pause control.
  Future<DeliveryControl> readControl();

  /// Persists an automatic pause. Resume is the only way to clear it.
  Future<DeliveryMutationResult> pause(PausedDeliveryDecision pause);

  /// Clears the persisted pause.
  Future<DeliveryMutationResult> resume();

  /// Aggregate summaries of the queue, without occurrence data.
  Stream<DeliveryQueueSummary> watchSummary();
}
