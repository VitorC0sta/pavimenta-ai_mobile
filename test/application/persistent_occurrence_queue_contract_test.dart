import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';

void main() {
  group('PersistentOccurrenceQueue contract', () {
    // **Validates: Requirements RF-11.8, RF-12.1–5, RF-12.9–11,
    // RNF-03.5, RNF-03.10, RNF-05.1–4, RNF-06.3, RNF-06.9–10**
    test(
      'supports persistence, observation, reconstruction, count, and internal removal',
      () async {
        final queue = _ContractQueue();
        final snapshots = <QueueSnapshot>[];
        final subscription = queue.snapshots.listen(snapshots.add);
        addTearDown(() async {
          await subscription.cancel();
          await queue.close();
        });

        final initial = await queue.bootstrap();
        final occurrence = _occurrence();
        final acceptance = await queue.persist(occurrence);
        final pending = await queue.listPending();

        expect(initial.health, QueueHealth.ready);
        expect(initial.pendingCount, 0);
        expect(acceptance, isA<OccurrencePersisted>());
        expect((acceptance as OccurrencePersisted).snapshot.pendingCount, 1);
        expect(await queue.countPending(), 1);
        expect(pending, hasLength(1));
        expect(pending.single.idempotencyKey, occurrence.idempotencyKey);
        expect(pending.single.detectedAtIso8601, occurrence.detectedAtIso8601);
        expect(pending.single.latitude, occurrence.latitude);
        expect(pending.single.longitude, occurrence.longitude);
        expect(pending.single.accuracyMeters, occurrence.accuracyMeters);
        expect(pending.single.speedKmh, occurrence.speedKmh);
        expect(pending.single.confidence, 1);
        expect(pending.single.defectClass, 'pothole');
        expect(pending.single.image.relativeName, 'opaque-1.jpg');

        final removal = await queue.removeInternal(occurrence.idempotencyKey);
        expect(removal, isA<QueueOccurrenceRemoved>());
        expect((removal as QueueOccurrenceRemoved).snapshot.pendingCount, 0);
        expect(await queue.countPending(), 0);
        expect(await queue.listPending(), isEmpty);

        final missing = await queue.removeInternal(occurrence.idempotencyKey);
        expect(missing, isA<QueueOccurrenceNotFound>());
        expect(
          snapshots.map((snapshot) => snapshot.pendingCount),
          <int>[0, 1, 0],
        );
      },
    );

    // **Validates: Requirements RF-12.3–5, RNF-05.3–4**
    test('reconstructed list and emitted snapshots cannot mutate queue state',
        () async {
      final queue = _ContractQueue();
      addTearDown(queue.close);

      await queue.bootstrap();
      await queue.persist(_occurrence());
      final firstRead = await queue.listPending();

      expect(() => firstRead.add(firstRead.single), throwsUnsupportedError);
      expect(firstRead.single.record, same(firstRead.single.record));
      expect(await queue.countPending(), 1);
      expect((await queue.listPending()).single.idempotencyKey,
          firstRead.single.idempotencyKey);
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
    image: const _OwnedImage(),
  );
}

final class _ContractQueue implements PersistentOccurrenceQueue {
  final StreamController<QueueSnapshot> _snapshots =
      StreamController<QueueSnapshot>.broadcast(sync: true);
  final List<QueueRecordProjection> _records = <QueueRecordProjection>[];
  var _nextSequence = 1;
  var _closed = false;

  @override
  Stream<QueueSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<QueueSnapshot> bootstrap() async {
    final snapshot = _snapshot();
    _snapshots.add(snapshot);
    return snapshot;
  }

  @override
  Future<QueueSnapshot> retryBootstrap() => bootstrap();

  @override
  Future<OccurrenceAcceptanceResult> persist(
    InMemoryOccurrence occurrence,
  ) async {
    final existing = _records
        .where((record) => record.idempotencyKey == occurrence.idempotencyKey)
        .firstOrNull;
    if (existing != null) {
      return OccurrenceAlreadyPersistedEquivalent(_snapshot());
    }

    _records.add(
      QueueRecordProjection(
        queueSequence: _nextSequence++,
        idempotencyKey: occurrence.idempotencyKey,
        detectedAtIso8601: occurrence.detectedAtIso8601,
        latitude: occurrence.latitude,
        longitude: occurrence.longitude,
        accuracyMeters: occurrence.accuracyMeters,
        speedKmh: occurrence.speedKmh,
        confidence: occurrence.confidence,
        defectClass: occurrence.defectClass,
        image: const PersistedImageProjection(
          relativeName: 'opaque-1.jpg',
          mimeType: 'image/jpeg',
          byteLength: 3,
          sha256:
              '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          width: 3,
          height: 1,
          quality: 85,
        ),
      ),
    );
    final snapshot = _snapshot();
    _snapshots.add(snapshot);
    return OccurrencePersisted(snapshot);
  }

  @override
  Future<List<ReconstructedPendingOccurrence>> listPending() async =>
      List<ReconstructedPendingOccurrence>.unmodifiable(
        _records.map(ReconstructedPendingOccurrence.new),
      );

  @override
  Future<int> countPending() async => _records.length;

  @override
  Future<QueueRemovalResult> removeInternal(String idempotencyKey) async {
    final index = _records.indexWhere(
      (record) => record.idempotencyKey == idempotencyKey,
    );
    if (index < 0) {
      return QueueOccurrenceNotFound(_snapshot());
    }

    _records.removeAt(index);
    final snapshot = _snapshot();
    _snapshots.add(snapshot);
    return QueueOccurrenceRemoved(snapshot);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _snapshots.close();
  }

  QueueSnapshot _snapshot() => QueueSnapshot(
        health: QueueHealth.ready,
        pendingCount: _records.length,
      );
}

final class _OwnedImage implements OwnedPreparedImage {
  const _OwnedImage();

  @override
  Future<void> dispose() async {}
}
