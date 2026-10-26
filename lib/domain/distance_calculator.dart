import 'dart:math' as math;

import 'location_snapshot.dart';

/// Calculates the distance between two geographic points.
abstract interface class DistanceCalculator {
  double metersBetween(GeoPoint from, GeoPoint to);
}

/// Pure-Dart great-circle distance calculated with the Haversine formula.
final class HaversineDistanceCalculator implements DistanceCalculator {
  const HaversineDistanceCalculator();

  static const double earthRadiusMeters = 6371000;

  @override
  double metersBetween(GeoPoint from, GeoPoint to) {
    _validatePoint(from);
    _validatePoint(to);

    final fromLatitude = _degreesToRadians(from.latitude);
    final toLatitude = _degreesToRadians(to.latitude);
    final latitudeDelta = toLatitude - fromLatitude;
    final longitudeDelta = _degreesToRadians(to.longitude - from.longitude);

    final latitudeTerm = math.sin(latitudeDelta / 2);
    final longitudeTerm = math.sin(longitudeDelta / 2);
    final haversine = latitudeTerm * latitudeTerm +
        math.cos(fromLatitude) *
            math.cos(toLatitude) *
            longitudeTerm *
            longitudeTerm;
    final centralAngle = 2 *
        math.atan2(
          math.sqrt(haversine.clamp(0, 1)),
          math.sqrt((1 - haversine).clamp(0, 1)),
        );
    return earthRadiusMeters * centralAngle;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  static void _validatePoint(GeoPoint point) {
    if (!isValidLatitude(point.latitude)) {
      throw RangeError.range(point.latitude, -90, 90, 'latitude');
    }
    if (!isValidLongitude(point.longitude)) {
      throw RangeError.range(point.longitude, -180, 180, 'longitude');
    }
  }
}
