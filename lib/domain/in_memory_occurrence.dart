import '../infrastructure/image_artifacts.dart';
import 'location_snapshot.dart';

/// Complete E1 occurrence retained only in memory.
///
/// The model intentionally has no source, highway, or km fields and contains
/// no persistence or network representation.
final class InMemoryOccurrence {
  const InMemoryOccurrence._({
    required this.idempotencyKey,
    required this.detectedAt,
    required this.location,
    required this.speedKmh,
    required this.confidence,
    required this.image,
  });

  static const double manualConfidence = 1.0;
  static const String potholeDefectClass = 'pothole';

  /// E5 (design E5.9): manual candidates keep [manualConfidence]; model
  /// candidates carry any finite confidence in [0, 1].
  static bool isValidConfidence(double value) =>
      value.isFinite && value >= 0 && value <= 1;

  final String idempotencyKey;
  final DateTime detectedAt;
  final ImmutableLocationSnapshot location;
  final double? speedKmh;
  final double confidence;
  final OwnedPreparedImage image;

  double get latitude => location.point.latitude;

  double get longitude => location.point.longitude;

  double? get accuracyMeters => location.accuracyMeters;

  String get defectClass => potholeDefectClass;

  /// ISO 8601 representation with explicit UTC or local offset information.
  String get detectedAtIso8601 => dateTimeWithOffsetToIso8601(detectedAt);
}

/// Source-independent occurrence creation boundary used by the application.
abstract interface class InMemoryOccurrenceCreator {
  InMemoryOccurrence create({
    required String idempotencyKey,
    required DateTime detectedAt,
    required LocationSnapshot location,
    required String defectClass,
    required double confidence,
    required OwnedPreparedImage image,
  });
}

/// Creates only complete E1 occurrences from already accepted data.
final class InMemoryOccurrenceFactory implements InMemoryOccurrenceCreator {
  const InMemoryOccurrenceFactory();

  @override
  InMemoryOccurrence create({
    required String idempotencyKey,
    required DateTime detectedAt,
    required LocationSnapshot location,
    required String defectClass,
    required double confidence,
    required OwnedPreparedImage image,
  }) {
    if (defectClass != InMemoryOccurrence.potholeDefectClass ||
        !InMemoryOccurrence.isValidConfidence(confidence)) {
      throw const FormatException(
        'Occurrences require pothole and a finite confidence in [0, 1].',
      );
    }
    return _createValidated(
      idempotencyKey: idempotencyKey,
      detectedAt: detectedAt,
      location: location,
      confidence: confidence,
      image: image,
    );
  }

  InMemoryOccurrence createManual({
    required String idempotencyKey,
    required DateTime detectedAt,
    required LocationSnapshot location,
    required OwnedPreparedImage image,
  }) {
    return create(
      idempotencyKey: idempotencyKey,
      detectedAt: detectedAt,
      location: location,
      defectClass: InMemoryOccurrence.potholeDefectClass,
      confidence: InMemoryOccurrence.manualConfidence,
      image: image,
    );
  }

  InMemoryOccurrence _createValidated({
    required String idempotencyKey,
    required DateTime detectedAt,
    required LocationSnapshot location,
    required double confidence,
    required OwnedPreparedImage image,
  }) {
    if (!isUuidV4(idempotencyKey)) {
      throw const FormatException('idempotencyKey must be a valid UUID v4.');
    }

    final immutableLocation = ImmutableLocationSnapshot(
      point: location.point,
      accuracyMeters: location.accuracyMeters,
      speedMetersPerSecond: location.speedMetersPerSecond,
    );

    return InMemoryOccurrence._(
      idempotencyKey: idempotencyKey,
      detectedAt: detectedAt,
      location: immutableLocation,
      speedKmh: speedMetersPerSecondToKmh(
        immutableLocation.speedMetersPerSecond,
      ),
      confidence: confidence,
      image: image,
    );
  }
}

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isUuidV4(String value) => _uuidV4Pattern.hasMatch(value);

String dateTimeWithOffsetToIso8601(DateTime value) {
  if (value.isUtc) {
    return value.toIso8601String();
  }

  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absoluteOffset = offset.abs();
  final hours = absoluteOffset.inHours.toString().padLeft(2, '0');
  final minutes = (absoluteOffset.inMinutes % 60).toString().padLeft(2, '0');
  return '${value.toIso8601String()}$sign$hours:$minutes';
}
