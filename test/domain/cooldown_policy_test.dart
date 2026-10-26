import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/cooldown_policy.dart';
import 'package:pavimenta_ai_mobile/domain/distance_calculator.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';

void main() {
  group('HaversineDistanceCalculator', () {
    const calculator = HaversineDistanceCalculator();

    test('returns zero for the same point', () {
      final point = _point(-23.5505, -46.6333);

      expect(calculator.metersBetween(point, point), 0);
    });

    test('calculates a known one-degree equatorial distance', () {
      final distance = calculator.metersBetween(
        _point(0, 0),
        _point(0, 1),
      );

      expect(distance, closeTo(111194.9266, 0.001));
    });

    test('is symmetric across representative valid coordinates', () {
      final points = <ImmutableGeoPoint>[
        _point(-90, -180),
        _point(-23.5505, -46.6333),
        _point(0, 0),
        _point(51.5074, -0.1278),
        _point(90, 180),
      ];

      for (final from in points) {
        for (final to in points) {
          expect(
            calculator.metersBetween(from, to),
            closeTo(calculator.metersBetween(to, from), 1e-8),
          );
        }
      }
    });

    test('rejects invalid coordinates supplied through the interface', () {
      expect(
        () => calculator.metersBetween(_MutablePoint(91, 0), _point(0, 0)),
        throwsRangeError,
      );
      expect(
        () => calculator.metersBetween(
          _point(0, 0),
          _MutablePoint(0, double.nan),
        ),
        throwsRangeError,
      );
    });
  });

  group('CooldownPolicy', () {
    final origin = _point(-23.5505, -46.6333);
    final initialTime = DateTime.utc(2025, 1, 1, 12);

    test('uses the approved five-second and fifteen-meter defaults', () {
      final policy = CooldownPolicy();

      expect(policy.minimumElapsed, const Duration(seconds: 5));
      expect(policy.minimumDistanceMeters, 15);
    });

    // **Validates: Requirements 09.1**
    test('allows the first occurrence without a committed reference', () {
      final policy = CooldownPolicy();

      final decision = policy.evaluate(initialTime, origin);

      expect(decision.isAllowed, isTrue);
      expect(decision.isFirstOccurrence, isTrue);
      expect(decision.elapsed, isNull);
      expect(decision.distanceMeters, isNull);
    });

    // **Validates: Requirements 09.2, 09.3, 09.4, 09.5, 09.6, 09.8**
    test('allows time or distance at their inclusive boundaries', () {
      final distance = _FakeDistanceCalculator();
      final policy = CooldownPolicy(distanceCalculator: distance);
      policy.commit(_occurrence(initialTime, origin));

      distance.value = 14.999;
      expect(
        policy
            .evaluate(initialTime.add(const Duration(seconds: 5)), origin)
            .isAllowed,
        isTrue,
      );

      distance.value = 15;
      expect(
        policy
            .evaluate(
              initialTime.add(const Duration(milliseconds: 4999)),
              origin,
            )
            .isAllowed,
        isTrue,
      );
    });

    // **Validates: Requirements 09.2, 09.3, 09.4, 09.8**
    test('obeys time OR distance for representative input pairs', () {
      final distance = _FakeDistanceCalculator();
      final policy = CooldownPolicy(distanceCalculator: distance);
      policy.commit(_occurrence(initialTime, origin));

      for (final elapsedMilliseconds in <int>[0, 1, 4999, 5000, 5001, 10000]) {
        for (final meters in <double>[0, 0.1, 14.999, 15, 15.001, 100]) {
          distance.value = meters;
          final decision = policy.evaluate(
            initialTime.add(Duration(milliseconds: elapsedMilliseconds)),
            origin,
          );
          final expected = elapsedMilliseconds >= 5000 || meters >= 15;

          expect(
            decision.isAllowed,
            expected,
            reason: 'elapsed=$elapsedMilliseconds ms, distance=$meters m',
          );
          expect(decision.isBlocked, !expected);
        }
      }
    });

    // **Validates: Requirements 09.4, 09.9, 09.10**
    test('rejects only when both time and distance are below minimums', () {
      final distance = _FakeDistanceCalculator()..value = 14.999;
      final policy = CooldownPolicy(distanceCalculator: distance);
      policy.commit(_occurrence(initialTime, origin));

      final decision = policy.evaluate(
        initialTime.add(const Duration(milliseconds: 4999)),
        origin,
      );

      expect(decision.isBlocked, isTrue);
      expect(decision.elapsed, const Duration(milliseconds: 4999));
      expect(decision.distanceMeters, 14.999);
    });

    test('treats a regressive clock as below the time threshold', () {
      final distance = _FakeDistanceCalculator()..value = 1;
      final policy = CooldownPolicy(distanceCalculator: distance);
      policy.commit(_occurrence(initialTime, origin));

      final decision = policy.evaluate(
        initialTime.subtract(const Duration(days: 1)),
        origin,
      );

      expect(decision.isBlocked, isTrue);
      expect(decision.elapsed, Duration.zero);
    });

    // **Validates: Requirements 09.7, 09.11**
    test('a rejected evaluation does not advance the committed reference', () {
      final distance = _FakeDistanceCalculator()..value = 0;
      final policy = CooldownPolicy(distanceCalculator: distance);
      policy.commit(_occurrence(initialTime, origin));

      expect(
        policy
            .evaluate(initialTime.add(const Duration(seconds: 1)), origin)
            .isBlocked,
        isTrue,
      );
      expect(
        policy
            .evaluate(initialTime.add(const Duration(seconds: 5)), origin)
            .isAllowed,
        isTrue,
      );
    });

    // **Validates: Requirements 09.7, 09.11**
    test('an allowed evaluation without a successful commit changes nothing',
        () {
      final distance = _FakeDistanceCalculator()..value = 0;
      final policy = CooldownPolicy(distanceCalculator: distance);
      policy.commit(_occurrence(initialTime, origin));
      final attempt = initialTime.add(const Duration(seconds: 5));

      expect(policy.evaluate(attempt, origin).isAllowed, isTrue);
      expect(policy.evaluate(attempt, origin).isAllowed, isTrue);
    });

    test('commit advances the reference only with a complete occurrence', () {
      final distance = _FakeDistanceCalculator()..value = 0;
      final policy = CooldownPolicy(distanceCalculator: distance);
      policy.commit(_occurrence(initialTime, origin));
      final nextTime = initialTime.add(const Duration(seconds: 5));

      expect(policy.evaluate(nextTime, origin).isAllowed, isTrue);
      policy.commit(_occurrence(nextTime, origin));

      expect(
        policy
            .evaluate(nextTime.add(const Duration(seconds: 1)), origin)
            .isBlocked,
        isTrue,
      );
    });
    test('restores the highest queue sequence regardless of wall-clock order',
        () {
      final distance = _FakeDistanceCalculator()..value = 0;
      final policy = CooldownPolicy(distanceCalculator: distance);
      final laterByClock = initialTime.add(const Duration(seconds: 200));
      final latestAccepted = initialTime.add(const Duration(seconds: 100));

      policy.restoreRecoveredPending(<ReconstructedPendingOccurrence>[
        _pending(sequence: 4, detectedAt: laterByClock, point: origin),
        _pending(sequence: 9, detectedAt: latestAccepted, point: origin),
        _pending(sequence: 6, detectedAt: initialTime, point: origin),
      ]);

      expect(
        policy
            .evaluate(latestAccepted.add(const Duration(seconds: 6)), origin)
            .isAllowed,
        isTrue,
      );
    });

    // **Validates: Requirements 09.1, 09.2, 09.3, 09.4, 12.3**
    test('clears a restored reference only for a recovered empty queue', () {
      final distance = _FakeDistanceCalculator()..value = 0;
      final policy = CooldownPolicy(distanceCalculator: distance);
      policy.restoreRecoveredPending(<ReconstructedPendingOccurrence>[
        _pending(sequence: 1, detectedAt: initialTime, point: origin),
      ]);

      expect(
        policy
            .evaluate(initialTime.add(const Duration(seconds: 1)), origin)
            .isBlocked,
        isTrue,
      );

      policy.restoreRecoveredPending(const <ReconstructedPendingOccurrence>[]);

      expect(policy.evaluate(initialTime, origin).isFirstOccurrence, isTrue);
    });
  });
}

ReconstructedPendingOccurrence _pending({
  required int sequence,
  required DateTime detectedAt,
  required GeoPoint point,
}) =>
    ReconstructedPendingOccurrence(
      QueueRecordProjection(
        queueSequence: sequence,
        idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
        detectedAtIso8601: detectedAt.toIso8601String(),
        latitude: point.latitude,
        longitude: point.longitude,
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

ImmutableGeoPoint _point(double latitude, double longitude) =>
    ImmutableGeoPoint(
      latitude: latitude,
      longitude: longitude,
    );

InMemoryOccurrence _occurrence(DateTime detectedAt, GeoPoint point) {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
    detectedAt: detectedAt,
    location: ImmutableLocationSnapshot(point: point),
    image: _OwnedPreparedImage(),
  );
}

final class _MutablePoint implements GeoPoint {
  _MutablePoint(this.latitude, this.longitude);

  @override
  final double latitude;

  @override
  final double longitude;
}

final class _FakeDistanceCalculator implements DistanceCalculator {
  double value = 0;

  @override
  double metersBetween(GeoPoint from, GeoPoint to) => value;
}

final class _OwnedPreparedImage implements OwnedPreparedImage {
  @override
  Future<void> dispose() async {}
}
