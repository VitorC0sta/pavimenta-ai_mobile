import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect;
import 'package:pavimenta_ai_mobile/domain/cooldown_policy.dart';
import 'package:pavimenta_ai_mobile/domain/distance_calculator.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';

void main() {
  final inputs =
      any.combine3<_RecoveredQueueKind, List<int>, int, _PropertyInput>(
    any.choose(_RecoveredQueueKind.values),
    any.nonEmptyList(any.positiveIntOrZero),
    any.positiveIntOrZero,
    (kind, values, seed) => _PropertyInput(
      kind: kind,
      entryCount: 1 + values.length % 8,
      seed: seed,
    ),
  );

  // Feature: mvp-app-flutter, Property 20: Restauração da referência de cooldown
  // **Validates: Requirements RF-09.1, RF-09.2, RF-09.3, RF-09.4, RF-12.3**
  Glados<_PropertyInput>(
    inputs,
    ExploreConfig(numRuns: 120),
  ).test(
    'restores only the highest queue sequence regardless of clock or iterable order',
    (_PropertyInput input) {
      final recovered = switch (input.kind) {
        _RecoveredQueueKind.empty => const <ReconstructedPendingOccurrence>[],
        _RecoveredQueueKind.nonEmpty => _recoveredPending(input),
      };
      final expected = recovered.isEmpty
          ? null
          : recovered.reduce(
              (latest, occurrence) =>
                  occurrence.queueSequence > latest.queueSequence
                      ? occurrence
                      : latest,
            );
      final expectedPoint = expected == null
          ? ImmutableGeoPoint(latitude: 0, longitude: 0)
          : ImmutableGeoPoint(
              latitude: expected.latitude,
              longitude: expected.longitude,
            );
      final policy = CooldownPolicy(
        distanceCalculator: _ReferenceAwareDistanceCalculator(expectedPoint),
      );

      policy.restoreRecoveredPending(recovered);

      if (expected == null) {
        final decision =
            policy.evaluate(DateTime.utc(2025, 1, 1), expectedPoint);

        expect(decision.isFirstOccurrence, isTrue);
        expect(decision.isAllowed, isTrue);
        return;
      }

      final decision = policy.evaluate(
        DateTime.parse(expected.detectedAtIso8601)
            .add(const Duration(milliseconds: 1)),
        expectedPoint,
      );

      expect(
        decision.isBlocked,
        isTrue,
        reason:
            'only the greatest queueSequence may remain as the cooldown reference',
      );
      expect(decision.elapsed, const Duration(milliseconds: 1));
      expect(decision.distanceMeters, 0);
    },
  );
}

List<ReconstructedPendingOccurrence> _recoveredPending(_PropertyInput input) {
  final base = DateTime.utc(2025, 1, 1, 12);
  final entries = List<ReconstructedPendingOccurrence>.generate(
    input.entryCount,
    (index) {
      final sequence = index + 1;
      return _pending(
        sequence: sequence,
        // The highest sequence deliberately has the oldest clock value.
        detectedAt: base.add(Duration(minutes: input.entryCount - sequence)),
        latitude: -20 + sequence / 1000,
        longitude: -40 - sequence / 1000,
      );
    },
  );

  // Recovery must not depend on either persisted-clock or iterable order.
  entries.sort((left, right) =>
      ((left.queueSequence * 31 + input.seed) % input.entryCount).compareTo(
        (right.queueSequence * 31 + input.seed) % input.entryCount,
      ));
  return entries;
}

ReconstructedPendingOccurrence _pending({
  required int sequence,
  required DateTime detectedAt,
  required double latitude,
  required double longitude,
}) =>
    ReconstructedPendingOccurrence(
      QueueRecordProjection(
        queueSequence: sequence,
        idempotencyKey: _uuidFor(sequence),
        detectedAtIso8601: detectedAt.toIso8601String(),
        latitude: latitude,
        longitude: longitude,
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

String _uuidFor(int sequence) =>
    '00000000-0000-4000-8000-${sequence.toRadixString(16).padLeft(12, '0')}';

enum _RecoveredQueueKind { empty, nonEmpty }

final class _PropertyInput {
  const _PropertyInput({
    required this.kind,
    required this.entryCount,
    required this.seed,
  });

  final _RecoveredQueueKind kind;
  final int entryCount;
  final int seed;
}

final class _ReferenceAwareDistanceCalculator implements DistanceCalculator {
  const _ReferenceAwareDistanceCalculator(this.expectedReference);

  final GeoPoint expectedReference;

  @override
  double metersBetween(GeoPoint from, GeoPoint to) {
    final isExpectedReference = from.latitude == expectedReference.latitude &&
        from.longitude == expectedReference.longitude;
    final isExpectedCandidate = to.latitude == expectedReference.latitude &&
        to.longitude == expectedReference.longitude;
    return isExpectedReference && isExpectedCandidate ? 0 : 15;
  }
}
