import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/occurrence_acceptance_port.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/cooldown_policy.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';

void main() {
  group('E1PostCandidateProcessor', () {
    // **Validates: Requirements 03.13, 07.5, 07.7, 07.12, 07.13, 08.2, 08.6, 08.7, 08.9, 11.1**
    test('executes the complete normative order exactly once', () async {
      final harness = _Harness();
      final observedAt = DateTime.parse('2025-02-03T04:05:06-03:00');

      final result = await harness.processor.process(
        harness.candidate(observedAt: observedAt),
      );

      expect(result, isA<CandidateCreated<InMemoryOccurrence>>());
      final occurrence =
          (result as CandidateCreated<InMemoryOccurrence>).occurrence;
      expect(occurrence.detectedAt, same(observedAt));
      expect(occurrence.idempotencyKey, _validUuid);
      expect(occurrence.latitude, -23.5505);
      expect(occurrence.longitude, -46.6333);
      expect(occurrence.confidence, 1.0);
      expect(occurrence.defectClass, 'pothole');
      expect(occurrence.image, same(harness.preparedImage));
      expect(harness.acquisitionCount, 1);
      expect(harness.cooldown.commitCount, 1);
      expect(harness.occurrenceAcceptancePort.callCount, 1);
      expect(harness.occurrenceAcceptancePort.queueOwnsAcceptedImage, isTrue);
      expect(
        harness.occurrenceAcceptancePort.acceptedOccurrence?.image,
        same(harness.preparedImage),
      );
      expect(
        harness.processor.occurrenceAcceptancePort,
        same(harness.occurrenceAcceptancePort),
      );
      expect(harness.preparedImage.isDisposed, isFalse);
      expect(
        harness.events,
        <String>[
          'cooldown.evaluate',
          'image.acquire',
          'image.prepare',
          'capture.dispose',
          'uuid.generate',
          'occurrence.create',
          'occurrence.accept',
          'cooldown.commit',
        ],
      );

      await occurrence.image.dispose();
    });

    // **Validates: Requirements RF-05.4–5, RF-12.1–2, RF-12.7,
    // RF-12.10–11, RNF-05.1–3, RNF-06.3, RNF-06.9–10**
    test('acceptance equivalence and failures never publish a partial success',
        () async {
      final equivalent = _Harness(
        acceptanceResult:
            const OccurrenceAlreadyPersistedEquivalent(_readySnapshot),
      );

      final equivalentResult =
          await equivalent.processor.process(equivalent.candidate());

      expect(
        equivalentResult,
        isA<CandidateAlreadyPersistedEquivalent<InMemoryOccurrence>>(),
      );
      expect(equivalent.cooldown.commitCount, 0);
      expect(equivalent.preparedImage.isDisposed, isTrue);
      expect(
          equivalent.occurrenceAcceptancePort.queueOwnsAcceptedImage, isFalse);
      expect(
        equivalent.events,
        containsAllInOrder(<String>[
          'occurrence.create',
          'occurrence.accept',
          'prepared.dispose',
        ]),
      );

      final failures = <OccurrenceAcceptanceResult>[
        const OccurrenceIdentityConflict(),
        const OccurrenceStorageUnavailable(),
        const OccurrenceInvalidData(),
        const OccurrenceImageFailure(),
        const OccurrenceTransactionalFailure(),
      ];
      for (final failure in failures) {
        final harness = _Harness(acceptanceResult: failure);

        final result = await harness.processor.process(harness.candidate());

        expect(
          result,
          isA<CandidateFailed<InMemoryOccurrence>>().having(
            (value) => value.stage,
            'stage for ${failure.runtimeType}',
            CandidateFailureStage.durableAcceptance,
          ),
        );
        expect(harness.cooldown.commitCount, 0);
        expect(harness.preparedImage.isDisposed, isTrue);
        expect(
            harness.occurrenceAcceptancePort.queueOwnsAcceptedImage, isFalse);
      }
    });

    // **Validates: Requirements RF-21.4, RF-12.1**
    test(
        'cancels and cleans artifacts when lifecycle changes before durability',
        () async {
      final harness = _Harness();
      var isCurrent = true;
      final candidate = harness.candidate(
        processingGuard: () => isCurrent,
        acquireImage: () async {
          harness.events.add('image.acquire');
          isCurrent = false;
          return harness.capture;
        },
      );

      final result = await harness.processor.process(candidate);

      expect(result, isA<CandidateCancelled<InMemoryOccurrence>>());
      expect(harness.capture.isDisposed, isTrue);
      expect(harness.preparedImage.isDisposed, isFalse);
      expect(harness.occurrenceAcceptancePort.callCount, 0);
      expect(harness.cooldown.commitCount, 0);
    });

    // **Validates: Requirements RF-21.4, RF-21.5, RF-12.1, RF-12.7**
    test('finishes the durable section after lifecycle changes without cleanup',
        () async {
      final harness = _Harness(deferAcceptance: true);
      var isCurrent = true;

      final processing = harness.processor.process(
        harness.candidate(processingGuard: () => isCurrent),
      );
      await harness.occurrenceAcceptancePort.started.future;
      isCurrent = false;
      harness.occurrenceAcceptancePort.complete();

      final result = await processing;

      expect(result, isA<CandidateCreated<InMemoryOccurrence>>());
      expect(harness.occurrenceAcceptancePort.callCount, 1);
      expect(harness.cooldown.commitCount, 1);
      expect(harness.preparedImage.isDisposed, isFalse);
      expect(
        harness.events,
        containsAllInOrder(<String>[
          'occurrence.accept',
          'cooldown.commit',
        ]),
      );

      await harness.preparedImage.dispose();
    });

    // **Validates: Requirements 03.14, 03.15, 09.7, 09.9, 09.10, 09.11**
    test('cooldown blocking has no acquisition, UUID, commit, or artifact',
        () async {
      final harness = _Harness(
        cooldownDecision: const CooldownDecision.blocked(
          elapsed: Duration(seconds: 2),
          distanceMeters: 4,
        ),
      );

      final result = await harness.processor.process(harness.candidate());

      expect(result, isA<CandidateBlockedByCooldown<InMemoryOccurrence>>());
      final blocked = result as CandidateBlockedByCooldown<InMemoryOccurrence>;
      expect(blocked.elapsed, const Duration(seconds: 2));
      expect(blocked.distanceMeters, 4);
      expect(harness.acquisitionCount, 0);
      expect(harness.uuidGenerator.callCount, 0);
      expect(harness.occurrenceCreator.callCount, 0);
      expect(harness.cooldown.commitCount, 0);
      expect(harness.events, <String>['cooldown.evaluate']);
    });

    // **Validates: Requirements 07.5, 07.6, 11.5**
    test('validates candidate and freezes a valid snapshot before cooldown',
        () async {
      final invalidCandidateHarness = _Harness();
      final invalidCandidate = invalidCandidateHarness.candidate(
        defectClass: 'crack',
      );

      final invalidCandidateResult =
          await invalidCandidateHarness.processor.process(invalidCandidate);

      expect(
        invalidCandidateResult,
        isA<CandidatePreconditionFailed<InMemoryOccurrence>>().having(
          (result) => result.reason,
          'reason',
          CandidatePrecondition.invalidCandidate,
        ),
      );
      expect(invalidCandidateHarness.events, isEmpty);

      final invalidLocationHarness = _Harness();
      final invalidLocation = invalidLocationHarness.candidate(
        location: _RawLocation(latitude: 91, longitude: 0),
      );

      final invalidLocationResult =
          await invalidLocationHarness.processor.process(invalidLocation);

      expect(
        invalidLocationResult,
        isA<CandidatePreconditionFailed<InMemoryOccurrence>>().having(
          (result) => result.reason,
          'reason',
          CandidatePrecondition.invalidLocation,
        ),
      );
      expect(invalidLocationHarness.events, isEmpty);
    });

    // **Validates: Requirements 09.10, 10.14, 11.5, 11.7, RNF-06.7, RNF-06.8**
    test('cleans owned artifacts and never commits at every failure point',
        () async {
      final cases = <_FailureCase>[
        const _FailureCase(
          point: _FailurePoint.acquisition,
          expectedStage: CandidateFailureStage.imageAcquisition,
          captureDisposed: false,
          preparedDisposed: false,
        ),
        const _FailureCase(
          point: _FailurePoint.preparation,
          expectedStage: CandidateFailureStage.imagePreparation,
          captureDisposed: true,
          preparedDisposed: false,
        ),
        const _FailureCase(
          point: _FailurePoint.identity,
          expectedStage: CandidateFailureStage.identityGeneration,
          captureDisposed: true,
          preparedDisposed: true,
        ),
        const _FailureCase(
          point: _FailurePoint.occurrence,
          expectedStage: CandidateFailureStage.occurrenceCreation,
          captureDisposed: true,
          preparedDisposed: true,
        ),
      ];

      for (final testCase in cases) {
        final harness = _Harness(failurePoint: testCase.point);

        final result = await harness.processor.process(harness.candidate());

        expect(
          result,
          isA<CandidateFailed<InMemoryOccurrence>>().having(
            (failure) => failure.stage,
            'stage for ${testCase.point.name}',
            testCase.expectedStage,
          ),
        );
        expect(
          harness.capture.isDisposed,
          testCase.captureDisposed,
          reason: testCase.point.name,
        );
        expect(
          harness.preparedImage.isDisposed,
          testCase.preparedDisposed,
          reason: testCase.point.name,
        );
        expect(harness.cooldown.commitCount, 0, reason: testCase.point.name);
      }
    });

    // **Validates: Requirements 07.5, 07.11, RNF-01.4, RNF-01.5, RNF-01.6, RNF-01.9, RNF-01.10, RNF-01.11**
    test('processes normalized candidates without knowing their source',
        () async {
      final harness = _Harness();
      final candidates = <CandidateInput>[
        harness.candidate(observedAt: DateTime.utc(2025, 1, 1)),
        harness.candidate(observedAt: DateTime.utc(2025, 1, 2)),
      ];

      for (final candidate in candidates) {
        final result = await harness.processor.process(candidate);
        expect(result, isA<CandidateCreated<InMemoryOccurrence>>());
      }

      expect(harness.acquisitionCount, 2);
      expect(harness.cooldown.commitCount, 2);
      expect(harness.occurrenceCreator.callCount, 2);
    });

    test('imports no manual source, Flutter widget, persistence, or network',
        () async {
      final source = await File(
        'lib/application/post_candidate_processor.dart',
      ).readAsString();
      final imports = RegExp("^import '([^']+)';", multiLine: true)
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toList();

      expect(imports,
          isNot(contains('../candidate/manual_candidate_source.dart')));
      expect(imports, isNot(contains('package:flutter/material.dart')));
      expect(source, isNot(contains('HttpClient')));
      expect(source, isNot(contains('Repository')));
      expect(source, isNot(contains('Navigator')));
    });
  });
}

const String _validUuid = '123e4567-e89b-42d3-a456-426614174000';
const QueueSnapshot _readySnapshot = QueueSnapshot(
  health: QueueHealth.ready,
  pendingCount: 1,
);

enum _FailurePoint { none, acquisition, preparation, identity, occurrence }

final class _FailureCase {
  const _FailureCase({
    required this.point,
    required this.expectedStage,
    required this.captureDisposed,
    required this.preparedDisposed,
  });

  final _FailurePoint point;
  final CandidateFailureStage expectedStage;
  final bool captureDisposed;
  final bool preparedDisposed;
}

final class _Harness {
  _Harness({
    this.failurePoint = _FailurePoint.none,
    this.deferAcceptance = false,
    this.acceptanceResult = const OccurrencePersisted(_readySnapshot),
    CooldownDecision cooldownDecision =
        const CooldownDecision.firstOccurrence(),
  })  : events = <String>[],
        _cooldownDecision = cooldownDecision {
    capture = _FakeCapture(events);
    preparedImage = _FakePreparedImage(events);
    cooldown = _FakeCooldown(events, _cooldownDecision);
    imagePreparer = _FakeImagePreparer(
      events,
      preparedImage,
      shouldFail: failurePoint == _FailurePoint.preparation,
    );
    uuidGenerator = _FakeUuidGenerator(
      events,
      shouldFail: failurePoint == _FailurePoint.identity,
    );
    occurrenceCreator = _FakeOccurrenceCreator(
      events,
      shouldFail: failurePoint == _FailurePoint.occurrence,
    );
    occurrenceAcceptancePort = _FakeOccurrenceAcceptancePort(
      events,
      deferResult: deferAcceptance,
      result: acceptanceResult,
    );
    processor = E1PostCandidateProcessor(
      cooldown: cooldown,
      imagePreparer: imagePreparer,
      uuidGenerator: uuidGenerator,
      occurrenceAcceptancePort: occurrenceAcceptancePort,
      occurrenceCreator: occurrenceCreator,
    );
  }

  final _FailurePoint failurePoint;
  final bool deferAcceptance;
  final OccurrenceAcceptanceResult acceptanceResult;
  final CooldownDecision _cooldownDecision;
  final List<String> events;
  late final _FakeCapture capture;
  late final _FakePreparedImage preparedImage;
  late final _FakeCooldown cooldown;
  late final _FakeImagePreparer imagePreparer;
  late final _FakeUuidGenerator uuidGenerator;
  late final _FakeOccurrenceCreator occurrenceCreator;
  late final _FakeOccurrenceAcceptancePort occurrenceAcceptancePort;
  late final E1PostCandidateProcessor processor;
  int acquisitionCount = 0;

  CandidateInput candidate({
    DateTime? observedAt,
    LocationSnapshot? location,
    String defectClass = 'pothole',
    double confidence = 1,
    bool Function()? processingGuard,
    Future<TemporaryCapture> Function()? acquireImage,
  }) {
    return CandidateInput(
      observedAt: observedAt ?? DateTime.utc(2025, 1, 1, 12),
      location:
          location ?? _RawLocation(latitude: -23.5505, longitude: -46.6333),
      defectClass: defectClass,
      confidence: confidence,
      acquireImage: acquireImage ??
          () async {
            events.add('image.acquire');
            acquisitionCount++;
            if (failurePoint == _FailurePoint.acquisition) {
              throw StateError('capture failed');
            }
            return capture;
          },
      processingGuard: processingGuard,
    );
  }
}

final class _RawPoint implements GeoPoint {
  const _RawPoint(this.latitude, this.longitude);

  @override
  final double latitude;

  @override
  final double longitude;
}

final class _RawLocation implements LocationSnapshot {
  _RawLocation({required double latitude, required double longitude})
      : point = _RawPoint(latitude, longitude);

  @override
  final GeoPoint point;

  @override
  double? get accuracyMeters => 3;

  @override
  double? get speedMetersPerSecond => 10;
}

final class _FakeCapture implements TemporaryCapture {
  _FakeCapture(this.events);

  final List<String> events;
  bool isDisposed = false;

  @override
  Future<void> dispose() async {
    if (isDisposed) {
      return;
    }
    isDisposed = true;
    events.add('capture.dispose');
  }
}

final class _FakePreparedImage implements OwnedPreparedImage {
  _FakePreparedImage(this.events);

  final List<String> events;
  bool isDisposed = false;

  @override
  Future<void> dispose() async {
    if (isDisposed) {
      return;
    }
    isDisposed = true;
    events.add('prepared.dispose');
  }
}

final class _FakeCooldown implements CandidateCooldown {
  _FakeCooldown(this.events, this.decision);

  final List<String> events;
  final CooldownDecision decision;
  int commitCount = 0;

  @override
  CooldownDecision evaluate(DateTime attemptedAt, GeoPoint point) {
    events.add('cooldown.evaluate');
    return decision;
  }

  @override
  void commit(InMemoryOccurrence occurrence) {
    events.add('cooldown.commit');
    commitCount++;
  }
}

final class _FakeImagePreparer implements ImagePreparer {
  _FakeImagePreparer(
    this.events,
    this.preparedImage, {
    required this.shouldFail,
  });

  final List<String> events;
  final OwnedPreparedImage preparedImage;
  final bool shouldFail;

  @override
  Future<OwnedPreparedImage> prepare(TemporaryCapture capture) async {
    events.add('image.prepare');
    if (shouldFail) {
      throw StateError('preparation failed');
    }
    return preparedImage;
  }
}

final class _FakeUuidGenerator implements UuidGenerator {
  _FakeUuidGenerator(this.events, {required this.shouldFail});

  final List<String> events;
  final bool shouldFail;
  int callCount = 0;

  @override
  String newV4() {
    events.add('uuid.generate');
    callCount++;
    if (shouldFail) {
      throw StateError('UUID failed');
    }
    return _validUuid;
  }
}

final class _FakeOccurrenceCreator implements InMemoryOccurrenceCreator {
  _FakeOccurrenceCreator(this.events, {required this.shouldFail});

  final List<String> events;
  final bool shouldFail;
  int callCount = 0;

  @override
  InMemoryOccurrence create({
    required String idempotencyKey,
    required DateTime detectedAt,
    required LocationSnapshot location,
    required String defectClass,
    required double confidence,
    required OwnedPreparedImage image,
  }) {
    events.add('occurrence.create');
    callCount++;
    if (shouldFail) {
      throw StateError('occurrence failed');
    }
    return const InMemoryOccurrenceFactory().create(
      idempotencyKey: idempotencyKey,
      detectedAt: detectedAt,
      location: location,
      defectClass: defectClass,
      confidence: confidence,
      image: image,
    );
  }
}

final class _FakeOccurrenceAcceptancePort implements OccurrenceAcceptancePort {
  _FakeOccurrenceAcceptancePort(
    this.events, {
    required this.deferResult,
    required this.result,
  });

  final List<String> events;
  final bool deferResult;
  final OccurrenceAcceptanceResult result;
  final Completer<void> started = Completer<void>();
  final Completer<OccurrenceAcceptanceResult> _completion =
      Completer<OccurrenceAcceptanceResult>();
  int callCount = 0;
  InMemoryOccurrence? acceptedOccurrence;
  bool queueOwnsAcceptedImage = false;

  @override
  Future<OccurrenceAcceptanceResult> accept(
    InMemoryOccurrence occurrence,
  ) {
    callCount++;
    acceptedOccurrence = occurrence;
    events.add('occurrence.accept');
    if (!started.isCompleted) {
      started.complete();
    }
    if (result is OccurrencePersisted) {
      queueOwnsAcceptedImage = true;
    }
    return deferResult
        ? _completion.future
        : Future<OccurrenceAcceptanceResult>.value(result);
  }

  void complete() {
    if (!_completion.isCompleted) {
      queueOwnsAcceptedImage = true;
      _completion.complete(const OccurrencePersisted(_readySnapshot));
    }
  }
}
