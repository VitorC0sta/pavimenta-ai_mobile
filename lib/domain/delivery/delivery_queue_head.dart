import 'delivery_decision.dart';

/// Opaque reference to the durable JPEG of a queued occurrence.
///
/// Only the byte length (needed for the request size) is readable. The handle
/// is meaningful solely to the queue implementation that produced it and never
/// exposes a path, a digest, or bytes.
final class DeliveryImageRef {
  DeliveryImageRef({required this.byteLength, required this.opaqueHandle}) {
    if (byteLength <= 0) {
      throw ArgumentError('An image length must be positive.');
    }
  }

  final int byteLength;
  final Object opaqueHandle;

  @override
  String toString() => 'DeliveryImageRef(<redacted>)';
}

/// Canonical persisted values that an attempt transmits.
///
/// Values are carried exactly as persisted: an absent [speedKmh] stays `null`
/// while an explicit zero stays a valid value. This model is internal to the
/// delivery boundary and never reaches presentation.
final class DeliveryOccurrencePayload {
  const DeliveryOccurrencePayload({
    required this.detectedAtIso8601,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.confidence,
    required this.defectClass,
    required this.image,
  });

  final String detectedAtIso8601;
  final double latitude;
  final double longitude;
  final double? speedKmh;
  final double confidence;
  final String defectClass;
  final DeliveryImageRef image;

  @override
  String toString() => 'DeliveryOccurrencePayload(<redacted>)';
}

/// Identity and delivery state of the FIFO head of the queue.
final class DeliveryQueueHead {
  DeliveryQueueHead({
    required this.idempotencyKey,
    required this.queueSequence,
    this.attemptCount = 0,
    this.cleanupAttemptCount = 0,
  }) {
    if (idempotencyKey.isEmpty ||
        queueSequence < 1 ||
        attemptCount < 0 ||
        cleanupAttemptCount < 0) {
      throw ArgumentError('Invalid delivery queue head.');
    }
  }

  final String idempotencyKey;
  final int queueSequence;

  /// Consecutive recoverable failures recorded for this item.
  final int attemptCount;

  /// Failed local cleanup attempts after a definitive decision.
  final int cleanupAttemptCount;

  @override
  String toString() => 'DeliveryQueueHead(<redacted>)';
}

/// What the queue reports when asked for the next item to deliver.
sealed class DeliveryHeadResult {
  const DeliveryHeadResult();
}

/// The queue could not be used.
final class DeliveryQueueUnavailable extends DeliveryHeadResult {
  const DeliveryQueueUnavailable();

  @override
  String toString() => 'DeliveryQueueUnavailable()';
}

/// There is nothing to deliver.
final class DeliveryQueueEmpty extends DeliveryHeadResult {
  const DeliveryQueueEmpty();

  @override
  String toString() => 'DeliveryQueueEmpty()';
}

/// The head may be attempted now.
final class DeliveryHeadEligible extends DeliveryHeadResult {
  const DeliveryHeadEligible({required this.head, required this.payload});

  final DeliveryQueueHead head;
  final DeliveryOccurrencePayload payload;

  @override
  String toString() => 'DeliveryHeadEligible(<redacted>)';
}

/// The head waits for its backoff; later items must not overtake it.
final class DeliveryHeadInBackoff extends DeliveryHeadResult {
  const DeliveryHeadInBackoff(
      {required this.head, required this.nextAttemptAt});

  final DeliveryQueueHead head;
  final DateTime nextAttemptAt;

  @override
  String toString() => 'DeliveryHeadInBackoff(<redacted>)';
}

/// A definitive remote decision was recorded; only local removal remains.
///
/// [dueAt] is `null` when the cleanup may run now.
final class DeliveryHeadPendingCleanup extends DeliveryHeadResult {
  const DeliveryHeadPendingCleanup({
    required this.head,
    required this.disposition,
    this.dueAt,
  });

  final DeliveryQueueHead head;
  final DeliveryDisposition disposition;
  final DateTime? dueAt;

  @override
  String toString() => 'DeliveryHeadPendingCleanup(<redacted>)';
}

/// The head image is missing or invalid; no network call may be made.
final class DeliveryHeadLocalIntegrityFailure extends DeliveryHeadResult {
  const DeliveryHeadLocalIntegrityFailure({required this.head});

  final DeliveryQueueHead head;

  @override
  String toString() => 'DeliveryHeadLocalIntegrityFailure(<redacted>)';
}
