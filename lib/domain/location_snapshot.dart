/// Geographic point consumed by E1 domain contracts.
abstract interface class GeoPoint {
  double get latitude;

  double get longitude;
}

/// Latest immutable location view accepted by the operational flow.
abstract interface class LocationSnapshot {
  GeoPoint get point;

  double? get accuracyMeters;

  double? get speedMetersPerSecond;
}

/// Immutable, validated geographic point.
final class ImmutableGeoPoint implements GeoPoint {
  factory ImmutableGeoPoint({
    required double latitude,
    required double longitude,
  }) {
    if (!isValidLatitude(latitude)) {
      throw RangeError.range(latitude, -90, 90, 'latitude');
    }
    if (!isValidLongitude(longitude)) {
      throw RangeError.range(longitude, -180, 180, 'longitude');
    }
    return ImmutableGeoPoint._(latitude: latitude, longitude: longitude);
  }

  const ImmutableGeoPoint._({
    required this.latitude,
    required this.longitude,
  });

  @override
  final double latitude;

  @override
  final double longitude;
}

/// Immutable copy of one provider snapshot.
///
/// Coordinates are mandatory and validated. Accuracy is informational and is
/// omitted when unusable. Provider speed is retained as observed so occurrence
/// creation can normalize or omit it according to the E1 domain rules.
final class ImmutableLocationSnapshot implements LocationSnapshot {
  factory ImmutableLocationSnapshot({
    required GeoPoint point,
    double? accuracyMeters,
    double? speedMetersPerSecond,
  }) {
    return ImmutableLocationSnapshot._(
      point: ImmutableGeoPoint(
        latitude: point.latitude,
        longitude: point.longitude,
      ),
      accuracyMeters: _usableAccuracy(accuracyMeters),
      speedMetersPerSecond: speedMetersPerSecond,
    );
  }

  const ImmutableLocationSnapshot._({
    required this.point,
    required this.accuracyMeters,
    required this.speedMetersPerSecond,
  });

  @override
  final ImmutableGeoPoint point;

  @override
  final double? accuracyMeters;

  @override
  final double? speedMetersPerSecond;
}

bool isValidLatitude(double latitude) =>
    latitude.isFinite && latitude >= -90 && latitude <= 90;

bool isValidLongitude(double longitude) =>
    longitude.isFinite && longitude >= -180 && longitude <= 180;

/// Converts provider speed to km/h when it belongs to the occurrence contract.
double? speedMetersPerSecondToKmh(double? metersPerSecond) {
  if (metersPerSecond == null ||
      !metersPerSecond.isFinite ||
      metersPerSecond < 0) {
    return null;
  }

  final kilometersPerHour = metersPerSecond * 3.6;
  if (!kilometersPerHour.isFinite || kilometersPerHour > 300) {
    return null;
  }
  return kilometersPerHour;
}

double? _usableAccuracy(double? accuracyMeters) {
  if (accuracyMeters == null ||
      !accuracyMeters.isFinite ||
      accuracyMeters < 0) {
    return null;
  }
  return accuracyMeters;
}
