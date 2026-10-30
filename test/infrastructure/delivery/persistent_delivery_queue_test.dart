import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_backoff_policy.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/persistent_delivery_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_delivery_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _keyA = '123e4567-e89b-42d3-a456-426614174000';
const String _keyB = '223e4567-e89b-42d3-a456-426614174000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory sandbox;
  late String databasePath;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e4_delivery_queue_');
    databasePath =
        '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName';
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<QueueDatabase> openDatabase() => QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );

  CoordinatedPersistentOccurrenceQueue openQueue() =>
      CoordinatedPersistentOccurrenceQueue(
        imageStore: PrivateDurableImageStore.at(sandbox),
        databaseOpener: openDatabase,
      );

  /// Writes delivery state through a second connection, as a later task will.
  Future<void> seedState(
    String key, {
    int attemptCount = 0,
    String? nextAttemptAt,
    String? disposition,
    int cleanupAttemptCount = 0,
    String? nextCleanupAt,
  }) async {
    final extra = await openDatabase();
    try {
      await extra.database.insert(e4DeliveryStateTable, <String, Object?>{
        'idempotency_key': key,
        'attempt_count': attemptCount,
        'next_attempt_at': nextAttemptAt,
        'pending_local_disposition': disposition,
        'cleanup_attempt_count': cleanupAttemptCount,
        'next_cleanup_at': nextCleanupAt,
      });
    } finally {
      await extra.close();
    }
  }

  Future<(CoordinatedPersistentOccurrenceQueue, PersistentDeliveryQueue)>
      readyQueue() async {
    final queue = openQueue();
    addTearDown(queue.close);
    await queue.bootstrap();
    return (queue, PersistentDeliveryQueue(queue));
  }

  Future<Map<String, Object?>?> stateRow(String key) async {
    final extra = await openDatabase();
    try {
      final rows = await extra.database.query(
        e4DeliveryStateTable,
        where: 'idempotency_key = ?',
        whereArgs: <Object>[key],
      );
      return rows.isEmpty ? null : rows.single;
    } finally {
      await extra.close();
    }
  }

  final now = DateTime.utc(2025, 3, 4, 5, 6, 7);

  // **Validates: Requirements RF-12.9–11, RF-14, RF-17**
  group('task 64.4 head selection, private read and summaries', () {
    test('reports an empty queue', () async {
      final (_, delivery) = await readyQueue();

      expect(await delivery.nextHead(now), isA<DeliveryQueueEmpty>());
    });

    test('selects the FIFO head with canonical values and streams its JPEG',
        () async {
      final firstBytes = _jpeg(width: 17, height: 11, red: 12);
      final (queue, delivery) = await readyQueue();
      await queue.persist(
        _occurrence(
          key: _keyA,
          detectedAt: DateTime.utc(2025, 1, 2, 3, 4, 5),
          bytes: firstBytes,
          width: 17,
          height: 11,
          speedMetersPerSecond: 0,
        ),
      );
      await queue.persist(
        _occurrence(
          key: _keyB,
          detectedAt: DateTime.utc(2025, 1, 2, 3, 9, 5),
          bytes: _jpeg(width: 6, height: 6, red: 2),
          width: 6,
          height: 6,
        ),
      );

      final result = await delivery.nextHead(now);

      expect(result, isA<DeliveryHeadEligible>());
      final eligible = result as DeliveryHeadEligible;
      expect(eligible.head.idempotencyKey, _keyA);
      expect(eligible.head.queueSequence, 1);
      expect(eligible.head.attemptCount, 0);
      expect(eligible.payload.detectedAtIso8601, '2025-01-02T03:04:05.000Z');
      expect(eligible.payload.latitude, -23.5505);
      expect(eligible.payload.longitude, -46.6333);
      expect(eligible.payload.speedKmh, 0);
      expect(eligible.payload.confidence, 1.0);
      expect(eligible.payload.defectClass, 'pothole');
      expect(eligible.payload.image.byteLength, firstBytes.length);
      expect(eligible.toString(), isNot(contains(_keyA)));

      final streamed =
          await delivery.openImage(eligible).expand((chunk) => chunk).toList();
      expect(streamed, firstBytes);
    });

    test('does not let later items overtake a head in backoff', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await queue.persist(_simple(_keyB, red: 2));
      final due = now.add(const Duration(seconds: 30));
      await seedState(
        _keyA,
        attemptCount: 2,
        nextAttemptAt: due.toIso8601String(),
      );

      final waiting = await delivery.nextHead(now);
      expect(waiting, isA<DeliveryHeadInBackoff>());
      final backoff = waiting as DeliveryHeadInBackoff;
      expect(backoff.head.idempotencyKey, _keyA);
      expect(backoff.head.attemptCount, 2);
      expect(backoff.nextAttemptAt.isAtSameMomentAs(due), isTrue);

      final atDue = await delivery.nextHead(due);
      expect(atDue, isA<DeliveryHeadEligible>());
      expect((atDue as DeliveryHeadEligible).head.idempotencyKey, _keyA);
    });

    test('an invalid backoff timestamp never postpones the head', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await seedState(_keyA, attemptCount: 1, nextAttemptAt: 'not-a-date');

      final result = await delivery.nextHead(now);

      expect(result, isA<DeliveryHeadEligible>());
      expect((result as DeliveryHeadEligible).head.attemptCount, 1);
    });

    test('reports pending local cleanup before backoff and image checks',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      final cleanupDue = now.add(const Duration(minutes: 1));
      await seedState(
        _keyA,
        attemptCount: 3,
        nextAttemptAt: now.add(const Duration(hours: 1)).toIso8601String(),
        disposition: DeliveryDisposition.conflict.name,
        cleanupAttemptCount: 2,
        nextCleanupAt: cleanupDue.toIso8601String(),
      );

      final waiting = await delivery.nextHead(now);
      expect(waiting, isA<DeliveryHeadPendingCleanup>());
      final pending = waiting as DeliveryHeadPendingCleanup;
      expect(pending.disposition, DeliveryDisposition.conflict);
      expect(pending.head.cleanupAttemptCount, 2);
      expect(pending.dueAt?.isAtSameMomentAs(cleanupDue), isTrue);

      final ready = await delivery.nextHead(cleanupDue);
      expect((ready as DeliveryHeadPendingCleanup).dueAt, isNull);
    });

    test('reports a local integrity failure when the JPEG is missing',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await queue.persist(_simple(_keyB, red: 2));
      final record = (await queue.listPending()).first.record;
      await PrivateDurableImageStore.at(sandbox).delete(record.image);

      final result = await delivery.nextHead(now);

      expect(result, isA<DeliveryHeadLocalIntegrityFailure>());
      expect(
        (result as DeliveryHeadLocalIntegrityFailure).head.idempotencyKey,
        _keyA,
      );
    });

    test('image stream fails when the head was removed after selection',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      final eligible = await delivery.nextHead(now) as DeliveryHeadEligible;
      expect(await queue.removeInternal(_keyA), isA<QueueOccurrenceRemoved>());

      await expectLater(
        delivery.openImage(eligible).toList(),
        throwsA(isA<StateError>()),
      );
      expect(await delivery.nextHead(now), isA<DeliveryQueueEmpty>());
    });

    test('image stream rejects a reference not issued by the queue', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      final eligible = await delivery.nextHead(now) as DeliveryHeadEligible;
      final foreign = DeliveryHeadEligible(
        head: eligible.head,
        payload: DeliveryOccurrencePayload(
          detectedAtIso8601: eligible.payload.detectedAtIso8601,
          latitude: eligible.payload.latitude,
          longitude: eligible.payload.longitude,
          speedKmh: eligible.payload.speedKmh,
          confidence: eligible.payload.confidence,
          defectClass: eligible.payload.defectClass,
          image: DeliveryImageRef(
            byteLength: eligible.payload.image.byteLength,
            opaqueHandle: Object(),
          ),
        ),
      );

      await expectLater(
        delivery.openImage(foreign).toList(),
        throwsA(isA<StateError>()),
      );
    });

    test('does not hold the serial region while the image is being read',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      final eligible = await delivery.nextHead(now) as DeliveryHeadEligible;

      final reader = StreamIterator<List<int>>(delivery.openImage(eligible));
      expect(await reader.moveNext(), isTrue);

      final result = await queue
          .persist(_simple(_keyB, red: 2))
          .timeout(const Duration(seconds: 10));
      expect(result, isA<OccurrencePersisted>());

      while (await reader.moveNext()) {}
      await reader.cancel();
    });

    test('reports the queue as unavailable for a future schema', () async {
      final future = await databaseFactoryFfi.openDatabase(databasePath);
      await future.setVersion(e2QueueDatabaseVersion + 1);
      await future.close();
      final (_, delivery) = await readyQueue();

      expect(await delivery.nextHead(now), isA<DeliveryQueueUnavailable>());
    });

    test('publishes aggregate summaries from the shared queue snapshots',
        () async {
      final (queue, delivery) = await readyQueue();
      final summaries = <QueueSnapshot>[];
      final subscription = delivery.watchSummary().listen(summaries.add);
      addTearDown(subscription.cancel);

      await queue.persist(_simple(_keyA, red: 1));
      await queue.removeInternal(_keyA);
      await Future<void>.delayed(Duration.zero);

      expect(
        summaries.map((snapshot) => snapshot.pendingCount),
        containsAllInOrder(<int>[1, 0]),
      );
    });
  });

  // **Validates: Requirements RF-12.9–11, RF-15.10–12, RF-16, RF-17, RF-18**
  group('task 64.5 attempt, backoff, pause and clock reconciliation', () {
    /// Closes [queue] and reopens the same database, as after a force-stop.
    Future<PersistentDeliveryQueue> reopen(
      CoordinatedPersistentOccurrenceQueue queue,
    ) async {
      await queue.close();
      final reopened = openQueue();
      addTearDown(reopened.close);
      await reopened.bootstrap();
      return PersistentDeliveryQueue(reopened);
    }

    test('records attempts atomically and keeps them after reopening',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      expect(await stateRow(_keyA), isNull);

      final firstAt = now;
      final firstDue = firstAt.add(const Duration(seconds: 5));
      expect(
        await delivery.recordRecoverableFailure(_keyA, firstAt, firstDue),
        DeliveryMutationResult.applied,
      );
      final secondAt = firstDue;
      final secondDue = secondAt.add(const Duration(seconds: 15));
      expect(
        await delivery.recordRecoverableFailure(_keyA, secondAt, secondDue),
        DeliveryMutationResult.applied,
      );

      final row = (await stateRow(_keyA))!;
      expect(row['attempt_count'], 2);
      expect(row['backoff_calculated_at'], secondAt.toIso8601String());
      expect(row['next_attempt_at'], secondDue.toIso8601String());

      final reopened = await reopen(queue);
      final head = await reopened.nextHead(secondAt) as DeliveryHeadInBackoff;
      expect(head.head.attemptCount, 2);
      expect(head.nextAttemptAt.isAtSameMomentAs(secondDue), isTrue);
    });

    test('stores non-UTC instants as UTC ISO 8601', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      final local = DateTime(2025, 3, 4, 5, 6, 7);

      await delivery.recordRecoverableFailure(
        _keyA,
        local,
        local.add(const Duration(seconds: 5)),
      );

      final row = (await stateRow(_keyA))!;
      expect(row['backoff_calculated_at'], local.toUtc().toIso8601String());
      expect((row['next_attempt_at'] as String).endsWith('Z'), isTrue);
    });

    test('reports an unknown item and rejects invalid delays', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));

      expect(
        await delivery.recordRecoverableFailure(
          _keyB,
          now,
          now.add(const Duration(seconds: 5)),
        ),
        DeliveryMutationResult.notFound,
      );
      await expectLater(
        delivery.recordRecoverableFailure(_keyA, now, now),
        throwsArgumentError,
      );
      await expectLater(
        delivery.recordRecoverableFailure(
          _keyA,
          now,
          now.add(const Duration(minutes: 16)),
        ),
        throwsArgumentError,
      );
      expect(await stateRow(_keyA), isNull);
    });

    test('never gives a retry instant to an item with a recorded decision',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await seedState(_keyA, disposition: DeliveryDisposition.conflict.name);

      final result = await delivery.recordRecoverableFailure(
        _keyA,
        now,
        now.add(const Duration(seconds: 5)),
      );

      expect(result, DeliveryMutationResult.storageFailure);
      final row = (await stateRow(_keyA))!;
      expect(row['attempt_count'], 0);
      expect(row['next_attempt_at'], isNull);
    });

    test(
        'persists the global pause, including the sanitized status, and '
        'resumes without touching backoff', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      expect(await delivery.readControl(), isA<DeliveryControlRunning>());
      await delivery.recordRecoverableFailure(
        _keyA,
        now,
        now.add(const Duration(seconds: 5)),
      );

      for (final reason in <DeliveryPauseReason>[
        DeliveryPauseReason.authentication,
        DeliveryPauseReason.access,
        DeliveryPauseReason.localFailure,
      ]) {
        expect(
          await delivery.pause(PausedDeliveryDecision(reason)),
          DeliveryMutationResult.applied,
        );
        final control = await delivery.readControl() as DeliveryControlPaused;
        expect(control.reason, reason);
        expect(control.unexpectedStatusCode, isNull);
      }

      expect(
        await delivery.pause(
          PausedDeliveryDecision(
            DeliveryPauseReason.unexpectedResponse,
            unexpectedStatusCode: 302,
          ),
        ),
        DeliveryMutationResult.applied,
      );
      final reopened = await reopen(queue);
      final paused = await reopened.readControl() as DeliveryControlPaused;
      expect(paused.reason, DeliveryPauseReason.unexpectedResponse);
      expect(paused.unexpectedStatusCode, 302);

      expect(await reopened.resume(), DeliveryMutationResult.applied);
      expect(await reopened.readControl(), isA<DeliveryControlRunning>());
      final row = (await stateRow(_keyA))!;
      expect(row['attempt_count'], 1);
      expect(row['next_attempt_at'], isNotNull);
    });

    test('rejects an out-of-range status and keeps the previous pause',
        () async {
      final (_, delivery) = await readyQueue();
      await delivery.pause(PausedDeliveryDecision(DeliveryPauseReason.access));

      final result = await delivery.pause(
        PausedDeliveryDecision(
          DeliveryPauseReason.unexpectedResponse,
          unexpectedStatusCode: 999,
        ),
      );

      expect(result, DeliveryMutationResult.storageFailure);
      final control = await delivery.readControl() as DeliveryControlPaused;
      expect(control.reason, DeliveryPauseReason.access);
    });

    test('uses the injected clock for the pause update time', () async {
      final queue = openQueue();
      addTearDown(queue.close);
      await queue.bootstrap();
      final delivery = PersistentDeliveryQueue(queue, clock: _FixedClock(now));

      await delivery.pause(PausedDeliveryDecision(DeliveryPauseReason.access));

      final extra = await openDatabase();
      try {
        final rows = await extra.database.query(e4DeliveryControlTable);
        expect(rows.single['updated_at'], now.toIso8601String());
      } finally {
        await extra.close();
      }
    });

    test('mutations report a storage failure when the queue is unavailable',
        () async {
      final future = await databaseFactoryFfi.openDatabase(databasePath);
      await future.setVersion(e2QueueDatabaseVersion + 1);
      await future.close();
      final (_, delivery) = await readyQueue();

      expect(await delivery.readControl(), isA<DeliveryControlUnavailable>());
      expect(
        await delivery.pause(
          PausedDeliveryDecision(DeliveryPauseReason.access),
        ),
        DeliveryMutationResult.storageFailure,
      );
      expect(await delivery.resume(), DeliveryMutationResult.storageFailure);
      expect(
        await delivery.recordRecoverableFailure(
          _keyA,
          now,
          now.add(const Duration(seconds: 5)),
        ),
        DeliveryMutationResult.storageFailure,
      );
    });

    test('an expired deadline makes the head eligible and keeps its attempts',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await delivery.recordRecoverableFailure(
        _keyA,
        now,
        now.add(const Duration(seconds: 5)),
      );
      final before = await stateRow(_keyA);

      final result = await delivery.nextHead(now.add(const Duration(hours: 2)))
          as DeliveryHeadEligible;

      expect(result.head.attemptCount, 1);
      expect(await stateRow(_keyA), before);
    });

    test('a regressed clock is reconciled once and survives reopening',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      // Calculated while the clock was one hour ahead of the current time.
      final calculatedAt = now.add(const Duration(hours: 1));
      const delay = Duration(seconds: 45);
      await delivery.recordRecoverableFailure(
        _keyA,
        calculatedAt,
        calculatedAt.add(delay),
      );

      final first = await delivery.nextHead(now) as DeliveryHeadInBackoff;
      expect(first.nextAttemptAt.isAtSameMomentAs(now.add(delay)), isTrue);
      final persisted = (await stateRow(_keyA))!;
      expect(persisted['backoff_calculated_at'], now.toIso8601String());
      expect(
        persisted['next_attempt_at'],
        now.add(delay).toIso8601String(),
      );

      final reopened = await reopen(queue);
      final later = now.add(const Duration(seconds: 10));
      final again = await reopened.nextHead(later) as DeliveryHeadInBackoff;
      expect(again.nextAttemptAt.isAtSameMomentAs(now.add(delay)), isTrue);
      expect(await stateRow(_keyA), persisted);

      final due = await reopened.nextHead(now.add(delay));
      expect(due, isA<DeliveryHeadEligible>());
    });

    test('a regression never extends the delay beyond the ceiling', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await seedState(
        _keyA,
        attemptCount: 9,
        nextAttemptAt: now.add(const Duration(days: 2)).toIso8601String(),
      );

      final head = await delivery.nextHead(now) as DeliveryHeadInBackoff;

      // The stored deadline is implausibly far and has no calculation instant:
      // the delay is recomputed from the attempt count (ceiling: 15 min).
      expect(
        head.nextAttemptAt.isAtSameMomentAs(
          now.add(const Duration(minutes: 15)),
        ),
        isTrue,
      );
      expect(
        (await stateRow(_keyA))!['next_attempt_at'],
        now.add(const Duration(minutes: 15)).toIso8601String(),
      );
    });

    test('a calculated delay above the ceiling is capped on regression',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      final calculatedAt = now.add(const Duration(hours: 1));
      await seedState(
        _keyA,
        attemptCount: 2,
        nextAttemptAt:
            calculatedAt.add(const Duration(hours: 5)).toIso8601String(),
      );
      final extra = await openDatabase();
      await extra.database.update(
        e4DeliveryStateTable,
        <String, Object?>{
          'backoff_calculated_at': calculatedAt.toIso8601String(),
        },
      );
      await extra.close();

      final head = await delivery.nextHead(now) as DeliveryHeadInBackoff;

      expect(
        head.nextAttemptAt.isAtSameMomentAs(
          now.add(const Duration(minutes: 15)),
        ),
        isTrue,
      );
    });

    test('an invalid deadline is repaired durably and does not postpone',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await seedState(_keyA, attemptCount: 3, nextAttemptAt: 'garbage');

      final result = await delivery.nextHead(now) as DeliveryHeadEligible;

      expect(result.head.attemptCount, 3);
      final row = (await stateRow(_keyA))!;
      expect(row['attempt_count'], 3);
      expect(row['next_attempt_at'], isNull);
      expect(row['backoff_calculated_at'], isNull);
    });
  });

  // **Validates: Requirements RF-15.10–12, RF-16, RF-17, RF-18, RNF-05**
  group('task 64.6 durable definitive-decision mark and local removal', () {
    Future<PersistentDeliveryQueue> reopen(
      CoordinatedPersistentOccurrenceQueue queue,
    ) async {
      await queue.close();
      final reopened = openQueue();
      addTearDown(reopened.close);
      await reopened.bootstrap();
      return PersistentDeliveryQueue(reopened);
    }

    test('marks the decision durably and keeps row, JPEG and anchor', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await delivery.recordRecoverableFailure(
        _keyA,
        now,
        now.add(const Duration(seconds: 5)),
      );

      expect(
        await delivery.recordDefinitiveDecision(
          _keyA,
          DeliveryDisposition.created,
        ),
        DeliveryMutationResult.applied,
      );

      final row = (await stateRow(_keyA))!;
      expect(row['pending_local_disposition'], 'created');
      expect(row['attempt_count'], 1);
      expect(row['next_attempt_at'], isNull);
      expect(row['backoff_calculated_at'], isNull);
      expect((await queue.listPending()).length, 1);
      expect(await queue.readAcceptedAnchor(), isNotNull);

      final reopened = await reopen(queue);
      final head = await reopened.nextHead(now) as DeliveryHeadPendingCleanup;
      expect(head.disposition, DeliveryDisposition.created);
      expect(head.head.idempotencyKey, _keyA);
      expect(head.dueAt, isNull);
    });

    test('creates the state row for an item that never failed', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));

      await delivery.recordDefinitiveDecision(
        _keyA,
        DeliveryDisposition.conflict,
      );

      final row = (await stateRow(_keyA))!;
      expect(row['attempt_count'], 0);
      expect(row['pending_local_disposition'], 'conflict');
    });

    test('is idempotent, refuses another disposition and reports unknown keys',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await delivery.recordDefinitiveDecision(
        _keyA,
        DeliveryDisposition.alreadyExisting,
      );

      expect(
        await delivery.recordDefinitiveDecision(
          _keyA,
          DeliveryDisposition.alreadyExisting,
        ),
        DeliveryMutationResult.applied,
      );
      expect(
        await delivery.recordDefinitiveDecision(
          _keyA,
          DeliveryDisposition.imageTooLarge,
        ),
        DeliveryMutationResult.storageFailure,
      );
      expect(
        (await stateRow(_keyA))!['pending_local_disposition'],
        'alreadyExisting',
      );
      expect(
        await delivery.recordDefinitiveDecision(
          _keyB,
          DeliveryDisposition.created,
        ),
        DeliveryMutationResult.notFound,
      );
      expect(await stateRow(_keyB), isNull);
    });

    test('a crash before the mark leaves the item eligible for resending',
        () async {
      final (queue, _) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));

      final reopened = await reopen(queue);

      expect(await reopened.nextHead(now), isA<DeliveryHeadEligible>());
    });

    test(
        'after a crash, finishes only the local removal with a persisted '
        'pause and without any delivery configuration', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await queue.persist(_simple(_keyB, red: 2));
      final firstImage = (await queue.listPending()).first.record.image;
      await delivery.pause(
        PausedDeliveryDecision(DeliveryPauseReason.authentication),
      );
      await delivery.recordDefinitiveDecision(
        _keyA,
        DeliveryDisposition.created,
      );

      final reopened = await reopen(queue);
      final head = await reopened.nextHead(now) as DeliveryHeadPendingCleanup;
      final removed =
          await reopened.completePendingLocalRemoval(head.head.idempotencyKey);

      expect(removed, isA<QueueOccurrenceRemoved>());
      expect((removed as QueueOccurrenceRemoved).snapshot.pendingCount, 1);
      expect(await stateRow(_keyA), isNull);
      expect(
        await PrivateDurableImageStore.at(sandbox).inspect(firstImage),
        isNot(DurableImageIntegrity.valid),
      );
      final next = await reopened.nextHead(now) as DeliveryHeadEligible;
      expect(next.head.idempotencyKey, _keyB);
      expect(await reopened.readControl(), isA<DeliveryControlPaused>());
    });

    test('keeps the cooldown anchor after the last item is removed', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      final anchor = await queue.readAcceptedAnchor();
      await delivery.recordDefinitiveDecision(
        _keyA,
        DeliveryDisposition.invalidContract,
      );

      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemoved>(),
      );

      expect(await delivery.nextHead(now), isA<DeliveryQueueEmpty>());
      final kept = await queue.readAcceptedAnchor();
      expect(kept?.queueSequence, anchor?.queueSequence);
      expect(kept?.detectedAtIso8601, anchor?.detectedAtIso8601);
    });

    test('removal is idempotent for an already removed item', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      await delivery.recordDefinitiveDecision(
        _keyA,
        DeliveryDisposition.created,
      );
      await delivery.completePendingLocalRemoval(_keyA);

      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceNotFound>(),
      );
    });

    test('refuses to remove an item without a recorded decision', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));

      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemovalFailed>(),
      );
      expect((await queue.listPending()).length, 1);
      expect(await delivery.nextHead(now), isA<DeliveryHeadEligible>());
    });

    test('reports failures as typed results when the queue is unavailable',
        () async {
      final future = await databaseFactoryFfi.openDatabase(databasePath);
      await future.setVersion(e2QueueDatabaseVersion + 1);
      await future.close();
      final (_, delivery) = await readyQueue();

      expect(
        await delivery.recordDefinitiveDecision(
          _keyA,
          DeliveryDisposition.created,
        ),
        DeliveryMutationResult.storageFailure,
      );
      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemovalFailed>(),
      );
    });
  });

  // **Validates: Requirements RF-15.10–12, RF-17, RF-18, RNF-05**
  group('task 64.7 bounded cleanup retry after a failed removal', () {
    Future<PersistentDeliveryQueue> reopen(
      CoordinatedPersistentOccurrenceQueue queue,
    ) async {
      await queue.close();
      final reopened = openQueue();
      addTearDown(reopened.close);
      await reopened.bootstrap();
      return PersistentDeliveryQueue(reopened, clock: _FixedClock(now));
    }

    Future<(CoordinatedPersistentOccurrenceQueue, PersistentDeliveryQueue)>
        decidedQueue({Clock? clock}) async {
      final queue = openQueue();
      addTearDown(queue.close);
      await queue.bootstrap();
      final delivery =
          PersistentDeliveryQueue(queue, clock: clock ?? _FixedClock(now));
      await queue.persist(_simple(_keyA, red: 1));
      await delivery.recordRecoverableFailure(
        _keyA,
        now,
        now.add(const Duration(seconds: 5)),
      );
      await delivery.recordDefinitiveDecision(
        _keyA,
        DeliveryDisposition.created,
      );
      return (queue, delivery);
    }

    test('persists the attempt and the next instant, keeping the decision',
        () async {
      final (queue, delivery) = await decidedQueue();
      final due = now.add(DeliveryBackoffPolicy.delayFor(1));

      expect(
        await delivery.recordCleanupFailure(_keyA, now, due),
        DeliveryMutationResult.applied,
      );

      final row = (await stateRow(_keyA))!;
      expect(row['cleanup_attempt_count'], 1);
      expect(row['next_cleanup_at'], due.toIso8601String());
      expect(row['pending_local_disposition'], 'created');
      expect(row['attempt_count'], 1);
      expect(row['next_attempt_at'], isNull);
      expect((await queue.listPending()).length, 1);
      expect(await queue.readAcceptedAnchor(), isNotNull);
    });

    test('the deferred cleanup survives a force-stop and is not looped',
        () async {
      final (queue, delivery) = await decidedQueue();
      final due = now.add(DeliveryBackoffPolicy.delayFor(1));
      await delivery.recordCleanupFailure(_keyA, now, due);

      final reopened = await reopen(queue);
      final waiting =
          await reopened.nextHead(now) as DeliveryHeadPendingCleanup;

      expect(waiting.dueAt, due);
      expect(waiting.head.cleanupAttemptCount, 1);
      expect(waiting.disposition, DeliveryDisposition.created);
      // Repeated evaluations before the instant keep returning the same wait.
      final again = await reopened.nextHead(now) as DeliveryHeadPendingCleanup;
      expect(again.dueAt, due);

      final ready = await reopened.nextHead(due) as DeliveryHeadPendingCleanup;
      expect(ready.dueAt, isNull);
    });

    test('follows the bounded progression and never exceeds the ceiling',
        () async {
      final (_, delivery) = await decidedQueue();
      var at = now;
      for (var attempt = 1; attempt <= 9; attempt++) {
        final delay = DeliveryBackoffPolicy.delayFor(attempt);
        expect(
          await delivery.recordCleanupFailure(_keyA, at, at.add(delay)),
          DeliveryMutationResult.applied,
        );
        expect((await stateRow(_keyA))!['cleanup_attempt_count'], attempt);
        at = at.add(delay);
      }
      await expectLater(
        delivery.recordCleanupFailure(
          _keyA,
          at,
          at.add(DeliveryBackoffPolicy.maxDelay + const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
      await expectLater(
        delivery.recordCleanupFailure(_keyA, at, at),
        throwsArgumentError,
      );
      expect((await stateRow(_keyA))!['cleanup_attempt_count'], 9);
    });

    test('a manual retry cannot run the removal before the instant', () async {
      final due = now.add(DeliveryBackoffPolicy.delayFor(1));
      final (queue, early) = await decidedQueue(clock: _FixedClock(now));
      await early.recordCleanupFailure(_keyA, now, due);

      expect(
        await early.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemovalFailed>(),
      );
      expect((await queue.listPending()).length, 1);
      var row = (await stateRow(_keyA))!;
      expect(row['cleanup_attempt_count'], 1);
      expect(row['next_cleanup_at'], due.toIso8601String());

      // A failure reported for that refused call does not move the instant.
      expect(
        await early.recordCleanupFailure(
          _keyA,
          now,
          now.add(const Duration(seconds: 6)),
        ),
        DeliveryMutationResult.storageFailure,
      );
      row = (await stateRow(_keyA))!;
      expect(row['cleanup_attempt_count'], 1);
      expect(row['next_cleanup_at'], due.toIso8601String());

      final late = PersistentDeliveryQueue(queue, clock: _FixedClock(due));
      expect(
        await late.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemoved>(),
      );
      expect(await stateRow(_keyA), isNull);
    });

    test('the cleanup stays local: pause and backoff do not affect it',
        () async {
      final (queue, delivery) = await decidedQueue();
      await delivery.pause(
        PausedDeliveryDecision(DeliveryPauseReason.authentication),
      );
      final due = now.add(DeliveryBackoffPolicy.delayFor(1));
      await delivery.recordCleanupFailure(_keyA, now, due);

      final reopened = await reopen(queue);
      expect(await reopened.nextHead(now), isA<DeliveryHeadPendingCleanup>());
      expect(await reopened.nextHead(due), isA<DeliveryHeadPendingCleanup>());
      expect(await reopened.readControl(), isA<DeliveryControlPaused>());
      // Never turned back into something sendable.
      expect(
        (await stateRow(_keyA))!['pending_local_disposition'],
        'created',
      );
    });

    test('refuses a cleanup failure without a decision or for unknown keys',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_simple(_keyA, red: 1));
      final due = now.add(const Duration(seconds: 5));

      expect(
        await delivery.recordCleanupFailure(_keyA, now, due),
        DeliveryMutationResult.storageFailure,
      );
      expect(await stateRow(_keyA), isNull);
      expect(
        await delivery.recordCleanupFailure(_keyB, now, due),
        DeliveryMutationResult.notFound,
      );
    });

    test('a regressed clock never defers the cleanup beyond the ceiling',
        () async {
      final (queue, _) = await decidedQueue();
      final farFuture = now.add(const Duration(days: 30));
      final extra = await openDatabase();
      await extra.database.update(
        e4DeliveryStateTable,
        <String, Object?>{
          'cleanup_attempt_count': 2,
          'next_cleanup_at': farFuture.toIso8601String(),
        },
      );
      await extra.close();

      final reopened = await reopen(queue);
      final waiting =
          await reopened.nextHead(now) as DeliveryHeadPendingCleanup;
      final expected = now.add(DeliveryBackoffPolicy.delayFor(2));

      expect(waiting.dueAt, expected);
      expect(
        (await stateRow(_keyA))!['next_cleanup_at'],
        expected.toIso8601String(),
      );
      // Re-evaluating keeps the persisted, reconciled value.
      expect(
        (await reopened.nextHead(now) as DeliveryHeadPendingCleanup).dueAt,
        expected,
      );
    });

    test('an unreadable deadline is repaired and the cleanup runs now',
        () async {
      final (queue, delivery) = await decidedQueue();
      final extra = await openDatabase();
      await extra.database.update(
        e4DeliveryStateTable,
        <String, Object?>{'next_cleanup_at': 'not-a-date'},
      );
      await extra.close();

      final head = await delivery.nextHead(now) as DeliveryHeadPendingCleanup;

      expect(head.dueAt, isNull);
      expect((await stateRow(_keyA))!['next_cleanup_at'], isNull);
      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemoved>(),
      );
      expect((await queue.listPending()), isEmpty);
    });
  });
}

final class _FixedClock implements Clock {
  const _FixedClock(this._value);

  final DateTime _value;

  @override
  DateTime now() => _value;
}

InMemoryOccurrence _simple(String key, {required int red}) => _occurrence(
      key: key,
      detectedAt: DateTime.utc(2025, 1, 2, 3, 4, red),
      bytes: _jpeg(width: 8, height: 8, red: red),
      width: 8,
      height: 8,
    );

InMemoryOccurrence _occurrence({
  required String key,
  required DateTime detectedAt,
  required List<int> bytes,
  required int width,
  required int height,
  double? speedMetersPerSecond,
}) {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: key,
    detectedAt: detectedAt,
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      accuracyMeters: null,
      speedMetersPerSecond: speedMetersPerSecond,
    ),
    image: _Lease(bytes, width, height),
  );
}

List<int> _jpeg({required int width, required int height, required int red}) {
  final image = image_codec.Image(width: width, height: height);
  image.clear(image_codec.ColorRgb8(red, 32, 16));
  return image_codec.encodeJpg(image, quality: 85);
}

final class _Lease implements PreparedImageLease {
  _Lease(this.bytes, this.width, this.height);

  final List<int> bytes;
  final int width;
  final int height;
  var _hasOwnership = true;

  @override
  bool get hasOwnership => _hasOwnership;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: bytes.length,
        width: width,
        height: height,
        quality: 85,
      );

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(bytes);

  @override
  PreparedImageLease promoteOwnership() => this;

  @override
  Future<void> withdrawOwnership() async {
    _hasOwnership = false;
  }

  @override
  Future<void> dispose() => withdrawOwnership();
}
