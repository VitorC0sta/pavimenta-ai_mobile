import 'package:camera/camera.dart';

enum PermissionPhase {
  cameraPending,
  cameraResolving,
  cameraResolved,
  locationPending,
  locationResolving,
  permissionsResolved,
}

enum PermissionRequestType {
  camera,
  location,
}

enum PermissionDecision {
  granted,
  reducedAccuracy,
  denied,
  deniedPermanently,
  failed,
}

enum CameraDiagnosticStatus {
  initial,
  initializing,
  available,
  permissionDenied,
  permissionDeniedPermanently,
  noRearCamera,
  cameraInUse,
  initializationFailed,
  paused,
}

enum LocationDiagnosticStatus {
  waitingForCamera,
  checking,
  waitingForPosition,
  available,
  serviceDisabled,
  permissionDenied,
  permissionDeniedPermanently,
  reducedAccuracy,
  positionUnavailable,
  paused,
}

enum HttpsDiagnosticStatus {
  notChecked,
  invalidConfiguration,
  checking,
  reachable,
  responded,
  incompleteResponse,
  timeout,
  tlsFailure,
  unavailable,
  lifecycleCancelled,
}

const Object _notProvided = Object();

class E0State {
  const E0State({
    required this.permissionPhase,
    required this.cameraStatus,
    required this.locationStatus,
    required this.httpsStatus,
    this.activePermissionRequest,
    this.cameraPermissionDecision,
    this.locationPermissionDecision,
    this.cameraMessage,
    CameraController? cameraController,
    this.locationMessage,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.speedMetersPerSecond,
    this.httpsMessage,
    this.httpStatusCode,
    this.isHttpsRequestInProgress = false,
  }) : _cameraController = cameraController;

  factory E0State.initial() {
    return const E0State(
      permissionPhase: PermissionPhase.cameraPending,
      cameraStatus: CameraDiagnosticStatus.initial,
      cameraMessage: 'Aguardando início do diagnóstico da câmera.',
      locationStatus: LocationDiagnosticStatus.waitingForCamera,
      locationMessage: 'Aguardando conclusão da permissão de câmera.',
      httpsStatus: HttpsDiagnosticStatus.notChecked,
      httpsMessage: 'Diagnóstico HTTPS ainda não executado.',
    );
  }

  final PermissionPhase permissionPhase;
  final PermissionRequestType? activePermissionRequest;
  final PermissionDecision? cameraPermissionDecision;
  final PermissionDecision? locationPermissionDecision;
  final CameraDiagnosticStatus cameraStatus;
  final String? cameraMessage;
  final CameraController? _cameraController;

  CameraController? get cameraController {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }

    return controller;
  }

  final LocationDiagnosticStatus locationStatus;
  final String? locationMessage;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final double? speedMetersPerSecond;

  final HttpsDiagnosticStatus httpsStatus;
  final String? httpsMessage;
  final int? httpStatusCode;
  final bool isHttpsRequestInProgress;

  bool get isPermissionRequestInProgress => activePermissionRequest != null;

  E0State copyWith({
    PermissionPhase? permissionPhase,
    Object? activePermissionRequest = _notProvided,
    Object? cameraPermissionDecision = _notProvided,
    Object? locationPermissionDecision = _notProvided,
    CameraDiagnosticStatus? cameraStatus,
    Object? cameraMessage = _notProvided,
    Object? cameraController = _notProvided,
    LocationDiagnosticStatus? locationStatus,
    Object? locationMessage = _notProvided,
    Object? latitude = _notProvided,
    Object? longitude = _notProvided,
    Object? accuracyMeters = _notProvided,
    Object? speedMetersPerSecond = _notProvided,
    HttpsDiagnosticStatus? httpsStatus,
    Object? httpsMessage = _notProvided,
    Object? httpStatusCode = _notProvided,
    bool? isHttpsRequestInProgress,
  }) {
    return E0State(
      permissionPhase: permissionPhase ?? this.permissionPhase,
      activePermissionRequest: identical(activePermissionRequest, _notProvided)
          ? this.activePermissionRequest
          : activePermissionRequest as PermissionRequestType?,
      cameraPermissionDecision:
          identical(cameraPermissionDecision, _notProvided)
              ? this.cameraPermissionDecision
              : cameraPermissionDecision as PermissionDecision?,
      locationPermissionDecision:
          identical(locationPermissionDecision, _notProvided)
              ? this.locationPermissionDecision
              : locationPermissionDecision as PermissionDecision?,
      cameraStatus: cameraStatus ?? this.cameraStatus,
      cameraMessage: identical(cameraMessage, _notProvided)
          ? this.cameraMessage
          : cameraMessage as String?,
      cameraController: identical(cameraController, _notProvided)
          ? this.cameraController
          : cameraController as CameraController?,
      locationStatus: locationStatus ?? this.locationStatus,
      locationMessage: identical(locationMessage, _notProvided)
          ? this.locationMessage
          : locationMessage as String?,
      latitude: identical(latitude, _notProvided)
          ? this.latitude
          : latitude as double?,
      longitude: identical(longitude, _notProvided)
          ? this.longitude
          : longitude as double?,
      accuracyMeters: identical(accuracyMeters, _notProvided)
          ? this.accuracyMeters
          : accuracyMeters as double?,
      speedMetersPerSecond: identical(speedMetersPerSecond, _notProvided)
          ? this.speedMetersPerSecond
          : speedMetersPerSecond as double?,
      httpsStatus: httpsStatus ?? this.httpsStatus,
      httpsMessage: identical(httpsMessage, _notProvided)
          ? this.httpsMessage
          : httpsMessage as String?,
      httpStatusCode: identical(httpStatusCode, _notProvided)
          ? this.httpStatusCode
          : httpStatusCode as int?,
      isHttpsRequestInProgress:
          isHttpsRequestInProgress ?? this.isHttpsRequestInProgress,
    );
  }
}
