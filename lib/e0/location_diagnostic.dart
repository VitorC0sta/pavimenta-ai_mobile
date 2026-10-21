import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationDiagnosticOutcome {
  available,
  serviceDisabled,
  permissionDenied,
  permissionDeniedPermanently,
  reducedAccuracy,
  waitingForPosition,
  positionUnavailable,
  cancelled,
}

class LocationDiagnosticReading {
  const LocationDiagnosticReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.speedMetersPerSecond,
  });

  factory LocationDiagnosticReading.fromPosition(Position position) {
    final speed = position.speed;

    return LocationDiagnosticReading(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      speedMetersPerSecond: speed.isFinite && speed >= 0 ? speed : null,
    );
  }

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? speedMetersPerSecond;
}

class LocationDiagnosticResult {
  const LocationDiagnosticResult._(this.outcome, this.reading);

  const LocationDiagnosticResult.withoutPosition(
    LocationDiagnosticOutcome outcome,
  ) : this._(outcome, null);

  const LocationDiagnosticResult.available(
    LocationDiagnosticReading reading,
  ) : this._(LocationDiagnosticOutcome.available, reading);

  final LocationDiagnosticOutcome outcome;
  final LocationDiagnosticReading? reading;
}

typedef LocationDiagnosticUpdate = void Function(
  LocationDiagnosticResult result,
);

class LocationDiagnostic {
  LocationDiagnostic({
    LocationSettings? currentPositionSettings,
    LocationSettings? positionStreamSettings,
  })  : _currentPositionSettings = currentPositionSettings ??
            const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
        _positionStreamSettings = positionStreamSettings ??
            AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 5),
            );

  final LocationSettings _currentPositionSettings;
  final LocationSettings _positionStreamSettings;

  StreamSubscription<Position>? _positionSubscription;
  Future<LocationDiagnosticResult>? _startOperation;
  Future<void>? _stopOperation;
  LocationDiagnosticReading? _latestReading;
  int _operationGeneration = 0;
  bool _permissionRequestNeedsReconciliation = false;
  bool _disposed = false;

  bool get isRunning => _positionSubscription != null;
  bool get isStarting => _startOperation != null;
  bool get permissionRequestNeedsReconciliation =>
      _permissionRequestNeedsReconciliation;
  LocationDiagnosticReading? get latestReading => _latestReading;

  Future<LocationDiagnosticResult> start({
    required LocationDiagnosticUpdate onUpdate,
    bool allowPermissionRequest = true,
  }) {
    if (_disposed) {
      return Future.value(
        const LocationDiagnosticResult.withoutPosition(
          LocationDiagnosticOutcome.cancelled,
        ),
      );
    }

    final activeOperation = _startOperation;
    if (activeOperation != null) {
      return activeOperation;
    }

    final activeReading = _latestReading;
    if (_positionSubscription != null) {
      return Future.value(
        activeReading != null
            ? LocationDiagnosticResult.available(activeReading)
            : const LocationDiagnosticResult.withoutPosition(
                LocationDiagnosticOutcome.waitingForPosition,
              ),
      );
    }

    final generation = ++_operationGeneration;
    late final Future<LocationDiagnosticResult> operation;
    operation = _start(
      generation,
      onUpdate,
      allowPermissionRequest: allowPermissionRequest,
    ).whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    });
    _startOperation = operation;
    return operation;
  }

  Future<LocationDiagnosticResult> _start(
    int generation,
    LocationDiagnosticUpdate onUpdate, {
    required bool allowPermissionRequest,
  }) async {
    final stopOperation = _stopOperation;
    if (stopOperation != null) {
      try {
        await stopOperation;
      } catch (_) {
        return _cancelledResult;
      }
      if (!_isCurrent(generation)) {
        return _cancelledResult;
      }
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isCurrent(generation)) {
        return _cancelledResult;
      }
      if (!serviceEnabled) {
        return const LocationDiagnosticResult.withoutPosition(
          LocationDiagnosticOutcome.serviceDisabled,
        );
      }

      final permission = await _checkOrRequestForegroundPermission(
        allowPermissionRequest: allowPermissionRequest,
      );
      if (!_isCurrent(generation)) {
        return _cancelledResult;
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationDiagnosticResult.withoutPosition(
          LocationDiagnosticOutcome.permissionDeniedPermanently,
        );
      }
      if (!_grantsForegroundLocation(permission)) {
        return const LocationDiagnosticResult.withoutPosition(
          LocationDiagnosticOutcome.permissionDenied,
        );
      }

      final accuracy = await Geolocator.getLocationAccuracy();
      if (!_isCurrent(generation)) {
        return _cancelledResult;
      }
      if (accuracy != LocationAccuracyStatus.precise) {
        return const LocationDiagnosticResult.withoutPosition(
          LocationDiagnosticOutcome.reducedAccuracy,
        );
      }

      onUpdate(
        const LocationDiagnosticResult.withoutPosition(
          LocationDiagnosticOutcome.waitingForPosition,
        ),
      );

      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: _currentPositionSettings,
      );
      if (!_isCurrent(generation)) {
        return _cancelledResult;
      }

      final initialReading =
          LocationDiagnosticReading.fromPosition(initialPosition);
      _latestReading = initialReading;
      _listenForPositionUpdates(generation, onUpdate);
      return LocationDiagnosticResult.available(initialReading);
    } on LocationServiceDisabledException {
      return _isCurrent(generation)
          ? const LocationDiagnosticResult.withoutPosition(
              LocationDiagnosticOutcome.serviceDisabled,
            )
          : _cancelledResult;
    } on TimeoutException {
      return _isCurrent(generation)
          ? const LocationDiagnosticResult.withoutPosition(
              LocationDiagnosticOutcome.positionUnavailable,
            )
          : _cancelledResult;
    } catch (_) {
      return _isCurrent(generation)
          ? const LocationDiagnosticResult.withoutPosition(
              LocationDiagnosticOutcome.positionUnavailable,
            )
          : _cancelledResult;
    }
  }

  Future<LocationPermission> _checkOrRequestForegroundPermission({
    required bool allowPermissionRequest,
  }) async {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.denied || !allowPermissionRequest) {
      return permission;
    }

    // Keep this flag until the controller reconciles the result after resume.
    // The Android dialog may outlive the resource generation that opened it.
    _permissionRequestNeedsReconciliation = true;
    return Geolocator.requestPermission();
  }

  void markPermissionRequestReconciled() {
    _permissionRequestNeedsReconciliation = false;
  }

  bool _grantsForegroundLocation(LocationPermission permission) {
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  void _listenForPositionUpdates(
    int generation,
    LocationDiagnosticUpdate onUpdate,
  ) {
    if (_positionSubscription != null) {
      return;
    }

    StreamSubscription<Position>? subscription;
    subscription = Geolocator.getPositionStream(
      locationSettings: _positionStreamSettings,
    ).listen(
      (position) {
        if (!_isCurrent(generation) ||
            !identical(_positionSubscription, subscription)) {
          return;
        }

        final reading = LocationDiagnosticReading.fromPosition(position);
        _latestReading = reading;
        onUpdate(LocationDiagnosticResult.available(reading));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_isCurrent(generation) ||
            !identical(_positionSubscription, subscription)) {
          return;
        }

        _positionSubscription = null;
        _latestReading = null;
        onUpdate(
          LocationDiagnosticResult.withoutPosition(
            error is LocationServiceDisabledException
                ? LocationDiagnosticOutcome.serviceDisabled
                : LocationDiagnosticOutcome.positionUnavailable,
          ),
        );
      },
      onDone: () {
        if (!_isCurrent(generation) ||
            !identical(_positionSubscription, subscription)) {
          return;
        }

        _positionSubscription = null;
        _latestReading = null;
        onUpdate(
          const LocationDiagnosticResult.withoutPosition(
            LocationDiagnosticOutcome.positionUnavailable,
          ),
        );
      },
      cancelOnError: true,
    );
    _positionSubscription = subscription;
  }

  Future<void> stop() {
    ++_operationGeneration;
    _latestReading = null;

    final previousStop = _stopOperation;
    final subscription = _positionSubscription;
    _positionSubscription = null;

    late final Future<void> operation;
    operation = () async {
      try {
        if (previousStop != null) {
          await previousStop;
        }
      } finally {
        await subscription?.cancel();
      }
    }()
        .whenComplete(() {
      if (identical(_stopOperation, operation)) {
        _stopOperation = null;
      }
    });
    _stopOperation = operation;
    return operation;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await stop();
  }

  bool _isCurrent(int generation) {
    return !_disposed && generation == _operationGeneration;
  }

  static const LocationDiagnosticResult _cancelledResult =
      LocationDiagnosticResult.withoutPosition(
    LocationDiagnosticOutcome.cancelled,
  );
}
