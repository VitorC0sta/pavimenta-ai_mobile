import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_diagnostic.dart';
import 'diagnostic_http_client.dart';
import 'e0_state.dart';
import 'location_diagnostic.dart';

class E0Controller extends ChangeNotifier {
  E0Controller({
    required CameraDiagnostic cameraDiagnostic,
    required this.locationDiagnostic,
    required this.diagnosticHttpClient,
  })  : _cameraDiagnostic = cameraDiagnostic,
        _state = E0State.initial();

  final CameraDiagnostic _cameraDiagnostic;
  final LocationDiagnostic locationDiagnostic;
  final DiagnosticHttpClient diagnosticHttpClient;

  E0State _state;
  int _generation = 0;
  bool _isInForeground = false;
  bool _isDisposed = false;
  bool _locationWasInterruptedByLifecycle = false;
  Future<void> _resourceRelease = Future<void>.value();
  Future<void>? _foregroundEntryOperation;
  Future<void>? _cameraPermissionOperation;
  Future<void>? _cameraPreviewOperation;
  Future<void>? _locationPermissionOperation;
  Future<void>? _locationResumeOperation;
  Future<void>? _httpsDiagnosticOperation;
  _PermissionRequestInFlight? _permissionRequestInFlight;
  _CameraResolution? _pendingCameraResolution;
  final Set<CameraController> _retiredCameraControllers =
      Set<CameraController>.identity();
  final Completer<void> _disposalCompletion = Completer<void>();
  Future<void>? _disposalOperation;
  bool _changeNotifierDisposed = false;

  E0State get state => _state;

  /// Completes only after every E0 asynchronous operation and resource has
  /// settled, allowing the owning route to hand hardware back safely.
  Future<void> get disposalComplete => _disposalCompletion.future;

  bool get canRetryCameraDiagnostic =>
      !_isDisposed &&
      _isInForeground &&
      _state.permissionPhase == PermissionPhase.permissionsResolved &&
      !_state.isPermissionRequestInProgress &&
      _cameraPermissionOperation == null &&
      _cameraPreviewOperation == null;

  bool get canRetryLocationDiagnostic =>
      !_isDisposed &&
      _isInForeground &&
      _state.permissionPhase == PermissionPhase.permissionsResolved &&
      !_state.isPermissionRequestInProgress &&
      _locationPermissionOperation == null &&
      _locationResumeOperation == null;

  Future<void> retryCameraDiagnostic() async {
    if (!canRetryCameraDiagnostic) {
      return;
    }

    final generation = _generation;
    final cameraController = _activeCameraController;
    _state = _state.copyWith(
      permissionPhase: PermissionPhase.cameraPending,
      activePermissionRequest: null,
      cameraPermissionDecision: null,
      cameraStatus: CameraDiagnosticStatus.initializing,
      cameraMessage: 'Reiniciando diagnóstico da câmera.',
      cameraController: null,
    );
    _notifyListeners();

    await _ignoreCleanupFailure(_retireCameraController(cameraController));
    if (_isCurrentGeneration(generation)) {
      await resolveCameraPermission();
    }
  }

  Future<void> retryLocationDiagnostic() async {
    if (!canRetryLocationDiagnostic) {
      return;
    }

    final generation = _generation;
    _state = _state.copyWith(
      permissionPhase: PermissionPhase.locationPending,
      activePermissionRequest: null,
      locationPermissionDecision: null,
      locationStatus: LocationDiagnosticStatus.checking,
      locationMessage: 'Reiniciando diagnóstico de localização.',
      latitude: null,
      longitude: null,
      accuracyMeters: null,
      speedMetersPerSecond: null,
    );
    _notifyListeners();

    await _ignoreCleanupFailure(locationDiagnostic.stop());
    if (_isCurrentGeneration(generation)) {
      await _startLocationVerification(generation: generation);
    }
  }

  Future<void> runHttpsDiagnostic() {
    if (_isDisposed || !_isInForeground || _state.isHttpsRequestInProgress) {
      return Future<void>.value();
    }

    final activeOperation = _httpsDiagnosticOperation;
    if (activeOperation != null) {
      return activeOperation;
    }

    final generation = _generation;
    _state = _state.copyWith(
      httpsStatus: HttpsDiagnosticStatus.checking,
      httpsMessage: 'Verificando destino HTTPS de teste.',
      httpStatusCode: null,
      isHttpsRequestInProgress: true,
    );
    _notifyListeners();

    late final Future<void> operation;
    operation = _performHttpsDiagnostic(generation).whenComplete(() {
      if (identical(_httpsDiagnosticOperation, operation)) {
        _httpsDiagnosticOperation = null;
      }
    });
    _httpsDiagnosticOperation = operation;
    return operation;
  }

  Future<void> _performHttpsDiagnostic(int generation) async {
    final result = await diagnosticHttpClient.run();
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    final (status, message) = switch (result.outcome) {
      DiagnosticHttpOutcome.reachable => (
          HttpsDiagnosticStatus.reachable,
          'Destino de teste acessível.',
        ),
      DiagnosticHttpOutcome.responded => (
          HttpsDiagnosticStatus.responded,
          'Destino de teste respondeu com código HTTP.',
        ),
      DiagnosticHttpOutcome.invalidConfiguration => (
          HttpsDiagnosticStatus.invalidConfiguration,
          'Configuração HTTPS ausente ou inválida.',
        ),
      DiagnosticHttpOutcome.incompleteResponse => (
          HttpsDiagnosticStatus.incompleteResponse,
          'Resposta excessiva ou incompleta.',
        ),
      DiagnosticHttpOutcome.timeout => (
          HttpsDiagnosticStatus.timeout,
          'Tempo limite do diagnóstico HTTPS excedido.',
        ),
      DiagnosticHttpOutcome.tlsFailure => (
          HttpsDiagnosticStatus.tlsFailure,
          'Falha na validação TLS do destino de teste.',
        ),
      DiagnosticHttpOutcome.unavailable => (
          HttpsDiagnosticStatus.unavailable,
          'Rede indisponível ou destino de teste inacessível.',
        ),
      DiagnosticHttpOutcome.cancelled => (
          HttpsDiagnosticStatus.lifecycleCancelled,
          'Diagnóstico HTTPS cancelado pelo ciclo de vida.',
        ),
    };

    _state = _state.copyWith(
      httpsStatus: status,
      httpsMessage: message,
      httpStatusCode: result.statusCode,
      isHttpsRequestInProgress: false,
    );
    _notifyListeners();
  }

  Future<void> handleLifecycleState(AppLifecycleState lifecycleState) {
    if (_isDisposed) {
      return Future<void>.value();
    }

    return lifecycleState == AppLifecycleState.resumed
        ? _enterForeground()
        : _leaveForeground();
  }

  Future<void> _enterForeground() {
    if (_isDisposed) {
      return Future<void>.value();
    }

    final activeEntry = _foregroundEntryOperation;
    if (_isInForeground) {
      return activeEntry ?? Future<void>.value();
    }

    _isInForeground = true;
    final generation = ++_generation;

    late final Future<void> operation;
    operation = _resumeAfterPreviousEntry(
      previousEntry: activeEntry,
      generation: generation,
    ).whenComplete(() {
      if (identical(_foregroundEntryOperation, operation)) {
        _foregroundEntryOperation = null;
      }
    });
    _foregroundEntryOperation = operation;
    return operation;
  }

  Future<void> _resumeAfterPreviousEntry({
    required Future<void>? previousEntry,
    required int generation,
  }) async {
    if (previousEntry != null) {
      await _ignoreCleanupFailure(previousEntry);
    }
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    await _resumeForegroundGeneration(generation);
  }

  Future<void> _resumeForegroundGeneration(int generation) async {
    await _resourceRelease;
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    final activePermissionOperation = _activePermissionOperation;
    if (activePermissionOperation != null) {
      await activePermissionOperation;
      if (!_isCurrentGeneration(generation)) {
        return;
      }
    }

    final pendingCameraResolution = _pendingCameraResolution;
    if (pendingCameraResolution != null) {
      _pendingCameraResolution = null;
      await _applyCameraPermissionResolution(
        pendingCameraResolution,
        generation,
      );
      if (!_isCurrentGeneration(generation)) {
        return;
      }
    }

    await _reconcileEquivalentResourceOperations(generation);
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    switch (_state.permissionPhase) {
      case PermissionPhase.cameraPending:
        await resolveCameraPermission();
      case PermissionPhase.cameraResolving:
        // A system permission dialog or camera initialization is still active.
        // Its future remains the single authority for reconciliation.
        return;
      case PermissionPhase.cameraResolved:
        if (markLocationPermissionPending()) {
          await _startLocationVerification(generation: generation);
        }
      case PermissionPhase.locationPending:
        await _startLocationVerification(generation: generation);
      case PermissionPhase.locationResolving:
        await _resumeInterruptedLocationPermission(generation);
        if (_isCurrentGeneration(generation) &&
            _state.permissionPhase == PermissionPhase.permissionsResolved) {
          await _restartResolvedDiagnostics(generation);
        }
      case PermissionPhase.permissionsResolved:
        await _restartResolvedDiagnostics(generation);
    }
  }

  Future<void> _reconcileEquivalentResourceOperations(int generation) async {
    final operations = <Future<void>>[
      if (_cameraPreviewOperation case final operation?) operation,
      if (_locationResumeOperation case final operation?) operation,
    ];
    if (operations.isEmpty) {
      return;
    }

    await Future.wait(operations.map(_ignoreCleanupFailure));
    if (!_isCurrentGeneration(generation)) {
      return;
    }
  }

  Future<void> _leaveForeground() {
    if (_isDisposed) {
      return Future<void>.value();
    }

    _isInForeground = false;
    ++_generation;
    final wasHttpsRequestInProgress = _state.isHttpsRequestInProgress;
    final httpsRelease = diagnosticHttpClient.cancelActive();
    _locationWasInterruptedByLifecycle = _locationWasInterruptedByLifecycle ||
        locationDiagnostic.isStarting ||
        locationDiagnostic.isRunning ||
        _state.locationPermissionDecision == PermissionDecision.granted;

    final cameraController = _activeCameraController;
    _state = _state.copyWith(
      cameraStatus: CameraDiagnosticStatus.paused,
      cameraMessage:
          'Câmera pausada enquanto o aplicativo está em segundo plano.',
      cameraController: null,
      locationStatus: LocationDiagnosticStatus.paused,
      locationMessage:
          'Localização pausada enquanto o aplicativo está em segundo plano.',
      latitude: null,
      longitude: null,
      accuracyMeters: null,
      speedMetersPerSecond: null,
      httpsStatus: wasHttpsRequestInProgress
          ? HttpsDiagnosticStatus.lifecycleCancelled
          : _state.httpsStatus,
      httpsMessage: wasHttpsRequestInProgress
          ? 'Diagnóstico HTTPS cancelado pelo ciclo de vida.'
          : _state.httpsMessage,
      httpStatusCode: wasHttpsRequestInProgress ? null : _state.httpStatusCode,
      isHttpsRequestInProgress: false,
    );
    _notifyListeners();

    final previousRelease = _resourceRelease;
    _resourceRelease = () async {
      // Detaching the resources from state above makes repeated lifecycle
      // notifications harmless. Cleanup failures are contained so one failed
      // release cannot prevent this or a later pause from releasing resources.
      await _ignoreCleanupFailure(previousRelease);
      await Future.wait<void>([
        _ignoreCleanupFailure(httpsRelease),
        _ignoreCleanupFailure(locationDiagnostic.stop()),
        if (cameraController != null)
          _ignoreCleanupFailure(_retireCameraController(cameraController)),
      ]);
    }();
    return _resourceRelease;
  }

  Future<void> _ignoreCleanupFailure(Future<void> cleanup) async {
    try {
      await cleanup;
    } catch (_) {
      // Lifecycle cleanup is best effort and must remain idempotent.
    }
  }

  CameraController? get _activeCameraController {
    final controller = _state.cameraController;
    if (controller == null || _retiredCameraControllers.contains(controller)) {
      return null;
    }

    return controller;
  }

  Future<void> _retireCameraController(CameraController? controller) async {
    if (controller == null || !_retiredCameraControllers.add(controller)) {
      return;
    }

    await controller.dispose();
  }

  Future<void>? get _activePermissionOperation =>
      _permissionRequestInFlight?.completion;

  Future<void> resolveCameraPermission() {
    if (_isDisposed || !_isInForeground) {
      return Future<void>.value();
    }

    final activeOperation = _cameraPermissionOperation;
    if (activeOperation != null) {
      return activeOperation;
    }
    if (!beginCameraPermissionResolution()) {
      return Future<void>.value();
    }

    final permissionRequest =
        _trackPermissionRequest(PermissionRequestType.camera);
    final generation = _generation;
    _state = _state.copyWith(
      cameraStatus: CameraDiagnosticStatus.initializing,
      cameraMessage: 'Solicitando permissão de câmera.',
    );
    _notifyListeners();

    late final Future<void> operation;
    operation = _resolveCameraPermission(generation).whenComplete(() {
      if (identical(_cameraPermissionOperation, operation)) {
        _cameraPermissionOperation = null;
      }
      permissionRequest.markOperationCompleted();
    });
    _cameraPermissionOperation = operation;
    return operation;
  }

  Future<void> _resolveCameraPermission(int generation) async {
    final resolution = await _obtainCameraResolution();

    if (!_isCurrentGeneration(generation)) {
      final previewController = resolution.previewController;
      if (previewController != null) {
        await _retireCameraController(previewController);
      }
      _pendingCameraResolution = resolution.withoutPreview();
      return;
    }

    await _applyCameraPermissionResolution(resolution, generation);
  }

  Future<_CameraResolution> _obtainCameraResolution() async {
    try {
      final cameras = await enumerateCamerasWhenAuthorized();
      final backCamera = cameras == null
          ? null
          : _cameraDiagnostic.selectFirstBackCamera(cameras);

      if (backCamera == null) {
        return const _CameraResolution(
          decision: PermissionDecision.failed,
          status: CameraDiagnosticStatus.noRearCamera,
          message: 'Nenhuma câmera traseira foi encontrada.',
        );
      }

      final previewController =
          await _cameraDiagnostic.initializePreviewController(backCamera);
      return _CameraResolution(
        decision: PermissionDecision.granted,
        status: CameraDiagnosticStatus.available,
        message: 'Câmera traseira disponível.',
        previewController: previewController,
      );
    } on CameraException catch (error) {
      switch (await _cameraDiagnostic.classifyFailure(error)) {
        case CameraFailureType.permissionDenied:
          return const _CameraResolution(
            decision: PermissionDecision.denied,
            status: CameraDiagnosticStatus.permissionDenied,
            message: 'Permissão de câmera negada.',
          );
        case CameraFailureType.permissionDeniedPermanently:
          return const _CameraResolution(
            decision: PermissionDecision.deniedPermanently,
            status: CameraDiagnosticStatus.permissionDeniedPermanently,
            message:
                'Permissão de câmera negada permanentemente. Habilite-a nas configurações do Android.',
          );
        case CameraFailureType.cameraInUse:
          return const _CameraResolution(
            decision: PermissionDecision.failed,
            status: CameraDiagnosticStatus.cameraInUse,
            message: 'Câmera ocupada por outro aplicativo.',
          );
        case CameraFailureType.initializationFailed:
          return const _CameraResolution(
            decision: PermissionDecision.failed,
            status: CameraDiagnosticStatus.initializationFailed,
            message: 'Falha ao inicializar a câmera traseira.',
          );
      }
    } catch (_) {
      return const _CameraResolution(
        decision: PermissionDecision.failed,
        status: CameraDiagnosticStatus.initializationFailed,
        message: 'Falha ao inicializar a câmera traseira.',
      );
    }
  }

  Future<void> _applyCameraPermissionResolution(
    _CameraResolution resolution,
    int generation,
  ) async {
    if (!_isCurrentGeneration(generation)) {
      await _retireCameraController(resolution.previewController);
      return;
    }
    if (!completeCameraPermissionResolution(resolution.decision)) {
      await _retireCameraController(resolution.previewController);
      return;
    }

    _state = _state.copyWith(
      cameraStatus: resolution.status,
      cameraMessage: resolution.message,
      cameraController: resolution.previewController,
    );
    _notifyListeners();

    if (resolution.needsPreviewRestart &&
        resolution.decision == PermissionDecision.granted) {
      unawaited(_restartCameraPreview(generation));
    }

    if (markLocationPermissionPending()) {
      await _startLocationVerification(generation: generation);
    }
  }

  Future<void> _restartResolvedDiagnostics(int generation) async {
    final operations = <Future<void>>[];

    if (_state.cameraPermissionDecision == PermissionDecision.granted &&
        _activeCameraController == null) {
      operations.add(_restartCameraPreview(generation));
    }

    if (_state.locationPermissionDecision == PermissionDecision.granted ||
        _locationWasInterruptedByLifecycle) {
      operations.add(_resumeLocationVerification(generation));
    }

    await Future.wait(operations);
  }

  Future<void> _restartCameraPreview(int generation) {
    final activeOperation = _cameraPreviewOperation;
    if (activeOperation != null) {
      return activeOperation;
    }

    late final Future<void> operation;
    operation = _initializeResumedCamera(generation).whenComplete(() {
      if (identical(_cameraPreviewOperation, operation)) {
        _cameraPreviewOperation = null;
      }
    });
    _cameraPreviewOperation = operation;
    return operation;
  }

  Future<void> _initializeResumedCamera(int generation) async {
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    _state = _state.copyWith(
      cameraStatus: CameraDiagnosticStatus.initializing,
      cameraMessage: 'Reinicializando câmera traseira.',
      cameraController: null,
    );
    _notifyListeners();

    CameraController? previewController;
    CameraDiagnosticStatus status;
    String message;

    try {
      final cameras = await _cameraDiagnostic.enumerateAvailableCameras();
      final backCamera = _cameraDiagnostic.selectFirstBackCamera(cameras);
      if (backCamera == null) {
        status = CameraDiagnosticStatus.noRearCamera;
        message = 'Nenhuma câmera traseira foi encontrada.';
      } else {
        previewController =
            await _cameraDiagnostic.initializePreviewController(backCamera);
        status = CameraDiagnosticStatus.available;
        message = 'Câmera traseira disponível.';
      }
    } on CameraException catch (error) {
      final failure = await _cameraDiagnostic.classifyFailure(error);
      (status, message) = switch (failure) {
        CameraFailureType.permissionDenied => (
            CameraDiagnosticStatus.permissionDenied,
            'Permissão de câmera negada.',
          ),
        CameraFailureType.permissionDeniedPermanently => (
            CameraDiagnosticStatus.permissionDeniedPermanently,
            'Permissão de câmera negada permanentemente. Habilite-a nas configurações do Android.',
          ),
        CameraFailureType.cameraInUse => (
            CameraDiagnosticStatus.cameraInUse,
            'Câmera ocupada por outro aplicativo.',
          ),
        CameraFailureType.initializationFailed => (
            CameraDiagnosticStatus.initializationFailed,
            'Falha ao inicializar a câmera traseira.',
          ),
      };
    } catch (_) {
      status = CameraDiagnosticStatus.initializationFailed;
      message = 'Falha ao inicializar a câmera traseira.';
    }

    if (!_isCurrentGeneration(generation)) {
      await _retireCameraController(previewController);
      return;
    }

    _state = _state.copyWith(
      cameraStatus: status,
      cameraMessage: message,
      cameraController: previewController,
    );
    _notifyListeners();
  }

  Future<void> _startLocationVerification({required int generation}) {
    final activeOperation = _locationPermissionOperation;
    if (activeOperation != null) {
      return activeOperation;
    }
    if (!_isCurrentGeneration(generation) ||
        !beginLocationPermissionResolution()) {
      return Future<void>.value();
    }

    final permissionRequest =
        _trackPermissionRequest(PermissionRequestType.location);
    _state = _state.copyWith(
      locationStatus: LocationDiagnosticStatus.checking,
      locationMessage: 'Verificando serviço e permissão de localização.',
    );
    _notifyListeners();

    late final Future<void> operation;
    operation = _resolveLocationPermission(generation).whenComplete(() {
      if (identical(_locationPermissionOperation, operation)) {
        _locationPermissionOperation = null;
      }
      permissionRequest.markOperationCompleted();
    });
    _locationPermissionOperation = operation;
    return operation;
  }

  Future<void> _resolveLocationPermission(int generation) async {
    final result = await _obtainForegroundLocation(
      generation,
      allowPermissionRequest:
          !locationDiagnostic.permissionRequestNeedsReconciliation,
    );
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    _locationWasInterruptedByLifecycle =
        result.outcome == LocationDiagnosticOutcome.cancelled;
    locationDiagnostic.markPermissionRequestReconciled();
    final permissionDecision = _locationPermissionDecision(result.outcome);
    if (!completeLocationPermissionResolution(permissionDecision)) {
      return;
    }
    _publishLocationResult(result, generation: generation);
  }

  Future<void> _resumeInterruptedLocationPermission(int generation) async {
    final activeOperation = _locationPermissionOperation;
    if (activeOperation != null) {
      await activeOperation;
      if (!_isCurrentGeneration(generation)) {
        return;
      }
    }

    if (_state.permissionPhase != PermissionPhase.locationResolving) {
      return;
    }

    final result = await _obtainForegroundLocation(
      generation,
      allowPermissionRequest:
          !locationDiagnostic.permissionRequestNeedsReconciliation,
    );
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    locationDiagnostic.markPermissionRequestReconciled();
    _locationWasInterruptedByLifecycle = false;
    if (completeLocationPermissionResolution(
      _locationPermissionDecision(result.outcome),
    )) {
      _publishLocationResult(result, generation: generation);
    }
  }

  Future<void> _resumeLocationVerification(int generation) {
    final activeOperation = _locationResumeOperation;
    if (activeOperation != null) {
      return activeOperation;
    }

    late final Future<void> operation;
    operation =
        _obtainAndPublishForegroundLocation(generation).whenComplete(() {
      if (identical(_locationResumeOperation, operation)) {
        _locationResumeOperation = null;
      }
    });
    _locationResumeOperation = operation;
    return operation;
  }

  Future<void> _obtainAndPublishForegroundLocation(int generation) async {
    final result = await _obtainForegroundLocation(
      generation,
      allowPermissionRequest: false,
    );
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    _locationWasInterruptedByLifecycle =
        result.outcome == LocationDiagnosticOutcome.cancelled;
    if (result.outcome != LocationDiagnosticOutcome.cancelled) {
      _state = _state.copyWith(
        locationPermissionDecision: _locationPermissionDecision(result.outcome),
      );
      _notifyListeners();
      _publishLocationResult(result, generation: generation);
    }
  }

  Future<LocationDiagnosticResult> _obtainForegroundLocation(
    int generation, {
    required bool allowPermissionRequest,
  }) {
    return locationDiagnostic.start(
      allowPermissionRequest: allowPermissionRequest,
      onUpdate: (result) {
        _publishLocationResult(result, generation: generation);
      },
    );
  }

  PermissionDecision _locationPermissionDecision(
    LocationDiagnosticOutcome outcome,
  ) {
    switch (outcome) {
      case LocationDiagnosticOutcome.available:
      case LocationDiagnosticOutcome.waitingForPosition:
      case LocationDiagnosticOutcome.positionUnavailable:
        return PermissionDecision.granted;
      case LocationDiagnosticOutcome.reducedAccuracy:
        return PermissionDecision.reducedAccuracy;
      case LocationDiagnosticOutcome.permissionDenied:
        return PermissionDecision.denied;
      case LocationDiagnosticOutcome.permissionDeniedPermanently:
        return PermissionDecision.deniedPermanently;
      case LocationDiagnosticOutcome.serviceDisabled:
      case LocationDiagnosticOutcome.cancelled:
        return PermissionDecision.failed;
    }
  }

  void _publishLocationResult(
    LocationDiagnosticResult result, {
    required int generation,
  }) {
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    final reading = result.reading;
    final (status, message) = switch (result.outcome) {
      LocationDiagnosticOutcome.available => (
          LocationDiagnosticStatus.available,
          'Localização precisa disponível.',
        ),
      LocationDiagnosticOutcome.serviceDisabled => (
          LocationDiagnosticStatus.serviceDisabled,
          'Serviço de localização desativado.',
        ),
      LocationDiagnosticOutcome.permissionDenied => (
          LocationDiagnosticStatus.permissionDenied,
          'Permissão de localização negada.',
        ),
      LocationDiagnosticOutcome.permissionDeniedPermanently => (
          LocationDiagnosticStatus.permissionDeniedPermanently,
          'Permissão de localização negada permanentemente. Habilite-a nas configurações do Android.',
        ),
      LocationDiagnosticOutcome.reducedAccuracy => (
          LocationDiagnosticStatus.reducedAccuracy,
          'Localização precisa não autorizada.',
        ),
      LocationDiagnosticOutcome.waitingForPosition => (
          LocationDiagnosticStatus.waitingForPosition,
          'Aguardando posição.',
        ),
      LocationDiagnosticOutcome.positionUnavailable => (
          LocationDiagnosticStatus.positionUnavailable,
          'Posição indisponível.',
        ),
      LocationDiagnosticOutcome.cancelled => (
          LocationDiagnosticStatus.positionUnavailable,
          'Verificação de localização cancelada.',
        ),
    };

    updateLocationState(
      status: status,
      message: message,
      latitude: reading?.latitude,
      longitude: reading?.longitude,
      accuracyMeters: reading?.accuracyMeters,
      speedMetersPerSecond: reading?.speedMetersPerSecond,
      generation: generation,
    );
  }

  bool updateCameraState({
    required CameraDiagnosticStatus status,
    required String message,
    CameraController? cameraController,
    int? generation,
  }) {
    if (!_diagnosticUpdatesAreAllowed ||
        (generation != null && !_isCurrentGeneration(generation)) ||
        (cameraController != null &&
            _retiredCameraControllers.contains(cameraController))) {
      return false;
    }

    _state = _state.copyWith(
      cameraStatus: status,
      cameraMessage: message,
      cameraController: cameraController,
    );
    _notifyListeners();
    return true;
  }

  bool updateLocationState({
    required LocationDiagnosticStatus status,
    required String message,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    double? speedMetersPerSecond,
    int? generation,
  }) {
    if (!_locationUpdatesAreAllowed ||
        (generation != null && !_isCurrentGeneration(generation))) {
      return false;
    }

    _state = _state.copyWith(
      locationStatus: status,
      locationMessage: message,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      speedMetersPerSecond: speedMetersPerSecond,
    );
    _notifyListeners();
    return true;
  }

  bool get _diagnosticUpdatesAreAllowed =>
      !_isDisposed &&
      _isInForeground &&
      _state.permissionPhase == PermissionPhase.permissionsResolved &&
      _state.activePermissionRequest == null;

  bool get _locationUpdatesAreAllowed =>
      _diagnosticUpdatesAreAllowed ||
      (!_isDisposed &&
          _isInForeground &&
          _state.permissionPhase == PermissionPhase.locationResolving &&
          _state.activePermissionRequest == PermissionRequestType.location);

  bool get canBeginCameraPermissionResolution => _canBeginPermissionRequest(
        phase: PermissionPhase.cameraPending,
        request: PermissionRequestType.camera,
      );

  bool get canBeginLocationPermissionResolution =>
      _state.cameraPermissionDecision != null &&
      _canBeginPermissionRequest(
        phase: PermissionPhase.locationPending,
        request: PermissionRequestType.location,
      );

  Future<List<CameraDescription>?> enumerateCamerasWhenAuthorized() {
    if (_state.permissionPhase != PermissionPhase.cameraResolving ||
        _state.activePermissionRequest != PermissionRequestType.camera) {
      return Future<List<CameraDescription>?>.value();
    }

    return _cameraDiagnostic.enumerateAvailableCameras();
  }

  bool beginCameraPermissionResolution() {
    return _beginPermissionRequest(
      from: PermissionPhase.cameraPending,
      to: PermissionPhase.cameraResolving,
      request: PermissionRequestType.camera,
    );
  }

  bool completeCameraPermissionResolution(PermissionDecision decision) {
    if (_state.permissionPhase != PermissionPhase.cameraResolving ||
        _state.activePermissionRequest != PermissionRequestType.camera) {
      return false;
    }

    _state = _state.copyWith(
      permissionPhase: PermissionPhase.cameraResolved,
      activePermissionRequest: null,
      cameraPermissionDecision: decision,
    );
    _finishPermissionRequest(PermissionRequestType.camera);
    _notifyListeners();
    return true;
  }

  bool markLocationPermissionPending() {
    if (_state.cameraPermissionDecision == null) {
      return false;
    }

    return _transitionPermissionPhase(
      from: PermissionPhase.cameraResolved,
      to: PermissionPhase.locationPending,
    );
  }

  bool beginLocationPermissionResolution() {
    return _beginPermissionRequest(
      from: PermissionPhase.locationPending,
      to: PermissionPhase.locationResolving,
      request: PermissionRequestType.location,
    );
  }

  bool completeLocationPermissionResolution(PermissionDecision decision) {
    if (_state.permissionPhase != PermissionPhase.locationResolving ||
        _state.activePermissionRequest != PermissionRequestType.location) {
      return false;
    }

    _state = _state.copyWith(
      permissionPhase: PermissionPhase.permissionsResolved,
      activePermissionRequest: null,
      locationPermissionDecision: decision,
    );
    _finishPermissionRequest(PermissionRequestType.location);
    _notifyListeners();
    return true;
  }

  bool _beginPermissionRequest({
    required PermissionPhase from,
    required PermissionPhase to,
    required PermissionRequestType request,
  }) {
    if (!_canBeginPermissionRequest(phase: from, request: request)) {
      return false;
    }

    _updatePermissionState(
      permissionPhase: to,
      activePermissionRequest: request,
    );
    return true;
  }

  bool _canBeginPermissionRequest({
    required PermissionPhase phase,
    required PermissionRequestType request,
  }) {
    if (_isDisposed ||
        !_isInForeground ||
        _permissionRequestInFlight != null ||
        _state.permissionPhase != phase ||
        _state.isPermissionRequestInProgress) {
      return false;
    }

    switch (request) {
      case PermissionRequestType.camera:
        return phase == PermissionPhase.cameraPending;
      case PermissionRequestType.location:
        return phase == PermissionPhase.locationPending &&
            _state.cameraPermissionDecision != null;
    }
  }

  _PermissionRequestInFlight _trackPermissionRequest(
    PermissionRequestType type,
  ) {
    final request = _PermissionRequestInFlight(type);
    _permissionRequestInFlight = request;
    return request;
  }

  void _finishPermissionRequest(PermissionRequestType type) {
    final request = _permissionRequestInFlight;
    if (request?.type == type) {
      _permissionRequestInFlight = null;
    }
  }

  bool _transitionPermissionPhase({
    required PermissionPhase from,
    required PermissionPhase to,
  }) {
    if (_isDisposed ||
        _state.permissionPhase != from ||
        _state.activePermissionRequest != null) {
      return false;
    }

    _updatePermissionState(permissionPhase: to);
    return true;
  }

  void _updatePermissionState({
    required PermissionPhase permissionPhase,
    Object? activePermissionRequest = _notProvided,
  }) {
    _state = _state.copyWith(
      permissionPhase: permissionPhase,
      activePermissionRequest: identical(activePermissionRequest, _notProvided)
          ? _state.activePermissionRequest
          : activePermissionRequest,
    );
    _notifyListeners();
  }

  bool _isCurrentGeneration(int generation) {
    return !_isDisposed && _isInForeground && generation == _generation;
  }

  void _notifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Begins idempotent E0 shutdown and returns its observable completion.
  ///
  /// Resource cancellation starts synchronously. Completion additionally
  /// waits for callbacks already handed to plugins, which must retire any
  /// controller they created after this generation was invalidated.
  Future<void> shutdown() {
    final operation = _startShutdown();
    dispose();
    return operation;
  }

  Future<void> _startShutdown() {
    final activeDisposal = _disposalOperation;
    if (activeDisposal != null) {
      return activeDisposal;
    }

    _isDisposed = true;
    _isInForeground = false;
    ++_generation;
    _pendingCameraResolution = null;

    final cameraController = _activeCameraController;
    _state = _state.copyWith(cameraController: null);
    final pendingOperations = <Future<void>>[
      if (_foregroundEntryOperation case final operation?) operation,
      if (_cameraPermissionOperation case final operation?) operation,
      if (_cameraPreviewOperation case final operation?) operation,
      if (_locationPermissionOperation case final operation?) operation,
      if (_locationResumeOperation case final operation?) operation,
      if (_httpsDiagnosticOperation case final operation?) operation,
    ];
    final cleanupOperations = <Future<void>>[
      _resourceRelease,
      locationDiagnostic.dispose(),
      diagnosticHttpClient.dispose(),
      _retireCameraController(cameraController),
    ];

    late final Future<void> operation;
    operation = () async {
      await Future.wait(cleanupOperations.map(_ignoreCleanupFailure));
      await Future.wait(pendingOperations.map(_ignoreCleanupFailure));
      // Pending callbacks can reach their own stale-result cleanup only after
      // the first cancellation pass, so reconcile each idempotent owner once.
      await Future.wait<void>([
        _ignoreCleanupFailure(locationDiagnostic.dispose()),
        _ignoreCleanupFailure(diagnosticHttpClient.dispose()),
      ]);
    }()
        .whenComplete(() {
      if (!_disposalCompletion.isCompleted) {
        _disposalCompletion.complete();
      }
    });
    _disposalOperation = operation;
    return operation;
  }

  @override
  void dispose() {
    unawaited(_startShutdown());
    if (_changeNotifierDisposed) {
      return;
    }
    _changeNotifierDisposed = true;
    super.dispose();
  }
}

class _PermissionRequestInFlight {
  _PermissionRequestInFlight(this.type);

  final PermissionRequestType type;
  final Completer<void> _operationCompletion = Completer<void>();

  Future<void> get completion => _operationCompletion.future;

  void markOperationCompleted() {
    if (!_operationCompletion.isCompleted) {
      _operationCompletion.complete();
    }
  }
}

class _CameraResolution {
  const _CameraResolution({
    required this.decision,
    required this.status,
    required this.message,
    this.previewController,
    this.needsPreviewRestart = false,
  });

  final PermissionDecision decision;
  final CameraDiagnosticStatus status;
  final String message;
  final CameraController? previewController;
  final bool needsPreviewRestart;

  _CameraResolution withoutPreview() {
    return _CameraResolution(
      decision: decision,
      status: decision == PermissionDecision.granted
          ? CameraDiagnosticStatus.paused
          : status,
      message: decision == PermissionDecision.granted
          ? 'Permissão de câmera resolvida; preview será reiniciado.'
          : message,
      needsPreviewRestart: decision == PermissionDecision.granted,
    );
  }
}

const Object _notProvided = Object();
