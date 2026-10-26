import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/distance_calculator.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/main.dart';

void main() {
  group('E1 candidate contracts', () {
    test('preserve observation data and defer image acquisition', () async {
      final observedAt = DateTime.parse('2025-01-02T03:04:05-03:00');
      final location = _LocationSnapshot();
      final capture = _TemporaryCapture();
      var acquisitionCount = 0;
      Future<TemporaryCapture> acquireImage() async {
        acquisitionCount++;
        return capture;
      }

      final source = _CandidateSource();
      final candidate = await source.requestCandidate(
        CandidateSeed(
          observedAt: observedAt,
          location: location,
          acquireImage: acquireImage,
        ),
      );

      expect(candidate.observedAt, same(observedAt));
      expect(candidate.location, same(location));
      expect(candidate.defectClass, 'pothole');
      expect(candidate.confidence, 1.0);
      expect(acquisitionCount, 0);
      expect(await candidate.acquireImage(), same(capture));
      expect(acquisitionCount, 1);
    });

    test('exposes every source-independent processor result category', () {
      final results = <CandidateResult<String>>[
        const CandidateCreated('occurrence'),
        const CandidateBlockedByCooldown(
          elapsed: Duration(seconds: 2),
          distanceMeters: 4,
        ),
        const CandidatePreconditionFailed(
          CandidatePrecondition.invalidLocation,
        ),
        const CandidateCancelled(CandidateCancellation.lifecycleChanged),
        const CandidateFailed(CandidateFailureStage.imagePreparation),
      ];

      expect(results[0], isA<CandidateCreated<String>>());
      expect(results[1], isA<CandidateBlockedByCooldown<String>>());
      expect(results[2], isA<CandidatePreconditionFailed<String>>());
      expect(results[3], isA<CandidateCancelled<String>>());
      expect(results[4], isA<CandidateFailed<String>>());
    });
  });

  test('composition root retains each explicitly supplied dependency', () {
    final source = _CandidateSource();
    final processor = _Processor();
    final camera = _Camera();
    final location = _Location();
    final imagePreparer = _ImagePreparer();
    final clock = _Clock();
    final uuidGenerator = _UuidGenerator();
    final distanceCalculator = _DistanceCalculator();
    final screenAwake = _ScreenAwake();

    final composition = composeE1<String, String>(
      candidateSource: source,
      postCandidateProcessor: processor,
      camera: camera,
      location: location,
      imagePreparer: imagePreparer,
      clock: clock,
      uuidGenerator: uuidGenerator,
      distanceCalculator: distanceCalculator,
      screenAwake: screenAwake,
    );

    expect(composition.candidateSource, same(source));
    expect(composition.postCandidateProcessor, same(processor));
    expect(composition.camera, same(camera));
    expect(composition.location, same(location));
    expect(composition.imagePreparer, same(imagePreparer));
    expect(composition.clock, same(clock));
    expect(composition.uuidGenerator, same(uuidGenerator));
    expect(composition.distanceCalculator, same(distanceCalculator));
    expect(composition.screenAwake, same(screenAwake));
  });
}

final class _GeoPoint implements GeoPoint {
  @override
  double get latitude => 0;

  @override
  double get longitude => 0;
}

final class _LocationSnapshot implements LocationSnapshot {
  final GeoPoint _point = _GeoPoint();

  @override
  double? get accuracyMeters => null;

  @override
  GeoPoint get point => _point;

  @override
  double? get speedMetersPerSecond => null;
}

final class _TemporaryCapture implements TemporaryCapture {
  @override
  Future<void> dispose() async {}
}

final class _OwnedPreparedImage implements OwnedPreparedImage {
  @override
  Future<void> dispose() async {}
}

final class _CandidateSource implements OccurrenceCandidateSource {
  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) async {
    return CandidateInput(
      observedAt: seed.observedAt,
      location: seed.location,
      defectClass: 'pothole',
      confidence: 1,
      acquireImage: seed.acquireImage,
    );
  }
}

final class _Processor implements PostCandidateProcessor<String> {
  @override
  Future<CandidateResult<String>> process(CandidateInput candidate) async {
    return const CandidateCreated('occurrence');
  }
}

final class _Camera implements OperationalCameraPort<String> {
  @override
  String? get previewHandle => null;

  @override
  Future<void> acquirePreview() async {}

  @override
  Future<void> release() async {}

  @override
  Future<TemporaryCapture> takePicture() async => _TemporaryCapture();
}

final class _Location implements OperationalLocationPort {
  @override
  LocationSnapshot? get latestValidSnapshot => null;

  @override
  Future<void> acquireForegroundUpdates() async {}

  @override
  Future<void> release() async {}
}

final class _ImagePreparer implements ImagePreparer {
  @override
  Future<OwnedPreparedImage> prepare(TemporaryCapture capture) async {
    return _OwnedPreparedImage();
  }
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2025);
}

final class _UuidGenerator implements UuidGenerator {
  @override
  String newV4() => '00000000-0000-4000-8000-000000000000';
}

final class _DistanceCalculator implements DistanceCalculator {
  @override
  double metersBetween(GeoPoint from, GeoPoint to) => 0;
}

final class _ScreenAwake implements ScreenAwakePort {
  @override
  Future<void> setEnabled(bool enabled) async {}
}
