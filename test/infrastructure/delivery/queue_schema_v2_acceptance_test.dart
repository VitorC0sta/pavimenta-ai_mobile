import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/cooldown_policy.dart';
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
import 'package:pavimenta_ai_mobile/infrastructure/queue_record_mapper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/e4/fake_clock.dart';

const String _keyA = '123e4567-e89b-42d3-a456-426614174000';
const String _keyB = '223e4567-e89b-42d3-a456-426614174000';
const String _keyC = '323e4567-e89b-42d3-a456-426614174000';
const String _orphanKey = '423e4567-e89b-42d3-a456-426614174000';

/// Acceptance coverage of task 64.8.
///
/// Every scenario starts from a real temporary SQLite file created with the
/// schema v1 DDL, whose JPEGs are real files in the private durable store. The
/// production opener migrates it; nothing is mocked or replaced.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const mapper = QueueRecordMapper();
  late Directory sandbox;
  late String databasePath;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e4_schema_v2_accept_');
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

  /// Opens the file with the v1 layout only, exactly as a pre-E4 install.
  Future<Database> openV1Raw() => databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, version) => createE2QueueSchemaV1(database),
          singleInstance: false,
        ),
      );

  /// Opens the current file without migration side effects of the app code.
  Future<Database> openRaw() => databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );

  /// Builds a v1 database with [items] and their real JPEGs.
  Future<List<_V1Item>> seedV1(List<_V1Item> items) async {
    final store = PrivateDurableImageStore.at(sandbox);
    final database = await openV1Raw();
    try {
      for (final item in items) {
        final image = await store.promote(
          _Lease(item.bytes, item.width, item.height),
        );
        await database.insert(
          e2QueueTable,
          mapper.toInsertMap(
            QueueRecordProjection(
              queueSequence: 0,
              idempotencyKey: item.key,
              detectedAtIso8601: item.detectedAt,
              latitude: item.latitude,
              longitude: item.longitude,
              accuracyMeters: item.accuracyMeters,
              speedKmh: item.speedKmh,
              confidence: 1.0,
              defectClass: 'pothole',
              image: image,
            ),
          ),
        );
      }
      expect(await database.getVersion(), 1);
    } finally {
      await database.close();
    }
    return items;
  }

  Future<List<_V1Item>> seedThree() => seedV1(_threeItems());

  Future<CoordinatedPersistentOccurrenceQueue> bootstrapped() async {
    final queue = openQueue();
    addTearDown(queue.close);
    await queue.bootstrap();
    return queue;
  }

  /// Closes [queue] and reopens the same files, as after a force-stop.
  Future<(CoordinatedPersistentOccurrenceQueue, PersistentDeliveryQueue)>
      reopen(
    CoordinatedPersistentOccurrenceQueue queue, {
    Clock? clock,
  }) async {
    await queue.close();
    final reopened = openQueue();
    addTearDown(reopened.close);
    await reopened.bootstrap();
    return (
      reopened,
      PersistentDeliveryQueue(reopened, clock: clock ?? FakeClock(_t0)),
    );
  }

  Future<Map<String, Object?>?> stateRow(String key) async {
    final raw = await openRaw();
    try {
      final rows = await raw.query(
        e4DeliveryStateTable,
        where: 'idempotency_key = ?',
        whereArgs: <Object>[key],
      );
      return rows.isEmpty ? null : rows.single;
    } finally {
      await raw.close();
    }
  }

  Future<int> count(String table) async {
    final raw = await openRaw();
    try {
      final rows = await raw.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return rows.single['c']! as int;
    } finally {
      await raw.close();
    }
  }

  // **Validates: Requirements RF-09, RF-12.9–11, RNF-05, RNF-06.9–11**
  group('task 64.8 migration of a real temporary v1 database', () {
    test(
        'adds schema v2 keeping rows, DDL and JPEG files byte-identical and '
        'seeding the anchor with the greatest sequence', () async {
      final items = await seedThree();
      final v1 = await openV1Raw();
      final rowsBefore = await v1.query(
        e2QueueTable,
        orderBy: QueueRecordColumns.queueSequence,
      );
      final ddlBefore = await _tableDdl(v1);
      await v1.close();
      final filesBefore = await _namespaceFiles(sandbox);
      expect(filesBefore, hasLength(3));

      final queue = openQueue();
      addTearDown(queue.close);
      final snapshot = await queue.bootstrap();

      expect(snapshot.health, QueueHealth.ready);
      expect(snapshot.pendingCount, 3);
      expect(snapshot.attentionCount, 0);

      final raw = await openRaw();
      addTearDown(raw.close);
      expect(await raw.getVersion(), e2QueueDatabaseVersion);
      expect(
        await raw.query(e2QueueTable,
            orderBy: QueueRecordColumns.queueSequence),
        rowsBefore,
      );
      // E5 (task 79): the v3 rebuild only widens the confidence CHECK; the
      // rest of the E2 DDL is unchanged.
      expect(_asV1Ddl(await _tableDdl(raw)), ddlBefore);
      expect(await _namespaceFiles(sandbox), filesBefore);
      expect(await raw.query(e4DeliveryStateTable), isEmpty);
      expect(await raw.query(e4DeliveryControlTable), isEmpty);
      expect(await raw.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(await raw.query(e4AcceptedAnchorTable), <Map<String, Object?>>[
        <String, Object?>{
          'singleton_id': 1,
          'queue_sequence': 3,
          'detected_at': items[2].detectedAt,
          'latitude': items[2].latitude,
          'longitude': items[2].longitude,
        },
      ]);

      // The migrated pending items are delivered in the original FIFO order
      // with their untouched JPEG bytes.
      final delivery = PersistentDeliveryQueue(queue);
      final head = await delivery.nextHead(_t0) as DeliveryHeadEligible;
      expect(head.head.idempotencyKey, _keyA);
      expect(head.head.queueSequence, 1);
      expect(head.head.attemptCount, 0);
      expect(head.payload.detectedAtIso8601, items[0].detectedAt);
      expect(
        await delivery.openImage(head).expand((chunk) => chunk).toList(),
        items[0].bytes,
      );
      expect(
        (await queue.listPending()).map((entry) => entry.idempotencyKey),
        <String>[_keyA, _keyB, _keyC],
      );
    });

    test('opening the migrated database again changes nothing', () async {
      await seedThree();
      final first = await bootstrapped();
      final delivery = PersistentDeliveryQueue(first);
      await delivery.recordRecoverableFailure(
        _keyA,
        _t0,
        _t0.add(const Duration(seconds: 5)),
      );
      final stateBefore = await stateRow(_keyA);
      final anchorBefore = await first.readAcceptedAnchor();
      final filesBefore = await _namespaceFiles(sandbox);

      final (second, _) = await reopen(first);

      expect((await second.readAcceptedAnchor())?.queueSequence, 3);
      expect(
        (await second.readAcceptedAnchor())?.detectedAtIso8601,
        anchorBefore?.detectedAtIso8601,
      );
      expect(await stateRow(_keyA), stateBefore);
      expect(await _namespaceFiles(sandbox), filesBefore);
      expect(await second.countPending(), 3);
    });

    test('a failed migration rolls back and leaves v1 rows and JPEGs intact',
        () async {
      await seedThree();
      final v1 = await openV1Raw();
      // A conflicting structure makes the last migration statement fail.
      await v1.execute('CREATE TABLE $e4AcceptedAnchorTable (x INTEGER)');
      final rowsBefore = await v1.query(
        e2QueueTable,
        orderBy: QueueRecordColumns.queueSequence,
      );
      await v1.close();
      final filesBefore = await _namespaceFiles(sandbox);

      final queue = openQueue();
      addTearDown(queue.close);
      final snapshot = await queue.bootstrap();

      expect(snapshot.health, QueueHealth.unavailable);
      expect(
        await PersistentDeliveryQueue(queue).nextHead(_t0),
        isA<DeliveryQueueUnavailable>(),
      );

      final after = await openV1Raw();
      addTearDown(after.close);
      expect(await after.getVersion(), 1);
      expect(
        await after.query(
          e2QueueTable,
          orderBy: QueueRecordColumns.queueSequence,
        ),
        rowsBefore,
      );
      final tables = await after.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(
        tables.map((row) => row['name']),
        isNot(anyOf(
            contains(e4DeliveryStateTable), contains(e4DeliveryControlTable))),
      );
      expect(await _namespaceFiles(sandbox), filesBefore);
    });
  });

  // **Validates: Requirements RF-12.9–11, RNF-05, RNF-06.2–5, RNF-06.9–11**
  group('task 64.8 cascade and recovery on the migrated database', () {
    test('recovery drops only orphan state; removal cascades its own state',
        () async {
      final items = await seedThree();
      final first = await bootstrapped();
      final delivery = PersistentDeliveryQueue(first);
      for (final key in <String>[_keyA, _keyB]) {
        await delivery.recordRecoverableFailure(
          key,
          _t0,
          _t0.add(const Duration(seconds: 5)),
        );
      }
      await first.close();

      // A state row left by a connection that ran without enforcement.
      final raw = await openRaw();
      await raw.execute('PRAGMA foreign_keys = OFF');
      await raw.insert(e4DeliveryStateTable, <String, Object?>{
        'idempotency_key': _orphanKey,
        'attempt_count': 4,
      });
      await raw.close();
      expect(await count(e4DeliveryStateTable), 3);

      // Recovery is idempotent: two openings give the same result.
      var queue = openQueue();
      for (var run = 0; run < 2; run++) {
        await queue.close();
        queue = openQueue();
        addTearDown(queue.close);
        final snapshot = await queue.bootstrap();
        expect(snapshot.health, QueueHealth.ready);
        expect(await stateRow(_orphanKey), isNull);
        expect((await stateRow(_keyA))!['attempt_count'], 1);
        expect((await stateRow(_keyB))!['attempt_count'], 1);
        expect(await queue.countPending(), 3);
      }

      final imageB = (await queue.listPending())[1].record.image;
      final store = PrivateDurableImageStore.at(sandbox);
      expect(await store.inspect(imageB), DurableImageIntegrity.valid);

      expect(await queue.removeInternal(_keyB), isA<QueueOccurrenceRemoved>());

      expect(await stateRow(_keyB), isNull);
      expect(await stateRow(_keyA), isNotNull);
      expect(await store.inspect(imageB), isNot(DurableImageIntegrity.valid));
      expect(await _namespaceFiles(sandbox), hasLength(2));
      expect(
        (await queue.listPending()).map((entry) => entry.idempotencyKey),
        <String>[_keyA, _keyC],
      );
      final raw2 = await openRaw();
      addTearDown(raw2.close);
      expect(await raw2.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect((await queue.readAcceptedAnchor())?.queueSequence, 3);
      expect(
        (await queue.readAcceptedAnchor())?.detectedAtIso8601,
        items[2].detectedAt,
      );
    });
  });

  // **Validates: Requirements RF-15.10–12, RF-16, RF-17, RF-18, RNF-05**
  group('task 64.8 crash before and after the definitive decision', () {
    test(
        'a crash before the mark keeps the item queued with its retry and '
        'pause, and the JPEG still streams byte-identical', () async {
      final items = await seedThree();
      final queue = await bootstrapped();
      final delivery = PersistentDeliveryQueue(queue);
      final due = _t0.add(const Duration(seconds: 45));
      await delivery.recordRecoverableFailure(_keyA, _t0, due);
      await delivery.pause(
        PausedDeliveryDecision(
          DeliveryPauseReason.unexpectedResponse,
          unexpectedStatusCode: 302,
        ),
      );

      // Force-stop: the remote answer was never marked locally.
      final (reopened, afterCrash) = await reopen(queue);

      final waiting = await afterCrash.nextHead(_t0) as DeliveryHeadInBackoff;
      expect(waiting.head.idempotencyKey, _keyA);
      expect(waiting.head.attemptCount, 1);
      expect(waiting.nextAttemptAt.isAtSameMomentAs(due), isTrue);
      final control = await afterCrash.readControl() as DeliveryControlPaused;
      expect(control.reason, DeliveryPauseReason.unexpectedResponse);
      expect(control.unexpectedStatusCode, 302);
      expect((await stateRow(_keyA))!['pending_local_disposition'], isNull);
      // Without a mark the local cleanup is refused: nothing is removed.
      expect(
        await afterCrash.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemovalFailed>(),
      );
      expect(await reopened.countPending(), 3);

      final eligible = await afterCrash.nextHead(due) as DeliveryHeadEligible;
      expect(eligible.head.attemptCount, 1);
      expect(
        await afterCrash.openImage(eligible).expand((chunk) => chunk).toList(),
        items[0].bytes,
      );
    });

    test(
        'a crash after the mark completes only the local cleanup of every '
        'item, with no configuration and a persisted pause', () async {
      await seedThree();
      var queue = await bootstrapped();
      var delivery = PersistentDeliveryQueue(queue);
      await delivery.pause(
        PausedDeliveryDecision(DeliveryPauseReason.access),
      );
      final dispositions = <String, DeliveryDisposition>{
        _keyA: DeliveryDisposition.created,
        _keyB: DeliveryDisposition.conflict,
        _keyC: DeliveryDisposition.imageTooLarge,
      };
      final store = PrivateDurableImageStore.at(sandbox);
      final images = <String, PersistedImageProjection>{
        for (final entry in await queue.listPending())
          entry.idempotencyKey: entry.record.image,
      };

      var remaining = 3;
      for (final entry in dispositions.entries) {
        expect(
          await delivery.recordDefinitiveDecision(entry.key, entry.value),
          DeliveryMutationResult.applied,
        );

        // Force-stop between the mark and the removal.
        (queue, delivery) = await reopen(queue);

        final head = await delivery.nextHead(_t0) as DeliveryHeadPendingCleanup;
        expect(head.head.idempotencyKey, entry.key);
        expect(head.disposition, entry.value);
        expect(head.dueAt, isNull);
        expect(await delivery.readControl(), isA<DeliveryControlPaused>());

        // Only the queue is needed: no URL, key, transport or snapshot.
        final removed = await delivery.completePendingLocalRemoval(entry.key);

        expect(removed, isA<QueueOccurrenceRemoved>());
        remaining--;
        expect((removed as QueueOccurrenceRemoved).snapshot.pendingCount,
            remaining);
        expect(await stateRow(entry.key), isNull);
        expect(
          await store.inspect(images[entry.key]!),
          isNot(DurableImageIntegrity.valid),
        );
      }

      expect(await delivery.nextHead(_t0), isA<DeliveryQueueEmpty>());
      expect(await _namespaceFiles(sandbox), isEmpty);
      expect(await count(e4DeliveryStateTable), 0);
      expect((await queue.readAcceptedAnchor())?.queueSequence, 3);
      expect(await delivery.readControl(), isA<DeliveryControlPaused>());
    });

    test(
        'a removal that fails stays recoverable and is retried after a restart',
        () async {
      await seedThree();
      final clock = FakeClock(_t0);
      var queue = await bootstrapped();
      var delivery = PersistentDeliveryQueue(queue, clock: clock);
      final imageA = (await queue.listPending()).first.record.image;
      await delivery.recordDefinitiveDecision(
        _keyA,
        DeliveryDisposition.alreadyExisting,
      );
      final blocker = await openRaw();
      await blocker.execute('''
CREATE TRIGGER reject_e2_delete
BEFORE DELETE ON $e2QueueTable
BEGIN SELECT RAISE(ABORT, 'injected removal failure'); END
''');

      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemovalFailed>(),
      );
      final retryAt = _t0.add(DeliveryBackoffPolicy.delayFor(1));
      expect(
        await delivery.recordCleanupFailure(_keyA, _t0, retryAt),
        DeliveryMutationResult.applied,
      );

      // Nothing was lost by the failure: the row and the mark are intact and
      // the JPEG is only parked under its recoverable deleting marker (E2).
      expect(await queue.countPending(), 3);
      expect(await _namespaceFiles(sandbox), hasLength(3));
      final row = (await stateRow(_keyA))!;
      expect(row['pending_local_disposition'], 'alreadyExisting');
      expect(row['cleanup_attempt_count'], 1);
      // A manual retry before the instant is refused without touching it.
      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemovalFailed>(),
      );
      expect(await stateRow(_keyA), row);

      await blocker.execute('DROP TRIGGER reject_e2_delete');
      await blocker.close();
      (queue, delivery) = await reopen(queue, clock: clock);
      final waiting =
          await delivery.nextHead(_t0) as DeliveryHeadPendingCleanup;
      expect(waiting.dueAt, retryAt);
      // Recovery restored the parked JPEG, so the retry has all it needs.
      expect(
        await PrivateDurableImageStore.at(sandbox).inspect(imageA),
        DurableImageIntegrity.valid,
      );

      clock.set(retryAt);
      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemoved>(),
      );
      expect(await stateRow(_keyA), isNull);
      expect(await queue.countPending(), 2);
    });
  });

  // **Validates: Requirements RF-12.9–11, RF-16, RF-17, RNF-05, RNF-06.2–5**
  group('task 64.8 regressive clock with reopening', () {
    test('a retry calculated by a later clock is re-anchored once and kept',
        () async {
      await seedThree();
      final queue = await bootstrapped();
      final delivery = PersistentDeliveryQueue(queue);
      // Three attempts, the last computed while the clock was one hour ahead.
      final calculatedAt = _t0.add(const Duration(hours: 1));
      for (var attempt = 1; attempt <= 3; attempt++) {
        final delay = DeliveryBackoffPolicy.delayFor(attempt);
        await delivery.recordRecoverableFailure(
          _keyA,
          calculatedAt,
          calculatedAt.add(delay),
        );
      }
      final delay = DeliveryBackoffPolicy.delayFor(3);

      // The wall clock went back to _t0.
      final first = await delivery.nextHead(_t0) as DeliveryHeadInBackoff;
      expect(first.head.idempotencyKey, _keyA);
      expect(first.nextAttemptAt.isAtSameMomentAs(_t0.add(delay)), isTrue);
      final persisted = (await stateRow(_keyA))!;
      expect(persisted['backoff_calculated_at'], _t0.toIso8601String());
      expect(persisted['next_attempt_at'], _t0.add(delay).toIso8601String());

      // Force-stop: the reconciled values are what is read, not postponed
      // again, and later items never overtake the head meanwhile.
      final (_, reopened) = await reopen(queue);
      final again =
          await reopened.nextHead(_t0.add(const Duration(seconds: 10)))
              as DeliveryHeadInBackoff;
      expect(again.head.idempotencyKey, _keyA);
      expect(again.nextAttemptAt.isAtSameMomentAs(_t0.add(delay)), isTrue);
      expect(await stateRow(_keyA), persisted);

      final due =
          await reopened.nextHead(_t0.add(delay)) as DeliveryHeadEligible;
      expect(due.head.idempotencyKey, _keyA);
      expect(due.head.attemptCount, 3);
    });

    test('a cleanup scheduled by a later clock is re-anchored and not looped',
        () async {
      await seedThree();
      final clock = FakeClock(_t0.add(const Duration(hours: 1)));
      final queue = await bootstrapped();
      var delivery = PersistentDeliveryQueue(queue, clock: clock);
      await delivery.recordDefinitiveDecision(
          _keyA, DeliveryDisposition.created);
      final scheduledBy = clock.now();
      expect(
        await delivery.recordCleanupFailure(
          _keyA,
          scheduledBy,
          scheduledBy.add(DeliveryBackoffPolicy.delayFor(1)),
        ),
        DeliveryMutationResult.applied,
      );

      // The wall clock went back an hour before the force-stop.
      clock.set(_t0);
      final (reopened, afterStop) = await reopen(queue, clock: clock);
      delivery = afterStop;
      final reanchored = _t0.add(DeliveryBackoffPolicy.delayFor(1));

      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemovalFailed>(),
      );
      expect(
        (await stateRow(_keyA))!['next_cleanup_at'],
        reanchored.toIso8601String(),
      );
      final waiting =
          await delivery.nextHead(_t0) as DeliveryHeadPendingCleanup;
      expect(waiting.dueAt, reanchored);

      clock.advance(const Duration(seconds: 4));
      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemovalFailed>(),
      );
      clock.advance(const Duration(seconds: 1));
      expect(
        await delivery.completePendingLocalRemoval(_keyA),
        isA<QueueOccurrenceRemoved>(),
      );
      expect(await reopened.countPending(), 2);
      expect(await stateRow(_keyA), isNull);
    });
  });

  // **Validates: Requirements RF-09, RF-12.9–11, RNF-05, RNF-06.9–11**
  group('task 64.8 cooldown after the queue becomes empty', () {
    test(
        'the anchor seeded by the migration restores the cooldown after every '
        'item is delivered, removed and the app is reopened', () async {
      final items = await seedThree();
      var queue = await bootstrapped();
      var delivery = PersistentDeliveryQueue(queue);
      for (final key in <String>[_keyA, _keyB, _keyC]) {
        await delivery.recordDefinitiveDecision(
            key, DeliveryDisposition.created);
        expect(
          await delivery.completePendingLocalRemoval(key),
          isA<QueueOccurrenceRemoved>(),
        );
      }
      expect(await delivery.nextHead(_t0), isA<DeliveryQueueEmpty>());

      (queue, delivery) = await reopen(queue);

      expect(await queue.countPending(), 0);
      final anchor = await queue.readAcceptedAnchor();
      expect(anchor?.queueSequence, 3);
      expect(anchor?.detectedAtIso8601, items[2].detectedAt);

      final cooldown = CooldownPolicy();
      cooldown.restoreAcceptedAnchor(anchor);
      final detectedAt = DateTime.parse(items[2].detectedAt);
      final samePoint = ImmutableGeoPoint(
        latitude: items[2].latitude,
        longitude: items[2].longitude,
      );

      expect(
        cooldown
            .evaluate(detectedAt.add(const Duration(seconds: 4)), samePoint)
            .isBlocked,
        isTrue,
      );
      expect(
        cooldown
            .evaluate(detectedAt.add(const Duration(seconds: 5)), samePoint)
            .isAllowed,
        isTrue,
      );
      // Roughly 111 m north of the last accepted point within one second.
      expect(
        cooldown
            .evaluate(
              detectedAt.add(const Duration(seconds: 1)),
              ImmutableGeoPoint(
                latitude: items[2].latitude + 0.001,
                longitude: items[2].longitude,
              ),
            )
            .isAllowed,
        isTrue,
      );
    });

    test('a new accept moves the anchor and the next empty queue keeps it',
        () async {
      await seedThree();
      var queue = await bootstrapped();
      final delivery = PersistentDeliveryQueue(queue);
      for (final key in <String>[_keyA, _keyB, _keyC]) {
        await delivery.recordDefinitiveDecision(
            key, DeliveryDisposition.created);
        await delivery.completePendingLocalRemoval(key);
      }
      final accepted = DateTime.utc(2025, 2, 3, 4, 5, 6);
      final result = await queue.persist(
        _newOccurrence(_keyOrphanFreeKey, accepted),
      );
      expect(result, isA<OccurrencePersisted>());
      // The sequence continues after the migrated ones (AUTOINCREMENT).
      expect((await queue.readAcceptedAnchor())?.queueSequence, 4);

      await delivery.recordDefinitiveDecision(
        _keyOrphanFreeKey,
        DeliveryDisposition.alreadyExisting,
      );
      await delivery.completePendingLocalRemoval(_keyOrphanFreeKey);
      (queue, _) = await reopen(queue);

      expect(await queue.countPending(), 0);
      final anchor = await queue.readAcceptedAnchor();
      expect(anchor?.queueSequence, 4);
      expect(anchor?.detectedAtIso8601, accepted.toIso8601String());
    });
  });
}

const String _keyOrphanFreeKey = '523e4567-e89b-42d3-a456-426614174000';

final DateTime _t0 = DateTime.utc(2025, 3, 4, 5, 6, 7);

final class _V1Item {
  const _V1Item({
    required this.key,
    required this.detectedAt,
    required this.latitude,
    required this.longitude,
    required this.bytes,
    required this.width,
    required this.height,
    this.accuracyMeters,
    this.speedKmh,
  });

  final String key;
  final String detectedAt;
  final double latitude;
  final double longitude;
  final List<int> bytes;
  final int width;
  final int height;
  final double? accuracyMeters;
  final double? speedKmh;
}

List<_V1Item> _threeItems() => <_V1Item>[
      _V1Item(
        key: _keyA,
        detectedAt: '2025-01-02T03:04:05.678-03:00',
        latitude: -23.55052,
        longitude: -46.633308,
        accuracyMeters: 4.5,
        speedKmh: 30.5,
        bytes: _jpeg(width: 17, height: 11, red: 12),
        width: 17,
        height: 11,
      ),
      _V1Item(
        key: _keyB,
        detectedAt: '2025-01-02T03:05:00.000Z',
        latitude: -23.55060,
        longitude: -46.633400,
        speedKmh: 0,
        bytes: _jpeg(width: 9, height: 7, red: 40),
        width: 9,
        height: 7,
      ),
      _V1Item(
        key: _keyC,
        detectedAt: '2025-01-02T03:06:30.250Z',
        latitude: -23.55070,
        longitude: -46.633500,
        accuracyMeters: 0,
        bytes: _jpeg(width: 6, height: 6, red: 90),
        width: 6,
        height: 6,
      ),
    ];

InMemoryOccurrence _newOccurrence(String key, DateTime detectedAt) {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: key,
    detectedAt: detectedAt,
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      accuracyMeters: null,
      speedMetersPerSecond: null,
    ),
    image: _Lease(_jpeg(width: 8, height: 8, red: 3), 8, 8),
  );
}

/// Maps the v3 DDL of `pendingOccurrences` back to the v1 text: the rebuilt
/// table is renamed (SQLite quotes the name) and only its confidence CHECK
/// differs.
List<Map<String, Object?>> _asV1Ddl(List<Map<String, Object?>> rows) => [
      for (final row in rows)
        {
          ...row,
          'sql': (row['sql'] as String?)
              ?.replaceFirst(
                'CREATE TABLE "$e2QueueTable"',
                'CREATE TABLE $e2QueueTable',
              )
              .replaceFirst(
                "CHECK (typeof(${QueueRecordColumns.confidence}) = 'real' AND "
                    '${QueueRecordColumns.confidence} BETWEEN 0.0 AND 1.0)',
                'CHECK (${QueueRecordColumns.confidence} = 1.0)',
              ),
        },
    ];

/// Table and index definitions of the E2 table, for a byte-level comparison.
Future<List<Map<String, Object?>>> _tableDdl(Database database) {
  return database.rawQuery(
    'SELECT type, name, tbl_name, sql FROM sqlite_master '
    "WHERE tbl_name = '$e2QueueTable' ORDER BY type, name",
  );
}

/// Relative file name to bytes of every file in the durable image namespace.
Future<Map<String, List<int>>> _namespaceFiles(Directory sandbox) async {
  final namespace = Directory(
    '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
  );
  final files = <String, List<int>>{};
  if (!await namespace.exists()) {
    return files;
  }
  await for (final entry in namespace.list(followLinks: false)) {
    if (entry is File) {
      files[entry.uri.pathSegments.last] = await entry.readAsBytes();
    }
  }
  return files;
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
