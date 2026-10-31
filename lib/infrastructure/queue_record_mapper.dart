import '../domain/persistent_occurrence.dart';

/// Canonical SQLite column names for the E2 queue schema.
abstract final class QueueRecordColumns {
  static const String queueSequence = 'queueSequence';
  static const String idempotencyKey = 'idempotencyKey';
  static const String detectedAtIso8601 = 'detectedAtIso8601';
  static const String latitude = 'latitude';
  static const String longitude = 'longitude';
  static const String accuracyMeters = 'accuracyMeters';
  static const String speedKmh = 'speedKmh';
  static const String confidence = 'confidence';
  static const String defectClass = 'defectClass';
  static const String imageRelativeName = 'imageRelativeName';
  static const String imageMimeType = 'imageMimeType';
  static const String imageByteLength = 'imageByteLength';
  static const String imageSha256 = 'imageSha256';
  static const String imageWidth = 'imageWidth';
  static const String imageHeight = 'imageHeight';
  static const String imageQuality = 'imageQuality';

  static const List<String> all = <String>[
    queueSequence,
    idempotencyKey,
    detectedAtIso8601,
    latitude,
    longitude,
    accuracyMeters,
    speedKmh,
    confidence,
    defectClass,
    imageRelativeName,
    imageMimeType,
    imageByteLength,
    imageSha256,
    imageWidth,
    imageHeight,
    imageQuality,
  ];
}

/// Maps confirmed E2 records without regenerating or normalizing their values.
final class QueueRecordMapper {
  const QueueRecordMapper();

  /// Values used for an insert whose sequence is assigned by SQLite.
  Map<String, Object?> toInsertMap(QueueRecordProjection record) =>
      <String, Object?>{
        QueueRecordColumns.idempotencyKey: record.idempotencyKey,
        QueueRecordColumns.detectedAtIso8601: record.detectedAtIso8601,
        QueueRecordColumns.latitude: record.latitude,
        QueueRecordColumns.longitude: record.longitude,
        QueueRecordColumns.accuracyMeters: record.accuracyMeters,
        QueueRecordColumns.speedKmh: record.speedKmh,
        QueueRecordColumns.confidence: record.confidence,
        QueueRecordColumns.defectClass: record.defectClass,
        QueueRecordColumns.imageRelativeName: record.image.relativeName,
        QueueRecordColumns.imageMimeType: record.image.mimeType,
        QueueRecordColumns.imageByteLength: record.image.byteLength,
        QueueRecordColumns.imageSha256: record.image.sha256,
        QueueRecordColumns.imageWidth: record.image.width,
        QueueRecordColumns.imageHeight: record.image.height,
        QueueRecordColumns.imageQuality: record.image.quality,
      };

  /// Reconstructs exactly the values stored in one confirmed SQLite row.
  QueueRecordProjection fromMap(Map<String, Object?> row) {
    return QueueRecordProjection(
      queueSequence: _requiredInt(row, QueueRecordColumns.queueSequence),
      idempotencyKey: _requiredString(row, QueueRecordColumns.idempotencyKey),
      detectedAtIso8601:
          _requiredString(row, QueueRecordColumns.detectedAtIso8601),
      latitude: _requiredDouble(row, QueueRecordColumns.latitude),
      longitude: _requiredDouble(row, QueueRecordColumns.longitude),
      accuracyMeters: _nullableDouble(row, QueueRecordColumns.accuracyMeters),
      speedKmh: _nullableDouble(row, QueueRecordColumns.speedKmh),
      confidence: _requiredConfidence(row),
      defectClass: _requiredString(row, QueueRecordColumns.defectClass),
      image: PersistedImageProjection(
        relativeName:
            _requiredString(row, QueueRecordColumns.imageRelativeName),
        mimeType: _requiredString(row, QueueRecordColumns.imageMimeType),
        byteLength: _requiredInt(row, QueueRecordColumns.imageByteLength),
        sha256: _requiredString(row, QueueRecordColumns.imageSha256),
        width: _requiredInt(row, QueueRecordColumns.imageWidth),
        height: _requiredInt(row, QueueRecordColumns.imageHeight),
        quality: _requiredInt(row, QueueRecordColumns.imageQuality),
      ),
    );
  }
}

String _requiredString(Map<String, Object?> row, String column) {
  final value = row[column];
  if (value is! String) {
    throw FormatException('Invalid persisted value for $column.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> row, String column) {
  final value = row[column];
  if (value is! int) {
    throw FormatException('Invalid persisted value for $column.');
  }
  return value;
}

double _requiredDouble(Map<String, Object?> row, String column) {
  final value = row[column];
  if (value is! num) {
    throw FormatException('Invalid persisted value for $column.');
  }
  return value.toDouble();
}

/// Schema v3 (E5): manual `1.0` or a model confidence, always finite in
/// [0, 1].
double _requiredConfidence(Map<String, Object?> row) {
  final value = _requiredDouble(row, QueueRecordColumns.confidence);
  if (!value.isFinite || value < 0 || value > 1) {
    throw const FormatException(
      'Invalid persisted value for ${QueueRecordColumns.confidence}.',
    );
  }
  return value;
}

double? _nullableDouble(Map<String, Object?> row, String column) {
  final value = row[column];
  if (value == null) {
    return null;
  }
  if (value is! num) {
    throw FormatException('Invalid persisted value for $column.');
  }
  return value.toDouble();
}
