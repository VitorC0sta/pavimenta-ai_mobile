import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/occurrence_acceptance_port.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';

void main() {
  group('OccurrenceAcceptancePort', () {
    // **Validates: Requirements RF-12.1, RF-12.7, RF-12.8**
    test('returns every durable acceptance outcome as a distinct type',
        () async {
      final occurrence = _occurrence();
      const snapshot = QueueSnapshot(
        health: QueueHealth.ready,
        pendingCount: 1,
      );
      final outcomes = <OccurrenceAcceptanceResult>[
        const OccurrencePersisted(snapshot),
        const OccurrenceAlreadyPersistedEquivalent(snapshot),
        const OccurrenceIdentityConflict(),
        const OccurrenceStorageUnavailable(),
        const OccurrenceInvalidData(),
        const OccurrenceImageFailure(),
        const OccurrenceTransactionalFailure(),
      ];

      for (final outcome in outcomes) {
        final port = _FakeOccurrenceAcceptancePort(outcome);

        expect(await port.accept(occurrence), same(outcome));
        expect(port.acceptedOccurrence, same(occurrence));
      }

      expect(
        outcomes.map((outcome) => outcome.runtimeType).toSet(),
        hasLength(outcomes.length),
      );
    });
  });
}

InMemoryOccurrence _occurrence() {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
    detectedAt: DateTime.utc(2025, 4, 12, 14, 30),
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      accuracyMeters: 4.5,
      speedMetersPerSecond: 8,
    ),
    image: _FakePreparedImage(),
  );
}

final class _FakeOccurrenceAcceptancePort implements OccurrenceAcceptancePort {
  _FakeOccurrenceAcceptancePort(this.result);

  final OccurrenceAcceptanceResult result;
  InMemoryOccurrence? acceptedOccurrence;

  @override
  Future<OccurrenceAcceptanceResult> accept(
    InMemoryOccurrence occurrence,
  ) async {
    acceptedOccurrence = occurrence;
    return result;
  }
}

final class _FakePreparedImage implements OwnedPreparedImage {
  @override
  Future<void> dispose() async {}
}
