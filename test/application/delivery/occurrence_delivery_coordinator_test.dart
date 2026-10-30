import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_change_service.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_snapshot_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_technical_logger.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_timer_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_coordinator.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_transport_port.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_backoff_policy.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_transport_result.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/sanitized_delivery_technical_logger.dart';

// Explicitly fictitious values.
final Uri _baseUrl = Uri.parse('https://delivery.example.invalid');
const String _secret = 'testprefix.fictitious-secret-for-tests-only';

/// Order of the observable port calls of one test.
final List<String> _events = <String>[];

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 1, 1, 12);
}

final class _ManualClock implements Clock {
  DateTime current = DateTime.utc(2026, 1, 1, 12);

  @override
  DateTime now() => current;
}

final class _ManualTimerHandle implements DeliveryTimerHandle {
  _ManualTimerHandle(this.dueAt, this.onDue);

  final DateTime dueAt;
  final void Function() onDue;
  bool _active = true;
  bool cancelled = false;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    if (_active) {
      cancelled = true;
    }
    _active = false;
  }
}

/// Timer that fires only when the test says so.
final class _ManualTimer implements DeliveryTimerPort {
  _ManualTimer(this._clock);

  final _ManualClock _clock;
  final List<_ManualTimerHandle> armed = <_ManualTimerHandle>[];
  int maxActive = 0;

  List<_ManualTimerHandle> get active =>
      armed.where((handle) => handle.isActive).toList();

  @override
  DeliveryTimerHandle arm(DateTime dueAt, void Function() onDue) {
    final handle = _ManualTimerHandle(dueAt, onDue);
    armed.add(handle);
    if (active.length > maxActive) {
      maxActive = active.length;
    }
    return handle;
  }

  /// Moves the clock to the due instant and fires the active timer, if any.
  void fire() {
    final handle = active.single;
    if (_clock.current.isBefore(handle.dueAt)) {
      _clock.current = handle.dueAt;
    }
    handle._active = false;
    handle.onDue();
  }
}

/// Fake FIFO queue with a real serial region, so a test can tell whether the
/// coordinator keeps it locked while the transport is in use.
final class _FakeQueue implements OccurrenceDeliveryQueuePort {
  final List<String> keys = <String>[];
  final List<String> removed = <String>[];
  final List<String> decisions = <String>[];

  /// When set, `nextHead` reports this instead of the real head.
  DeliveryHeadResult Function(String headKey)? headOverride;
  DeliveryControl control = const DeliveryControlRunning();

  int nextHeadCalls = 0;
  int recoverableFailures = 0;
  int pauses = 0;
  int openImageCalls = 0;
  bool openImageThrows = false;
  bool removalFails = false;
  final List<(String, DateTime, DateTime)> failureRecords =
      <(String, DateTime, DateTime)>[];
  final List<(String, DateTime, DateTime)> cleanupFailureRecords =
      <(String, DateTime, DateTime)>[];
  DeliveryMutationResult decisionResult = DeliveryMutationResult.applied;
  final List<PausedDeliveryDecision> pausedWith = <PausedDeliveryDecision>[];

  /// True while any queue operation holds the serial region.
  bool regionHeld = false;
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(T Function() body) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) async {
      regionHeld = true;
      try {
        // Yield, as a real database call would.
        await Future<void>.delayed(Duration.zero);
        return body();
      } finally {
        regionHeld = false;
        done.complete();
      }
    });
  }

  /// Persists a new occurrence through the same region (E2 acceptance).
  Future<void> enqueue(String key) => _serial<void>(() => keys.add(key));

  DeliveryHeadEligible _eligible(String key) => DeliveryHeadEligible(
        head: DeliveryQueueHead(
          idempotencyKey: key,
          queueSequence: keys.indexOf(key) + 1,
        ),
        payload: DeliveryOccurrencePayload(
          detectedAtIso8601: '2026-01-01T12:00:00Z',
          latitude: -23.5,
          longitude: -46.6,
          speedKmh: null,
          confidence: 1.0,
          defectClass: 'pothole',
          image: DeliveryImageRef(byteLength: 3, opaqueHandle: key),
        ),
      );

  @override
  Future<DeliveryHeadResult> nextHead(DateTime now) => _serial(() {
        nextHeadCalls++;
        if (keys.isEmpty) {
          return const DeliveryQueueEmpty();
        }
        final override = headOverride;
        return override != null ? override(keys.first) : _eligible(keys.first);
      });

  @override
  Stream<List<int>> openImage(DeliveryHeadEligible head) {
    openImageCalls++;
    _events.add('openImage');
    if (openImageThrows) {
      throw StateError('image unavailable');
    }
    return Stream<List<int>>.value(<int>[1, 2, 3]);
  }

  @override
  Future<DeliveryMutationResult> recordDefinitiveDecision(
    String idempotencyKey,
    DeliveryDisposition disposition,
  ) =>
      _serial(() {
        _events.add('decision');
        if (decisionResult == DeliveryMutationResult.applied) {
          decisions.add('$idempotencyKey:${disposition.name}');
        }
        return decisionResult;
      });

  @override
  Future<QueueRemovalResult> completePendingLocalRemoval(
    String idempotencyKey,
  ) =>
      _serial<QueueRemovalResult>(() {
        _events.add('remove');
        if (removalFails) {
          return const QueueOccurrenceRemovalFailed();
        }
        keys.remove(idempotencyKey);
        removed.add(idempotencyKey);
        return QueueOccurrenceRemoved(
          QueueSnapshot(health: QueueHealth.ready, pendingCount: keys.length),
        );
      });

  @override
  Future<DeliveryMutationResult> recordRecoverableFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextAttemptAt,
  ) async {
    recoverableFailures++;
    failureRecords.add((idempotencyKey, calculatedAt, nextAttemptAt));
    return DeliveryMutationResult.applied;
  }

  @override
  Future<DeliveryMutationResult> recordCleanupFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextCleanupAt,
  ) async {
    cleanupFailureRecords.add((idempotencyKey, calculatedAt, nextCleanupAt));
    return DeliveryMutationResult.applied;
  }

  @override
  Future<DeliveryControl> readControl() => _serial(() {
        _events.add('control');
        return control;
      });

  @override
  Future<DeliveryMutationResult> pause(PausedDeliveryDecision pause) async {
    pauses++;
    pausedWith.add(pause);
    return DeliveryMutationResult.applied;
  }

  int resumes = 0;
  DeliveryMutationResult resumeResult = DeliveryMutationResult.applied;

  @override
  Future<DeliveryMutationResult> resume() async {
    resumes++;
    if (resumeResult == DeliveryMutationResult.applied) {
      control = const DeliveryControlRunning();
    }
    return resumeResult;
  }

  @override
  Stream<DeliveryQueueSummary> watchSummary() => const Stream.empty();
}

final class _FakeConfiguration implements DeliveryConfigurationSnapshotPort {
  DeliveryConfigurationResult result = DeliveryConfigurationAvailable(
    DeliveryConfiguration(
      revision: 1,
      baseUrl: _baseUrl,
      credential: NonPrintableSecret(_secret),
    ),
  );
  int currentRevision = 1;
  int reads = 0;
  void Function()? afterRead;

  @override
  Future<DeliveryConfigurationResult> readForAttempt() async {
    reads++;
    _events.add('read');
    final snapshot = result;
    afterRead?.call();
    return snapshot;
  }

  @override
  Future<T> runConfigurationMutation<T>(Future<T> Function() action) =>
      action();

  @override
  bool isCurrent(int revision) {
    _events.add('isCurrent');
    return revision == currentRevision;
  }
}

/// Transport whose attempts can be held open by the test.
final class _FakeTransport implements OccurrenceTransportPort {
  _FakeTransport(this._queue);

  final _FakeQueue _queue;

  /// Statuses to answer, per call; when exhausted, answers 201.
  final List<int> statuses = <int>[];
  bool hold = false;
  final List<Completer<OccurrenceTransportResult>> pending =
      <Completer<OccurrenceTransportResult>>[];

  /// Results to answer before the statuses, per call.
  final List<OccurrenceTransportResult> results = <OccurrenceTransportResult>[];
  bool readImage = false;
  final List<OccurrenceUploadRequest> requests = <OccurrenceUploadRequest>[];
  final List<int> sentImageBytes = <int>[];

  final List<String> sentKeys = <String>[];
  int active = 0;
  int maxActive = 0;
  bool regionHeldAtSend = false;
  int cancelCalls = 0;

  /// When false, a cancel request does not end the attempt in flight (the
  /// response had already arrived).
  bool honorsCancel = true;

  @override
  Future<OccurrenceTransportResult> send(
      OccurrenceUploadRequest request) async {
    _events.add('send');
    requests.add(request);
    regionHeldAtSend = regionHeldAtSend || _queue.regionHeld;
    sentKeys.add(request.idempotencyKey);
    active++;
    if (active > maxActive) {
      maxActive = active;
    }
    if (hold) {
      final gate = Completer<OccurrenceTransportResult>();
      pending.add(gate);
      return gate.future.whenComplete(() => active--);
    }
    if (readImage) {
      await for (final chunk in request.imageStream) {
        sentImageBytes.addAll(chunk);
      }
    }
    active--;
    if (results.isNotEmpty) {
      return results.removeAt(0);
    }
    final status = statuses.isEmpty ? 201 : statuses.removeAt(0);
    return TransportHttpResponse(status);
  }

  @override
  Future<void> cancelActive() async {
    cancelCalls++;
    if (!honorsCancel) {
      return;
    }
    for (final gate in pending) {
      if (!gate.isCompleted) {
        gate.complete(const TransportCancelled());
      }
    }
  }
}

void main() {
  late _FakeQueue queue;
  late _FakeConfiguration configuration;
  late _FakeTransport transport;
  late OccurrenceDeliveryCoordinator coordinator;
  late List<String> logLines;

  setUp(() {
    logLines = <String>[];
    _events.clear();
    queue = _FakeQueue();
    configuration = _FakeConfiguration();
    transport = _FakeTransport(queue);
    coordinator = OccurrenceDeliveryCoordinator(
      queue: queue,
      configuration: configuration,
      transport: transport,
      clock: _FixedClock(),
      logger: SanitizedDeliveryTechnicalLogger(logLines.add),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
  });

  group('FIFO', () {
    test('delivers the heads strictly in queue order and then goes idle',
        () async {
      queue.keys.addAll(<String>['a', 'b', 'c']);

      coordinator.start();
      await pumpEventQueue();

      expect(transport.sentKeys, <String>['a', 'b', 'c']);
      expect(queue.removed, <String>['a', 'b', 'c']);
      expect(
        queue.decisions,
        <String>['a:created', 'b:created', 'c:created'],
      );
      expect(coordinator.isEvaluating, isFalse);
    });

    test('a head that is not eligible blocks the items behind it', () async {
      queue.keys.addAll(<String>['a', 'b']);
      queue.headOverride = (key) => DeliveryHeadInBackoff(
            head: DeliveryQueueHead(idempotencyKey: key, queueSequence: 1),
            nextAttemptAt: DateTime.utc(2026, 1, 1, 13),
          );

      coordinator.start();
      await pumpEventQueue();

      expect(transport.sentKeys, isEmpty);
      expect(configuration.reads, 0);
      expect(queue.openImageCalls, 0);
      expect(queue.keys, <String>['a', 'b']);
    });

    test('a failing head is not skipped in favor of a later item', () async {
      queue.keys.addAll(<String>['a', 'b']);
      transport.statuses.add(503);

      coordinator.start();
      await pumpEventQueue();

      expect(transport.sentKeys, <String>['a']);
      expect(queue.keys, <String>['a', 'b']);
    });
  });

  group('single flight and coalescing', () {
    test('never runs two attempts and folds notifications into one follow-up',
        () async {
      queue.keys.add('a');
      transport.hold = true;

      coordinator.start();
      await pumpEventQueue();
      expect(transport.pending, hasLength(1));
      expect(coordinator.isEvaluating, isTrue);

      for (var i = 0; i < 5; i++) {
        coordinator.onQueueChanged();
      }
      await pumpEventQueue();
      expect(transport.sentKeys, <String>['a']);
      expect(transport.maxActive, 1);

      transport.pending.single.complete(const TransportHttpResponse(201));
      await pumpEventQueue();

      // First evaluation: head `a`, then the empty queue. The five notifications
      // produce one more evaluation, not five.
      expect(queue.nextHeadCalls, 3);
      expect(transport.maxActive, 1);
      expect(coordinator.isEvaluating, isFalse);
    });

    test('repeated start and notifications on an idle queue do not loop',
        () async {
      coordinator.start();
      coordinator.start();
      coordinator.onQueueChanged();
      await pumpEventQueue();

      // The first request starts the evaluation; the two later ones, made
      // while it runs, fold into a single follow-up.
      expect(queue.nextHeadCalls, 2);
      expect(transport.sentKeys, isEmpty);
    });

    test('ignores notifications before start', () async {
      queue.keys.add('a');

      coordinator.onQueueChanged();
      await pumpEventQueue();

      expect(queue.nextHeadCalls, 0);
      expect(transport.sentKeys, isEmpty);
    });

    test('a later notification evaluates again after an unconcluded head',
        () async {
      queue.keys.add('a');
      transport.statuses.add(503);

      coordinator.start();
      await pumpEventQueue();
      expect(transport.sentKeys, <String>['a']);
      expect(coordinator.isEvaluating, isFalse);

      coordinator.onQueueChanged();
      await pumpEventQueue();

      expect(transport.sentKeys, <String>['a', 'a']);
      expect(queue.keys, isEmpty);
    });
  });

  group('serial region', () {
    test('is not held while the transport is in use', () async {
      queue.keys.add('a');
      transport.hold = true;

      coordinator.start();
      await pumpEventQueue();

      expect(transport.pending, hasLength(1));
      expect(transport.regionHeldAtSend, isFalse);
      expect(queue.regionHeld, isFalse);

      // A new occurrence is persisted while the upload is still in flight.
      await queue.enqueue('b').timeout(const Duration(seconds: 1));
      coordinator.onQueueChanged();
      await pumpEventQueue();
      expect(queue.keys, <String>['a', 'b']);
      expect(transport.sentKeys, <String>['a']);

      transport.pending.single.complete(const TransportHttpResponse(201));
      transport.hold = false;
      await pumpEventQueue();

      // The occurrence persisted during the upload keeps its order.
      expect(transport.sentKeys, <String>['a', 'b']);
      expect(queue.removed, <String>['a', 'b']);
    });
  });

  group('attempt preconditions', () {
    test('a paused delivery makes no configuration read, image or socket',
        () async {
      queue.keys.add('a');
      queue.control = DeliveryControlPaused(DeliveryPauseReason.access);

      coordinator.start();
      await pumpEventQueue();

      expect(configuration.reads, 0);
      expect(queue.openImageCalls, 0);
      expect(transport.sentKeys, isEmpty);
    });

    test('an unavailable configuration opens neither image nor socket',
        () async {
      queue.keys.add('a');
      configuration.result = const DeliveryConfigurationMissing();

      coordinator.start();
      await pumpEventQueue();

      expect(configuration.reads, 1);
      expect(queue.openImageCalls, 0);
      expect(transport.sentKeys, isEmpty);
      expect(queue.keys, <String>['a']);
    });

    test('a stale configuration revision never reaches the transport',
        () async {
      queue.keys.add('a');
      configuration.currentRevision = 2;

      coordinator.start();
      await pumpEventQueue();

      expect(queue.openImageCalls, 0);
      expect(transport.sentKeys, isEmpty);
      expect(queue.keys, <String>['a']);
    });
  });

  group('cleanup priority and idle', () {
    DeliveryHeadPendingCleanup pendingCleanup(String key, {DateTime? dueAt}) =>
        DeliveryHeadPendingCleanup(
          head: DeliveryQueueHead(idempotencyKey: key, queueSequence: 1),
          disposition: DeliveryDisposition.created,
          dueAt: dueAt,
        );

    test('pending cleanup runs despite pause and missing configuration',
        () async {
      queue.keys.addAll(<String>['a', 'b']);
      queue.control = DeliveryControlPaused(DeliveryPauseReason.access);
      configuration.result = const DeliveryConfigurationMissing();
      queue.headOverride = (key) =>
          key == 'a' ? pendingCleanup(key) : const DeliveryQueueEmpty();

      coordinator.start();
      await pumpEventQueue();

      expect(queue.removed, <String>['a']);
      expect(configuration.reads, 0);
      expect(queue.openImageCalls, 0);
      expect(transport.sentKeys, isEmpty);
    });

    test('cleanup not yet due waits without removing or using the network',
        () async {
      queue.keys.add('a');
      queue.headOverride =
          (key) => pendingCleanup(key, dueAt: DateTime.utc(2026, 1, 1, 13));

      coordinator.start();
      await pumpEventQueue();

      expect(queue.removed, isEmpty);
      expect(queue.keys, <String>['a']);
      expect(transport.sentKeys, isEmpty);
      expect(coordinator.isEvaluating, isFalse);
    });

    test('an empty queue goes idle without reading configuration', () async {
      coordinator.start();
      await pumpEventQueue();

      expect(configuration.reads, 0);
      expect(transport.sentKeys, isEmpty);
      expect(coordinator.isEvaluating, isFalse);
    });
  });

  group('attempt orchestration', () {
    test('uses one snapshot and checks its revision right before the socket',
        () async {
      queue.keys.add('a');
      transport.readImage = true;

      coordinator.start();
      await pumpEventQueue();

      expect(
        _events.take(5).toList(),
        <String>['control', 'read', 'isCurrent', 'openImage', 'send'],
      );
      final request = transport.requests.single;
      expect(request.baseUrl, _baseUrl);
      expect(request.configurationRevision, 1);
      expect(request.idempotencyKey, 'a');
      expect(request.payload.image.byteLength, 3);
      expect(transport.sentImageBytes, <int>[1, 2, 3]);
    });

    test('a revision that goes stale while the snapshot is read never sends',
        () async {
      queue.keys.add('a');
      configuration.afterRead = () => configuration.currentRevision = 2;

      coordinator.start();
      await pumpEventQueue();

      expect(_events, containsAllInOrder(<String>['read', 'isCurrent']));
      expect(queue.openImageCalls, 0);
      expect(transport.sentKeys, isEmpty);
      expect(queue.keys, <String>['a']);
      expect(queue.pauses, 0);
    });

    test('a retry reuses the same key and persisted representation', () async {
      queue.keys.add('a');
      transport.statuses.add(503);

      coordinator.start();
      await pumpEventQueue();
      coordinator.onQueueChanged();
      await pumpEventQueue();

      expect(transport.requests, hasLength(2));
      expect(transport.requests[0].idempotencyKey, 'a');
      expect(transport.requests[1].idempotencyKey, 'a');
      expect(
        transport.requests[1].payload.detectedAtIso8601,
        transport.requests[0].payload.detectedAtIso8601,
      );
    });

    test('records the definitive decision before the local removal', () async {
      queue.keys.add('a');
      transport.statuses.add(400);

      coordinator.start();
      await pumpEventQueue();

      expect(queue.decisions, <String>['a:invalidContract']);
      expect(
        _events.where((e) => e == 'decision' || e == 'remove').toList(),
        <String>['decision', 'remove'],
      );
      expect(queue.keys, isEmpty);
    });

    test('an unrecorded decision never removes the item', () async {
      queue.keys.add('a');
      queue.decisionResult = DeliveryMutationResult.storageFailure;

      coordinator.start();
      await pumpEventQueue();

      expect(transport.sentKeys, <String>['a']);
      expect(queue.removed, isEmpty);
      expect(queue.keys, <String>['a']);
      expect(coordinator.isEvaluating, isFalse);
    });
  });

  group('local failures', () {
    DeliveryHeadLocalIntegrityFailure integrityFailure(String key) =>
        DeliveryHeadLocalIntegrityFailure(
          head: DeliveryQueueHead(idempotencyKey: key, queueSequence: 1),
        );

    test('an invalid JPEG pauses as local failure without configuration',
        () async {
      queue.keys.addAll(<String>['a', 'b']);
      queue.headOverride = integrityFailure;

      coordinator.start();
      await pumpEventQueue();

      expect(
        queue.pausedWith,
        <PausedDeliveryDecision>[
          PausedDeliveryDecision(DeliveryPauseReason.localFailure),
        ],
      );
      expect(configuration.reads, 0);
      expect(queue.openImageCalls, 0);
      expect(transport.sentKeys, isEmpty);
      expect(queue.keys, <String>['a', 'b']);
      expect(coordinator.isEvaluating, isFalse);
    });

    test('an integrity failure keeps an active pause and does not rewrite it',
        () async {
      queue.keys.add('a');
      queue.headOverride = integrityFailure;
      queue.control = DeliveryControlPaused(DeliveryPauseReason.access);

      coordinator.start();
      await pumpEventQueue();

      expect(queue.pauses, 0);
      expect(transport.sentKeys, isEmpty);
    });

    test('an image that cannot be opened pauses without a socket', () async {
      queue.keys.add('a');
      queue.openImageThrows = true;

      coordinator.start();
      await pumpEventQueue();

      expect(queue.pausedWith.single.reason, DeliveryPauseReason.localFailure);
      expect(transport.sentKeys, isEmpty);
      expect(queue.keys, <String>['a']);
    });

    test('a transport local failure pauses and preserves the item', () async {
      queue.keys.add('a');
      transport.results.add(const TransportLocalFailure());

      coordinator.start();
      await pumpEventQueue();

      expect(queue.pausedWith.single.reason, DeliveryPauseReason.localFailure);
      expect(queue.decisions, isEmpty);
      expect(queue.recoverableFailures, 0);
      expect(queue.keys, <String>['a']);
      expect(transport.sentKeys, hasLength(1));
    });

    test('an unavailable secure storage pauses without image or socket',
        () async {
      queue.keys.add('a');
      configuration.result = const DeliverySecureStorageUnavailable();

      coordinator.start();
      await pumpEventQueue();

      expect(queue.pausedWith.single.reason, DeliveryPauseReason.localFailure);
      expect(queue.openImageCalls, 0);
      expect(transport.sentKeys, isEmpty);
      expect(queue.keys, <String>['a']);
    });

    test('a missing configuration does not pause', () async {
      queue.keys.add('a');
      configuration.result = const DeliveryDestinationInvalid();

      coordinator.start();
      await pumpEventQueue();

      expect(queue.pauses, 0);
      expect(queue.openImageCalls, 0);
    });
  });

  group('decision matrix', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    DeliveryHeadEligible eligibleWithAttempts(String key, int attempts) =>
        DeliveryHeadEligible(
          head: DeliveryQueueHead(
            idempotencyKey: key,
            queueSequence: 1,
            attemptCount: attempts,
          ),
          payload: DeliveryOccurrencePayload(
            detectedAtIso8601: '2026-01-01T12:00:00Z',
            latitude: -23.5,
            longitude: -46.6,
            speedKmh: null,
            confidence: 1.0,
            defectClass: 'pothole',
            image: DeliveryImageRef(byteLength: 3, opaqueHandle: key),
          ),
        );

    Future<void> runOnce() async {
      coordinator.start();
      await pumpEventQueue();
    }

    const definitive = <int, DeliveryDisposition>{
      200: DeliveryDisposition.alreadyExisting,
      201: DeliveryDisposition.created,
      400: DeliveryDisposition.invalidContract,
      409: DeliveryDisposition.conflict,
      413: DeliveryDisposition.imageTooLarge,
      415: DeliveryDisposition.unsupportedFormat,
    };
    for (final entry in definitive.entries) {
      test('${entry.key} records ${entry.value.name} and removes the item',
          () async {
        queue.keys.add('a');
        transport.statuses.add(entry.key);

        await runOnce();

        expect(queue.decisions, <String>['a:${entry.value.name}']);
        expect(queue.removed, <String>['a']);
        expect(queue.pauses, 0);
        expect(queue.recoverableFailures, 0);
        expect(transport.sentKeys, <String>['a']);
        expect(
          logLines,
          entry.value.isAccepted
              ? isEmpty
              : <String>[
                  'E4_DELIVERY_DEFINITIVE_REJECTION '
                      'disposition=${entry.value.name}',
                ],
        );
      });
    }

    test('401 and 403 pause for authentication and access and keep the item',
        () async {
      for (final (status, reason) in <(int, DeliveryPauseReason)>[
        (401, DeliveryPauseReason.authentication),
        (403, DeliveryPauseReason.access),
      ]) {
        queue.keys
          ..clear()
          ..add('a');
        queue.pausedWith.clear();
        queue.control = const DeliveryControlRunning();
        transport.statuses.add(status);
        coordinator.start();
        await pumpEventQueue();

        expect(queue.pausedWith, <PausedDeliveryDecision>[
          PausedDeliveryDecision(reason),
        ]);
        expect(queue.keys, <String>['a']);
      }
      expect(queue.decisions, isEmpty);
      expect(queue.recoverableFailures, 0);
      expect(logLines, isEmpty);
    });

    test('every other status pauses conservatively and logs the status',
        () async {
      for (final status in <int>[100, 204, 302, 404, 418, 429]) {
        queue.keys
          ..clear()
          ..add('a');
        queue.pausedWith.clear();
        transport.statuses.add(status);
        coordinator.start();
        await pumpEventQueue();

        expect(queue.pausedWith, <PausedDeliveryDecision>[
          PausedDeliveryDecision(
            DeliveryPauseReason.unexpectedResponse,
            unexpectedStatusCode: status,
          ),
        ]);
        expect(queue.keys, <String>['a']);
      }
      expect(queue.decisions, isEmpty);
      expect(queue.recoverableFailures, 0);
      expect(logLines, <String>[
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=100',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=204',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=302',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=404',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=418',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=429',
      ]);
    });

    test('5xx, network failure and timeout record a backoff and keep the item',
        () async {
      queue.keys.add('a');
      transport.statuses.add(503);
      transport.results
        ..add(const TransportNetworkFailure())
        ..add(const TransportTimeout());

      // Results answer before statuses: network, timeout, then 503.
      for (var i = 0; i < 3; i++) {
        coordinator.start();
        await pumpEventQueue();
      }

      expect(queue.failureRecords, hasLength(3));
      for (final (key, calculatedAt, nextAttemptAt) in queue.failureRecords) {
        expect(key, 'a');
        expect(calculatedAt, now);
        expect(nextAttemptAt, now.add(DeliveryBackoffPolicy.delayFor(1)));
      }
      expect(queue.pauses, 0);
      expect(queue.decisions, isEmpty);
      expect(queue.keys, <String>['a']);
      expect(logLines, <String>[
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=network',
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=timeout',
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=serverError',
      ]);
    });

    test('the backoff grows with the consecutive failures of the head',
        () async {
      queue.keys.add('a');
      queue.headOverride = (key) => eligibleWithAttempts(key, 3);
      transport.statuses.add(500);

      await runOnce();

      final (_, calculatedAt, nextAttemptAt) = queue.failureRecords.single;
      expect(nextAttemptAt.difference(calculatedAt),
          DeliveryBackoffPolicy.delayFor(4));
      expect(
          nextAttemptAt.difference(calculatedAt), const Duration(seconds: 135));
    });

    test('the backoff saturates at the ceiling', () async {
      queue.keys.add('a');
      queue.headOverride = (key) => eligibleWithAttempts(key, 1000);
      transport.statuses.add(500);

      await runOnce();

      final (_, calculatedAt, nextAttemptAt) = queue.failureRecords.single;
      expect(nextAttemptAt.difference(calculatedAt),
          DeliveryBackoffPolicy.maxDelay);
    });

    test('a cancelled attempt records no failure, decision or pause', () async {
      queue.keys.add('a');
      transport.results.add(const TransportCancelled());

      await runOnce();

      expect(queue.failureRecords, isEmpty);
      expect(queue.decisions, isEmpty);
      expect(queue.pauses, 0);
      expect(queue.keys, <String>['a']);
      expect(logLines, isEmpty);
    });

    test('a failed cleanup keeps the decision and never sends again', () async {
      queue.keys.add('a');
      queue.removalFails = true;

      await runOnce();

      expect(queue.decisions, <String>['a:created']);
      expect(queue.keys, <String>['a']);
      expect(queue.cleanupFailureRecords, hasLength(1));
      final (key, calculatedAt, nextCleanupAt) =
          queue.cleanupFailureRecords.single;
      expect(key, 'a');
      expect(
          nextCleanupAt, calculatedAt.add(DeliveryBackoffPolicy.delayFor(1)));
      expect(queue.recoverableFailures, 0);
      expect(queue.pauses, 0);
      expect(logLines, <String>['E4_DELIVERY_CLEANUP_FAILURE']);

      // The queue now reports the recorded decision: only cleanup is tried.
      queue.headOverride = (key) => DeliveryHeadPendingCleanup(
            head: DeliveryQueueHead(
              idempotencyKey: key,
              queueSequence: 1,
              cleanupAttemptCount: 2,
            ),
            disposition: DeliveryDisposition.created,
          );
      coordinator.onQueueChanged();
      await pumpEventQueue();

      expect(queue.cleanupFailureRecords, hasLength(2));
      final (_, secondAt, secondNext) = queue.cleanupFailureRecords.last;
      expect(
          secondNext.difference(secondAt), DeliveryBackoffPolicy.delayFor(3));

      queue.removalFails = false;
      coordinator.onQueueChanged();
      await pumpEventQueue();

      expect(queue.removed, <String>['a']);
      expect(transport.sentKeys, <String>['a']);
      expect(configuration.reads, 1);
      expect(queue.openImageCalls, 1);
    });

    test('log lines use only fixed categories and closed values', () async {
      queue.keys.add('a');
      transport.results
        ..add(const TransportTimeout())
        ..add(const TransportNetworkFailure());
      transport.statuses.addAll(<int>[418, 400]);
      queue.removalFails = true;

      for (var i = 0; i < 4; i++) {
        queue.pausedWith.clear();
        coordinator.start();
        await pumpEventQueue();
      }

      expect(logLines, isNotEmpty);
      final shape = RegExp(r'^E4_DELIVERY_[A-Z_]+( [a-z]+=[A-Za-z0-9]+)?$');
      for (final line in logLines) {
        expect(line, matches(shape));
        expect(line, isNot(contains(_secret)));
        expect(line, isNot(contains('example')));
        expect(line, isNot(contains('http')));
      }
    });
  });

  group('pause, backoff and resume', () {
    DeliveryControlPaused paused(DeliveryPauseReason reason) =>
        DeliveryControlPaused(
          reason,
          unexpectedStatusCode:
              reason == DeliveryPauseReason.unexpectedResponse ? 418 : null,
        );

    DeliveryHeadResult inBackoff(String key) => DeliveryHeadInBackoff(
          head: DeliveryQueueHead(
            idempotencyKey: key,
            queueSequence: 1,
            attemptCount: 2,
          ),
          nextAttemptAt: DateTime.utc(2026, 1, 1, 13),
        );

    DeliveryHeadResult cleanupNotDue(String key) => DeliveryHeadPendingCleanup(
          head: DeliveryQueueHead(
            idempotencyKey: key,
            queueSequence: 1,
            cleanupAttemptCount: 1,
          ),
          disposition: DeliveryDisposition.created,
          dueAt: DateTime.utc(2026, 1, 1, 13),
        );

    void expectNothingSentOrRecorded() {
      expect(transport.sentKeys, isEmpty);
      expect(queue.openImageCalls, 0);
      expect(queue.failureRecords, isEmpty);
      expect(queue.cleanupFailureRecords, isEmpty);
      expect(queue.removed, isEmpty);
      expect(queue.keys, <String>['a']);
    }

    group('no automatic retry', () {
      test('a persisted pause stops every later trigger', () async {
        queue.keys.add('a');
        transport.statuses.add(401);
        coordinator.start();
        await pumpEventQueue();
        expect(
            queue.pausedWith.single.reason, DeliveryPauseReason.authentication);

        queue.control = paused(DeliveryPauseReason.authentication);
        for (var i = 0; i < 3; i++) {
          coordinator.start();
          coordinator.onQueueChanged();
          await pumpEventQueue();
        }

        expect(transport.sentKeys, <String>['a']);
        expect(configuration.reads, 1);
        expect(queue.pauses, 1);
        expect(coordinator.isEvaluating, isFalse);
      });

      test('a recoverable backoff stops every later trigger', () async {
        queue.keys.add('a');
        transport.statuses.add(503);
        coordinator.start();
        await pumpEventQueue();
        expect(queue.failureRecords, hasLength(1));

        queue.headOverride = inBackoff;
        for (var i = 0; i < 3; i++) {
          coordinator.onQueueChanged();
          await pumpEventQueue();
        }

        expect(transport.sentKeys, <String>['a']);
        expect(queue.failureRecords, hasLength(1));
        expect(coordinator.isEvaluating, isFalse);
      });

      test('a cleanup backoff stops every later trigger without the network',
          () async {
        queue.keys.add('a');
        queue.headOverride = cleanupNotDue;

        for (var i = 0; i < 3; i++) {
          coordinator.start();
          coordinator.onQueueChanged();
          await pumpEventQueue();
        }

        expectNothingSentOrRecorded();
        expect(configuration.reads, 0);
        expect(coordinator.isEvaluating, isFalse);
      });
    });

    group('confirmed configuration correction', () {
      for (final reason in <DeliveryPauseReason>[
        DeliveryPauseReason.authentication,
        DeliveryPauseReason.access,
        DeliveryPauseReason.unexpectedResponse,
      ]) {
        test('clears the ${reason.name} pause and evaluates once', () async {
          queue.keys.add('a');
          queue.control = paused(reason);
          coordinator.start();
          await pumpEventQueue();
          expect(transport.sentKeys, isEmpty);

          await coordinator.onConfigurationCorrected();
          await pumpEventQueue();

          expect(queue.resumes, 1);
          expect(queue.control, isA<DeliveryControlRunning>());
          expect(transport.sentKeys, <String>['a']);
        });
      }

      test('keeps a local failure pause', () async {
        queue.keys.add('a');
        queue.control = paused(DeliveryPauseReason.localFailure);
        coordinator.start();
        await pumpEventQueue();

        await coordinator.onConfigurationCorrected();
        await pumpEventQueue();

        expect(queue.resumes, 0);
        expect(queue.control, isA<DeliveryControlPaused>());
        expectNothingSentOrRecorded();
      });

      test('does not write anything when delivery is running', () async {
        coordinator.start();
        await pumpEventQueue();

        await coordinator.onConfigurationCorrected();
        await pumpEventQueue();

        expect(queue.resumes, 0);
        expect(queue.pauses, 0);
      });

      test('a failed clearing keeps the pause and sends nothing', () async {
        queue.keys.add('a');
        queue.control = paused(DeliveryPauseReason.access);
        queue.resumeResult = DeliveryMutationResult.storageFailure;
        coordinator.start();
        await pumpEventQueue();

        await coordinator.onConfigurationCorrected();
        await pumpEventQueue();

        expect(queue.control, isA<DeliveryControlPaused>());
        expectNothingSentOrRecorded();
      });

      test('does not anticipate a recoverable or cleanup backoff', () async {
        queue.keys.add('a');
        for (final head in <DeliveryHeadResult Function(String)>[
          inBackoff,
          cleanupNotDue,
        ]) {
          queue.headOverride = head;
          queue.control = paused(DeliveryPauseReason.authentication);

          await coordinator.onConfigurationCorrected();
          coordinator.start();
          await pumpEventQueue();

          expectNothingSentOrRecorded();
        }
        expect(queue.resumes, 2);
      });

      test('is ignored after dispose', () async {
        queue.control = paused(DeliveryPauseReason.access);
        await coordinator.dispose();

        await coordinator.onConfigurationCorrected();

        expect(queue.resumes, 0);
      });
    });

    group('manual retry', () {
      for (final reason in DeliveryPauseReason.values) {
        test('clears the explicit ${reason.name} pause and evaluates',
            () async {
          queue.keys.add('a');
          queue.control = paused(reason);
          coordinator.start();
          await pumpEventQueue();
          expect(transport.sentKeys, isEmpty);

          final result = await coordinator.retryManually();
          await pumpEventQueue();

          expect(result, DeliveryManualRetryResult.resumed);
          expect(queue.resumes, 1);
          expect(transport.sentKeys, <String>['a']);
        });
      }

      test('without a pause only requests an evaluation', () async {
        queue.keys.add('a');
        queue.headOverride = inBackoff;
        coordinator.start();
        await pumpEventQueue();
        final readsBefore = queue.nextHeadCalls;

        final result = await coordinator.retryManually();
        await pumpEventQueue();

        expect(result, DeliveryManualRetryResult.evaluationRequested);
        expect(queue.resumes, 0);
        expect(queue.nextHeadCalls, greaterThan(readsBefore));
        expectNothingSentOrRecorded();
      });

      test('does not anticipate a recoverable or cleanup backoff', () async {
        queue.keys.add('a');
        for (final head in <DeliveryHeadResult Function(String)>[
          inBackoff,
          cleanupNotDue,
        ]) {
          queue.headOverride = head;
          queue.control = paused(DeliveryPauseReason.localFailure);

          final result = await coordinator.retryManually();
          coordinator.start();
          await pumpEventQueue();

          expect(result, DeliveryManualRetryResult.resumed);
          expectNothingSentOrRecorded();
          expect(configuration.reads, 0);
        }
      });

      test('an unreadable control changes nothing', () async {
        queue.keys.add('a');
        queue.control = const DeliveryControlUnavailable();
        coordinator.start();
        await pumpEventQueue();

        final result = await coordinator.retryManually();
        await pumpEventQueue();

        expect(result, DeliveryManualRetryResult.notApplied);
        expect(queue.resumes, 0);
        expectNothingSentOrRecorded();
      });

      test('a pause that cannot be cleared is reported and not evaluated',
          () async {
        queue.keys.add('a');
        queue.control = paused(DeliveryPauseReason.access);
        queue.resumeResult = DeliveryMutationResult.storageFailure;
        coordinator.start();
        await pumpEventQueue();

        final result = await coordinator.retryManually();
        await pumpEventQueue();

        expect(result, DeliveryManualRetryResult.notApplied);
        expect(queue.control, isA<DeliveryControlPaused>());
        expectNothingSentOrRecorded();
      });

      test('clears the pause before start but evaluates only after start',
          () async {
        queue.keys.add('a');
        queue.control = paused(DeliveryPauseReason.localFailure);

        await coordinator.retryManually();
        await pumpEventQueue();
        expect(queue.nextHeadCalls, 0);
        expect(queue.resumes, 1);

        coordinator.start();
        await pumpEventQueue();
        expect(transport.sentKeys, <String>['a']);
      });

      test('is ignored after dispose', () async {
        queue.control = paused(DeliveryPauseReason.access);
        await coordinator.dispose();

        final result = await coordinator.retryManually();

        expect(result, DeliveryManualRetryResult.notApplied);
        expect(queue.resumes, 0);
      });
    });
  });

  group('reactions, timer and lifecycle', () {
    late _ManualClock clock;
    late _ManualTimer timer;
    late List<DeliveryPhase> phases;

    DeliveryHeadResult inBackoff(String key) => DeliveryHeadInBackoff(
          head: DeliveryQueueHead(
            idempotencyKey: key,
            queueSequence: 1,
            attemptCount: 1,
          ),
          nextAttemptAt: DateTime.utc(2026, 1, 1, 13),
        );

    DeliveryControlPaused paused(DeliveryPauseReason reason) =>
        DeliveryControlPaused(reason);

    setUp(() async {
      await coordinator.dispose();
      clock = _ManualClock();
      timer = _ManualTimer(clock);
      coordinator = OccurrenceDeliveryCoordinator(
        queue: queue,
        configuration: configuration,
        transport: transport,
        clock: clock,
        timer: timer,
        logger: SanitizedDeliveryTechnicalLogger(logLines.add),
      );
      phases = <DeliveryPhase>[];
      coordinator.phases.listen(phases.add);
    });

    group('bootstrap, new pending item and resumed', () {
      test('bootstrap in the background waits for resumed', () async {
        queue.keys.add('a');
        await coordinator.onAppLeftForeground();

        coordinator.start();
        coordinator.onQueueChanged();
        await pumpEventQueue();
        expect(queue.nextHeadCalls, 0);
        expect(transport.sentKeys, isEmpty);

        coordinator.onAppResumed();
        await pumpEventQueue();
        expect(transport.sentKeys, <String>['a']);
        expect(queue.removed, <String>['a']);
      });

      test('a snapshot of a new pending item delivers it and returns to idle',
          () async {
        coordinator.start();
        await pumpEventQueue();
        expect(coordinator.phase, DeliveryPhase.idle);

        await queue.enqueue('a');
        coordinator.onQueueChanged();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a']);
        expect(phases, <DeliveryPhase>[
          DeliveryPhase.sending,
          DeliveryPhase.idle,
        ]);
      });

      test('resumed respects an existing pause', () async {
        queue.keys.add('a');
        queue.control = paused(DeliveryPauseReason.access);
        coordinator.start();
        await pumpEventQueue();

        await coordinator.onAppLeftForeground();
        coordinator.onAppResumed();
        coordinator.onAppResumed();
        await pumpEventQueue();

        expect(transport.sentKeys, isEmpty);
        expect(queue.resumes, 0);
        expect(coordinator.phase, DeliveryPhase.pausedAccess);
        expect(coordinator.isEvaluating, isFalse);
      });

      test('resumed does not anticipate a backoff', () async {
        queue.keys.add('a');
        queue.headOverride = inBackoff;
        coordinator.start();
        await pumpEventQueue();

        await coordinator.onAppLeftForeground();
        coordinator.onAppResumed();
        await pumpEventQueue();

        expect(transport.sentKeys, isEmpty);
        expect(coordinator.phase, DeliveryPhase.waitingBackoff);
        expect(timer.active, hasLength(1));
      });
    });

    group('timer', () {
      test('a backoff arms one timer and its expiry evaluates once', () async {
        queue.keys.add('a');
        queue.headOverride = inBackoff;
        coordinator.start();
        await pumpEventQueue();

        expect(timer.active.single.dueAt, DateTime.utc(2026, 1, 1, 13));
        expect(coordinator.phase, DeliveryPhase.waitingBackoff);
        expect(transport.sentKeys, isEmpty);

        // The queue now reports the head as due.
        queue.headOverride = null;
        timer.fire();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a']);
        expect(queue.removed, <String>['a']);
        expect(timer.active, isEmpty);
        expect(timer.maxActive, 1);
      });

      test('a failed attempt arms the timer for the backoff end', () async {
        queue.keys.add('a');
        transport.statuses.addAll(<int>[503, 201]);
        coordinator.start();
        await pumpEventQueue();

        expect(queue.failureRecords, hasLength(1));
        expect(timer.active.single.dueAt, queue.failureRecords.single.$3);
        expect(coordinator.phase, DeliveryPhase.waitingBackoff);
        expect(transport.sentKeys, <String>['a']);

        timer.fire();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a', 'a']);
        expect(queue.removed, <String>['a']);
        expect(timer.maxActive, 1);
        expect(timer.armed, hasLength(1));
      });

      test('a backoff already over arms nothing and does not spin', () async {
        queue.keys.add('a');
        queue.headOverride = (key) => DeliveryHeadInBackoff(
              head: DeliveryQueueHead(idempotencyKey: key, queueSequence: 1),
              nextAttemptAt: DateTime.utc(2026, 1, 1, 12),
            );
        coordinator.start();
        await pumpEventQueue();

        expect(timer.armed, isEmpty);
        expect(queue.nextHeadCalls, 1);
        expect(transport.sentKeys, isEmpty);
      });

      test('a backoff under a pause arms no timer', () async {
        queue.keys.add('a');
        queue.headOverride = inBackoff;
        queue.control = paused(DeliveryPauseReason.authentication);
        coordinator.start();
        await pumpEventQueue();

        expect(timer.armed, isEmpty);
        expect(coordinator.phase, DeliveryPhase.pausedAuthentication);
      });

      test('a later trigger replaces the timer instead of adding one',
          () async {
        queue.keys.add('a');
        queue.headOverride = inBackoff;
        coordinator.start();
        await pumpEventQueue();
        for (var i = 0; i < 3; i++) {
          coordinator.onQueueChanged();
          await pumpEventQueue();
        }

        expect(timer.active, hasLength(1));
        expect(timer.maxActive, 1);
        expect(transport.sentKeys, isEmpty);
      });

      test('a cleanup not yet due arms the timer and uses no network',
          () async {
        queue.keys.add('a');
        queue.headOverride = (key) => DeliveryHeadPendingCleanup(
              head: DeliveryQueueHead(
                idempotencyKey: key,
                queueSequence: 1,
                cleanupAttemptCount: 1,
              ),
              disposition: DeliveryDisposition.created,
              dueAt: DateTime.utc(2026, 1, 1, 13),
            );
        queue.control = paused(DeliveryPauseReason.authentication);
        configuration.result = const DeliveryConfigurationMissing();
        coordinator.start();
        await pumpEventQueue();

        expect(timer.active.single.dueAt, DateTime.utc(2026, 1, 1, 13));
        expect(coordinator.phase, DeliveryPhase.cleaning);

        queue.headOverride = (key) => DeliveryHeadPendingCleanup(
              head: DeliveryQueueHead(idempotencyKey: key, queueSequence: 1),
              disposition: DeliveryDisposition.created,
            );
        timer.fire();
        await pumpEventQueue();

        expect(queue.removed, <String>['a']);
        expect(transport.sentKeys, isEmpty);
        expect(configuration.reads, 0);
      });

      test('a failed cleanup arms the timer for the cleanup backoff', () async {
        queue.keys.add('a');
        queue.headOverride = (key) => DeliveryHeadPendingCleanup(
              head: DeliveryQueueHead(idempotencyKey: key, queueSequence: 1),
              disposition: DeliveryDisposition.created,
            );
        queue.removalFails = true;
        coordinator.start();
        await pumpEventQueue();

        expect(queue.cleanupFailureRecords, hasLength(1));
        expect(
            timer.active.single.dueAt, queue.cleanupFailureRecords.single.$3);
        expect(transport.sentKeys, isEmpty);
      });

      test('dispose cancels the timer and closes the phases', () async {
        queue.keys.add('a');
        queue.headOverride = inBackoff;
        coordinator.start();
        await pumpEventQueue();
        expect(timer.active, hasLength(1));

        await coordinator.dispose();

        expect(timer.active, isEmpty);
        expect(timer.armed.single.cancelled, isTrue);
      });
    });

    group('relevant configuration change', () {
      late DeliveryConfigurationChangeService service;

      setUp(() {
        service = DeliveryConfigurationChangeService(
          snapshot: configuration,
          queue: queue,
          delivery: coordinator,
        );
      });

      test('a confirmed correction clears the pause and sends the new pair',
          () async {
        queue.keys.add('a');
        queue.control = paused(DeliveryPauseReason.authentication);
        coordinator.start();
        await pumpEventQueue();
        expect(coordinator.phase, DeliveryPhase.pausedAuthentication);
        expect(transport.sentKeys, isEmpty);

        await service.replaceDestinationOrCredential<void>(() async {
          configuration.currentRevision = 2;
          configuration.result = DeliveryConfigurationAvailable(
            DeliveryConfiguration(
              revision: 2,
              baseUrl: _baseUrl,
              credential: NonPrintableSecret(_secret),
            ),
          );
        });
        await pumpEventQueue();

        expect(queue.resumes, 1);
        expect(transport.sentKeys, <String>['a']);
        expect(queue.removed, <String>['a']);
      });

      test(
          'removing the configuration publishes configurationRequired '
          'without any socket', () async {
        queue.keys.add('a');
        transport.hold = true;
        coordinator.start();
        await pumpEventQueue();
        expect(coordinator.phase, DeliveryPhase.sending);
        expect(transport.sentKeys, <String>['a']);

        await service.removeCredential<void>(() async {
          configuration.currentRevision = 2;
          configuration.result = const DeliveryConfigurationMissing();
        });
        await pumpEventQueue();

        expect(transport.cancelCalls, 1);
        expect(coordinator.phase, DeliveryPhase.configurationRequired);
        expect(transport.sentKeys, <String>['a']);
        expect(queue.decisions, isEmpty);
        expect(queue.failureRecords, isEmpty);
        expect(queue.pauses, 0);
        expect(queue.resumes, 0);
        expect(queue.keys, <String>['a']);
        expect(coordinator.isEvaluating, isFalse);
      });

      test('removing the destination keeps the pause and opens nothing',
          () async {
        queue.keys.add('a');
        queue.control = paused(DeliveryPauseReason.access);
        coordinator.start();
        await pumpEventQueue();

        await service.saveOperationalConfiguration<void>(
          readCurrentBaseUrl: () async => _baseUrl,
          newBaseUrl: null,
          write: () async {
            configuration.currentRevision = 2;
            configuration.result = const DeliveryConfigurationMissing();
          },
        );
        await pumpEventQueue();

        expect(queue.resumes, 0);
        expect(queue.control, isA<DeliveryControlPaused>());
        expect(coordinator.phase, DeliveryPhase.pausedAccess);
        expect(transport.sentKeys, isEmpty);
        expect(queue.openImageCalls, 0);
      });

      test(
          'a change during the upload cancels it and resends with the same key',
          () async {
        queue.keys.add('a');
        transport.hold = true;
        coordinator.start();
        await pumpEventQueue();
        expect(transport.pending, hasLength(1));
        transport.hold = false;

        await service.replaceDestinationOrCredential<void>(() async {
          // The old attempt can no longer persist anything here.
          expect(queue.decisions, isEmpty);
          expect(queue.failureRecords, isEmpty);
          expect(coordinator.isEvaluating, isFalse);
          configuration.currentRevision = 2;
          configuration.result = DeliveryConfigurationAvailable(
            DeliveryConfiguration(
              revision: 2,
              baseUrl: _baseUrl,
              credential: NonPrintableSecret(_secret),
            ),
          );
        });
        await pumpEventQueue();

        expect(transport.cancelCalls, 1);
        expect(transport.sentKeys, <String>['a', 'a']);
        expect(queue.removed, <String>['a']);
      });

      test('an operational change keeps an existing pause', () async {
        queue.keys.add('a');
        queue.control = paused(DeliveryPauseReason.authentication);
        coordinator.start();
        await pumpEventQueue();
        final evaluations = queue.nextHeadCalls;
        var written = 0;

        await service.saveOperationalConfiguration<void>(
          readCurrentBaseUrl: () async => _baseUrl,
          newBaseUrl: _baseUrl,
          write: () async => written++,
        );
        await pumpEventQueue();

        expect(written, 1);
        expect(queue.resumes, 0);
        expect(queue.control, isA<DeliveryControlPaused>());
        expect(queue.nextHeadCalls, evaluations);
        expect(coordinator.phase, DeliveryPhase.pausedAuthentication);
        expect(transport.sentKeys, isEmpty);
      });
    });

    group('leaving the foreground', () {
      test(
          'cancels the transport, keeps the item and resends with the same '
          'key on resumed', () async {
        queue.keys.add('a');
        transport.hold = true;
        coordinator.start();
        await pumpEventQueue();
        expect(transport.pending, hasLength(1));

        await coordinator.onAppLeftForeground();
        await pumpEventQueue();

        expect(transport.cancelCalls, 1);
        expect(queue.decisions, isEmpty);
        expect(queue.failureRecords, isEmpty);
        expect(queue.pauses, 0);
        expect(queue.keys, <String>['a']);
        expect(coordinator.isEvaluating, isFalse);
        expect(coordinator.phase, DeliveryPhase.ready);

        // Nothing starts in the background.
        final evaluations = queue.nextHeadCalls;
        coordinator.onQueueChanged();
        await pumpEventQueue();
        expect(queue.nextHeadCalls, evaluations);

        transport.hold = false;
        coordinator.onAppResumed();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a', 'a']);
        expect(queue.removed, <String>['a']);
      });

      test('a response that arrives after leaving is not persisted', () async {
        queue.keys.add('a');
        transport.hold = true;
        transport.honorsCancel = false;
        coordinator.start();
        await pumpEventQueue();

        await coordinator.onAppLeftForeground();
        transport.pending.single.complete(const TransportHttpResponse(400));
        await pumpEventQueue();

        expect(transport.cancelCalls, 1);
        expect(queue.decisions, isEmpty);
        expect(queue.removed, isEmpty);
        expect(queue.keys, <String>['a']);
        expect(coordinator.isEvaluating, isFalse);
      });

      test('cancels the timer and re-arms it on resumed', () async {
        queue.keys.add('a');
        queue.headOverride = inBackoff;
        coordinator.start();
        await pumpEventQueue();
        final armed = timer.active.single;

        await coordinator.onAppLeftForeground();

        expect(armed.cancelled, isTrue);
        expect(timer.active, isEmpty);
        expect(transport.cancelCalls, 0);

        coordinator.onAppResumed();
        await pumpEventQueue();

        expect(timer.active, hasLength(1));
        expect(timer.maxActive, 1);
        expect(transport.sentKeys, isEmpty);
      });

      test('leaving and returning during an upload never mixes attempts',
          () async {
        queue.keys.add('a');
        transport.hold = true;
        coordinator.start();
        await pumpEventQueue();
        transport.hold = false;

        await coordinator.onAppLeftForeground();
        coordinator.onAppResumed();
        await pumpEventQueue();

        expect(transport.maxActive, 1);
        expect(transport.sentKeys, <String>['a', 'a']);
        expect(queue.decisions, <String>['a:created']);
        expect(queue.removed, <String>['a']);
      });
    });
  });

  group('dispose', () {
    test('cancels the attempt in flight and persists nothing afterwards',
        () async {
      queue.keys.add('a');
      transport.hold = true;

      coordinator.start();
      await pumpEventQueue();
      expect(transport.pending, hasLength(1));

      await coordinator.dispose();

      expect(transport.cancelCalls, 1);
      expect(queue.decisions, isEmpty);
      expect(queue.keys, <String>['a']);
      expect(coordinator.isEvaluating, isFalse);

      coordinator.onQueueChanged();
      coordinator.start();
      await pumpEventQueue();
      expect(transport.sentKeys, hasLength(1));
    });

    test('is idempotent', () async {
      coordinator.start();
      await pumpEventQueue();
      await coordinator.dispose();
      await coordinator.dispose();

      expect(transport.cancelCalls, 0);
    });
  });

  group('delivery guarantees (E4.6, E4.9, E4.10, E4.13)', () {
    OccurrenceDeliveryCoordinator newCoordinator({
      Clock? clock,
      DeliveryTimerPort? timer,
      DeliveryTechnicalLogger? logger,
    }) =>
        OccurrenceDeliveryCoordinator(
          queue: queue,
          configuration: configuration,
          transport: transport,
          clock: clock ?? _FixedClock(),
          timer: timer,
          logger: logger ?? SanitizedDeliveryTechnicalLogger(logLines.add),
        );

    /// Replaces the running coordinator by a fresh one over the same queue,
    /// configuration and transport, as a process restart or crash would.
    Future<void> restart({Clock? clock, DeliveryTimerPort? timer}) async {
      await coordinator.dispose();
      coordinator = newCoordinator(clock: clock, timer: timer);
    }

    DeliveryHeadEligible eligibleWithAttempts(String key, int attempts) =>
        DeliveryHeadEligible(
          head: DeliveryQueueHead(
            idempotencyKey: key,
            queueSequence: 1,
            attemptCount: attempts,
          ),
          payload: DeliveryOccurrencePayload(
            detectedAtIso8601: '2026-01-01T12:00:00Z',
            latitude: -23.5,
            longitude: -46.6,
            speedKmh: null,
            confidence: 1.0,
            defectClass: 'pothole',
            image: DeliveryImageRef(byteLength: 3, opaqueHandle: key),
          ),
        );

    group('concurrency and persistence during the upload', () {
      test('every kind of trigger during an upload folds into one follow-up',
          () async {
        queue.keys.add('a');
        transport.hold = true;
        coordinator.start();
        await pumpEventQueue();
        expect(transport.pending, hasLength(1));

        coordinator.start();
        coordinator.onQueueChanged();
        coordinator.onAppResumed();
        await coordinator.onConfigurationCorrected();
        await coordinator.retryManually();
        coordinator.onQueueChanged();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a']);
        expect(transport.maxActive, 1);
        expect(queue.nextHeadCalls, 1);

        transport.pending.single.complete(const TransportHttpResponse(201));
        await pumpEventQueue();

        // Current evaluation: `a`, then the empty queue. All the triggers made
        // while it ran produce exactly one more evaluation.
        expect(queue.nextHeadCalls, 3);
        expect(transport.sentKeys, <String>['a']);
        expect(transport.maxActive, 1);
        expect(coordinator.isEvaluating, isFalse);
      });

      test(
          'occurrences persisted during an upload are not blocked and keep '
          'their order', () async {
        queue.keys.add('a');
        transport.hold = true;
        coordinator.start();
        await pumpEventQueue();

        for (final key in <String>['b', 'c', 'd']) {
          await queue.enqueue(key).timeout(const Duration(seconds: 1));
          coordinator.onQueueChanged();
        }
        await pumpEventQueue();

        expect(queue.keys, <String>['a', 'b', 'c', 'd']);
        expect(transport.sentKeys, <String>['a']);
        expect(queue.decisions, isEmpty);
        expect(queue.regionHeld, isFalse);

        transport.hold = false;
        transport.pending.single.complete(const TransportHttpResponse(201));
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a', 'b', 'c', 'd']);
        expect(queue.removed, <String>['a', 'b', 'c', 'd']);
        expect(transport.maxActive, 1);
        expect(transport.regionHeldAtSend, isFalse);
      });
    });

    group('idempotency after cancellation or crash', () {
      test('an upload lost to a crash is resent with the same key and data',
          () async {
        queue.keys.add('a');
        transport.hold = true;
        coordinator.start();
        await pumpEventQueue();
        expect(transport.pending, hasLength(1));

        await restart();
        transport.hold = false;
        coordinator.start();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a', 'a']);
        final first = transport.requests[0];
        final second = transport.requests[1];
        expect(second.idempotencyKey, first.idempotencyKey);
        expect(
            second.payload.detectedAtIso8601, first.payload.detectedAtIso8601);
        expect(second.payload.latitude, first.payload.latitude);
        expect(second.payload.longitude, first.payload.longitude);
        expect(queue.decisions, <String>['a:created']);
        expect(queue.removed, <String>['a']);
      });

      test('a crash after the recorded decision only finishes the cleanup',
          () async {
        queue.keys.add('a');
        queue.removalFails = true;
        coordinator.start();
        await pumpEventQueue();
        expect(queue.decisions, <String>['a:created']);
        expect(queue.keys, <String>['a']);

        // Restart: the queue now reports the recorded decision.
        await restart();
        queue.removalFails = false;
        queue.control = DeliveryControlPaused(DeliveryPauseReason.access);
        configuration.result = const DeliveryConfigurationMissing();
        queue.headOverride = (key) => DeliveryHeadPendingCleanup(
              head: DeliveryQueueHead(
                idempotencyKey: key,
                queueSequence: 1,
                cleanupAttemptCount: 1,
              ),
              disposition: DeliveryDisposition.created,
            );
        coordinator.start();
        await pumpEventQueue();

        expect(queue.removed, <String>['a']);
        expect(queue.decisions, <String>['a:created']);
        expect(transport.sentKeys, <String>['a']);
        expect(configuration.reads, 1);
        expect(queue.openImageCalls, 1);
      });

      test('a persisted pause survives a restart until a manual retry',
          () async {
        queue.keys.add('a');
        transport.statuses.add(401);
        coordinator.start();
        await pumpEventQueue();
        expect(
            queue.pausedWith.single.reason, DeliveryPauseReason.authentication);
        queue.control =
            DeliveryControlPaused(DeliveryPauseReason.authentication);

        await restart();
        coordinator.start();
        coordinator.onAppResumed();
        coordinator.onQueueChanged();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a']);
        expect(coordinator.phase, DeliveryPhase.pausedAuthentication);
        expect(queue.keys, <String>['a']);

        expect(await coordinator.retryManually(),
            DeliveryManualRetryResult.resumed);
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a', 'a']);
        expect(queue.removed, <String>['a']);
      });

      test('a persisted pause survives a restart until a confirmed correction',
          () async {
        queue.keys.add('a');
        transport.statuses.add(403);
        coordinator.start();
        await pumpEventQueue();
        queue.control = DeliveryControlPaused(DeliveryPauseReason.access);

        await restart();
        coordinator.start();
        await pumpEventQueue();
        expect(transport.sentKeys, <String>['a']);

        await coordinator.onConfigurationCorrected();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a', 'a']);
        expect(queue.removed, <String>['a']);
      });

      test('a persisted backoff survives a restart and waits for its instant',
          () async {
        final clock = _ManualClock();
        final timer = _ManualTimer(clock);
        queue.keys.add('a');
        queue.headOverride = (key) => DeliveryHeadInBackoff(
              head: DeliveryQueueHead(
                idempotencyKey: key,
                queueSequence: 1,
                attemptCount: 2,
              ),
              nextAttemptAt: DateTime.utc(2026, 1, 1, 12, 5),
            );
        await restart(clock: clock, timer: timer);

        coordinator.start();
        coordinator.onAppResumed();
        coordinator.onQueueChanged();
        await pumpEventQueue();

        expect(transport.sentKeys, isEmpty);
        expect(timer.active.single.dueAt, DateTime.utc(2026, 1, 1, 12, 5));
        expect(timer.maxActive, 1);

        queue.headOverride = null;
        timer.fire();
        await pumpEventQueue();

        expect(transport.sentKeys, <String>['a']);
        expect(queue.removed, <String>['a']);
        expect(timer.active, isEmpty);
      });
    });

    group('backoff progression', () {
      test('follows 5 s x3 up to the 15 min ceiling and never sends early',
          () async {
        final clock = _ManualClock();
        final timer = _ManualTimer(clock);
        await restart(clock: clock, timer: timer);
        queue.keys.add('a');
        const failures = 9;
        transport.statuses.addAll(List<int>.filled(failures, 503));
        queue.headOverride = (key) {
          final records = queue.failureRecords;
          final head = DeliveryQueueHead(
            idempotencyKey: key,
            queueSequence: 1,
            attemptCount: records.length,
          );
          if (records.isNotEmpty && clock.now().isBefore(records.last.$3)) {
            return DeliveryHeadInBackoff(
              head: head,
              nextAttemptAt: records.last.$3,
            );
          }
          return eligibleWithAttempts(key, records.length);
        };

        coordinator.start();
        await pumpEventQueue();
        for (var failure = 1; failure < failures; failure++) {
          expect(queue.failureRecords, hasLength(failure));
          expect(timer.active.single.dueAt, queue.failureRecords.last.$3);

          // Triggers before the due instant do not send.
          coordinator.onQueueChanged();
          coordinator.onAppResumed();
          await pumpEventQueue();
          expect(transport.sentKeys, hasLength(failure));

          timer.fire();
          await pumpEventQueue();
        }
        expect(queue.failureRecords, hasLength(failures));

        final delays = <Duration>[
          for (final (_, calculatedAt, nextAttemptAt) in queue.failureRecords)
            nextAttemptAt.difference(calculatedAt),
        ];
        expect(delays.take(6).toList(), const <Duration>[
          Duration(seconds: 5),
          Duration(seconds: 15),
          Duration(seconds: 45),
          Duration(seconds: 135),
          Duration(seconds: 405),
          Duration(minutes: 15),
        ]);
        expect(delays.skip(5), everyElement(DeliveryBackoffPolicy.maxDelay));
        expect(timer.maxActive, 1);
        expect(queue.pauses, 0);

        // The ceiling is a plateau: the next due instant still delivers.
        timer.fire();
        await pumpEventQueue();
        expect(transport.sentKeys, hasLength(failures + 1));
        expect(queue.removed, <String>['a']);
        expect(timer.active, isEmpty);
      });
    });

    group('no busy loop', () {
      final scenarios = <String, void Function()>{
        'an unavailable queue': () =>
            queue.headOverride = (_) => const DeliveryQueueUnavailable(),
        'an unreadable control': () =>
            queue.control = const DeliveryControlUnavailable(),
        'an explicit pause': () =>
            queue.control = DeliveryControlPaused(DeliveryPauseReason.access),
        'a missing configuration': () =>
            configuration.result = const DeliveryConfigurationMissing(),
        'a stale revision': () => configuration.currentRevision = 2,
        'an unrecorded decision': () =>
            queue.decisionResult = DeliveryMutationResult.storageFailure,
        'a recoverable failure without timer': () =>
            transport.statuses.add(503),
        'a transport local failure': () =>
            transport.results.add(const TransportLocalFailure()),
        'a cancelled attempt': () =>
            transport.results.add(const TransportCancelled()),
        'a local integrity failure': () => queue.headOverride = (key) =>
            DeliveryHeadLocalIntegrityFailure(
              head: DeliveryQueueHead(idempotencyKey: key, queueSequence: 1),
            ),
      };
      for (final entry in scenarios.entries) {
        test('${entry.key} ends after one evaluation and does not spin',
            () async {
          queue.keys.add('a');
          entry.value();

          coordinator.start();
          for (var i = 0; i < 20; i++) {
            await pumpEventQueue();
          }

          expect(queue.nextHeadCalls, 1);
          expect(transport.sentKeys.length, lessThanOrEqualTo(1));
          expect(coordinator.isEvaluating, isFalse);
          expect(queue.keys, <String>['a']);
        });
      }

      test('a failing cleanup and a pending backoff arm one future timer only',
          () async {
        final clock = _ManualClock();
        final timer = _ManualTimer(clock);
        await restart(clock: clock, timer: timer);
        queue.keys.add('a');
        queue.removalFails = true;

        coordinator.start();
        for (var i = 0; i < 20; i++) {
          await pumpEventQueue();
        }

        expect(queue.nextHeadCalls, 1);
        expect(queue.cleanupFailureRecords, hasLength(1));
        expect(timer.armed, hasLength(1));
        expect(timer.active.single.dueAt.isAfter(clock.now()), isTrue);
        expect(transport.sentKeys, <String>['a']);
      });
    });

    group('technical log', () {
      test('carries only fixed categories and never operation data', () async {
        const key = '3f9c2d1e-7a54-4b8e-9c10-aa55bb66cc77';
        queue.keys.add(key);
        transport.results
          ..add(const TransportTimeout())
          ..add(const TransportNetworkFailure());
        transport.statuses.addAll(<int>[503, 418, 400]);
        queue.removalFails = true;

        for (var i = 0; i < 6; i++) {
          coordinator.start();
          await pumpEventQueue();
        }

        expect(logLines, <String>[
          'E4_DELIVERY_RECOVERABLE_FAILURE cause=timeout',
          'E4_DELIVERY_RECOVERABLE_FAILURE cause=network',
          'E4_DELIVERY_RECOVERABLE_FAILURE cause=serverError',
          'E4_DELIVERY_UNEXPECTED_RESPONSE status=418',
          'E4_DELIVERY_DEFINITIVE_REJECTION disposition=invalidContract',
          'E4_DELIVERY_CLEANUP_FAILURE',
          'E4_DELIVERY_CLEANUP_FAILURE',
        ]);
        const forbidden = <String>[
          _secret,
          key,
          'example',
          'http',
          'x-api-key',
          'bearer',
          '-23.5',
          '-46.6',
          '2026',
          'pothole',
          '.jpg',
          '/',
        ];
        for (final line in logLines) {
          for (final word in forbidden) {
            expect(line.toLowerCase(), isNot(contains(word.toLowerCase())));
          }
        }
      });

      test('a failing logger never changes the delivery outcome', () async {
        await coordinator.dispose();
        coordinator = newCoordinator(logger: _ThrowingLogger());
        queue.keys.add('a');
        transport.statuses.add(400);

        coordinator.start();
        await pumpEventQueue();

        expect(queue.decisions, <String>['a:invalidContract']);
        expect(queue.removed, <String>['a']);
      });
    });
  });
}

final class _ThrowingLogger implements DeliveryTechnicalLogger {
  @override
  void cleanupFailure() => throw StateError('log sink failed');

  @override
  void definitiveRejection(DeliveryDisposition disposition) =>
      throw StateError('log sink failed');

  @override
  void recoverableFailure(RecoverableFailureCause cause) =>
      throw StateError('log sink failed');

  @override
  void unexpectedResponse(int statusCode) =>
      throw StateError('log sink failed');
}
