import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/candidate/manual_candidate_source.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';

void main() {
  group('ManualCandidateSource', () {
    // **Validates: Requirements 03.4, 07.1, 07.2, 07.3, 07.12, 08.2**
    test('emits a normalized manual candidate preserving time and location',
        () async {
      final attemptedAt = DateTime.parse('2025-04-12T14:30:15-03:00');
      final location = _FakeLocationSnapshot();
      final camera = _FakeCameraCapture();
      const source = ManualCandidateSource();

      final candidate = await source.requestCandidate(
        CandidateSeed(
          observedAt: attemptedAt,
          location: location,
          acquireImage: camera.takePicture,
        ),
      );

      expect(candidate.observedAt, same(attemptedAt));
      expect(candidate.location, same(location));
      expect(candidate.defectClass, equals('pothole'));
      expect(candidate.confidence, equals(1.0));
    });

    // **Validates: Requirements 03.5, 07.13, 08.6, 08.9**
    test('leaves image acquisition deferred until the candidate invokes it',
        () async {
      final camera = _FakeCameraCapture();
      final capture = _FakeTemporaryCapture();
      camera.nextCapture = capture;
      const source = ManualCandidateSource();

      final candidate = await source.requestCandidate(
        CandidateSeed(
          observedAt: DateTime.utc(2025, 4, 12),
          location: _FakeLocationSnapshot(),
          acquireImage: camera.takePicture,
        ),
      );

      expect(camera.captureCount, 0);

      final acquiredCapture = await candidate.acquireImage();

      expect(acquiredCapture, same(capture));
      expect(camera.captureCount, 1);
    });

    // **Validates: Requirements 07.4, 07.11, RNF-01.2, RNF-01.9, RNF-01.11**
    test('has no source identity, API, persistence, or processing dependency',
        () async {
      const source = ManualCandidateSource();
      final candidate = await source.requestCandidate(
        CandidateSeed(
          observedAt: DateTime.utc(2025, 4, 12),
          location: _FakeLocationSnapshot(),
          acquireImage: _FakeCameraCapture().takePicture,
        ),
      );
      final dynamic normalizedCandidate = candidate;

      expect(() => normalizedCandidate.source, throwsNoSuchMethodError);

      final implementation = File(
        'lib/candidate/manual_candidate_source.dart',
      ).readAsStringSync();
      final imports = RegExp(
        "^import\\s+['\"]([^'\"]+)['\"];",
        multiLine: true,
      ).allMatches(implementation).map((match) => match.group(1)).toList();

      expect(imports, <String>['occurrence_candidate_source.dart']);
      for (final forbiddenResponsibility in <String>[
        'CooldownPolicy',
        'UuidGenerator',
        'InMemoryOccurrenceFactory',
        'ImagePreparer',
        'HttpClient',
        'Repository',
      ]) {
        expect(
          implementation,
          isNot(contains(forbiddenResponsibility)),
          reason: 'Manual source must not own $forbiddenResponsibility',
        );
      }
    });
  });
}

final class _FakeGeoPoint implements GeoPoint {
  @override
  double get latitude => -23.5505;

  @override
  double get longitude => -46.6333;
}

final class _FakeLocationSnapshot implements LocationSnapshot {
  final GeoPoint _point = _FakeGeoPoint();

  @override
  double? get accuracyMeters => 4.5;

  @override
  GeoPoint get point => _point;

  @override
  double? get speedMetersPerSecond => 8;
}

final class _FakeCameraCapture {
  var captureCount = 0;
  TemporaryCapture nextCapture = _FakeTemporaryCapture();

  Future<TemporaryCapture> takePicture() async {
    captureCount++;
    return nextCapture;
  }
}

final class _FakeTemporaryCapture implements TemporaryCapture {
  @override
  Future<void> dispose() async {}
}
