import 'dart:async';

import 'package:flutter/widgets.dart';

import '../application/delivery/occurrence_delivery_coordinator.dart'
    show DeliveryManualRetryResult;
import '../application/delivery/operation_delivery_port.dart';
import '../application/e1_ports.dart';
import '../application/e2_persistence_ports.dart';
import '../application/e3_storage_ports.dart';
import '../application/post_candidate_processor.dart';
import '../candidate/occurrence_candidate_source.dart';
import '../domain/cooldown_policy.dart';
import '../domain/delivery/delivery_presentation_state.dart';
import '../domain/in_memory_occurrence.dart';
import '../domain/location_snapshot.dart';
import '../domain/persistent_occurrence.dart';
import '../infrastructure/image_artifacts.dart';
import 'operation_state.dart';

/// Coordinates operational resources, E2 queue bootstrap, and one manual action.
final class OperationController<TPreview extends Object>
    extends ChangeNotifier {
  OperationController({
    required OccurrenceCandidateSource candidateSource,
    required PostCandidateProcessor<InMemoryOccurrence> postCandidateProcessor,
    required OperationalCameraPort<TPreview> camera,
    required OperationalLocationPort location,
    required ScreenAwakePort screenAwake,
    required Clock clock,
    PersistentOccurrenceQueue? queue,
    CooldownReferenceRestorer? cooldownRestorer,
    CooldownConfigurationUpdater? cooldownConfigurationUpdater,
    AppSettingsPort? appSettings,
    OperationalConfigurationRepository? configurationRepository,
    DeviceCredentialStatusPort? credentialStore,
    OperationDeliveryPort? delivery,
    OperationState? initialState,
  })  : _candidateSource = candidateSource,
        _postCandidateProcessor = postCandidateProcessor,
        _camera = camera,
        _location = location,
        _screenAwake = screenAwake,
        _clock = clock,
        _queue = queue,
        _cooldownRestorer = cooldownRestorer,
        _cooldownConfigurationUpdater = cooldownConfigurationUpdater,
        _appSettings = appSettings ?? const _UnavailableAppSettings(),
        _configurationRepository = configurationRepository,
        _credentialStore = credentialStore,
        _delivery = delivery,
        _state = initialState ??
            OperationState.initial(
              queueSnapshot: queue == null
                  ? const QueueSnapshot(
                      health: QueueHealth.ready,
                      pendingCount: 0,
                    )
                  : const QueueSnapshot.initializing(),
            ).copyWith(deliveryPresentation: delivery?.presentation);

  final OccurrenceCandidateSource _candidateSource;
  final PostCandidateProcessor<InMemoryOccurrence> _postCandidateProcessor;
  final OperationalCameraPort<TPreview> _camera;
  final OperationalLocationPort _location;
  final ScreenAwakePort _screenAwake;
  final Clock _clock;
  final PersistentOccurrenceQueue? _queue;
  final CooldownReferenceRestorer? _cooldownRestorer;
  final CooldownConfigurationUpdater? _cooldownConfigurationUpdater;
  final AppSettingsPort _appSettings;
  final OperationalConfigurationRepository? _configurationRepository;
  final DeviceCredentialStatusPort? _credentialStore;

  /// Aggregate projection and minimal actions of the occurrence delivery. The
  /// composition root owns the delivery; this controller never disposes it.
  final OperationDeliveryPort? _delivery;

  OperationState _state;
  StreamSubscription<DeliveryPresentationState>? _deliverySubscription;
  Future<DeliveryManualRetryResult>? _deliveryRetry;
  int _lastDeliveryPendingCount = 0;
  Future<void> _resourceTransitions = Future<void>.value();
  Future<void>? _queueBootstrap;
  Future<void>? _queueRetry;
  StreamSubscription<QueueSnapshot>? _queueSnapshotSubscription;
  QueueSnapshot? _latestConfirmedQueueSnapshot;
  bool _queueBootstrapCompleted = false;
  int _generation = 0;
  int _nextOperationToken = 0;
  int? _activeOperationToken;
  Completer<void>? _activeOperationSettled;
  bool _lifecycleStarted = false;
  bool _cameraNeedsRelease = false;
  bool _locationNeedsRelease = false;
  bool _wakeLockApplied = false;
  bool _readinessResolutionInProgress = false;
  bool _disposed = false;
  int _sendingConfigurationRefreshToken = 0;
  int _operationalConfigurationRefreshToken = 0;

  OperationState get state => _state;

  int get generation => _generation;

  /// Completes after all lifecycle work queued so far has settled.
  Future<void> get lifecycleSettled => _resourceTransitions;

  /// Completes when the independent E2 queue bootstrap settles.
  Future<void> get queueBootstrapSettled =>
      _queueBootstrap ?? Future<void>.value();

  /// Reloads persisted E3 cooldown parameters without recreating the policy.
  ///
  /// Configurações calls this before Operation reacquires resources. A load or
  /// validation failure deliberately keeps the previous in-memory thresholds
  /// and E2-restored acceptance reference intact.
  Future<void> refreshCooldownConfiguration() async {
    final configurationRepository = _configurationRepository;
    final updater = _cooldownConfigurationUpdater;
    if (configurationRepository == null || updater == null) {
      return;
    }

    final refreshToken = ++_operationalConfigurationRefreshToken;
    try {
      final configuration = await configurationRepository.load();
      if (_disposed || refreshToken != _operationalConfigurationRefreshToken) {
        return;
      }
      updater.updateMinimums(
        minimumElapsed: configuration.cooldown,
        minimumDistanceMeters: configuration.minimumDistanceMeters,
      );
    } catch (_) {
      // The last valid policy remains active. Capture and the E2 queue stay
      // independent from a recoverable non-secret settings-store failure.
    }
  }

  /// Refreshes only the sanitized readiness of future occurrence delivery.
  ///
  /// The projection checks the non-secret destination and the credential
  /// presence separately. It never reads credential material, changes local
  /// capture or queue state, or performs transport.
  Future<void> refreshSendingConfigurationStatus() async {
    final refreshToken = ++_sendingConfigurationRefreshToken;
    final configurationRepository = _configurationRepository;
    final credentialStore = _credentialStore;
    if (configurationRepository == null || credentialStore == null) {
      return;
    }

    var isReady = false;
    try {
      final configuration = await configurationRepository.load();
      if (configuration.baseUrl != null) {
        isReady = await credentialStore.hasCredential();
      }
    } catch (_) {
      // Store failures are represented conservatively as pending and never
      // interrupt local capture, persistence, or the operational route.
    }

    _publishSendingConfigurationStatus(
      refreshToken,
      isReady
          ? OperationSendingConfigurationStatus.ready
          : OperationSendingConfigurationStatus.pending,
    );
  }

  void _publishSendingConfigurationStatus(
    int refreshToken,
    OperationSendingConfigurationStatus status,
  ) {
    if (_disposed || refreshToken != _sendingConfigurationRefreshToken) {
      return;
    }
    if (_state.sendingConfigurationStatus != status) {
      _publish(_state.copyWith(sendingConfigurationStatus: status));
    }
  }

  /// Starts recovery without acquiring or releasing camera/GPS resources.
  void _startQueueBootstrapIfNeeded() {
    final queue = _queue;
    if (queue == null || _queueBootstrap != null) {
      return;
    }

    _queueSnapshotSubscription = queue.snapshots.listen(_observeQueueSnapshot);
    _queueBootstrap = () async {
      QueueSnapshot snapshot;
      try {
        snapshot = await queue.bootstrap();
        if (snapshot.isReady) {
          final anchor = await queue.readAcceptedAnchor();
          _cooldownRestorer?.restoreAcceptedAnchor(anchor);
        }
      } catch (_) {
        snapshot = const QueueSnapshot(
          health: QueueHealth.unavailable,
          pendingCount: 0,
        );
      }
      _queueBootstrapCompleted = true;
      if (!_disposed) {
        final confirmed = _latestConfirmedQueueSnapshot ?? snapshot;
        _publish(_state.withQueueSnapshot(confirmed));
        _startDeliveryAfterBootstrap(confirmed);
      }
    }();
  }

  /// Subscribes once to the aggregate delivery projection. The delivery itself
  /// is owned by the composition root and is not touched by capture, camera,
  /// GPS or the Diagnostic.
  void _startDeliveryObservationIfNeeded() {
    final delivery = _delivery;
    if (delivery == null || _deliverySubscription != null) {
      return;
    }
    _deliverySubscription = delivery.presentations.listen(_observeDelivery);
    _observeDelivery(delivery.presentation);
  }

  void _observeDelivery(DeliveryPresentationState presentation) {
    if (_disposed || _state.deliveryPresentation == presentation) {
      return;
    }
    _publish(_state.copyWith(deliveryPresentation: presentation));
  }

  /// Allows delivery only once the local queue is confirmed fully usable. A
  /// degraded or unavailable queue keeps delivery stopped.
  void _startDeliveryAfterBootstrap(QueueSnapshot confirmed) {
    _lastDeliveryPendingCount = confirmed.pendingCount;
    if (confirmed.isReady) {
      _delivery?.start();
    }
  }

  /// Tells the delivery about a new pending item from a confirmed aggregate.
  /// Removals and unchanged counts need no notification.
  void _notifyDeliveryOfQueueSnapshot(QueueSnapshot snapshot) {
    final previous = _lastDeliveryPendingCount;
    _lastDeliveryPendingCount = snapshot.pendingCount;
    if (snapshot.isReady && snapshot.pendingCount > previous) {
      _delivery?.onQueueChanged();
    }
  }

  /// Manual "try sending again", offered only while the projection allows it.
  ///
  /// It neither creates an occurrence, nor changes the credential, nor removes
  /// an item, and it never touches camera, GPS or the Diagnostic. Concurrent
  /// calls share one request.
  Future<DeliveryManualRetryResult> retryDeliveryManually() {
    final active = _deliveryRetry;
    if (active != null) {
      return active;
    }
    final delivery = _delivery;
    if (_disposed || delivery == null || !_state.canRetryDelivery) {
      return Future<DeliveryManualRetryResult>.value(
        DeliveryManualRetryResult.notApplied,
      );
    }
    final retry = () async {
      try {
        return await delivery.retryManually();
      } catch (_) {
        return DeliveryManualRetryResult.notApplied;
      }
    }();
    _deliveryRetry = retry;
    unawaited(
      retry.whenComplete(() {
        if (identical(_deliveryRetry, retry)) {
          _deliveryRetry = null;
        }
      }),
    );
    return retry;
  }

  /// Applies only confirmed queue aggregates after bootstrap has restored
  /// cooldown state. A transient `initializing` event has no confirmed count.
  void _observeQueueSnapshot(QueueSnapshot snapshot) {
    if (_disposed || snapshot.health == QueueHealth.initializing) {
      return;
    }
    _latestConfirmedQueueSnapshot = snapshot;
    if (_queueBootstrapCompleted) {
      _publish(_state.withQueueSnapshot(snapshot));
      _notifyDeliveryOfQueueSnapshot(snapshot);
    }
  }

  /// Starts resource ownership for the current operational context once.
  Future<void> startOperationalLifecycle({
    AppLifecycleState? lifecycleState,
    bool? isVisible,
    bool? isForeground,
    bool? isCurrentRoute,
  }) {
    if (_disposed) {
      return _resourceTransitions;
    }
    _startQueueBootstrapIfNeeded();
    _startDeliveryObservationIfNeeded();
    unawaited(refreshSendingConfigurationStatus());
    if (_lifecycleStarted) {
      if (lifecycleState != null ||
          isVisible != null ||
          isForeground != null ||
          isCurrentRoute != null) {
        return updateOperationalContext(
          lifecycleState: lifecycleState,
          isVisible: isVisible,
          isForeground: isForeground,
          isCurrentRoute: isCurrentRoute,
        );
      }
      return _resourceTransitions;
    }

    final contextChanged =
        (lifecycleState != null && lifecycleState != _state.lifecycleState) ||
            (isVisible != null && isVisible != _state.isVisible) ||
            (isForeground != null && isForeground != _state.isForeground) ||
            (isCurrentRoute != null && isCurrentRoute != _state.isCurrentRoute);
    if (contextChanged) {
      return updateOperationalContext(
        lifecycleState: lifecycleState,
        isVisible: isVisible,
        isForeground: isForeground,
        isCurrentRoute: isCurrentRoute,
      );
    }

    _lifecycleStarted = true;
    _enqueueResourceTransition(
      transitionGeneration: _generation,
      shouldBeActive: _state.isOperationallyActive,
    );
    return _resourceTransitions;
  }

  /// Publishes a camera callback only when it belongs to the current generation.
  void publishCameraState({
    required int generation,
    required OperationCameraStatus status,
    String? message,
  }) {
    if (!_accepts(generation)) {
      return;
    }
    final preview =
        status == OperationCameraStatus.ready ? _camera.previewHandle : null;
    _publish(
      _state.copyWith(
        cameraStatus: preview == null && status == OperationCameraStatus.ready
            ? OperationCameraStatus.unavailable
            : status,
        previewHandle: preview,
        cameraMessage: message ?? _cameraMessage(status, preview != null),
      ),
    );
  }

  /// Freezes a location callback before exposing it to readiness or the UI.
  void publishLocationState({
    required int generation,
    required OperationLocationStatus status,
    LocationSnapshot? snapshot,
    String? message,
  }) {
    if (!_accepts(generation)) {
      return;
    }

    ImmutableLocationSnapshot? immutableSnapshot;
    var effectiveStatus = status;
    if (status == OperationLocationStatus.ready && snapshot != null) {
      try {
        immutableSnapshot = _freezeSnapshot(snapshot);
      } catch (_) {
        effectiveStatus = OperationLocationStatus.unavailable;
      }
    } else if (status == OperationLocationStatus.ready) {
      effectiveStatus = OperationLocationStatus.unavailable;
    }

    _publish(
      _state.copyWith(
        locationStatus: effectiveStatus,
        locationSnapshot: immutableSnapshot,
        locationMessage:
            message ?? _locationMessage(effectiveStatus, immutableSnapshot),
      ),
    );
  }

  /// Records wake-lock state only for a current lifecycle generation.
  void publishWakeLockState({
    required int generation,
    required bool isEnabled,
  }) {
    if (!_accepts(generation)) {
      return;
    }
    _publish(_state.copyWith(isWakeLockEnabled: isEnabled));
  }

  /// Suspends Operation and settles all owned work before another route starts.
  ///
  /// The route is marked non-current synchronously, so registration and stale
  /// callbacks are blocked before this method first awaits. Resource release is
  /// sequenced after any in-flight registration has completed its cleanup.
  Future<void> suspendForDiagnostic() => _suspendForRouteNavigation();

  /// Applies the same ownership hand-off before opening Configurações.
  ///
  /// Configurações does not own camera, location, or wake-lock resources, but
  /// Operation must still release them before its route is covered.
  Future<void> suspendForSettings() => _suspendForRouteNavigation();

  Future<void> _suspendForRouteNavigation() {
    if (_disposed) {
      return _resourceTransitions;
    }
    final processingSettled = _activeOperationSettled?.future;
    return _updateOperationalContext(
      isCurrentRoute: false,
      deactivationBarrier: processingSettled,
    );
  }

  /// Applies context changes immediately and serializes cleanup/reacquisition.
  Future<void> updateOperationalContext({
    bool? isVisible,
    bool? isForeground,
    bool? isCurrentRoute,
    AppLifecycleState? lifecycleState,
    bool forceResourceSync = false,
  }) {
    return _updateOperationalContext(
      isVisible: isVisible,
      isForeground: isForeground,
      isCurrentRoute: isCurrentRoute,
      lifecycleState: lifecycleState,
      forceResourceSync: forceResourceSync,
    );
  }

  /// Rechecks only the camera after an explicit action.
  Future<void> retryCameraReadiness() =>
      _retryReadiness(OperationReadinessTarget.camera);

  /// Rechecks only location after an explicit action.
  Future<void> retryLocationReadiness() =>
      _retryReadiness(OperationReadinessTarget.location);

  /// Retries only a confirmed unavailable E2 queue bootstrap.
  ///
  /// Queue recovery does not acquire or release camera/GPS resources and does
  /// not change route state, keeping the preserved Diagnostic action visible.
  Future<void> retryQueueBootstrap() {
    final activeRetry = _queueRetry;
    if (activeRetry != null) {
      return activeRetry;
    }

    final queue = _queue;
    if (_disposed || queue == null || !_state.canRetryQueueBootstrap) {
      return Future<void>.value();
    }

    _queueBootstrapCompleted = false;
    _publish(_state.withQueueSnapshot(const QueueSnapshot.initializing()));
    final retry = _retryQueueBootstrap(queue);
    _queueRetry = retry;
    return retry;
  }

  Future<void> _retryQueueBootstrap(PersistentOccurrenceQueue queue) async {
    QueueSnapshot snapshot;
    try {
      snapshot = await queue.retryBootstrap();
      if (snapshot.isReady) {
        final anchor = await queue.readAcceptedAnchor();
        _cooldownRestorer?.restoreAcceptedAnchor(anchor);
      }
    } catch (_) {
      snapshot = const QueueSnapshot(
        health: QueueHealth.unavailable,
        pendingCount: 0,
      );
    } finally {
      _queueRetry = null;
    }

    _queueBootstrapCompleted = true;
    if (!_disposed) {
      _latestConfirmedQueueSnapshot = snapshot;
      _publish(_state.withQueueSnapshot(snapshot));
      _startDeliveryAfterBootstrap(snapshot);
    }
  }

  /// Opens Android application settings after permanent camera denial.
  Future<void> openCameraPermissionSettings() =>
      _openPermissionSettings(OperationReadinessTarget.camera);

  /// Opens Android application settings after permanent location denial.
  Future<void> openLocationPermissionSettings() =>
      _openPermissionSettings(OperationReadinessTarget.location);

  Future<void> _retryReadiness(OperationReadinessTarget target) {
    final canRetry = switch (target) {
      OperationReadinessTarget.camera => _state.canRetryCameraReadiness,
      OperationReadinessTarget.location => _state.canRetryLocationReadiness,
      OperationReadinessTarget.appSettings => false,
    };
    if (_disposed || !canRetry || _readinessResolutionInProgress) {
      return _resourceTransitions;
    }

    _readinessResolutionInProgress = true;
    final transitionGeneration = _generation;
    _publish(
      target == OperationReadinessTarget.camera
          ? _state.copyWith(
              cameraStatus: OperationCameraStatus.initializing,
              previewHandle: null,
              cameraMessage: 'Verificando câmera',
              readinessTarget: target,
            )
          : _state.copyWith(
              locationStatus: OperationLocationStatus.initializing,
              locationSnapshot: null,
              locationMessage: 'Verificando localização precisa',
              readinessTarget: target,
            ),
    );

    _resourceTransitions = _resourceTransitions.then((_) async {
      if (!_isActiveGeneration(transitionGeneration)) {
        return;
      }
      if (target == OperationReadinessTarget.camera) {
        await _retryCamera(transitionGeneration);
      } else {
        await _retryLocation(transitionGeneration);
      }
    }).whenComplete(() {
      _readinessResolutionInProgress = false;
      if (_accepts(transitionGeneration)) {
        _publish(_state.copyWith(readinessTarget: null));
      }
    }).catchError((Object _) {
      // Controlled adapter failures are mapped by the target retry.
    });
    return _resourceTransitions;
  }

  Future<void> _openPermissionSettings(OperationReadinessTarget target) {
    final canOpen = switch (target) {
      OperationReadinessTarget.camera => _state.canOpenCameraSettings,
      OperationReadinessTarget.location => _state.canOpenLocationSettings,
      OperationReadinessTarget.appSettings => false,
    };
    if (_disposed || !canOpen || _readinessResolutionInProgress) {
      return _resourceTransitions;
    }

    _readinessResolutionInProgress = true;
    final transitionGeneration = _generation;
    _publish(
      _state.copyWith(
        readinessTarget: OperationReadinessTarget.appSettings,
        feedback: const OperationFeedback(
          kind: OperationFeedbackKind.information,
          message:
              'Ative a permissão necessária nas configurações e retorne ao aplicativo.',
        ),
      ),
    );
    _resourceTransitions = _resourceTransitions.then((_) async {
      final opened = await _appSettings.open();
      if (_accepts(transitionGeneration) && !opened) {
        _publish(
          _state.copyWith(
            feedback: const OperationFeedback(
              kind: OperationFeedbackKind.error,
              message: 'Não foi possível abrir as configurações do Android.',
            ),
          ),
        );
      }
    }).whenComplete(() {
      _readinessResolutionInProgress = false;
      if (_accepts(transitionGeneration)) {
        _publish(_state.copyWith(readinessTarget: null));
      }
    }).catchError((Object _) {
      if (_accepts(transitionGeneration)) {
        _publish(
          _state.copyWith(
            readinessTarget: null,
            feedback: const OperationFeedback(
              kind: OperationFeedbackKind.error,
              message: 'Não foi possível abrir as configurações do Android.',
            ),
          ),
        );
      }
    });
    return _resourceTransitions;
  }

  Future<void> _updateOperationalContext({
    bool? isVisible,
    bool? isForeground,
    bool? isCurrentRoute,
    AppLifecycleState? lifecycleState,
    bool forceResourceSync = false,
    Future<void>? deactivationBarrier,
  }) {
    if (_disposed) {
      return _resourceTransitions;
    }

    // Android permission sheets transiently report `inactive`. Tearing down
    // here invalidates the permission result and makes `resumed` immediately
    // start the same request again. Keep the initializing state stable until
    // that sheet settles; real pauses/hidden/detached states still deactivate.
    if (_readinessResolutionInProgress &&
        lifecycleState == AppLifecycleState.inactive) {
      return _resourceTransitions;
    }

    final nextVisible = isVisible ?? _state.isVisible;
    final nextForeground = isForeground ?? _state.isForeground;
    final nextCurrentRoute = isCurrentRoute ?? _state.isCurrentRoute;
    final nextLifecycle = lifecycleState ?? _state.lifecycleState;
    final unchanged = nextVisible == _state.isVisible &&
        nextForeground == _state.isForeground &&
        nextCurrentRoute == _state.isCurrentRoute &&
        nextLifecycle == _state.lifecycleState;
    if (unchanged && !forceResourceSync) {
      return _resourceTransitions;
    }

    _lifecycleStarted = true;
    final wasBusy = _state.isBusy;
    _invalidateActiveOperation();
    final transitionGeneration = _generation;
    final willBeActive = nextVisible &&
        nextForeground &&
        nextLifecycle == AppLifecycleState.resumed &&
        nextCurrentRoute;

    _publish(
      _state.copyWith(
        isVisible: nextVisible,
        isForeground: nextForeground,
        isCurrentRoute: nextCurrentRoute,
        lifecycleState: nextLifecycle,
        cameraStatus: willBeActive
            ? OperationCameraStatus.initializing
            : OperationCameraStatus.paused,
        previewHandle: null,
        cameraMessage: willBeActive ? 'Inicializando câmera' : 'Câmera pausada',
        locationStatus: willBeActive
            ? OperationLocationStatus.initializing
            : OperationLocationStatus.paused,
        locationSnapshot: null,
        locationMessage: willBeActive
            ? 'Aguardando localização precisa'
            : 'Localização pausada',
        readinessTarget: null,
        processingStatus: wasBusy
            ? OperationProcessingStatus.cancelled
            : _state.processingStatus,
        isBusy: false,
        isPersisting: false,
        feedback: wasBusy
            ? const OperationFeedback(
                kind: OperationFeedbackKind.information,
                message: 'Registro cancelado por mudança do aplicativo.',
              )
            : _state.feedback,
        lastOccurrence: willBeActive ? _state.lastOccurrence : null,
        isWakeLockEnabled: willBeActive && _wakeLockApplied,
      ),
    );

    _enqueueResourceTransition(
      transitionGeneration: transitionGeneration,
      shouldBeActive: willBeActive,
      deactivationBarrier: deactivationBarrier,
    );
    return _resourceTransitions;
  }

  /// Explicit invalidation hook for lifecycle/navigation coordinators.
  void invalidatePendingOperation() {
    if (_disposed) {
      return;
    }
    final wasBusy = _state.isBusy;
    _invalidateActiveOperation();
    if (wasBusy) {
      _publish(
        _state.copyWith(
          processingStatus: OperationProcessingStatus.cancelled,
          isBusy: false,
          isPersisting: false,
          feedback: const OperationFeedback(
            kind: OperationFeedbackKind.information,
            message: 'Registro cancelado por mudança do aplicativo.',
          ),
        ),
      );
    }
  }

  /// Starts at most one manual operation and captures time/location synchronously.
  Future<CandidateResult<InMemoryOccurrence>?> registerManualPothole() async {
    if (_disposed || _activeOperationToken != null) {
      return null;
    }
    if (!_state.canRegister) {
      _publish(
        _state.copyWith(
          feedback: const OperationFeedback(
            kind: OperationFeedbackKind.information,
            message:
                'Registro indisponível: verifique câmera, GPS e aplicativo.',
          ),
        ),
      );
      return null;
    }

    final operationToken = ++_nextOperationToken;
    _activeOperationToken = operationToken;
    final operationSettled = Completer<void>();
    _activeOperationSettled = operationSettled;
    final operationGeneration = _generation;

    final attemptedAt = _clock.now();
    final latestSnapshot = _location.latestValidSnapshot;
    final ImmutableLocationSnapshot frozenSnapshot;
    try {
      if (latestSnapshot == null) {
        throw StateError('No valid location snapshot.');
      }
      frozenSnapshot = _freezeSnapshot(latestSnapshot);
    } catch (_) {
      _activeOperationToken = null;
      if (identical(_activeOperationSettled, operationSettled)) {
        _activeOperationSettled = null;
      }
      operationSettled.complete();
      _publish(
        _state.copyWith(
          locationStatus: OperationLocationStatus.unavailable,
          locationSnapshot: null,
          processingStatus: OperationProcessingStatus.failed,
          isBusy: false,
          feedback: const OperationFeedback(
            kind: OperationFeedbackKind.error,
            message: 'GPS indisponível para registrar o buraco.',
          ),
        ),
      );
      return const CandidatePreconditionFailed(
        CandidatePrecondition.invalidLocation,
      );
    }

    _publish(
      _state.copyWith(
        processingStatus: OperationProcessingStatus.validating,
        isBusy: true,
        isPersisting: false,
        feedback: null,
      ),
    );

    CandidateResult<InMemoryOccurrence>? result;
    try {
      final sourceCandidate = await _candidateSource.requestCandidate(
        CandidateSeed(
          observedAt: attemptedAt,
          location: frozenSnapshot,
          acquireImage: () => _acquireImageFor(
            operationGeneration,
            operationToken,
          ),
        ),
      );
      if (!_isOperationCurrent(operationGeneration, operationToken)) {
        return null;
      }

      final guardedCandidate = CandidateInput(
        observedAt: attemptedAt,
        location: frozenSnapshot,
        defectClass: sourceCandidate.defectClass,
        confidence: sourceCandidate.confidence,
        acquireImage: sourceCandidate.acquireImage,
        processingGuard: () =>
            _isOperationCurrent(operationGeneration, operationToken),
        onPersistenceStarted: () {
          if (_isOperationCurrent(operationGeneration, operationToken)) {
            _publish(_state.copyWith(isPersisting: true));
          }
        },
      );
      _publish(
        _state.copyWith(
          processingStatus: OperationProcessingStatus.processing,
          isPersisting: false,
        ),
      );

      result = await _postCandidateProcessor.process(guardedCandidate);
      if (!_isOperationCurrent(operationGeneration, operationToken)) {
        // A created result reaches this controller only after durable acceptance.
        // Its JPEG belongs to the queue, so a stale presentation callback must
        // not withdraw or dispose it.
        return null;
      }

      _applyResult(result);
      return result;
    } catch (_) {
      if (_isOperationCurrent(operationGeneration, operationToken)) {
        result = const CandidateFailed(CandidateFailureStage.unknown);
        _applyResult(result);
      }
      return result;
    } finally {
      if (_activeOperationToken == operationToken) {
        _activeOperationToken = null;
        if (_accepts(operationGeneration)) {
          _publish(_state.copyWith(isBusy: false, isPersisting: false));
        }
      }
      if (identical(_activeOperationSettled, operationSettled)) {
        _activeOperationSettled = null;
      }
      if (!operationSettled.isCompleted) {
        operationSettled.complete();
      }
    }
  }

  Future<TemporaryCapture> _acquireImageFor(
    int operationGeneration,
    int operationToken,
  ) async {
    if (!_isOperationCurrent(operationGeneration, operationToken)) {
      throw StateError('Operation is no longer current.');
    }
    final capture = await _camera.takePicture();
    if (!_isOperationCurrent(operationGeneration, operationToken)) {
      await capture.dispose();
      throw StateError('Operation became stale during capture.');
    }
    return capture;
  }

  void _enqueueResourceTransition({
    required int transitionGeneration,
    required bool shouldBeActive,
    Future<void>? deactivationBarrier,
  }) {
    _resourceTransitions = _resourceTransitions.then((_) async {
      if (!shouldBeActive) {
        await _deactivateResources(processingBarrier: deactivationBarrier);
        return;
      }
      if (!_accepts(transitionGeneration) || !_state.isOperationallyActive) {
        return;
      }
      await _activateResources(transitionGeneration);
    }).catchError((Object _) {
      // Every plugin boundary is handled locally. This keeps later queued
      // lifecycle transitions runnable if an unexpected implementation leaks.
    });
  }

  Future<void> _activateResources(int transitionGeneration) async {
    _readinessResolutionInProgress = true;
    try {
      await _enableWakeLock(transitionGeneration);
      if (!_isActiveGeneration(transitionGeneration)) {
        await _deactivateResources();
        return;
      }

      _cameraNeedsRelease = true;
      try {
        await _camera.acquirePreview();
        if (!_isActiveGeneration(transitionGeneration)) {
          await _deactivateResources();
          return;
        }
        publishCameraState(
          generation: transitionGeneration,
          status: OperationCameraStatus.ready,
        );
      } on OperationalCameraException catch (error) {
        if (_accepts(transitionGeneration)) {
          final status = switch (error.failure) {
            OperationalCameraFailure.permissionDenied =>
              OperationCameraStatus.permissionDenied,
            OperationalCameraFailure.permissionDeniedPermanently =>
              OperationCameraStatus.permissionDeniedPermanently,
            OperationalCameraFailure.unavailable =>
              OperationCameraStatus.unavailable,
          };
          publishCameraState(
            generation: transitionGeneration,
            status: status,
          );
        }
      } catch (_) {
        if (_accepts(transitionGeneration)) {
          publishCameraState(
            generation: transitionGeneration,
            status: OperationCameraStatus.unavailable,
            message: 'Câmera indisponível',
          );
        }
      }

      if (!_isActiveGeneration(transitionGeneration)) {
        await _deactivateResources();
        return;
      }

      _locationNeedsRelease = true;
      try {
        await _location.acquireForegroundUpdates();
        if (!_isActiveGeneration(transitionGeneration)) {
          await _deactivateResources();
          return;
        }
        final snapshot = _location.latestValidSnapshot;
        publishLocationState(
          generation: transitionGeneration,
          status: snapshot == null
              ? OperationLocationStatus.unavailable
              : OperationLocationStatus.ready,
          snapshot: snapshot,
        );
      } on OperationalLocationException catch (error) {
        if (_accepts(transitionGeneration)) {
          final status = switch (error.failure) {
            OperationalLocationFailure.serviceDisabled =>
              OperationLocationStatus.serviceDisabled,
            OperationalLocationFailure.permissionDenied =>
              OperationLocationStatus.permissionDenied,
            OperationalLocationFailure.permissionDeniedPermanently =>
              OperationLocationStatus.permissionDeniedPermanently,
            OperationalLocationFailure.reducedAccuracy =>
              OperationLocationStatus.reducedAccuracy,
            OperationalLocationFailure.positionUnavailable =>
              OperationLocationStatus.unavailable,
          };
          publishLocationState(
            generation: transitionGeneration,
            status: status,
          );
        }
      } catch (_) {
        if (_accepts(transitionGeneration)) {
          publishLocationState(
            generation: transitionGeneration,
            status: OperationLocationStatus.unavailable,
            message: 'Posição indisponível',
          );
        }
      }
    } finally {
      // A permission plugin may complete before Android dispatches `resumed`.
      // Do not replay the transient `inactive` here: doing so would release
      // readiness and make the delayed `resumed` request the permission again.
      // Real background transitions (`paused`, `hidden`, `detached`) are never
      // ignored by _updateOperationalContext and still release resources.
      _readinessResolutionInProgress = false;
    }
  }

  Future<void> _retryCamera(int transitionGeneration) async {
    _cameraNeedsRelease = true;
    try {
      await _camera.acquirePreview();
      if (_isActiveGeneration(transitionGeneration)) {
        publishCameraState(
          generation: transitionGeneration,
          status: OperationCameraStatus.ready,
        );
      }
    } on OperationalCameraException catch (error) {
      if (_accepts(transitionGeneration)) {
        publishCameraState(
          generation: transitionGeneration,
          status: switch (error.failure) {
            OperationalCameraFailure.permissionDenied =>
              OperationCameraStatus.permissionDenied,
            OperationalCameraFailure.permissionDeniedPermanently =>
              OperationCameraStatus.permissionDeniedPermanently,
            OperationalCameraFailure.unavailable =>
              OperationCameraStatus.unavailable,
          },
        );
      }
    } catch (_) {
      if (_accepts(transitionGeneration)) {
        publishCameraState(
          generation: transitionGeneration,
          status: OperationCameraStatus.unavailable,
          message: 'Câmera indisponível',
        );
      }
    }
  }

  Future<void> _retryLocation(int transitionGeneration) async {
    _locationNeedsRelease = true;
    try {
      await _location.acquireForegroundUpdates();
      if (_isActiveGeneration(transitionGeneration)) {
        final snapshot = _location.latestValidSnapshot;
        publishLocationState(
          generation: transitionGeneration,
          status: snapshot == null
              ? OperationLocationStatus.unavailable
              : OperationLocationStatus.ready,
          snapshot: snapshot,
        );
      }
    } on OperationalLocationException catch (error) {
      if (_accepts(transitionGeneration)) {
        publishLocationState(
          generation: transitionGeneration,
          status: switch (error.failure) {
            OperationalLocationFailure.serviceDisabled =>
              OperationLocationStatus.serviceDisabled,
            OperationalLocationFailure.permissionDenied =>
              OperationLocationStatus.permissionDenied,
            OperationalLocationFailure.permissionDeniedPermanently =>
              OperationLocationStatus.permissionDeniedPermanently,
            OperationalLocationFailure.reducedAccuracy =>
              OperationLocationStatus.reducedAccuracy,
            OperationalLocationFailure.positionUnavailable =>
              OperationLocationStatus.unavailable,
          },
        );
      }
    } catch (_) {
      if (_accepts(transitionGeneration)) {
        publishLocationState(
          generation: transitionGeneration,
          status: OperationLocationStatus.unavailable,
          message: 'Posição indisponível',
        );
      }
    }
  }

  Future<void> _deactivateResources({
    Future<void>? processingBarrier,
  }) async {
    await _disableWakeLock();
    try {
      await processingBarrier;
    } catch (_) {
      // Resource cleanup must continue if an implementation leaks an error.
    }
    if (_locationNeedsRelease) {
      _locationNeedsRelease = false;
      try {
        await _location.release();
      } catch (_) {
        // Resource release remains idempotent and does not reactivate state.
      }
    }
    if (_cameraNeedsRelease) {
      _cameraNeedsRelease = false;
      try {
        await _camera.release();
      } catch (_) {
        // Resource release remains idempotent and does not reactivate state.
      }
    }
  }

  Future<void> _enableWakeLock(int transitionGeneration) async {
    if (_wakeLockApplied) {
      return;
    }
    try {
      await _screenAwake.setEnabled(true);
      if (!_isActiveGeneration(transitionGeneration)) {
        await _screenAwake.setEnabled(false);
        _wakeLockApplied = false;
        return;
      }
      _wakeLockApplied = true;
      publishWakeLockState(
        generation: transitionGeneration,
        isEnabled: true,
      );
    } catch (_) {
      _wakeLockApplied = false;
      try {
        await _screenAwake.setEnabled(false);
      } catch (_) {
        // Best-effort compensation prevents an enable failure leaking state.
      }
      if (_accepts(transitionGeneration)) {
        _publish(
          _state.copyWith(
            isWakeLockEnabled: false,
            feedback: const OperationFeedback(
              kind: OperationFeedbackKind.error,
              message: 'Não foi possível manter a tela ligada.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _disableWakeLock() async {
    if (!_wakeLockApplied && !_state.isWakeLockEnabled) {
      return;
    }
    _wakeLockApplied = false;
    try {
      await _screenAwake.setEnabled(false);
    } catch (_) {
      if (!_disposed) {
        _publish(
          _state.copyWith(
            isWakeLockEnabled: false,
            feedback: const OperationFeedback(
              kind: OperationFeedbackKind.error,
              message: 'Não foi possível confirmar o desligamento da tela.',
            ),
          ),
        );
      }
    }
  }

  void _applyResult(CandidateResult<InMemoryOccurrence> result) {
    if (result is CandidateCreated<InMemoryOccurrence>) {
      _state = _state.copyWith(
        processingStatus: OperationProcessingStatus.succeeded,
        feedback: const OperationFeedback(
          kind: OperationFeedbackKind.success,
          message: 'Buraco salvo na fila local.',
        ),
        lastOccurrence:
            OperationOccurrenceSummary.fromOccurrence(result.occurrence),
        sessionOccurrenceCount: _state.sessionOccurrenceCount + 1,
      );
      return;
    }
    if (result is CandidateBlockedByCooldown<InMemoryOccurrence>) {
      _state = _state.copyWith(
        processingStatus: OperationProcessingStatus.blockedByCooldown,
        feedback: const OperationFeedback(
          kind: OperationFeedbackKind.cooldown,
          message:
              'Registro ignorado: tempo e distância ainda abaixo dos mínimos.',
        ),
      );
      return;
    }
    if (result is CandidateCancelled<InMemoryOccurrence>) {
      _state = _state.copyWith(
        processingStatus: OperationProcessingStatus.cancelled,
        feedback: const OperationFeedback(
          kind: OperationFeedbackKind.information,
          message: 'Registro cancelado por mudança do aplicativo.',
        ),
      );
      return;
    }
    if (result is CandidateAlreadyPersistedEquivalent<InMemoryOccurrence>) {
      _state = _state.copyWith(
        processingStatus: OperationProcessingStatus.idle,
        feedback: const OperationFeedback(
          kind: OperationFeedbackKind.information,
          message: 'A ocorrência já está salva na fila local.',
        ),
      );
      return;
    }
    final failureMessage = switch (result) {
      CandidatePreconditionFailed<InMemoryOccurrence>(
        reason: CandidatePrecondition.invalidLocation,
      ) =>
        'GPS indisponível para registrar o buraco.',
      CandidatePreconditionFailed<InMemoryOccurrence>() =>
        'Dados inválidos: o registro manual não pôde ser criado.',
      CandidateFailed<InMemoryOccurrence>(
        stage: CandidateFailureStage.imageAcquisition,
      ) =>
        'Falha na captura: não foi possível obter a imagem.',
      CandidateFailed<InMemoryOccurrence>(
        stage: CandidateFailureStage.imagePreparation,
      ) =>
        'Falha na imagem: não foi possível preparar o JPEG.',
      CandidateFailed<InMemoryOccurrence>(
        stage: CandidateFailureStage.cleanup,
      ) =>
        'Falha na imagem: a limpeza temporária não foi concluída.',
      CandidateFailed<InMemoryOccurrence>(
        stage: CandidateFailureStage.identityGeneration,
      ) =>
        'Falha ao identificar a ocorrência em memória.',
      CandidateFailed<InMemoryOccurrence>(
        stage: CandidateFailureStage.durableAcceptance,
      ) =>
        'Falha ao salvar a ocorrência na fila local.',
      CandidateFailed<InMemoryOccurrence>(
        stage: CandidateFailureStage.occurrenceCreation,
      ) =>
        'Falha ao criar a ocorrência em memória.',
      _ => 'Não foi possível registrar o buraco.',
    };
    _state = _state.copyWith(
      processingStatus: OperationProcessingStatus.failed,
      feedback: OperationFeedback(
        kind: OperationFeedbackKind.error,
        message: failureMessage,
      ),
    );
  }

  ImmutableLocationSnapshot _freezeSnapshot(LocationSnapshot snapshot) {
    return ImmutableLocationSnapshot(
      point: snapshot.point,
      accuracyMeters: snapshot.accuracyMeters,
      speedMetersPerSecond: snapshot.speedMetersPerSecond,
    );
  }

  bool _isOperationCurrent(int operationGeneration, int operationToken) {
    return _accepts(operationGeneration) &&
        _state.isOperationallyActive &&
        _activeOperationToken == operationToken;
  }

  bool _isActiveGeneration(int callbackGeneration) =>
      _accepts(callbackGeneration) && _state.isOperationallyActive;

  bool _accepts(int callbackGeneration) =>
      !_disposed && callbackGeneration == _generation;

  void _invalidateActiveOperation() {
    _generation++;
    _activeOperationToken = null;
  }

  void _publish(OperationState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  String _cameraMessage(OperationCameraStatus status, bool hasPreview) {
    return switch (status) {
      OperationCameraStatus.initializing => 'Inicializando câmera',
      OperationCameraStatus.ready when hasPreview => 'Câmera traseira pronta',
      OperationCameraStatus.ready => 'Preview da câmera indisponível',
      OperationCameraStatus.permissionDenied => 'Permissão de câmera negada',
      OperationCameraStatus.permissionDeniedPermanently =>
        'Habilite a câmera nas configurações do Android',
      OperationCameraStatus.unavailable => 'Câmera indisponível',
      OperationCameraStatus.paused => 'Câmera pausada',
    };
  }

  String _locationMessage(
    OperationLocationStatus status,
    ImmutableLocationSnapshot? snapshot,
  ) {
    return switch (status) {
      OperationLocationStatus.initializing => 'Aguardando localização precisa',
      OperationLocationStatus.ready when snapshot != null => 'GPS disponível',
      OperationLocationStatus.ready => 'Posição indisponível',
      OperationLocationStatus.serviceDisabled =>
        'Serviço de localização desativado',
      OperationLocationStatus.permissionDenied =>
        'Permissão de localização negada',
      OperationLocationStatus.permissionDeniedPermanently =>
        'Habilite a localização nas configurações do Android',
      OperationLocationStatus.reducedAccuracy =>
        'Localização precisa necessária',
      OperationLocationStatus.unavailable => 'Posição indisponível',
      OperationLocationStatus.paused => 'Localização pausada',
    };
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _invalidateActiveOperation();
    _state = _state.copyWith(
      isVisible: false,
      isForeground: false,
      isCurrentRoute: false,
      isDisposed: true,
      cameraStatus: OperationCameraStatus.paused,
      previewHandle: null,
      locationStatus: OperationLocationStatus.paused,
      locationSnapshot: null,
      lastOccurrence: null,
      isBusy: false,
      isPersisting: false,
      processingStatus: _state.isBusy
          ? OperationProcessingStatus.cancelled
          : _state.processingStatus,
      isWakeLockEnabled: false,
    );
    _disposed = true;
    final queueSnapshotSubscription = _queueSnapshotSubscription;
    _queueSnapshotSubscription = null;
    if (queueSnapshotSubscription != null) {
      unawaited(queueSnapshotSubscription.cancel());
    }
    final deliverySubscription = _deliverySubscription;
    _deliverySubscription = null;
    if (deliverySubscription != null) {
      unawaited(deliverySubscription.cancel());
    }
    _enqueueResourceTransition(
      transitionGeneration: _generation,
      shouldBeActive: false,
    );
    super.dispose();
  }
}

final class _UnavailableAppSettings implements AppSettingsPort {
  const _UnavailableAppSettings();

  @override
  Future<bool> open() async => false;
}
