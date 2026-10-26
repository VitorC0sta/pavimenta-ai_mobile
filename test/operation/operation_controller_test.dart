import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/occurrence_acceptance_port.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/cooldown_policy.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/operation/operation_controller.dart';
import 'package:pavimenta_ai_mobile/operation/operation_state.dart';

void main() {
  group('OperationState and readiness', () {
    // **Validates: Requirements 03.6, 03.7, 03.8, 03.9, 05.1, 05.2, 06.3, 21.3**
    test('covers route, lifecycle, camera, GPS, processing, and wake lock',
        () async {
      final harness = _Harness();
      final controller = harness.controller;
      addTearDown(controller.dispose);

      expect(controller.state.canRegister, isFalse);
      expect(controller.state.sessionOccurrenceCount, 0);
      expect(controller.state.isWakeLockEnabled, isFalse);

      harness.makeReady();
      expect(controller.state.canRegister, isTrue);
      expect(controller.state.locationSnapshot?.point.latitude, -23.5505);

      controller.publishWakeLockState(
        generation: controller.generation,
        isEnabled: true,
      );
      expect(controller.state.isWakeLockEnabled, isTrue);

      await controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.paused,
      );
      expect(controller.state.canRegister, isFalse);
      expect(controller.state.lifecycleState, AppLifecycleState.paused);

      await controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.resumed,
        isCurrentRoute: false,
      );
      expect(controller.state.canRegister, isFalse);

      await controller.updateOperationalContext(isCurrentRoute: true);
      expect(controller.state.canRegister, isTrue);
    });

    // **Validates: Requirements 03.5, 03.6, 03.7, 03.9, 06.3, 06.4**
    test('rejects a direct action while the operation button is blocked',
        () async {
      final harness = _Harness();
      addTearDown(harness.controller.dispose);

      final result = await harness.controller.registerManualPothole();

      expect(result, isNull);
      expect((harness.source as _RecordingSource).callCount, 0);
      expect(harness.camera.captureCount, 0);
      expect(harness.controller.state.feedback?.message, contains('GPS'));
      expect(harness.controller.state.sessionOccurrenceCount, 0);
    });
  });

  group('OperationController manual single-flight', () {
    // **Validates: Requirements 03.8, 03.10, 09.11, RNF-03.4, RNF-04.3**
    test('accepts only one operation from concurrent taps', () async {
      final processor = _CompleterProcessor();
      final harness = _Harness(processor: processor);
      harness.makeReady();
      addTearDown(harness.controller.dispose);

      final first = harness.controller.registerManualPothole();
      final second = harness.controller.registerManualPothole();

      expect(await second, isNull);
      await processor.started.future;
      expect(harness.clock.callCount, 1);
      expect((harness.source as _RecordingSource).callCount, 1);
      expect(harness.controller.state.isBusy, isTrue);
      expect(harness.controller.state.canRegister, isFalse);

      final occurrence = _occurrence(
        detectedAt: harness.clock.value,
        image: _FakePreparedImage(),
      );
      processor.complete(CandidateCreated(occurrence));
      final result = await first;

      expect(result, isA<CandidateCreated<InMemoryOccurrence>>());
      expect(harness.controller.state.isBusy, isFalse);
      expect(harness.controller.state.canRegister, isTrue);
      expect(harness.controller.state.sessionOccurrenceCount, 1);
    });

    // **Validates: Requirements 05.3, 05.4, 12.1, 12.2, 12.5, 12.7**
    test(
        'shows persistence progress and confirms success only after acceptance',
        () async {
      final processor = _CompleterProcessor();
      final harness = _Harness(processor: processor);
      harness.makeReady();
      addTearDown(harness.controller.dispose);

      final registration = harness.controller.registerManualPothole();
      await processor.started.future;
      expect(harness.controller.state.isPersisting, isFalse);
      expect(harness.controller.state.sessionOccurrenceCount, 0);
      expect(harness.controller.state.feedback, isNull);

      processor.beginPersistence();
      expect(harness.controller.state.isPersisting, isTrue);
      expect(
        harness.controller.state.processingStatus,
        OperationProcessingStatus.processing,
      );
      expect(harness.controller.state.sessionOccurrenceCount, 0);
      expect(harness.controller.state.feedback, isNull);

      processor.complete(
        CandidateCreated(
          _occurrence(
            detectedAt: harness.clock.value,
            image: _FakePreparedImage(),
          ),
        ),
      );
      await registration;

      expect(harness.controller.state.isPersisting, isFalse);
      expect(harness.controller.state.sessionOccurrenceCount, 1);
      expect(harness.controller.state.feedback?.kind,
          OperationFeedbackKind.success);
      expect(
        harness.controller.state.feedback?.message,
        'Buraco salvo na fila local.',
      );
    });

    // **Validates: Requirements 03.5, 03.13, 08.2, 08.6, 08.7, 08.9**
    test('captures attemptedAt and snapshot before the first await', () async {
      final source = _DelayedSource();
      final processor = _RecordingProcessor(
        const CandidateBlockedByCooldown(
          elapsed: Duration(seconds: 1),
          distanceMeters: 2,
        ),
      );
      final attemptedAt = DateTime.parse('2025-05-06T07:08:09-03:00');
      final harness = _Harness(
        source: source,
        processor: processor,
        clock: _FakeClock(attemptedAt),
      );
      harness.makeReady();
      addTearDown(harness.controller.dispose);

      final pending = harness.controller.registerManualPothole();
      expect(source.seed, isNotNull);
      expect(harness.clock.callCount, 1);
      expect(source.seed!.observedAt, same(attemptedAt));
      expect(source.seed!.location, isA<ImmutableLocationSnapshot>());

      harness.clock.value = DateTime.utc(2030);
      source.complete();
      await pending;

      expect(processor.candidate?.observedAt, same(attemptedAt));
      expect(processor.candidate?.location, same(source.seed!.location));
      expect(harness.clock.callCount, 1);
      expect(
        harness.controller.state.processingStatus,
        OperationProcessingStatus.blockedByCooldown,
      );
    });

    // **Validates: Requirements 05.4, 07.10, 09.11**
    test('increments the session counter only for created occurrences',
        () async {
      final firstImage = _FakePreparedImage();
      final processor =
          _SequenceProcessor(<CandidateResult<InMemoryOccurrence>>[
        CandidateCreated(
          _occurrence(
            detectedAt: DateTime.utc(2025, 1, 1),
            image: firstImage,
          ),
        ),
        const CandidateAlreadyPersistedEquivalent(),
        const CandidateFailed(CandidateFailureStage.durableAcceptance),
      ]);
      final harness = _Harness(processor: processor);
      harness.makeReady();
      addTearDown(harness.controller.dispose);

      await harness.controller.registerManualPothole();
      expect(harness.controller.state.sessionOccurrenceCount, 1);
      expect(harness.controller.state.lastOccurrence?.detectedAt,
          DateTime.utc(2025, 1, 1));

      await harness.controller.registerManualPothole();
      expect(harness.controller.state.sessionOccurrenceCount, 1);
      expect(
        harness.controller.state.feedback?.kind,
        OperationFeedbackKind.information,
      );
      expect(
        harness.controller.state.processingStatus,
        OperationProcessingStatus.idle,
      );

      await harness.controller.registerManualPothole();
      expect(harness.controller.state.sessionOccurrenceCount, 1);
      expect(
        harness.controller.state.processingStatus,
        OperationProcessingStatus.failed,
      );
      expect(
        harness.controller.state.feedback?.message,
        contains('fila local'),
      );
    });
  });

  group('OperationController generation', () {
    // **Validates: Requirements 21.3, 21.4, 21.5, RNF-04.2, RNF-04.3**
    test('stale preparation cannot publish, commit, count, or retain ownership',
        () async {
      final cooldown = _FakeCooldown();
      final preparer = _DelayedImagePreparer();
      final uuid = _FakeUuidGenerator();
      final processor = E1PostCandidateProcessor(
        cooldown: cooldown,
        imagePreparer: preparer,
        uuidGenerator: uuid,
        occurrenceAcceptancePort: const _UnavailableOccurrenceAcceptancePort(),
      );
      final harness = _Harness(processor: processor);
      harness.makeReady();
      addTearDown(harness.controller.dispose);

      final pending = harness.controller.registerManualPothole();
      await preparer.started.future;
      final staleGeneration = harness.controller.generation;

      harness.controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.paused,
      );
      expect(harness.controller.generation, greaterThan(staleGeneration));
      expect(harness.controller.state.isBusy, isFalse);
      expect(
        harness.controller.state.processingStatus,
        OperationProcessingStatus.cancelled,
      );

      preparer.complete();
      final result = await pending;

      expect(result, isNull);
      expect(cooldown.commitCount, 0);
      expect(uuid.callCount, 0);
      expect(preparer.image.isDisposed, isTrue);
      expect(harness.camera.capture.isDisposed, isTrue);
      expect(harness.controller.state.sessionOccurrenceCount, 0);
      expect(harness.controller.state.lastOccurrence, isNull);

      harness.controller.publishCameraState(
        generation: staleGeneration,
        status: OperationCameraStatus.unavailable,
      );
      expect(
        harness.controller.state.cameraStatus,
        OperationCameraStatus.paused,
      );
    });
  });

  group('Operation lifecycle and screen awake', () {
    // **Validates: Requirements 21.1, 21.2, 21.7**
    // Property 11: Wake lock accompanies the active Operation condition.
    test(
        'active state requires visible, foreground, resumed, and current route',
        () {
      for (final visible in [false, true]) {
        for (final foreground in [false, true]) {
          for (final resumed in [false, true]) {
            for (final currentRoute in [false, true]) {
              final state = OperationState.initial().copyWith(
                isVisible: visible,
                isForeground: foreground,
                lifecycleState: resumed
                    ? AppLifecycleState.resumed
                    : AppLifecycleState.paused,
                isCurrentRoute: currentRoute,
              );
              expect(
                state.isOperationallyActive,
                visible && foreground && resumed && currentRoute,
                reason:
                    'visible=$visible foreground=$foreground resumed=$resumed currentRoute=$currentRoute',
              );
            }
          }
        }
      }
    });

    // **Validates: Requirements 03.9, 21.1, 21.2, 21.3, 21.7**
    test('balances wake lock and resources idempotently across lifecycle',
        () async {
      final harness = _Harness();
      addTearDown(() async {
        harness.controller.dispose();
        await harness.controller.lifecycleSettled;
      });

      await harness.controller.startOperationalLifecycle();
      expect(harness.screenAwake.calls, [true]);
      expect(harness.controller.state.isWakeLockEnabled, isTrue);
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);
      expect(harness.controller.state.canRegister, isTrue);

      await harness.controller.startOperationalLifecycle();
      expect(harness.screenAwake.calls, [true]);

      await harness.controller.updateOperationalContext(isVisible: false);
      expect(harness.screenAwake.calls, [true, false]);
      expect(harness.controller.state.isWakeLockEnabled, isFalse);
      expect(harness.controller.state.canRegister, isFalse);
      expect(harness.camera.releaseCount, 1);
      expect(harness.location.releaseCount, 1);

      await harness.controller.updateOperationalContext(isVisible: false);
      expect(harness.screenAwake.calls, [true, false]);
      expect(harness.camera.releaseCount, 1);
      expect(harness.location.releaseCount, 1);

      await harness.controller.updateOperationalContext(isVisible: true);
      expect(harness.screenAwake.calls, [true, false, true]);
      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 2);
    });

    // **Validates: Requirements 00.4, 03.11, 21.2, 21.4, 21.6**
    test('diagnostic suspension blocks actions and settles work before release',
        () async {
      final processor = _CompleterProcessor();
      final harness = _Harness(processor: processor);
      addTearDown(() async {
        harness.controller.dispose();
        await harness.controller.lifecycleSettled;
      });

      await harness.controller.startOperationalLifecycle();
      final registration = harness.controller.registerManualPothole();
      await processor.started.future;
      final previousGeneration = harness.controller.generation;

      final suspension = harness.controller.suspendForDiagnostic();
      await Future<void>.delayed(Duration.zero);

      expect(harness.controller.state.isCurrentRoute, isFalse);
      expect(harness.controller.state.canRegister, isFalse);
      expect(harness.controller.state.isBusy, isFalse);
      expect(
        harness.controller.state.processingStatus,
        OperationProcessingStatus.cancelled,
      );
      expect(harness.controller.generation, greaterThan(previousGeneration));
      expect(harness.screenAwake.calls, [true, false]);
      expect(harness.location.releaseCount, 0);
      expect(harness.camera.releaseCount, 0);

      processor.complete(
        const CandidateBlockedByCooldown(
          elapsed: Duration(seconds: 1),
          distanceMeters: 1,
        ),
      );
      expect(await registration, isNull);
      await suspension;

      expect(harness.location.releaseCount, 1);
      expect(harness.camera.releaseCount, 1);
      expect(harness.controller.state.sessionOccurrenceCount, 0);
      expect(harness.controller.state.lastOccurrence, isNull);
    });

    // **Validates: Requirements 03.9, 21.2, 21.3, RNF-04.3**
    test('blocks registration for every lifecycle state outside resumed',
        () async {
      for (final lifecycle in [
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        final harness = _Harness();
        harness.makeReady();
        await harness.controller.updateOperationalContext(
          lifecycleState: lifecycle,
          isForeground: lifecycle == AppLifecycleState.inactive,
          isVisible: lifecycle == AppLifecycleState.inactive,
        );

        final result = await harness.controller.registerManualPothole();

        expect(result, isNull, reason: lifecycle.name);
        expect(harness.controller.state.canRegister, isFalse,
            reason: lifecycle.name);
        expect((harness.source as _RecordingSource).callCount, 0,
            reason: lifecycle.name);
        expect(harness.camera.captureCount, 0, reason: lifecycle.name);
        harness.controller.dispose();
        await harness.controller.lifecycleSettled;
      }
    });

    // **Validates: Requirements 05.4, 07.10, 11.8, 12.1, 12.2, 12.7, 21.4, 21.5, RNF-01.6, RNF-06.3, RNF-06.9**
    test(
        'navigation, pause, and disposal release resources without disposing a queued JPEG',
        () async {
      final image = _FakePreparedImage();
      final harness = _Harness(
        processor: _RecordingProcessor(
          CandidateCreated(
            _occurrence(detectedAt: DateTime.utc(2025), image: image),
          ),
        ),
      );
      addTearDown(() async {
        harness.controller.dispose();
        await harness.controller.lifecycleSettled;
      });

      await harness.controller.startOperationalLifecycle();
      await harness.controller.registerManualPothole();
      expect(harness.controller.state.lastOccurrence, isNotNull);

      await harness.controller.suspendForDiagnostic();
      expect(harness.controller.state.lastOccurrence, isNull);
      expect(image.isDisposed, isFalse);

      await harness.controller.updateOperationalContext(isCurrentRoute: true);
      final activeGeneration = harness.controller.generation;
      await harness.controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.paused,
        isVisible: false,
        isForeground: false,
      );

      expect(harness.controller.generation, greaterThan(activeGeneration));
      expect(harness.controller.state.canRegister, isFalse);
      expect(harness.controller.state.lastOccurrence, isNull);
      expect(harness.controller.state.isWakeLockEnabled, isFalse);
      expect(harness.location.releaseCount, 2);
      expect(harness.camera.releaseCount, 2);
      expect(image.isDisposed, isFalse);

      harness.controller.dispose();
      await harness.controller.lifecycleSettled;
      expect(image.isDisposed, isFalse);
    });

    // **Validates: Requirements 21.2, 21.3, 21.4, RNF-04.2**
    test('resume waits for prior cleanup before reacquiring resources',
        () async {
      final harness = _Harness();
      final releaseGate = Completer<void>();
      harness.camera.releaseGate = releaseGate;
      addTearDown(() async {
        if (!releaseGate.isCompleted) {
          releaseGate.complete();
        }
        harness.controller.dispose();
        await harness.controller.lifecycleSettled;
      });

      await harness.controller.startOperationalLifecycle();
      final pause = harness.controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.paused,
        isVisible: false,
        isForeground: false,
      );
      await Future<void>.delayed(Duration.zero);
      final resume = harness.controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.resumed,
        isVisible: true,
        isForeground: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(harness.camera.acquireCount, 1);
      expect(harness.controller.state.canRegister, isFalse);

      releaseGate.complete();
      await pause;
      await resume;

      expect(harness.camera.releaseCount, 1);
      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 2);
      expect(harness.controller.state.canRegister, isTrue);
    });

    // **Validates: Requirements 21.1, 21.2, 21.7**
    test('wake-lock enable failure is compensated and remains disabled',
        () async {
      final screenAwake = _FakeScreenAwake(failEnable: true);
      final harness = _Harness(screenAwake: screenAwake);
      addTearDown(() async {
        harness.controller.dispose();
        await harness.controller.lifecycleSettled;
      });

      await harness.controller.startOperationalLifecycle();

      expect(screenAwake.calls, [true, false]);
      expect(harness.controller.state.isWakeLockEnabled, isFalse);
      expect(
          harness.controller.state.feedback?.kind, OperationFeedbackKind.error);
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);

      await harness.controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.paused,
        isVisible: false,
        isForeground: false,
      );
      expect(screenAwake.calls, [true, false]);
    });

    // **Validates: Requirements 21.1, 21.2, 21.7**
    test('wake-lock disable failure stays blocked and is not duplicated',
        () async {
      final screenAwake = _FakeScreenAwake(failDisable: true);
      final harness = _Harness(screenAwake: screenAwake);
      addTearDown(() async {
        harness.controller.dispose();
        await harness.controller.lifecycleSettled;
      });

      await harness.controller.startOperationalLifecycle();
      await harness.controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.paused,
        isVisible: false,
        isForeground: false,
      );
      await harness.controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.paused,
        isVisible: false,
        isForeground: false,
      );

      expect(screenAwake.calls, [true, false]);
      expect(harness.controller.state.isWakeLockEnabled, isFalse);
      expect(
        harness.controller.state.feedback?.kind,
        OperationFeedbackKind.error,
      );
      expect(harness.controller.state.canRegister, isFalse);
    });
  });
}

final class _Harness {
  _Harness({
    OccurrenceCandidateSource? source,
    PostCandidateProcessor<InMemoryOccurrence>? processor,
    _FakeClock? clock,
    _FakeScreenAwake? screenAwake,
  })  : source = source ?? _RecordingSource(),
        processor = processor ??
            _RecordingProcessor(
              const CandidateBlockedByCooldown(
                elapsed: Duration(seconds: 1),
                distanceMeters: 1,
              ),
            ),
        clock = clock ?? _FakeClock(DateTime.utc(2025, 1, 1, 12)),
        screenAwake = screenAwake ?? _FakeScreenAwake() {
    controller = OperationController<String>(
      candidateSource: this.source,
      postCandidateProcessor: this.processor,
      camera: camera,
      location: location,
      screenAwake: this.screenAwake,
      clock: this.clock,
    );
  }

  final _FakeCamera camera = _FakeCamera();
  final _FakeLocation location = _FakeLocation();
  final OccurrenceCandidateSource source;
  final PostCandidateProcessor<InMemoryOccurrence> processor;
  final _FakeClock clock;
  final _FakeScreenAwake screenAwake;
  late final OperationController<String> controller;

  void makeReady() {
    controller.publishCameraState(
      generation: controller.generation,
      status: OperationCameraStatus.ready,
    );
    controller.publishLocationState(
      generation: controller.generation,
      status: OperationLocationStatus.ready,
      snapshot: location.latestValidSnapshot,
    );
  }
}

final class _Point implements GeoPoint {
  const _Point(this.latitude, this.longitude);

  @override
  final double latitude;

  @override
  final double longitude;
}

final class _Snapshot implements LocationSnapshot {
  const _Snapshot();

  @override
  double? get accuracyMeters => 3.5;

  @override
  GeoPoint get point => const _Point(-23.5505, -46.6333);

  @override
  double? get speedMetersPerSecond => 10;
}

final class _FakeLocation implements OperationalLocationPort {
  LocationSnapshot? snapshot = const _Snapshot();
  var acquireCount = 0;
  var releaseCount = 0;

  @override
  LocationSnapshot? get latestValidSnapshot => snapshot;

  @override
  Future<void> acquireForegroundUpdates() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }
}

final class _FakeCamera implements OperationalCameraPort<String> {
  final _FakeCapture capture = _FakeCapture();
  var acquireCount = 0;
  var captureCount = 0;
  var releaseCount = 0;
  Completer<void>? releaseGate;

  @override
  String? get previewHandle => 'rear-preview';

  @override
  Future<void> acquirePreview() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
    await releaseGate?.future;
    releaseGate = null;
  }

  @override
  Future<TemporaryCapture> takePicture() async {
    captureCount++;
    return capture;
  }
}

final class _FakeScreenAwake implements ScreenAwakePort {
  _FakeScreenAwake({this.failEnable = false, this.failDisable = false});

  final bool failEnable;
  final bool failDisable;
  final List<bool> calls = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async {
    calls.add(enabled);
    if (enabled && failEnable) {
      throw StateError('enable failed');
    }
    if (!enabled && failDisable) {
      throw StateError('disable failed');
    }
  }
}

final class _FakeClock implements Clock {
  _FakeClock(this.value);

  DateTime value;
  int callCount = 0;

  @override
  DateTime now() {
    callCount++;
    return value;
  }
}

class _RecordingSource implements OccurrenceCandidateSource {
  int callCount = 0;

  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) async {
    callCount++;
    return CandidateInput(
      observedAt: seed.observedAt,
      location: seed.location,
      defectClass: 'pothole',
      confidence: 1,
      acquireImage: seed.acquireImage,
    );
  }
}

final class _DelayedSource extends _RecordingSource {
  final Completer<CandidateInput> _completer = Completer<CandidateInput>();
  CandidateSeed? seed;

  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) {
    callCount++;
    this.seed = seed;
    return _completer.future;
  }

  void complete() {
    final currentSeed = seed!;
    _completer.complete(
      CandidateInput(
        observedAt: currentSeed.observedAt,
        location: currentSeed.location,
        defectClass: 'pothole',
        confidence: 1,
        acquireImage: currentSeed.acquireImage,
      ),
    );
  }
}

class _RecordingProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  _RecordingProcessor(this.result);

  final CandidateResult<InMemoryOccurrence> result;
  CandidateInput? candidate;

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) async {
    this.candidate = candidate;
    return result;
  }
}

final class _CompleterProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  final Completer<void> started = Completer<void>();
  final Completer<CandidateResult<InMemoryOccurrence>> _result =
      Completer<CandidateResult<InMemoryOccurrence>>();
  CandidateInput? _candidate;

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) {
    _candidate = candidate;
    started.complete();
    return _result.future;
  }

  void beginPersistence() => _candidate!.notifyPersistenceStarted();

  void complete(CandidateResult<InMemoryOccurrence> result) {
    _result.complete(result);
  }
}

final class _SequenceProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  _SequenceProcessor(this.results);

  final List<CandidateResult<InMemoryOccurrence>> results;
  var index = 0;

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) async {
    return results[index++];
  }
}

final class _FakeCooldown implements CandidateCooldown {
  int commitCount = 0;

  @override
  CooldownDecision evaluate(DateTime attemptedAt, GeoPoint point) {
    return const CooldownDecision.firstOccurrence();
  }

  @override
  void commit(InMemoryOccurrence occurrence) {
    commitCount++;
  }
}

final class _DelayedImagePreparer implements ImagePreparer {
  final Completer<void> started = Completer<void>();
  final Completer<OwnedPreparedImage> _result = Completer<OwnedPreparedImage>();
  final _FakePreparedImage image = _FakePreparedImage();

  @override
  Future<OwnedPreparedImage> prepare(TemporaryCapture capture) {
    started.complete();
    return _result.future;
  }

  void complete() => _result.complete(image);
}

final class _FakeUuidGenerator implements UuidGenerator {
  int callCount = 0;

  @override
  String newV4() {
    callCount++;
    return _validUuid;
  }
}

final class _FakeCapture implements TemporaryCapture {
  bool isDisposed = false;

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}

final class _FakePreparedImage implements OwnedPreparedImage {
  bool isDisposed = false;

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}

InMemoryOccurrence _occurrence({
  required DateTime detectedAt,
  required OwnedPreparedImage image,
}) {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: _validUuid,
    detectedAt: detectedAt,
    location: const _Snapshot(),
    image: image,
  );
}

const String _validUuid = '123e4567-e89b-42d3-a456-426614174000';

final class _UnavailableOccurrenceAcceptancePort
    implements OccurrenceAcceptancePort {
  const _UnavailableOccurrenceAcceptancePort();

  @override
  Future<OccurrenceAcceptanceResult> accept(
    InMemoryOccurrence occurrence,
  ) async =>
      const OccurrenceStorageUnavailable();
}
