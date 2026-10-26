import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';

void main() {
  group('E2 typed persistence results', () {
    const ready = QueueSnapshot(
      health: QueueHealth.ready,
      pendingCount: 1,
    );

    // **Validates: Requirements RF-12.1, RF-12.7, RF-12.8**
    test('acceptance outcomes are distinct and exhaustively classifiable', () {
      const results = <OccurrenceAcceptanceResult>[
        OccurrencePersisted(ready),
        OccurrenceAlreadyPersistedEquivalent(ready),
        OccurrenceIdentityConflict(),
        OccurrenceStorageUnavailable(),
        OccurrenceInvalidData(),
        OccurrenceImageFailure(),
        OccurrenceTransactionalFailure(),
      ];

      expect(
        results.map(_acceptanceCategory),
        <String>[
          'persisted',
          'equivalent',
          'identityConflict',
          'storageUnavailable',
          'invalidData',
          'imageFailure',
          'transactionalFailure',
        ],
      );
      expect(
        results.map((result) => result.runtimeType).toSet(),
        hasLength(results.length),
      );
    });

    // **Validates: Requirements RF-12.9, RNF-05.4, RNF-06.10**
    test('internal removal outcomes are distinct and exhaustively classifiable',
        () {
      const results = <QueueRemovalResult>[
        QueueOccurrenceRemoved(ready),
        QueueOccurrenceNotFound(ready),
        QueueOccurrenceRemovalFailed(),
      ];

      expect(
        results.map(_removalCategory),
        <String>['removed', 'notFound', 'failed'],
      );
      expect(
        results.map((result) => result.runtimeType).toSet(),
        hasLength(results.length),
      );
    });
  });

  group('E2 immutable projections', () {
    const image = PersistedImageProjection(
      relativeName: 'e2_image_opaque.jpg',
      mimeType: 'image/jpeg',
      byteLength: 1024,
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      width: 640,
      height: 360,
      quality: 85,
    );

    QueueRecordProjection recordWithNullableValues({
      double? accuracyMeters,
      double? speedKmh,
    }) {
      return QueueRecordProjection(
        queueSequence: 7,
        idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
        detectedAtIso8601: '2025-01-02T03:04:05.000-03:00',
        latitude: -23.5,
        longitude: -46.6,
        accuracyMeters: accuracyMeters,
        speedKmh: speedKmh,
        confidence: 1,
        defectClass: 'pothole',
        image: image,
      );
    }

    test('reconstruction preserves canonical values without exposing bytes',
        () {
      final pending = ReconstructedPendingOccurrence(
        recordWithNullableValues(speedKmh: 0),
      );

      expect(pending.queueSequence, 7);
      expect(pending.detectedAtIso8601, '2025-01-02T03:04:05.000-03:00');
      expect(pending.speedKmh, 0);
      expect(pending.accuracyMeters, isNull);
      expect(pending.image.relativeName, 'e2_image_opaque.jpg');
      expect(pending.image.byteLength, 1024);
    });

    test('distinguishes absent nullable values from explicit zeroes', () {
      final absent = ReconstructedPendingOccurrence(
        recordWithNullableValues(),
      );
      final zeroes = ReconstructedPendingOccurrence(
        recordWithNullableValues(accuracyMeters: 0, speedKmh: 0),
      );

      expect(absent.accuracyMeters, isNull);
      expect(absent.speedKmh, isNull);
      expect(zeroes.accuracyMeters, 0);
      expect(zeroes.speedKmh, 0);
    });

    test('snapshot contains only immutable aggregate queue state', () {
      const snapshot = QueueSnapshot(
        health: QueueHealth.degraded,
        pendingCount: 3,
        attentionCount: 1,
      );

      expect(snapshot.health, QueueHealth.degraded);
      expect(snapshot.pendingCount, 3);
      expect(snapshot.attentionCount, 1);
      expect(snapshot.isReady, isFalse);
      expect(const QueueSnapshot.initializing().pendingCount, 0);
    });
  });
}

String _acceptanceCategory(OccurrenceAcceptanceResult result) =>
    switch (result) {
      OccurrencePersisted() => 'persisted',
      OccurrenceAlreadyPersistedEquivalent() => 'equivalent',
      OccurrenceIdentityConflict() => 'identityConflict',
      OccurrenceStorageUnavailable() => 'storageUnavailable',
      OccurrenceInvalidData() => 'invalidData',
      OccurrenceImageFailure() => 'imageFailure',
      OccurrenceTransactionalFailure() => 'transactionalFailure',
    };

String _removalCategory(QueueRemovalResult result) => switch (result) {
      QueueOccurrenceRemoved() => 'removed',
      QueueOccurrenceNotFound() => 'notFound',
      QueueOccurrenceRemovalFailed() => 'failed',
    };
