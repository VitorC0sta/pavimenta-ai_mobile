import 'package:flutter/widgets.dart';

import '../domain/in_memory_occurrence.dart';
import '../domain/location_snapshot.dart';
import '../domain/persistent_occurrence.dart';

enum OperationCameraStatus {
  initializing,
  ready,
  permissionDenied,
  permissionDeniedPermanently,
  unavailable,
  paused,
}

enum OperationLocationStatus {
  initializing,
  ready,
  serviceDisabled,
  permissionDenied,
  permissionDeniedPermanently,
  reducedAccuracy,
  unavailable,
  paused,
}

enum OperationProcessingStatus {
  idle,
  validating,
  processing,
  succeeded,
  blockedByCooldown,
  cancelled,
  failed,
}

enum OperationReadinessTarget { camera, location, appSettings }

enum OperationFeedbackKind {
  information,
  success,
  cooldown,
  error,
}

/// Textual operation feedback whose meaning never depends only on color.
final class OperationFeedback {
  const OperationFeedback({required this.kind, required this.message});

  final OperationFeedbackKind kind;
  final String message;
}

/// UI-safe projection of an occurrence. It deliberately contains no image.
final class OperationOccurrenceSummary {
  const OperationOccurrenceSummary({
    required this.idempotencyKey,
    required this.detectedAt,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.speedKmh,
    required this.defectClass,
    required this.confidence,
  });

  factory OperationOccurrenceSummary.fromOccurrence(
    InMemoryOccurrence occurrence,
  ) {
    return OperationOccurrenceSummary(
      idempotencyKey: occurrence.idempotencyKey,
      detectedAt: occurrence.detectedAt,
      latitude: occurrence.latitude,
      longitude: occurrence.longitude,
      accuracyMeters: occurrence.accuracyMeters,
      speedKmh: occurrence.speedKmh,
      defectClass: occurrence.defectClass,
      confidence: occurrence.confidence,
    );
  }

  final String idempotencyKey;
  final DateTime detectedAt;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? speedKmh;
  final String defectClass;
  final double confidence;
}

/// Immutable presentation snapshot for the operational route.
///
/// Queue fields are aggregate and sanitized: they never carry a queue record,
/// identifier, path, coordinates, timestamp, digest, or image content.
final class OperationState {
  const OperationState({
    required this.isVisible,
    required this.isForeground,
    required this.isCurrentRoute,
    required this.lifecycleState,
    required this.cameraStatus,
    required this.previewHandle,
    required this.cameraMessage,
    required this.locationStatus,
    required this.locationSnapshot,
    required this.locationMessage,
    required this.readinessTarget,
    required this.processingStatus,
    required this.isBusy,
    required this.feedback,
    required this.lastOccurrence,
    required this.sessionOccurrenceCount,
    required this.queueHealth,
    required this.pendingCount,
    required this.queueMessage,
    required this.isPersisting,
    required this.isWakeLockEnabled,
    required this.isDisposed,
  }) : assert(pendingCount >= 0);

  factory OperationState.initial({QueueSnapshot? queueSnapshot}) {
    final snapshot = queueSnapshot ??
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 0);
    return OperationState(
      isVisible: true,
      isForeground: true,
      isCurrentRoute: true,
      lifecycleState: AppLifecycleState.resumed,
      cameraStatus: OperationCameraStatus.initializing,
      previewHandle: null,
      cameraMessage: 'Inicializando câmera',
      locationStatus: OperationLocationStatus.initializing,
      locationSnapshot: null,
      locationMessage: 'Aguardando localização precisa',
      readinessTarget: null,
      processingStatus: OperationProcessingStatus.idle,
      isBusy: false,
      feedback: null,
      lastOccurrence: null,
      sessionOccurrenceCount: 0,
      queueHealth: snapshot.health,
      pendingCount: snapshot.pendingCount,
      queueMessage: _queueMessageFor(snapshot.health),
      isPersisting: false,
      isWakeLockEnabled: false,
      isDisposed: false,
    );
  }

  final bool isVisible;
  final bool isForeground;
  final bool isCurrentRoute;
  final AppLifecycleState lifecycleState;
  final OperationCameraStatus cameraStatus;
  final Object? previewHandle;
  final String cameraMessage;
  final OperationLocationStatus locationStatus;
  final ImmutableLocationSnapshot? locationSnapshot;
  final String locationMessage;
  final OperationReadinessTarget? readinessTarget;
  final OperationProcessingStatus processingStatus;
  final bool isBusy;
  final OperationFeedback? feedback;
  final OperationOccurrenceSummary? lastOccurrence;
  final int sessionOccurrenceCount;

  /// Health reported by the last confirmed queue snapshot.
  final QueueHealth queueHealth;

  /// Persisted pending occurrences reported by the last confirmed snapshot.
  final int pendingCount;

  /// Sanitized recovery or availability message for the local queue.
  final String queueMessage;

  /// True only while the current single-flight has entered persistence.
  final bool isPersisting;

  /// True only after E2 bootstrap confirms a fully usable local queue.
  bool get isQueueReady => queueHealth == QueueHealth.ready;

  bool get isQueueRecovering => queueHealth == QueueHealth.initializing;

  /// A queue retry is only meaningful after a confirmed unavailable bootstrap.
  /// It remains independent from camera, GPS, and Diagnostic routing.
  bool get canRetryQueueBootstrap =>
      isOperationallyActive &&
      queueHealth == QueueHealth.unavailable &&
      !isBusy &&
      !isPersisting;

  final bool isWakeLockEnabled;
  final bool isDisposed;

  bool get isOperationallyActive =>
      isVisible &&
      isForeground &&
      lifecycleState == AppLifecycleState.resumed &&
      isCurrentRoute &&
      !isDisposed;

  bool get canRegister =>
      isOperationallyActive &&
      cameraStatus == OperationCameraStatus.ready &&
      previewHandle != null &&
      locationStatus == OperationLocationStatus.ready &&
      locationSnapshot != null &&
      isQueueReady &&
      !isBusy &&
      !isPersisting;

  bool get canRetryCameraReadiness =>
      isOperationallyActive &&
      readinessTarget == null &&
      !isBusy &&
      cameraStatus != OperationCameraStatus.initializing &&
      cameraStatus != OperationCameraStatus.ready &&
      cameraStatus != OperationCameraStatus.permissionDeniedPermanently &&
      cameraStatus != OperationCameraStatus.paused;

  bool get canRetryLocationReadiness =>
      isOperationallyActive &&
      readinessTarget == null &&
      !isBusy &&
      locationStatus != OperationLocationStatus.initializing &&
      locationStatus != OperationLocationStatus.ready &&
      locationStatus != OperationLocationStatus.permissionDeniedPermanently &&
      locationStatus != OperationLocationStatus.paused;

  bool get canOpenCameraSettings =>
      isOperationallyActive &&
      readinessTarget == null &&
      !isBusy &&
      cameraStatus == OperationCameraStatus.permissionDeniedPermanently;

  bool get canOpenLocationSettings =>
      isOperationallyActive &&
      readinessTarget == null &&
      !isBusy &&
      locationStatus == OperationLocationStatus.permissionDeniedPermanently;

  bool get canRetryReadiness =>
      canRetryCameraReadiness || canRetryLocationReadiness;

  /// Replaces queue projection only from a confirmed queue snapshot.
  OperationState withQueueSnapshot(QueueSnapshot snapshot) => copyWith(
        queueHealth: snapshot.health,
        pendingCount: snapshot.pendingCount,
        queueMessage: _queueMessageFor(snapshot.health),
      );

  OperationState copyWith({
    bool? isVisible,
    bool? isForeground,
    bool? isCurrentRoute,
    AppLifecycleState? lifecycleState,
    OperationCameraStatus? cameraStatus,
    Object? previewHandle = _notProvided,
    String? cameraMessage,
    OperationLocationStatus? locationStatus,
    Object? locationSnapshot = _notProvided,
    String? locationMessage,
    Object? readinessTarget = _notProvided,
    OperationProcessingStatus? processingStatus,
    bool? isBusy,
    Object? feedback = _notProvided,
    Object? lastOccurrence = _notProvided,
    int? sessionOccurrenceCount,
    QueueHealth? queueHealth,
    int? pendingCount,
    String? queueMessage,
    bool? isPersisting,
    bool? isWakeLockEnabled,
    bool? isDisposed,
  }) {
    return OperationState(
      isVisible: isVisible ?? this.isVisible,
      isForeground: isForeground ?? this.isForeground,
      isCurrentRoute: isCurrentRoute ?? this.isCurrentRoute,
      lifecycleState: lifecycleState ?? this.lifecycleState,
      cameraStatus: cameraStatus ?? this.cameraStatus,
      previewHandle: identical(previewHandle, _notProvided)
          ? this.previewHandle
          : previewHandle,
      cameraMessage: cameraMessage ?? this.cameraMessage,
      locationStatus: locationStatus ?? this.locationStatus,
      locationSnapshot: identical(locationSnapshot, _notProvided)
          ? this.locationSnapshot
          : locationSnapshot as ImmutableLocationSnapshot?,
      locationMessage: locationMessage ?? this.locationMessage,
      readinessTarget: identical(readinessTarget, _notProvided)
          ? this.readinessTarget
          : readinessTarget as OperationReadinessTarget?,
      processingStatus: processingStatus ?? this.processingStatus,
      isBusy: isBusy ?? this.isBusy,
      feedback: identical(feedback, _notProvided)
          ? this.feedback
          : feedback as OperationFeedback?,
      lastOccurrence: identical(lastOccurrence, _notProvided)
          ? this.lastOccurrence
          : lastOccurrence as OperationOccurrenceSummary?,
      sessionOccurrenceCount:
          sessionOccurrenceCount ?? this.sessionOccurrenceCount,
      queueHealth: queueHealth ?? this.queueHealth,
      pendingCount: pendingCount ?? this.pendingCount,
      queueMessage: queueMessage ?? this.queueMessage,
      isPersisting: isPersisting ?? this.isPersisting,
      isWakeLockEnabled: isWakeLockEnabled ?? this.isWakeLockEnabled,
      isDisposed: isDisposed ?? this.isDisposed,
    );
  }
}

const Object _notProvided = Object();

String _queueMessageFor(QueueHealth health) => switch (health) {
      QueueHealth.initializing => 'Recuperando fila local.',
      QueueHealth.ready => 'Fila local pronta.',
      QueueHealth.degraded => 'Atenção: a fila local precisa de recuperação.',
      QueueHealth.unavailable => 'Fila local indisponível.',
    };
