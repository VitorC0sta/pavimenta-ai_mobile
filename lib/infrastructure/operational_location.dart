import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../application/e1_ports.dart';
import '../domain/location_snapshot.dart';

typedef LocationServiceCheck = Future<bool> Function();
typedef LocationPermissionCheck = Future<LocationPermission> Function();
typedef LocationAccuracyCheck = Future<LocationAccuracyStatus> Function();
typedef CurrentPositionReader = Future<Position> Function(
  LocationSettings settings,
);
typedef PositionStreamReader = Stream<Position> Function(
  LocationSettings settings,
);

/// Owns precise foreground location updates for the active Operation route.
final class OperationalLocation implements OperationalLocationPort {
  OperationalLocation({
    LocationServiceCheck? isServiceEnabled,
    LocationPermissionCheck? checkPermission,
    LocationPermissionCheck? requestPermission,
    LocationAccuracyCheck? getLocationAccuracy,
    CurrentPositionReader? getCurrentPosition,
    PositionStreamReader? getPositionStream,
  })  : _isServiceEnabled =
            isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _getLocationAccuracy =
            getLocationAccuracy ?? Geolocator.getLocationAccuracy,
        _getCurrentPosition =
            getCurrentPosition ?? _readProductionCurrentPosition,
        _getPositionStream = getPositionStream ?? _readProductionPositionStream;

  final LocationServiceCheck _isServiceEnabled;
  final LocationPermissionCheck _checkPermission;
  final LocationPermissionCheck _requestPermission;
  final LocationAccuracyCheck _getLocationAccuracy;
  final CurrentPositionReader _getCurrentPosition;
  final PositionStreamReader _getPositionStream;

  StreamSubscription<Position>? _subscription;
  ImmutableLocationSnapshot? _latestSnapshot;

  @override
  LocationSnapshot? get latestValidSnapshot => _latestSnapshot;

  @override
  Future<void> acquireForegroundUpdates() async {
    await release();
    try {
      if (!await _isServiceEnabled()) {
        throw const OperationalLocationException(
          OperationalLocationFailure.serviceDisabled,
        );
      }

      var permission = await _checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const OperationalLocationException(
          OperationalLocationFailure.permissionDeniedPermanently,
        );
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const OperationalLocationException(
          OperationalLocationFailure.permissionDenied,
        );
      }
      if (await _getLocationAccuracy() != LocationAccuracyStatus.precise) {
        throw const OperationalLocationException(
          OperationalLocationFailure.reducedAccuracy,
        );
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      );
      _latestSnapshot = _snapshotFrom(await _getCurrentPosition(settings));
      _subscription = _getPositionStream(settings).listen(
        (position) {
          try {
            _latestSnapshot = _snapshotFrom(position);
          } catch (_) {
            _latestSnapshot = null;
          }
        },
        onError: (_) => _latestSnapshot = null,
      );
    } on OperationalLocationException {
      rethrow;
    } on LocationServiceDisabledException {
      throw const OperationalLocationException(
        OperationalLocationFailure.serviceDisabled,
      );
    } catch (_) {
      throw const OperationalLocationException(
        OperationalLocationFailure.positionUnavailable,
      );
    }
  }

  @override
  Future<void> release() async {
    final subscription = _subscription;
    _subscription = null;
    _latestSnapshot = null;
    await subscription?.cancel();
  }

  ImmutableLocationSnapshot _snapshotFrom(Position position) {
    return ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      accuracyMeters: position.accuracy.isFinite && position.accuracy >= 0
          ? position.accuracy
          : null,
      speedMetersPerSecond: position.speed,
    );
  }
}

Future<Position> _readProductionCurrentPosition(LocationSettings settings) {
  return Geolocator.getCurrentPosition(locationSettings: settings);
}

Stream<Position> _readProductionPositionStream(LocationSettings settings) {
  return Geolocator.getPositionStream(locationSettings: settings);
}
