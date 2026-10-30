import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_snapshot_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_coordinator.dart'
    show DeliveryManualRetryResult, OccurrenceDeliveryCoordinator;
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_transport_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/operation_delivery_port.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_presentation_state.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_transport_result.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/operation/operation_controller.dart';

void main() {
  // **Validates: Requirements RF-05.1–7, RF-13.14–16, RF-16.2, RF-16.4,
  // RF-18.3, RF-20, RF-21, RNF-02, RNF-04.2–3, RNF-04.6**
  group('OperationController delivery projection', () {
    test('has no delivery projection when none is composed', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.controller.startOperationalLifecycle();

      expect(harness.controller.state.deliveryPresentation, isNull);
      expect(harness.controller.state.canRetryDelivery, isFalse);
      expect(
        await harness.controller.retryDeliveryManually(),
        DeliveryManualRetryResult.notApplied,
      );
    });

    test('publishes the aggregate projection and stops after dispose',
        () async {
      final delivery = _FakeDelivery();
      final harness = _Harness(delivery: delivery);
      addTearDown(harness.dispose);

      expect(
        harness.controller.state.deliveryPresentation,
        DeliveryPresentationState(phase: DeliveryPhase.idle),
      );
      await harness.controller.startOperationalLifecycle();
      var notifications = 0;
      harness.controller.addListener(() => notifications++);

      delivery.emit(DeliveryPresentationState(phase: DeliveryPhase.sending));
      await pumpEventQueue();

      final shown = harness.controller.state.deliveryPresentation!;
      expect(shown.phase, DeliveryPhase.sending);
      expect(notifications, 1);

      harness.controller.dispose();
      delivery.emit(DeliveryPresentationState(phase: DeliveryPhase.ready));
      await pumpEventQueue();

      expect(delivery.disposeCalls, 0);
      expect(delivery.hasListener, isFalse);
    });

    test('starts delivery only after a ready bootstrap', () async {
      for (final health in <QueueHealth>[
        QueueHealth.degraded,
        QueueHealth.unavailable,
      ]) {
        final delivery = _FakeDelivery();
        final queue = _Queue();
        final harness = _Harness(delivery: delivery, queue: queue);
        addTearDown(harness.dispose);

        await harness.controller.startOperationalLifecycle();
        expect(delivery.startCalls, 0, reason: 'bootstrap still pending');
        queue.bootstrapCompleter
            .complete(QueueSnapshot(health: health, pendingCount: 1));
        await harness.controller.queueBootstrapSettled;

        expect(delivery.startCalls, 0, reason: health.name);
      }

      final delivery = _FakeDelivery();
      final queue = _Queue();
      final harness = _Harness(delivery: delivery, queue: queue);
      addTearDown(harness.dispose);
      await harness.controller.startOperationalLifecycle();
      queue.bootstrapCompleter.complete(
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 2),
      );
      await harness.controller.queueBootstrapSettled;

      expect(delivery.startCalls, 1);
    });

    test('notifies delivery of a new pending item but not of a removal',
        () async {
      final delivery = _FakeDelivery();
      final queue = _Queue();
      final harness = _Harness(delivery: delivery, queue: queue);
      addTearDown(harness.dispose);
      await harness.controller.startOperationalLifecycle();
      queue.bootstrapCompleter.complete(
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 2),
      );
      await harness.controller.queueBootstrapSettled;

      queue.emit(
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 3),
      );
      await pumpEventQueue();
      expect(delivery.queueChangedCalls, 1);
      expect(harness.controller.state.pendingCount, 3);

      queue.emit(
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 2),
      );
      queue.emit(
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 2),
      );
      await pumpEventQueue();
      expect(delivery.queueChangedCalls, 1);
      expect(harness.controller.state.pendingCount, 2);
    });

    test('lowers the pending count only from a confirmed queue snapshot',
        () async {
      final delivery = _FakeDelivery();
      final queue = _Queue();
      final harness = _Harness(delivery: delivery, queue: queue);
      addTearDown(harness.dispose);
      await harness.controller.startOperationalLifecycle();
      queue.bootstrapCompleter.complete(
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 1),
      );
      await harness.controller.queueBootstrapSettled;

      for (final phase in <DeliveryPhase>[
        DeliveryPhase.sending,
        DeliveryPhase.waitingBackoff,
        DeliveryPhase.cleaning,
        DeliveryPhase.pausedLocalFailure,
      ]) {
        delivery.emit(DeliveryPresentationState(phase: phase));
        await pumpEventQueue();
        expect(harness.controller.state.pendingCount, 1, reason: phase.name);
      }

      queue.emit(
        const QueueSnapshot(health: QueueHealth.initializing, pendingCount: 0),
      );
      await pumpEventQueue();
      expect(harness.controller.state.pendingCount, 1);

      queue.emit(
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 0),
      );
      delivery.emit(DeliveryPresentationState(phase: DeliveryPhase.idle));
      await pumpEventQueue();
      expect(harness.controller.state.pendingCount, 0);
    });

    test('offers the manual retry only when the projection allows it',
        () async {
      final delivery = _FakeDelivery();
      final harness = _Harness(delivery: delivery);
      addTearDown(harness.dispose);
      await harness.controller.startOperationalLifecycle();

      expect(
        await harness.controller.retryDeliveryManually(),
        DeliveryManualRetryResult.notApplied,
      );
      expect(delivery.retryCalls, 0);

      delivery.emit(
        DeliveryPresentationState(
          phase: DeliveryPhase.pausedAccess,
          canRetry: true,
        ),
      );
      await pumpEventQueue();
      expect(harness.controller.state.canRetryDelivery, isTrue);

      final gate = Completer<DeliveryManualRetryResult>();
      delivery.retryResult = gate.future;
      final first = harness.controller.retryDeliveryManually();
      final second = harness.controller.retryDeliveryManually();
      expect(identical(first, second), isTrue);
      gate.complete(DeliveryManualRetryResult.resumed);

      expect(await first, DeliveryManualRetryResult.resumed);
      expect(delivery.retryCalls, 1);

      delivery.retryResult = Future<DeliveryManualRetryResult>.value(
        DeliveryManualRetryResult.evaluationRequested,
      );
      expect(
        await harness.controller.retryDeliveryManually(),
        DeliveryManualRetryResult.evaluationRequested,
      );
      expect(delivery.retryCalls, 2);
    });

    test('keeps registration readiness independent of the delivery phase',
        () async {
      final delivery = _FakeDelivery();
      final queue = _Queue();
      final harness = _Harness(delivery: delivery, queue: queue);
      addTearDown(harness.dispose);
      await harness.controller.startOperationalLifecycle();
      queue.bootstrapCompleter.complete(
        const QueueSnapshot(health: QueueHealth.ready, pendingCount: 0),
      );
      await harness.controller.queueBootstrapSettled;
      final camera = harness.controller.state.cameraStatus;
      final location = harness.controller.state.locationStatus;

      for (final phase in DeliveryPhase.values) {
        delivery.emit(DeliveryPresentationState(phase: phase));
        await pumpEventQueue();
        expect(harness.controller.state.cameraStatus, camera,
            reason: phase.name);
        expect(harness.controller.state.locationStatus, location,
            reason: phase.name);
        expect(harness.controller.state.isQueueReady, isTrue,
            reason: phase.name);
      }
    });
  });

  // **Validates: Requirements RF-05.5, RF-13.14–16, RF-18.3, RNF-02**
  group('CoordinatorOperationDelivery', () {
    test('projects the coordinator phase and the retry rule', () async {
      final queue = _DeliveryQueue();
      final coordinator = OccurrenceDeliveryCoordinator(
        queue: queue,
        configuration: _UnusedSnapshot(),
        transport: _UnusedTransport(),
        clock: _FixedClock(DateTime.utc(2026, 1, 1, 12)),
      );
      final delivery = CoordinatorOperationDelivery(coordinator);
      addTearDown(() async {
        await coordinator.dispose();
        await delivery.dispose();
      });
      final seen = <DeliveryPresentationState>[];
      delivery.presentations.listen(seen.add);

      expect(delivery.presentation.phase, DeliveryPhase.idle);
      expect(delivery.presentation.canRetry, isFalse);

      queue.head = const DeliveryQueueUnavailable();
      delivery.start();
      await pumpEventQueue();
      expect(delivery.presentation.phase, DeliveryPhase.queueUnavailable);
      expect(delivery.presentation.canRetry, isFalse);

      final head = DeliveryQueueHead(
        idempotencyKey: 'fictitious-idempotency-key',
        queueSequence: 1,
      );
      queue.head = DeliveryHeadInBackoff(
        head: head,
        nextAttemptAt: DateTime.utc(2026, 1, 1, 12, 5),
      );
      queue.control = const DeliveryControlRunning();
      delivery.onQueueChanged();
      await pumpEventQueue();
      expect(delivery.presentation.phase, DeliveryPhase.waitingBackoff);
      expect(delivery.presentation.canRetry, isFalse);

      queue.control = DeliveryControlPaused(DeliveryPauseReason.access);
      delivery.onQueueChanged();
      await pumpEventQueue();
      expect(delivery.presentation.phase, DeliveryPhase.pausedAccess);
      expect(delivery.presentation.canRetry, isTrue);

      expect(
        seen.map((state) => state.phase),
        <DeliveryPhase>[
          DeliveryPhase.queueUnavailable,
          DeliveryPhase.waitingBackoff,
          DeliveryPhase.pausedAccess,
        ],
      );
      for (final state in seen) {
        expect(state.nextRetryAt, isNull);
        expect(
          '${state.message}$state',
          isNot(contains('fictitious-idempotency-key')),
        );
      }
    });

    test('follows the global lifecycle through the same coordinator', () async {
      final queue = _DeliveryQueue();
      final coordinator = OccurrenceDeliveryCoordinator(
        queue: queue,
        configuration: _UnusedSnapshot(),
        transport: _UnusedTransport(),
        clock: _FixedClock(DateTime.utc(2026, 1, 1, 12)),
      );
      final delivery = CoordinatorOperationDelivery(coordinator);
      final DeliveryLifecyclePort lifecycle = delivery;
      addTearDown(() async {
        await coordinator.dispose();
        await delivery.dispose();
      });
      delivery.start();
      await pumpEventQueue();
      expect(delivery.presentation.phase, DeliveryPhase.idle);

      await lifecycle.onAppLeftForeground();
      queue.head = DeliveryHeadInBackoff(
        head: DeliveryQueueHead(
          idempotencyKey: 'fictitious-idempotency-key',
          queueSequence: 1,
        ),
        nextAttemptAt: DateTime.utc(2026, 1, 1, 12, 5),
      );
      delivery.onQueueChanged();
      await pumpEventQueue();
      expect(delivery.presentation.phase, DeliveryPhase.idle);

      lifecycle.onAppResumed();
      await pumpEventQueue();
      expect(delivery.presentation.phase, DeliveryPhase.waitingBackoff);
    });

    test('retries manually through the same coordinator and disposes safely',
        () async {
      final queue = _DeliveryQueue()
        ..head = const DeliveryQueueEmpty()
        ..control = DeliveryControlPaused(DeliveryPauseReason.access);
      final coordinator = OccurrenceDeliveryCoordinator(
        queue: queue,
        configuration: _UnusedSnapshot(),
        transport: _UnusedTransport(),
        clock: _FixedClock(DateTime.utc(2026, 1, 1, 12)),
      );
      final delivery = CoordinatorOperationDelivery(coordinator);
      delivery.start();
      await pumpEventQueue();

      expect(
        await delivery.retryManually(),
        DeliveryManualRetryResult.resumed,
      );
      expect(queue.resumeCalls, 1);

      await delivery.dispose();
      await delivery.dispose();
      await coordinator.dispose();
      await coordinator.dispose();
      expect(
        await delivery.retryManually(),
        DeliveryManualRetryResult.notApplied,
      );
    });
  });
}

final class _FakeDelivery implements OperationDeliveryPort {
  final StreamController<DeliveryPresentationState> _controller =
      StreamController<DeliveryPresentationState>.broadcast();
  DeliveryPresentationState _presentation =
      DeliveryPresentationState(phase: DeliveryPhase.idle);
  Future<DeliveryManualRetryResult> retryResult =
      Future<DeliveryManualRetryResult>.value(
    DeliveryManualRetryResult.evaluationRequested,
  );
  int startCalls = 0;
  int queueChangedCalls = 0;
  int retryCalls = 0;
  int disposeCalls = 0;

  bool get hasListener => _controller.hasListener;

  void emit(DeliveryPresentationState state) {
    _presentation = state;
    _controller.add(state);
  }

  @override
  DeliveryPresentationState get presentation => _presentation;

  @override
  Stream<DeliveryPresentationState> get presentations => _controller.stream;

  @override
  void start() => startCalls++;

  @override
  void onQueueChanged() => queueChangedCalls++;

  @override
  Future<DeliveryManualRetryResult> retryManually() {
    retryCalls++;
    return retryResult;
  }
}

final class _Harness {
  _Harness(
      {OperationDeliveryPort? delivery, PersistentOccurrenceQueue? queue}) {
    controller = OperationController<String>(
      candidateSource: const _UnusedSource(),
      postCandidateProcessor: const _UnusedProcessor(),
      camera: _Camera(),
      location: _Location(),
      screenAwake: const _ScreenAwake(),
      clock: _FixedClock(DateTime.utc(2025)),
      queue: queue,
      delivery: delivery,
    );
  }

  late final OperationController<String> controller;

  Future<void> dispose() async {
    controller.dispose();
    await controller.lifecycleSettled;
  }
}

final class _Queue implements PersistentOccurrenceQueue {
  final Completer<QueueSnapshot> bootstrapCompleter =
      Completer<QueueSnapshot>();
  final StreamController<QueueSnapshot> _snapshots =
      StreamController<QueueSnapshot>.broadcast(sync: true);

  void emit(QueueSnapshot snapshot) => _snapshots.add(snapshot);

  @override
  Stream<QueueSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<QueueSnapshot> bootstrap() => bootstrapCompleter.future;

  @override
  Future<QueueSnapshot> retryBootstrap() => bootstrapCompleter.future;

  @override
  Future<OccurrenceAcceptanceResult> persist(
          InMemoryOccurrence occurrence) async =>
      const OccurrenceStorageUnavailable();

  @override
  Future<List<ReconstructedPendingOccurrence>> listPending() async =>
      const <ReconstructedPendingOccurrence>[];

  @override
  Future<AcceptedOccurrenceAnchor?> readAcceptedAnchor() async => null;

  @override
  Future<int> countPending() async => 0;

  @override
  Future<QueueRemovalResult> removeInternal(String idempotencyKey) async =>
      const QueueOccurrenceRemovalFailed();

  @override
  Future<void> close() async {
    await _snapshots.close();
  }
}

/// Delivery queue whose head and control are set by the test.
final class _DeliveryQueue implements OccurrenceDeliveryQueuePort {
  DeliveryHeadResult head = const DeliveryQueueEmpty();
  DeliveryControl control = const DeliveryControlRunning();
  int resumeCalls = 0;

  @override
  Future<DeliveryHeadResult> nextHead(DateTime now) async => head;

  @override
  Future<DeliveryControl> readControl() async => control;

  @override
  Future<DeliveryMutationResult> resume() async {
    resumeCalls++;
    control = const DeliveryControlRunning();
    return DeliveryMutationResult.applied;
  }

  @override
  Future<DeliveryMutationResult> pause(PausedDeliveryDecision pause) async =>
      DeliveryMutationResult.applied;

  @override
  Stream<DeliveryQueueSummary> watchSummary() =>
      const Stream<DeliveryQueueSummary>.empty();

  @override
  Stream<List<int>> openImage(DeliveryHeadEligible head) =>
      throw UnimplementedError();

  @override
  Future<DeliveryMutationResult> recordRecoverableFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextAttemptAt,
  ) =>
      throw UnimplementedError();

  @override
  Future<DeliveryMutationResult> recordDefinitiveDecision(
    String idempotencyKey,
    DeliveryDisposition disposition,
  ) =>
      throw UnimplementedError();

  @override
  Future<QueueRemovalResult> completePendingLocalRemoval(
          String idempotencyKey) =>
      throw UnimplementedError();

  @override
  Future<DeliveryMutationResult> recordCleanupFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextCleanupAt,
  ) =>
      throw UnimplementedError();
}

final class _UnusedSnapshot implements DeliveryConfigurationSnapshotPort {
  @override
  Future<DeliveryConfigurationResult> readForAttempt() =>
      throw UnimplementedError();

  @override
  Future<T> runConfigurationMutation<T>(Future<T> Function() action) =>
      throw UnimplementedError();

  @override
  bool isCurrent(int revision) => throw UnimplementedError();
}

final class _UnusedTransport implements OccurrenceTransportPort {
  @override
  Future<OccurrenceTransportResult> send(OccurrenceUploadRequest request) =>
      throw UnimplementedError();

  @override
  Future<void> cancelActive() async {}
}

final class _FixedClock implements Clock {
  _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

final class _Camera implements OperationalCameraPort<String> {
  @override
  String? get previewHandle => null;

  @override
  Future<void> acquirePreview() async {}

  @override
  Future<void> release() async {}

  @override
  Future<TemporaryCapture> takePicture() => throw UnimplementedError();
}

final class _Location implements OperationalLocationPort {
  @override
  LocationSnapshot? get latestValidSnapshot => null;

  @override
  Future<void> acquireForegroundUpdates() async {}

  @override
  Future<void> release() async {}
}

final class _ScreenAwake implements ScreenAwakePort {
  const _ScreenAwake();

  @override
  Future<void> setEnabled(bool enabled) async {}
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
