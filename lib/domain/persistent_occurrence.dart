/// Availability and integrity state exposed by the persistent queue.
enum QueueHealth { initializing, ready, degraded, unavailable }

/// Immutable metadata for one JPEG owned by the persistent queue.
///
/// Only an opaque relative name is retained. Absolute paths and image bytes
/// deliberately do not belong to this projection.
final class PersistedImageProjection {
  const PersistedImageProjection({
    required this.relativeName,
    required this.mimeType,
    required this.byteLength,
    required this.sha256,
    required this.width,
    required this.height,
    required this.quality,
  });

  final String relativeName;
  final String mimeType;
  final int byteLength;
  final String sha256;
  final int width;
  final int height;
  final int quality;
}

/// Immutable canonical representation of one confirmed queue row.
///
/// Values are stored exactly as accepted. In particular, nullable numeric
/// values remain absent while an explicit zero remains distinct and valid.
/// This persistence projection is not exposed by [QueueSnapshot].
final class QueueRecordProjection {
  const QueueRecordProjection({
    required this.queueSequence,
    required this.idempotencyKey,
    required this.detectedAtIso8601,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.speedKmh,
    required this.confidence,
    required this.defectClass,
    required this.image,
  });

  final int queueSequence;
  final String idempotencyKey;
  final String detectedAtIso8601;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? speedKmh;
  final double confidence;
  final String defectClass;
  final PersistedImageProjection image;
}

/// Pending occurrence reconstructed from a confirmed canonical record.
///
/// The wrapper makes reconstruction explicit without duplicating or
/// recalculating any persisted value.
final class ReconstructedPendingOccurrence {
  const ReconstructedPendingOccurrence(this.record);

  final QueueRecordProjection record;

  int get queueSequence => record.queueSequence;
  String get idempotencyKey => record.idempotencyKey;
  String get detectedAtIso8601 => record.detectedAtIso8601;
  double get latitude => record.latitude;
  double get longitude => record.longitude;
  double? get accuracyMeters => record.accuracyMeters;
  double? get speedKmh => record.speedKmh;
  double get confidence => record.confidence;
  String get defectClass => record.defectClass;
  PersistedImageProjection get image => record.image;
}

/// Durable reference of the last accepted occurrence, kept for the cooldown.
///
/// It survives the removal of every pending occurrence. It carries only the
/// canonical operational values the cooldown rule needs, never image data or
/// identifiers, and is not exposed by [QueueSnapshot].
final class AcceptedOccurrenceAnchor {
  const AcceptedOccurrenceAnchor({
    required this.queueSequence,
    required this.detectedAtIso8601,
    required this.latitude,
    required this.longitude,
  });

  final int queueSequence;
  final String detectedAtIso8601;
  final double latitude;
  final double longitude;
}

/// Sanitized immutable state published to observers and presentation.
///
/// It exposes only queue health and aggregate counts, never records, paths,
/// identifiers, digests, coordinates, timestamps, or image bytes.
final class QueueSnapshot {
  const QueueSnapshot({
    required this.health,
    required this.pendingCount,
    this.attentionCount = 0,
  })  : assert(pendingCount >= 0),
        assert(attentionCount >= 0);

  const QueueSnapshot.initializing()
      : health = QueueHealth.initializing,
        pendingCount = 0,
        attentionCount = 0;

  final QueueHealth health;
  final int pendingCount;
  final int attentionCount;

  bool get isReady => health == QueueHealth.ready;
}
