import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/cooldown_policy.dart';
import 'package:pavimenta_ai_mobile/domain/distance_calculator.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/operation/operation_controller.dart';

void main() {
  // **Validates: Requirements 03.6, 12.3, 20.6, 21.3**
  test(
      'keeps camera, GPS, and Diagnostic suspension independent while queue bootstrap is pending',
      () async {
    final queue = _ControlledQueue();
    final harness = _Harness(queue: queue);
    addTearDown(harness.dispose);

    await harness.controller.startOperationalLifecycle();

    expect(harness.camera.acquireCount, 1);
    expect(harness.location.acquireCount, 1);
    expect(harness.controller.state.isQueueReady, isFalse);
    expect(harness.controller.state.canRegister, isFalse);

    await harness.controller.suspendForDiagnostic();

    expect(harness.camera.releaseCount, 1);
    expect(harness.location.releaseCount, 1);
    expect(harness.controller.state.isCurrentRoute, isFalse);

    queue.complete(const QueueSnapshot(
      health: QueueHealth.ready,
      pendingCount: 0,
    ));
    await harness.controller.queueBootstrapSettled;
  });

  // **Validates: Requirements 05.4, 07.10, 09.1–4, 12.3**
  test(
      'restores recovered pending occurrences without incrementing the session counter',
      () async {
    final pending = _pending(sequence: 7);
    final queue =
        _ControlledQueue(pending: <ReconstructedPendingOccurrence>[pending]);
    final restorer = _RecordingCooldownRestorer();
    final harness = _Harness(queue: queue, cooldownRestorer: restorer);
    addTearDown(harness.dispose);

    await harness.controller.startOperationalLifecycle();
    queue.complete(const QueueSnapshot(
      health: QueueHealth.ready,
      pendingCount: 1,
    ));
    await harness.controller.queueBootstrapSettled;

    expect(restorer.anchorRestoreCount, 1);
    expect(restorer.restoredAnchor?.queueSequence, 7);
    expect(harness.controller.state.sessionOccurrenceCount, 0);
    expect(harness.controller.state.isQueueReady, isTrue);
  });

  // **Validates: Requirements RF-09.1–4, RF-12.3**
  test('restores the cooldown from the anchor when the queue is empty',
      () async {
    final queue = _ControlledQueue(
      anchor: AcceptedOccurrenceAnchor(
        queueSequence: 12,
        detectedAtIso8601: DateTime.utc(2025, 1, 1, 12).toIso8601String(),
        latitude: -23.5505,
        longitude: -46.6333,
      ),
    );
    final cooldown = CooldownPolicy(distanceCalculator: _FixedDistance());
    final harness = _Harness(queue: queue, cooldownRestorer: cooldown);
    addTearDown(harness.dispose);

    await harness.controller.startOperationalLifecycle();
    queue.complete(const QueueSnapshot(
      health: QueueHealth.ready,
      pendingCount: 0,
    ));
    await harness.controller.queueBootstrapSettled;

    expect(harness.controller.state.pendingCount, 0);
    expect(
      cooldown
          .evaluate(
            DateTime.utc(2025, 1, 1, 12).add(const Duration(seconds: 1)),
            const _Point(),
          )
          .isBlocked,
      isTrue,
    );
  });

  // **Validates: Requirements 03.6, 12.3, 12.5, 20.7**
  test(
      'enables registration only after a ready queue and keeps it blocked on failure',
      () async {
    final readyQueue = _ControlledQueue();
    final readyHarness = _Harness(queue: readyQueue);
    addTearDown(readyHarness.dispose);

    await readyHarness.controller.startOperationalLifecycle();
    expect(readyHarness.controller.state.canRegister, isFalse);

    readyQueue.complete(const QueueSnapshot(
      health: QueueHealth.ready,
      pendingCount: 2,
    ));
    await readyHarness.controller.queueBootstrapSettled;

    expect(readyHarness.controller.state.isQueueReady, isTrue);
    expect(readyHarness.controller.state.canRegister, isTrue);

    final failedQueue = _ControlledQueue();
    final failedHarness = _Harness(queue: failedQueue);
    addTearDown(failedHarness.dispose);

    await failedHarness.controller.startOperationalLifecycle();
    failedQueue.complete(const QueueSnapshot(
      health: QueueHealth.unavailable,
      pendingCount: 0,
    ));
    await failedHarness.controller.queueBootstrapSettled;

    expect(failedHarness.camera.acquireCount, 1);
    expect(failedHarness.location.acquireCount, 1);
    expect(failedHarness.controller.state.isQueueReady, isFalse);
    expect(failedHarness.controller.state.canRegister, isFalse);
  });

  // **Validates: Requirements RF-03.6–10, RF-05.5, RF-12.5, RF-12.7,
  // RNF-04.2–3, RNF-05.3–5**
  test(
      'projects only confirmed empty, degraded, and unavailable queue aggregates',
      () async {
    final emptyQueue = _ControlledQueue();
    final emptyHarness = _Harness(queue: emptyQueue);
    addTearDown(emptyHarness.dispose);

    await emptyHarness.controller.startOperationalLifecycle();
    expect(emptyHarness.controller.state.queueHealth, QueueHealth.initializing);
    expect(emptyHarness.controller.state.pendingCount, 0);
    expect(emptyHarness.controller.state.canRegister, isFalse);

    emptyQueue.complete(const QueueSnapshot(
      health: QueueHealth.ready,
      pendingCount: 0,
    ));
    await emptyHarness.controller.queueBootstrapSettled;

    expect(emptyHarness.controller.state.queueHealth, QueueHealth.ready);
    expect(emptyHarness.controller.state.pendingCount, 0);
    expect(emptyHarness.controller.state.canRegister, isTrue);

    final degradedQueue = _ControlledQueue();
    final degradedHarness = _Harness(queue: degradedQueue);
    addTearDown(degradedHarness.dispose);
    await degradedHarness.controller.startOperationalLifecycle();
    degradedQueue.complete(const QueueSnapshot(
      health: QueueHealth.degraded,
      pendingCount: 3,
      attentionCount: 1,
    ));
    await degradedHarness.controller.queueBootstrapSettled;

    expect(degradedHarness.controller.state.queueHealth, QueueHealth.degraded);
    expect(degradedHarness.controller.state.pendingCount, 3);
    expect(degradedHarness.controller.state.canRegister, isFalse);

    final unavailableQueue = _ControlledQueue();
    final unavailableHarness = _Harness(queue: unavailableQueue);
    addTearDown(unavailableHarness.dispose);
    await unavailableHarness.controller.startOperationalLifecycle();
    unavailableQueue.complete(const QueueSnapshot(
      health: QueueHealth.unavailable,
      pendingCount: 0,
    ));
    await unavailableHarness.controller.queueBootstrapSettled;

    expect(
      unavailableHarness.controller.state.queueHealth,
      QueueHealth.unavailable,
    );
    expect(unavailableHarness.controller.state.pendingCount, 0);
    expect(unavailableHarness.controller.state.canRegister, isFalse);
  });

  // **Validates: Requirements RF-05.4–5, RF-09.1–4, RF-12.3, RF-12.5,
  // RF-12.7, RNF-05.3–5**
  test(
      'reopening restores the highest accepted sequence, blocks a regressive clock, and resets only the session counter',
      () async {
    final oldestBySequence = _pending(
      sequence: 4,
      detectedAt: DateTime.utc(2025, 1, 1, 12, 10),
    );
    final latestBySequence = _pending(
      sequence: 9,
      detectedAt: DateTime.utc(2025, 1, 1, 12),
    );

    final firstSessionQueue = _ControlledQueue(
      pending: <ReconstructedPendingOccurrence>[
        oldestBySequence,
        latestBySequence,
      ],
    );
    final firstSession = _Harness(queue: firstSessionQueue);
    addTearDown(firstSession.dispose);
    await firstSession.controller.startOperationalLifecycle();
    firstSessionQueue.complete(const QueueSnapshot(
      health: QueueHealth.ready,
      pendingCount: 2,
    ));
    await firstSession.controller.queueBootstrapSettled;

    expect(firstSession.controller.state.pendingCount, 2);
    expect(firstSession.controller.state.sessionOccurrenceCount, 0);

    final distance = _FixedDistance();
    final cooldown = CooldownPolicy(distanceCalculator: distance);
    final reopenedQueue = _ControlledQueue(
      pending: <ReconstructedPendingOccurrence>[
        oldestBySequence,
        latestBySequence,
      ],
    );
    final reopened = _Harness(
      queue: reopenedQueue,
      cooldownRestorer: cooldown,
    );
    addTearDown(reopened.dispose);
    await reopened.controller.startOperationalLifecycle();
    reopenedQueue.complete(const QueueSnapshot(
      health: QueueHealth.ready,
      pendingCount: 2,
    ));
    await reopened.controller.queueBootstrapSettled;

    expect(reopened.controller.state.pendingCount, 2);
    expect(reopened.controller.state.sessionOccurrenceCount, 0);
    expect(
      cooldown
          .evaluate(
            DateTime.utc(2025, 1, 1, 12).add(const Duration(seconds: 6)),
            const _Point(),
          )
          .isAllowed,
      isTrue,
      reason: 'the greatest queueSequence, not the latest wall clock, wins',
    );
    expect(
      cooldown
          .evaluate(
            DateTime.utc(2025, 1, 1, 11, 59, 59),
            const _Point(),
          )
          .isBlocked,
      isTrue,
      reason: 'a regressive clock remains below the elapsed threshold',
    );
  });
}

final class _Harness {
  _Harness({
    required this.queue,
    CooldownReferenceRestorer? cooldownRestorer,
  }) {
    controller = OperationController<String>(
      candidateSource: const _UnusedSource(),
      postCandidateProcessor: const _UnusedProcessor(),
      camera: camera,
      location: location,
      screenAwake: const _ScreenAwake(),
      clock: const _Clock(),
      queue: queue,
      cooldownRestorer: cooldownRestorer,
    );
  }

  final _Camera camera = _Camera();
  final _Location location = _Location();
  final PersistentOccurrenceQueue queue;
  late final OperationController<String> controller;

  Future<void> dispose() async {
    controller.dispose();
    await controller.lifecycleSettled;
  }
}

final class _ControlledQueue implements PersistentOccurrenceQueue {
  /// [anchor] defaults to the pending occurrence with the greatest sequence,
  /// as the real v1 to v2 migration seeds it.
  _ControlledQueue({
    List<ReconstructedPendingOccurrence> pending =
        const <ReconstructedPendingOccurrence>[],
    AcceptedOccurrenceAnchor? anchor,
  })  : _pending = List<ReconstructedPendingOccurrence>.unmodifiable(pending),
        _anchor = anchor ?? _greatestSequenceAnchor(pending);

  final Completer<QueueSnapshot> _bootstrap = Completer<QueueSnapshot>();
  final List<ReconstructedPendingOccurrence> _pending;
  final AcceptedOccurrenceAnchor? _anchor;

  @override
  Stream<QueueSnapshot> get snapshots => const Stream<QueueSnapshot>.empty();

  @override
  Future<QueueSnapshot> bootstrap() => _bootstrap.future;

  @override
  Future<QueueSnapshot> retryBootstrap() => _bootstrap.future;

  void complete(QueueSnapshot snapshot) => _bootstrap.complete(snapshot);

  @override
  Future<OccurrenceAcceptanceResult> persist(
          InMemoryOccurrence occurrence) async =>
      const OccurrenceStorageUnavailable();

  @override
  Future<List<ReconstructedPendingOccurrence>> listPending() async => _pending;

  @override
  Future<AcceptedOccurrenceAnchor?> readAcceptedAnchor() async => _anchor;

  @override
  Future<int> countPending() async => 0;

  @override
  Future<QueueRemovalResult> removeInternal(String idempotencyKey) async =>
      const QueueOccurrenceRemovalFailed();

  @override
  Future<void> close() async {}
}

AcceptedOccurrenceAnchor? _greatestSequenceAnchor(
  List<ReconstructedPendingOccurrence> pending,
) {
  ReconstructedPendingOccurrence? greatest;
  for (final occurrence in pending) {
    if (greatest == null || occurrence.queueSequence > greatest.queueSequence) {
      greatest = occurrence;
    }
  }
  if (greatest == null) {
    return null;
  }
  return AcceptedOccurrenceAnchor(
    queueSequence: greatest.queueSequence,
    detectedAtIso8601: greatest.detectedAtIso8601,
    latitude: greatest.latitude,
    longitude: greatest.longitude,
  );
}

final class _RecordingCooldownRestorer implements CooldownReferenceRestorer {
  AcceptedOccurrenceAnchor? restoredAnchor;
  var anchorRestoreCount = 0;

  @override
  void restoreRecoveredPending(
    Iterable<ReconstructedPendingOccurrence> pending,
  ) {
    fail('The cooldown must be restored from the anchor, not pending rows.');
  }

  @override
  void restoreAcceptedAnchor(AcceptedOccurrenceAnchor? anchor) {
    restoredAnchor = anchor;
    anchorRestoreCount++;
  }
}

ReconstructedPendingOccurrence _pending({
  required int sequence,
  DateTime? detectedAt,
}) =>
    ReconstructedPendingOccurrence(
      QueueRecordProjection(
        queueSequence: sequence,
        idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
        detectedAtIso8601: (detectedAt ?? DateTime.utc(2025)).toIso8601String(),
        latitude: -23.5505,
        longitude: -46.6333,
        accuracyMeters: null,
        speedKmh: null,
        confidence: 1,
        defectClass: 'pothole',
        image: const PersistedImageProjection(
          relativeName: 'opaque.jpg',
          mimeType: 'image/jpeg',
          byteLength: 1,
          sha256:
              '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          width: 1,
          height: 1,
          quality: 85,
        ),
      ),
    );

final class _Camera implements OperationalCameraPort<String> {
  var acquireCount = 0;
  var releaseCount = 0;

  @override
  String? get previewHandle => 'rear-preview';

  @override
  Future<void> acquirePreview() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }

  @override
  Future<TemporaryCapture> takePicture() => throw UnimplementedError();
}

final class _Location implements OperationalLocationPort {
  var acquireCount = 0;
  var releaseCount = 0;

  @override
  LocationSnapshot? get latestValidSnapshot => const _Snapshot();

  @override
  Future<void> acquireForegroundUpdates() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }
}

final class _Snapshot implements LocationSnapshot {
  const _Snapshot();

  @override
  double? get accuracyMeters => 2;

  @override
  GeoPoint get point => const _Point();

  @override
  double? get speedMetersPerSecond => 0;
}

final class _Point implements GeoPoint {
  const _Point();

  @override
  double get latitude => -23.5505;

  @override
  double get longitude => -46.6333;
}

final class _FixedDistance implements DistanceCalculator {
  @override
  double metersBetween(GeoPoint from, GeoPoint to) => 0;
}

final class _ScreenAwake implements ScreenAwakePort {
  const _ScreenAwake();

  @override
  Future<void> setEnabled(bool enabled) async {}
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2025);
}

final class _UnusedSource implements OccurrenceCandidateSource {
  const _UnusedSource();

  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) =>
      throw UnimplementedError();
}

final class _UnusedProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  const _UnusedProcessor();

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
          CandidateInput candidate) =>
      throw UnimplementedError();
}
