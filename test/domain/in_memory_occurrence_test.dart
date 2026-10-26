import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/system_clock.dart';
import 'package:pavimenta_ai_mobile/infrastructure/uuid_v4_generator.dart';

void main() {
  group('immutable location models', () {
    test('accept latitude and longitude boundaries', () {
      for (final coordinates in <(double, double)>[
        (-90, -180),
        (-90, 180),
        (90, -180),
        (90, 180),
        (0, 0),
      ]) {
        final point = ImmutableGeoPoint(
          latitude: coordinates.$1,
          longitude: coordinates.$2,
        );

        expect(point.latitude, coordinates.$1);
        expect(point.longitude, coordinates.$2);
      }
    });

    test('rejects non-finite and out-of-range coordinates', () {
      for (final latitude in <double>[
        -90.000001,
        90.000001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => ImmutableGeoPoint(latitude: latitude, longitude: 0),
          throwsRangeError,
        );
      }
      for (final longitude in <double>[
        -180.000001,
        180.000001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => ImmutableGeoPoint(latitude: 0, longitude: longitude),
          throwsRangeError,
        );
      }
    });

    test('copies point values and omits unusable informational accuracy', () {
      final mutablePoint = _MutablePoint(latitude: -23.5, longitude: -46.6);
      final snapshot = ImmutableLocationSnapshot(
        point: mutablePoint,
        accuracyMeters: double.nan,
        speedMetersPerSecond: 4,
      );

      mutablePoint
        ..latitude = 10
        ..longitude = 20;

      expect(snapshot.point.latitude, -23.5);
      expect(snapshot.point.longitude, -46.6);
      expect(snapshot.accuracyMeters, isNull);
      expect(snapshot.speedMetersPerSecond, 4);
    });
  });

  group('speed normalization', () {
    // **Validates: Requirements 06.6, 06.7, 06.8**
    test('converts finite speeds and includes both contract boundaries', () {
      final examples = <double, double>{
        0: 0,
        1: 3.6,
        10: 36,
        300 / 3.6: 300,
      };

      for (final entry in examples.entries) {
        expect(
          speedMetersPerSecondToKmh(entry.key),
          closeTo(entry.value, 1e-10),
        );
      }
    });

    // **Validates: Requirements 06.6, 06.7, 06.8**
    test('omits absent, negative, non-finite, and above-limit speeds', () {
      expect(speedMetersPerSecondToKmh(null), isNull);
      for (final speed in <double>[
        -0.000001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        (300 / 3.6) + 0.000001,
      ]) {
        expect(speedMetersPerSecondToKmh(speed), isNull);
      }
    });

    test('applies m/s times 3.6 throughout representative valid values', () {
      for (var metersPerSecond = 0.0;
          metersPerSecond <= 80;
          metersPerSecond += 0.25) {
        expect(
          speedMetersPerSecondToKmh(metersPerSecond),
          closeTo(metersPerSecond * 3.6, 1e-10),
        );
      }
    });
  });

  group('manual in-memory occurrence factory', () {
    // **Validates: Requirements 06.2, 06.3, 07.2, 07.3, 07.5, 07.6,
    // 07.7, 07.8, 08.3, 11.1, 11.5**
    test('preserves one accepted instant and creates the complete model', () {
      final acceptedAt = DateTime.parse('2025-03-10T12:30:45.123Z');
      final clock = _FakeClock(acceptedAt);
      final uuidGenerator = _FakeUuidGenerator(
        '123e4567-e89b-42d3-a456-426614174000',
      );
      final mutablePoint =
          _MutablePoint(latitude: -23.5505, longitude: -46.6333);
      final mutableSnapshot = _MutableSnapshot(
        point: mutablePoint,
        accuracyMeters: 3.5,
        speedMetersPerSecond: 5,
      );
      final image = _OwnedPreparedImage();

      final detectedAt = clock.now();
      final idempotencyKey = uuidGenerator.newV4();
      final occurrence = const InMemoryOccurrenceFactory().createManual(
        idempotencyKey: idempotencyKey,
        detectedAt: detectedAt,
        location: mutableSnapshot,
        image: image,
      );

      mutablePoint.latitude = 0;
      mutableSnapshot.speedMetersPerSecond = 20;

      expect(clock.callCount, 1);
      expect(uuidGenerator.callCount, 1);
      expect(occurrence.detectedAt, same(acceptedAt));
      expect(occurrence.detectedAtIso8601, '2025-03-10T12:30:45.123Z');
      expect(occurrence.idempotencyKey, idempotencyKey);
      expect(occurrence.latitude, -23.5505);
      expect(occurrence.longitude, -46.6333);
      expect(occurrence.accuracyMeters, 3.5);
      expect(occurrence.speedKmh, 18);
      expect(occurrence.confidence, 1.0);
      expect(occurrence.defectClass, 'pothole');
      expect(occurrence.image, same(image));

      final dynamic publicModel = occurrence;
      expect(() => publicModel.source, throwsA(isA<NoSuchMethodError>()));
      expect(() => publicModel.highway, throwsA(isA<NoSuchMethodError>()));
      expect(() => publicModel.km, throwsA(isA<NoSuchMethodError>()));
    });

    test('rejects an invalid location before creating an occurrence', () {
      final invalidLocations = <LocationSnapshot>[
        _MutableSnapshot(
          point: _MutablePoint(latitude: -91, longitude: 0),
        ),
        _MutableSnapshot(
          point: _MutablePoint(latitude: 0, longitude: 181),
        ),
        _MutableSnapshot(
          point: _MutablePoint(latitude: double.nan, longitude: 0),
        ),
        _MutableSnapshot(
          point: _MutablePoint(latitude: 0, longitude: double.infinity),
        ),
      ];

      for (final location in invalidLocations) {
        expect(
          () => const InMemoryOccurrenceFactory().createManual(
            idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
            detectedAt: DateTime.utc(2025),
            location: location,
            image: _OwnedPreparedImage(),
          ),
          throwsRangeError,
        );
      }
    });

    test('rejects malformed, non-v4, and invalid-variant identifiers', () {
      for (final identifier in <String>[
        '',
        'not-a-uuid',
        '123e4567-e89b-12d3-a456-426614174000',
        '123e4567-e89b-42d3-7456-426614174000',
      ]) {
        expect(
          () => const InMemoryOccurrenceFactory().createManual(
            idempotencyKey: identifier,
            detectedAt: DateTime.utc(2025),
            location: _MutableSnapshot(
              point: _MutablePoint(latitude: 0, longitude: 0),
            ),
            image: _OwnedPreparedImage(),
          ),
          throwsFormatException,
        );
      }
    });

    test('omits invalid optional speed without rejecting the occurrence', () {
      for (final speed in <double?>[
        null,
        -1,
        double.nan,
        double.infinity,
        84,
      ]) {
        final occurrence = const InMemoryOccurrenceFactory().createManual(
          idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
          detectedAt: DateTime.utc(2025),
          location: _MutableSnapshot(
            point: _MutablePoint(latitude: 0, longitude: 0),
            speedMetersPerSecond: speed,
          ),
          image: _OwnedPreparedImage(),
        );

        expect(occurrence.speedKmh, isNull);
      }
    });
  });

  group('clock and UUID infrastructure', () {
    test('SystemClock returns a current local instant', () {
      const clock = SystemClock();
      final before = DateTime.now();
      final value = clock.now();
      final after = DateTime.now();

      expect(value.isBefore(before), isFalse);
      expect(value.isAfter(after), isFalse);
      expect(dateTimeWithOffsetToIso8601(value),
          contains(RegExp(r'(Z|[+-]\d\d:\d\d)$')));
    });

    test('UuidV4Generator always returns valid version 4 identifiers', () {
      const generator = UuidV4Generator();
      final generated = <String>{};

      for (var index = 0; index < 32; index++) {
        final value = generator.newV4();
        expect(isUuidV4(value), isTrue);
        generated.add(value);
      }

      expect(generated, hasLength(32));
    });
  });
}

final class _MutablePoint implements GeoPoint {
  _MutablePoint({required this.latitude, required this.longitude});

  @override
  double latitude;

  @override
  double longitude;
}

final class _MutableSnapshot implements LocationSnapshot {
  _MutableSnapshot({
    required this.point,
    this.accuracyMeters,
    this.speedMetersPerSecond,
  });

  @override
  final GeoPoint point;

  @override
  double? accuracyMeters;

  @override
  double? speedMetersPerSecond;
}

final class _OwnedPreparedImage implements OwnedPreparedImage {
  @override
  Future<void> dispose() async {}
}

final class _FakeClock implements Clock {
  _FakeClock(this.value);

  final DateTime value;
  int callCount = 0;

  @override
  DateTime now() {
    callCount++;
    return value;
  }
}

final class _FakeUuidGenerator implements UuidGenerator {
  _FakeUuidGenerator(this.value);

  final String value;
  int callCount = 0;

  @override
  String newV4() {
    callCount++;
    return value;
  }
}
