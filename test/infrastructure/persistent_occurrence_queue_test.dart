import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_record_mapper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory sandbox;
  late String databasePath;
  final openDatabases = <QueueDatabase>[];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e2_queue_coordinator_');
    databasePath = '${sandbox.path}${Platform.pathSeparator}'
        '$e2QueueDatabaseName';
  });

  tearDown(() async {
    for (final database in openDatabases) {
      try {
        await database.close();
      } catch (_) {
        // The queue may already own and close this database.
      }
    }
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<QueueDatabase> openDatabase() async {
    final database = await QueueDatabase.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
    openDatabases.add(database);
    return database;
  }

  group('task 41 queue bootstrap and single-writer coordination', () {
    // **Validates: Requirements RF-12.2–5, RNF-05.2–4, RNF-06.9–11**
    test(
      'reads confirmed rows before exclusively reconciling recognized crash artifacts',
      () async {
        final database = await openDatabase();
        const mapper = QueueRecordMapper();
        final retained = _record(sequence: 1, token: 'a');
        await database.database.insert(
          e2QueueTable,
          mapper.toInsertMap(retained),
        );

        final store = PrivateDurableImageStore.at(sandbox);
        final namespace = Directory(
          '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
        );
        await namespace.create(recursive: true);
        const codec = E2DurableImageNameCodec();
        final referencedDeleting = codec.deletingMarker(
          canonicalName: retained.image.relativeName,
          operationToken: _opaqueToken('b'),
        );
        final unreferencedDeleting = codec.deletingMarker(
          canonicalName: 'e2i_${_opaqueToken('c')}.jpg',
          operationToken: _opaqueToken('d'),
        );
        final staging = 'e2s_${_opaqueToken('e')}.staging';
        final orphanCanonical = 'e2i_${_opaqueToken('f')}.jpg';

        await File(
          '${namespace.path}${Platform.pathSeparator}$referencedDeleting',
        ).writeAsBytes(const <int>[0, 0, 0]);
        await File(
          '${namespace.path}${Platform.pathSeparator}$unreferencedDeleting',
        ).writeAsBytes(<int>[2]);
        await File(
          '${namespace.path}${Platform.pathSeparator}$staging',
        ).writeAsBytes(<int>[3]);
        await File(
          '${namespace.path}${Platform.pathSeparator}$orphanCanonical',
        ).writeAsBytes(<int>[4]);
        await database.close();

        final queue = CoordinatedPersistentOccurrenceQueue(
          imageStore: store,
          databaseOpener: openDatabase,
        );
        addTearDown(queue.close);

        final snapshot = await queue.bootstrap();

        expect(snapshot.health, QueueHealth.ready);
        expect(snapshot.pendingCount, 1);
        expect(await queue.listPending(), hasLength(1));
        expect(
          await File(
            '${namespace.path}${Platform.pathSeparator}'
            '${retained.image.relativeName}',
          ).readAsBytes(),
          <int>[0, 0, 0],
        );
        expect(
          await File(
            '${namespace.path}${Platform.pathSeparator}$referencedDeleting',
          ).exists(),
          isFalse,
        );
        expect(
          await File(
            '${namespace.path}${Platform.pathSeparator}$unreferencedDeleting',
          ).exists(),
          isFalse,
        );
        expect(
          await File('${namespace.path}${Platform.pathSeparator}$staging')
              .exists(),
          isFalse,
        );
        expect(
          await File(
            '${namespace.path}${Platform.pathSeparator}$orphanCanonical',
          ).exists(),
          isFalse,
        );
      },
    );

    // **Validates: Requirements RF-12.2–5, RNF-03.5, RNF-05.2–4,
    // RNF-06.9–11**
    test(
      'streams every referenced image and degrades without discarding missing, malformed, or divergent records',
      () async {
        final database = await openDatabase();
        const mapper = QueueRecordMapper();
        final valid = _record(sequence: 1, token: 'a');
        final missing = _record(sequence: 2, token: 'b');
        final sizeMismatch = _record(sequence: 3, token: 'c');
        final digestMismatch = _record(sequence: 4, token: 'd');
        final invalidName = _record(
          sequence: 5,
          token: 'e',
          relativeName: 'unrecognized-image.jpg',
        );
        for (final record in <QueueRecordProjection>[
          valid,
          missing,
          sizeMismatch,
          digestMismatch,
          invalidName,
        ]) {
          await database.database.insert(
            e2QueueTable,
            mapper.toInsertMap(record),
          );
        }

        final namespace = Directory(
          '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
        );
        await namespace.create(recursive: true);
        Future<void> writeImage(String name, List<int> bytes) => File(
              '${namespace.path}${Platform.pathSeparator}$name',
            ).writeAsBytes(bytes, flush: true);
        await writeImage(valid.image.relativeName, const <int>[0, 0, 0]);
        await writeImage(sizeMismatch.image.relativeName, const <int>[0, 0]);
        await writeImage(
            digestMismatch.image.relativeName, const <int>[1, 2, 3]);
        await writeImage(invalidName.image.relativeName, const <int>[0, 0, 0]);
        await database.close();

        final queue = CoordinatedPersistentOccurrenceQueue(
          imageStore: PrivateDurableImageStore.at(sandbox),
          databaseOpener: openDatabase,
        );
        addTearDown(queue.close);

        final snapshot = await queue.bootstrap();

        expect(snapshot.health, QueueHealth.degraded);
        expect(snapshot.pendingCount, 5);
        expect(snapshot.attentionCount, 4);
        expect(await queue.listPending(), hasLength(5));
        expect(
          await File(
            '${namespace.path}${Platform.pathSeparator}'
            '${sizeMismatch.image.relativeName}',
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            '${namespace.path}${Platform.pathSeparator}'
            '${digestMismatch.image.relativeName}',
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            '${namespace.path}${Platform.pathSeparator}'
            '${invalidName.image.relativeName}',
          ).exists(),
          isTrue,
        );
      },
    );

    // **Validates: Requirements RF-12.3, RF-12.5, RNF-03.5,
    // RNF-03.10, RNF-05.3**
    test('shares one bootstrap execution across concurrent callers', () async {
      final openGate = Completer<void>();
      var openCount = 0;
      final snapshots = <QueueSnapshot>[];
      final queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: _FakeDurableImageStore(),
        databaseOpener: () async {
          openCount++;
          await openGate.future;
          return openDatabase();
        },
      );
      final subscription = queue.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await queue.close();
      });

      final first = queue.bootstrap();
      final second = queue.bootstrap();
      final third = queue.bootstrap();

      expect(identical(first, second), isTrue);
      expect(identical(second, third), isTrue);
      expect(openCount, 0);
      await _pumpEventQueue();
      expect(openCount, 1);

      openGate.complete();
      final results = await Future.wait(<Future<QueueSnapshot>>[
        first,
        second,
        third,
      ]);

      expect(results.map((snapshot) => snapshot.health),
          everyElement(QueueHealth.ready));
      expect(openCount, 1);
      expect(
        snapshots.map((snapshot) => snapshot.health),
        <QueueHealth>[QueueHealth.initializing, QueueHealth.ready],
      );
    });

    // **Validates: Requirements RF-12.3, RF-12.7–8, RF-23.9,
    // RNF-04.2–3, RNF-05.3**
    test('reports unavailable and shares a controlled explicit retry',
        () async {
      final retryGate = Completer<void>();
      var openCount = 0;
      final logs = <String>[];
      final snapshots = <QueueSnapshot>[];
      final queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: _FakeDurableImageStore(),
        databaseOpener: () async {
          openCount++;
          if (openCount == 1) {
            throw const FileSystemException('private database unavailable');
          }
          await retryGate.future;
          return openDatabase();
        },
        logger: logs.add,
      );
      final subscription = queue.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await queue.close();
      });

      final failed = await queue.bootstrap();
      expect(failed.health, QueueHealth.unavailable);
      expect(failed.pendingCount, 0);
      await expectLater(
        queue.countPending(),
        throwsA(isA<QueueUnavailableException>()),
      );

      final retry = queue.retryBootstrap();
      final sharedRetry = queue.retryBootstrap();
      expect(identical(retry, sharedRetry), isTrue);
      await _pumpEventQueue();
      expect(openCount, 2);

      retryGate.complete();
      expect((await retry).health, QueueHealth.ready);
      expect(await sharedRetry, same(await retry));
      expect(logs, hasLength(1));
      expect(logs.single, contains('error=FileSystemException'));
      expect(logs.single, isNot(contains(databasePath)));
      expect(
        snapshots.map((snapshot) => snapshot.health),
        <QueueHealth>[
          QueueHealth.initializing,
          QueueHealth.unavailable,
          QueueHealth.initializing,
          QueueHealth.ready,
        ],
      );
    });

    // **Validates: Requirements RF-12.3, RF-12.7–8, RF-23.9,
    // RNF-04.2–3, RNF-05.3**
    test('requires explicit retry and leaves stable queue states untouched',
        () async {
      var openCount = 0;
      final queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: _FakeDurableImageStore(),
        databaseOpener: () async {
          openCount++;
          if (openCount == 1) {
            throw const FileSystemException('private database unavailable');
          }
          return openDatabase();
        },
      );
      addTearDown(queue.close);

      final unavailable = await queue.bootstrap();
      expect(unavailable.health, QueueHealth.unavailable);
      expect(openCount, 1);

      final repeatedBootstrap = await queue.bootstrap();
      expect(repeatedBootstrap, same(unavailable));
      expect(openCount, 1, reason: 'normal bootstrap must not retry a failure');

      final ready = await queue.retryBootstrap();
      expect(ready.health, QueueHealth.ready);
      expect(openCount, 2);

      final unnecessaryRetry = await queue.retryBootstrap();
      expect(unnecessaryRetry, same(ready));
      expect(openCount, 2, reason: 'a ready queue must not be reinitialized');
    });

    // **Validates: Requirements RF-08.3–5, RF-11.8, RF-12.1–2,
    // RF-12.4, RF-12.7–8, RF-12.10–11, RNF-03.5, RNF-05.1–5,
    // RNF-06.3, RNF-06.9–11**
    test(
      'confirms an equivalent key without a new row, image, count, or snapshot and preserves the first pending record on conflict',
      () async {
        final imageStore = _InMemoryDurableImageStore();
        final snapshots = <QueueSnapshot>[];
        final queue = CoordinatedPersistentOccurrenceQueue(
          imageStore: imageStore,
          databaseOpener: openDatabase,
        );
        final subscription = queue.snapshots.listen(snapshots.add);
        addTearDown(() async {
          await subscription.cancel();
          await queue.close();
        });

        await queue.bootstrap();
        final first = _persistableOccurrence(<int>[1, 2, 3, 4]);
        final firstResult = await queue.persist(first);
        final firstRecord = (await queue.listPending()).single.record;

        final equivalent = await queue.persist(
          _persistableOccurrence(<int>[1, 2, 3, 4]),
        );
        expect(firstResult, isA<OccurrencePersisted>());
        expect(equivalent, isA<OccurrenceAlreadyPersistedEquivalent>());
        expect(
          (equivalent as OccurrenceAlreadyPersistedEquivalent)
              .snapshot
              .pendingCount,
          1,
        );
        expect(imageStore.stageCalls, 1);
        expect(imageStore.publishCalls, 1);
        expect(await queue.countPending(), 1);
        expect(
          snapshots.map((snapshot) => snapshot.pendingCount),
          <int>[0, 0, 1],
        );

        final conflict = await queue.persist(
          _persistableOccurrence(<int>[4, 3, 2, 1]),
        );
        final preservedRecord = (await queue.listPending()).single.record;
        expect(conflict, isA<OccurrenceIdentityConflict>());
        expect(imageStore.stageCalls, 1);
        expect(imageStore.publishCalls, 1);
        expect(await queue.countPending(), 1);
        expect(preservedRecord.queueSequence, firstRecord.queueSequence);
        expect(preservedRecord.idempotencyKey, firstRecord.idempotencyKey);
        expect(
            preservedRecord.image.relativeName, firstRecord.image.relativeName);
        expect(preservedRecord.image.sha256, firstRecord.image.sha256);
        expect(imageStore.canonicalBytes, <int>[1, 2, 3, 4]);
        expect(
          snapshots.map((snapshot) => snapshot.pendingCount),
          <int>[0, 0, 1],
        );
      },
    );

    // **Validates: Requirements RF-12.3, RF-12.5, RNF-03.5,
    // RNF-03.10, RNF-05.3**
    test('public reads await the confirmed snapshot from an active retry',
        () async {
      final recovery = _BlockingRecovery();
      var openCount = 0;
      final queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: _FakeDurableImageStore(),
        databaseOpener: () async {
          openCount++;
          if (openCount == 1) {
            throw const FileSystemException('private database unavailable');
          }
          return openDatabase();
        },
        recovery: recovery,
      );
      addTearDown(queue.close);

      expect((await queue.bootstrap()).health, QueueHealth.unavailable);

      final retry = queue.retryBootstrap();
      await recovery.started.future;
      final count = queue.countPending();
      final pending = queue.listPending();
      var countCompleted = false;
      var pendingCompleted = false;
      unawaited(count.whenComplete(() => countCompleted = true));
      unawaited(pending.whenComplete(() => pendingCompleted = true));
      await _pumpEventQueue();

      expect(countCompleted, isFalse);
      expect(pendingCompleted, isFalse);

      recovery.release.complete();
      expect((await retry).health, QueueHealth.ready);
      expect(await count, 0);
      expect(await pending, isEmpty);
    });

    // **Validates: Requirements RF-05.5, RF-12.3, RF-12.5,
    // RNF-05.3–4**
    test('publishes aggregate degraded state from confirmed rows only',
        () async {
      final database = await openDatabase();
      const mapper = QueueRecordMapper();
      await database.database.insert(
        e2QueueTable,
        mapper.toInsertMap(_record(sequence: 99, token: '1')),
      );
      await database.database.insert(
        e2QueueTable,
        mapper.toInsertMap(_record(sequence: 100, token: '2')),
      );
      await database.close();

      final imageStore = _FakeDurableImageStore(failedSweepOperations: 1);
      final snapshots = <QueueSnapshot>[];
      final queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: imageStore,
        databaseOpener: openDatabase,
      );
      final subscription = queue.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await queue.close();
      });

      final snapshot = await queue.bootstrap();

      expect(snapshot.health, QueueHealth.degraded);
      expect(snapshot.pendingCount, 2);
      expect(snapshot.attentionCount, 1);
      expect(
        snapshots.map((item) => item.health),
        <QueueHealth>[QueueHealth.initializing, QueueHealth.degraded],
      );
      expect(imageStore.lastReferencedNames, hasLength(2));
      expect(await queue.countPending(), 2);
      final pending = await queue.listPending();
      expect(pending.map((item) => item.queueSequence), <int>[1, 2]);
      expect(() => pending.add(pending.first), throwsUnsupportedError);
    });

    // **Validates: Requirements RF-05.5, RF-12.5, RNF-05.4**
    test('publishes counts derived from confirmed rows after mutations',
        () async {
      final queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: _FakeDurableImageStore(),
        databaseOpener: openDatabase,
        mutationDriver: _RecordingMutationDriver(),
      );
      final snapshots = <QueueSnapshot>[];
      final subscription = queue.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await queue.close();
      });

      expect((await queue.bootstrap()).pendingCount, 0);
      final persisted = await queue.persist(_occurrence());
      expect(persisted, isA<OccurrencePersisted>());
      expect((persisted as OccurrencePersisted).snapshot.pendingCount, 1);

      expect(await queue.countPending(), 1);
      expect(await queue.listPending(), hasLength(1));

      final removed = await queue.removeInternal(_occurrence().idempotencyKey);
      expect(removed, isA<QueueOccurrenceRemoved>());
      expect((removed as QueueOccurrenceRemoved).snapshot.pendingCount, 0);

      expect(
        snapshots.map(
          (snapshot) => (health: snapshot.health, count: snapshot.pendingCount),
        ),
        <({QueueHealth health, int count})>[
          (health: QueueHealth.initializing, count: 0),
          (health: QueueHealth.ready, count: 0),
          (health: QueueHealth.ready, count: 1),
          (health: QueueHealth.ready, count: 0),
        ],
      );
    });

    // **Validates: Requirements RF-12.5, RF-12.9, RNF-03.5, RNF-05.4**
    test(
      'publishes the reduced count only after removal confirmation under the shared single-writer',
      () async {
        final mutations = _RecordingMutationDriver(blockRemoval: true);
        final snapshots = <QueueSnapshot>[];
        final queue = CoordinatedPersistentOccurrenceQueue(
          imageStore: _FakeDurableImageStore(),
          databaseOpener: openDatabase,
          mutationDriver: mutations,
        );
        final subscription = queue.snapshots.listen(snapshots.add);
        addTearDown(() async {
          await subscription.cancel();
          await queue.close();
        });

        await queue.bootstrap();
        await queue.persist(_occurrence());
        expect(await queue.countPending(), 1);

        final removal = queue.removeInternal(_occurrence().idempotencyKey);
        await mutations.removalStarted.future;
        final queuedCount = queue.countPending();
        var countCompleted = false;
        unawaited(queuedCount.whenComplete(() => countCompleted = true));
        await _pumpEventQueue();

        expect(countCompleted, isFalse);
        expect(
          snapshots.map((snapshot) => snapshot.pendingCount),
          <int>[0, 0, 1],
        );

        mutations.releaseRemoval.complete();
        final result = await removal;
        expect(result, isA<QueueOccurrenceRemoved>());
        expect((result as QueueOccurrenceRemoved).snapshot.pendingCount, 0);
        expect(await queuedCount, 0);
        expect(
          snapshots.map((snapshot) => snapshot.pendingCount),
          <int>[0, 0, 1, 0],
        );
        expect(mutations.events, <String>[
          'persist-start',
          'persist-end',
          'remove-start',
          'remove-end',
        ]);
      },
    );

    // **Validates: Requirements RF-12.3, RF-12.7–8, RNF-03.5,
    // RNF-03.10, RNF-05.1–4**
    test('recovery excludes persistence and public reads until confirmed',
        () async {
      final recovery = _BlockingRecovery();
      final mutations = _RecordingMutationDriver();
      final queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: _FakeDurableImageStore(),
        databaseOpener: openDatabase,
        recovery: recovery,
        mutationDriver: mutations,
      );
      addTearDown(queue.close);

      final bootstrap = queue.bootstrap();
      await recovery.started.future;
      final persistence = queue.persist(_occurrence());
      final read = queue.listPending();
      var persistenceCompleted = false;
      var readCompleted = false;
      unawaited(persistence.whenComplete(() => persistenceCompleted = true));
      unawaited(read.whenComplete(() => readCompleted = true));
      await _pumpEventQueue();

      expect(mutations.events, isEmpty);
      expect(persistenceCompleted, isFalse);
      expect(readCompleted, isFalse);

      recovery.release.complete();
      expect((await bootstrap).health, QueueHealth.ready);
      expect(await persistence, isA<OccurrencePersisted>());
      expect(await read, hasLength(1));
      expect(
        <String>[...recovery.events, ...mutations.events],
        containsAllInOrder(<String>[
          'recovery-start',
          'recovery-end',
          'persist-start',
          'persist-end',
        ]),
      );
    });

    // **Validates: Requirements RF-12.3, RF-12.5, RF-12.7–8,
    // RNF-03.5, RNF-03.10, RNF-05.1–5**
    test('serializes mutations and reads and closes after acquired work',
        () async {
      final mutations = _RecordingMutationDriver(blockPersistence: true);
      final queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: _FakeDurableImageStore(),
        databaseOpener: openDatabase,
        mutationDriver: mutations,
      );
      addTearDown(queue.close);
      await queue.bootstrap();

      final persistence = queue.persist(_occurrence());
      await mutations.persistenceStarted.future;
      final countAfterPersistence = queue.countPending();
      final removal = queue.removeInternal(_occurrence().idempotencyKey);
      var readCompleted = false;
      var removalCompleted = false;
      unawaited(
        countAfterPersistence.whenComplete(() => readCompleted = true),
      );
      unawaited(removal.whenComplete(() => removalCompleted = true));
      await _pumpEventQueue();

      expect(readCompleted, isFalse);
      expect(removalCompleted, isFalse);
      mutations.releasePersistence.complete();

      expect(await persistence, isA<OccurrencePersisted>());
      expect(await countAfterPersistence, 1);
      expect(await removal, isA<QueueOccurrenceRemoved>());
      expect(mutations.events, <String>[
        'persist-start',
        'persist-end',
        'remove-start',
        'remove-end',
      ]);
      expect(await queue.countPending(), 0);

      final closeMutations = _RecordingMutationDriver(blockPersistence: true);
      final closeQueue = CoordinatedPersistentOccurrenceQueue(
        imageStore: _FakeDurableImageStore(),
        databaseOpener: openDatabase,
        mutationDriver: closeMutations,
      );
      await closeQueue.bootstrap();
      final acquiredPersistence = closeQueue.persist(_occurrence());
      await closeMutations.persistenceStarted.future;
      final closing = closeQueue.close();
      var closeCompleted = false;
      unawaited(closing.whenComplete(() => closeCompleted = true));
      await _pumpEventQueue();
      expect(closeCompleted, isFalse);

      closeMutations.releasePersistence.complete();
      expect(await acquiredPersistence, isA<OccurrencePersisted>());
      await closing;
      expect(closeCompleted, isTrue);
      await expectLater(
        closeQueue.countPending(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('task 43.5 recovery reopening crash boundaries', () {
    // **Validates: Requirements RF-08.4–5, RF-12.2–5, RF-12.8, RNF-03.5,
    // RNF-05.2–4, RNF-06.3, RNF-06.9–11**
    test(
        'reopening removes stale staging only and preserves external artifacts',
        () async {
      final namespace = await _namespace(sandbox);
      final staging = File(
        '${namespace.path}${Platform.pathSeparator}'
        'e2s_${_opaqueToken('a')}.staging',
      );
      final unknown = File(
        '${namespace.path}${Platform.pathSeparator}operator-notes.txt',
      );
      final external = File(
        '${sandbox.path}${Platform.pathSeparator}'
        'e2i_${_opaqueToken('b')}.jpg',
      );
      await staging.writeAsBytes(const <int>[1]);
      await unknown.writeAsBytes(const <int>[2]);
      await external.writeAsBytes(const <int>[3]);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );

      expect(recovered.first.health, QueueHealth.ready);
      expect(recovered.second.health, QueueHealth.ready);
      expect(recovered.first.pendingCount, 0);
      expect(recovered.second.pendingCount, 0);
      expect(await staging.exists(), isFalse);
      expect(await unknown.readAsBytes(), <int>[2]);
      expect(await external.readAsBytes(), <int>[3]);
    });

    // **Validates: Requirements RF-12.2–5, RF-12.8, RNF-05.2–4,
    // RNF-06.3, RNF-06.9–11**
    test('reopening retires a recognized canonical orphan without a row',
        () async {
      final namespace = await _namespace(sandbox);
      final orphan = File(
        '${namespace.path}${Platform.pathSeparator}'
        'e2i_${_opaqueToken('a')}.jpg',
      );
      await orphan.writeAsBytes(const <int>[1, 2, 3]);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );

      expect(recovered.first.health, QueueHealth.ready);
      expect(recovered.second.health, QueueHealth.ready);
      expect(recovered.secondPending, isEmpty);
      expect(await orphan.exists(), isFalse);
    });

    // **Validates: Requirements RF-08.4–5, RF-12.2–5, RF-12.8,
    // RNF-03.5, RNF-05.2–4, RNF-06.3, RNF-06.9–11**
    test('reopening restores a deleting marker when its row is retained',
        () async {
      const codec = E2DurableImageNameCodec();
      final record = _record(sequence: 1, token: 'a');
      await _insertRecord(openDatabase, record);
      final namespace = await _namespace(sandbox);
      final marker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: record.image.relativeName,
          operationToken: _opaqueToken('b'),
        )}',
      );
      await marker.writeAsBytes(const <int>[0, 0, 0]);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );
      final canonical = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${record.image.relativeName}',
      );

      expect(recovered.first.health, QueueHealth.ready);
      expect(recovered.second.health, QueueHealth.ready);
      expect(recovered.secondPending.single.record.idempotencyKey,
          record.idempotencyKey);
      expect(await marker.exists(), isFalse);
      expect(await canonical.readAsBytes(), <int>[0, 0, 0]);
    });

    // **Validates: Requirements RF-12.3–5, RF-12.9, RF-12.11, RNF-03.5,
    // RNF-05.4, RNF-06.2, RNF-06.10–11**
    test('reopening reconciles deletion markers without losing pending rows',
        () async {
      const codec = E2DurableImageNameCodec();
      final restoredRecord = _record(sequence: 1, token: 'a');
      final collisionRecord = _record(sequence: 2, token: 'b');
      await _insertRecord(openDatabase, restoredRecord);
      await _insertRecord(openDatabase, collisionRecord);

      final namespace = await _namespace(sandbox);
      final restoredMarker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: restoredRecord.image.relativeName,
          operationToken: _opaqueToken('c'),
        )}',
      );
      final completedRemovalMarker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: 'e2i_${_opaqueToken('d')}.jpg',
          operationToken: _opaqueToken('e'),
        )}',
      );
      final collisionCanonical = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${collisionRecord.image.relativeName}',
      );
      final collisionMarker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: collisionRecord.image.relativeName,
          operationToken: _opaqueToken('f'),
        )}',
      );
      await restoredMarker.writeAsBytes(const <int>[0, 0, 0]);
      await completedRemovalMarker.writeAsBytes(const <int>[1, 2, 3]);
      await collisionCanonical.writeAsBytes(const <int>[0, 0, 0]);
      await collisionMarker.writeAsBytes(const <int>[9, 9, 9]);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );

      for (final snapshot in <QueueSnapshot>[
        recovered.first,
        recovered.second,
      ]) {
        expect(snapshot.health, QueueHealth.degraded);
        expect(snapshot.pendingCount, 2);
        expect(snapshot.attentionCount, 1);
      }
      expect(
        recovered.secondPending.map((item) => item.record.idempotencyKey),
        <String>[
          restoredRecord.idempotencyKey,
          collisionRecord.idempotencyKey,
        ],
      );
      expect(await restoredMarker.exists(), isFalse);
      expect(
        await File(
          '${namespace.path}${Platform.pathSeparator}'
          '${restoredRecord.image.relativeName}',
        ).readAsBytes(),
        <int>[0, 0, 0],
      );
      expect(await completedRemovalMarker.exists(), isFalse);
      expect(await collisionCanonical.readAsBytes(), <int>[0, 0, 0]);
      expect(await collisionMarker.readAsBytes(), <int>[9, 9, 9]);
    });

    // **Validates: Requirements RF-08.4–5, RF-12.2–5, RF-12.8,
    // RNF-03.5, RNF-05.2–4, RNF-06.3, RNF-06.9–11**
    test('reopening preserves and reconstructs an intact confirmed row',
        () async {
      final record = _record(sequence: 1, token: 'a');
      await _insertRecord(openDatabase, record);
      final canonical = File(
        '${(await _namespace(sandbox)).path}${Platform.pathSeparator}'
        '${record.image.relativeName}',
      );
      await canonical.writeAsBytes(const <int>[0, 0, 0]);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );

      expect(recovered.first.health, QueueHealth.ready);
      expect(recovered.second.health, QueueHealth.ready);
      expect(recovered.firstPending.single.record.idempotencyKey,
          record.idempotencyKey);
      expect(recovered.secondPending.single.record.detectedAtIso8601,
          record.detectedAtIso8601);
      expect(recovered.secondPending.single.record.image.sha256,
          record.image.sha256);
      expect(await canonical.readAsBytes(), <int>[0, 0, 0]);
    });

    // **Validates: Requirements RF-12.2–5, RF-12.8, RNF-03.5,
    // RNF-05.2–4, RNF-06.3, RNF-06.9–11**
    test('reopening preserves a row without its image as a degraded record',
        () async {
      final record = _record(sequence: 1, token: 'a');
      await _insertRecord(openDatabase, record);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );

      for (final snapshot in <QueueSnapshot>[
        recovered.first,
        recovered.second,
      ]) {
        expect(snapshot.health, QueueHealth.degraded);
        expect(snapshot.pendingCount, 1);
        expect(snapshot.attentionCount, 1);
      }
      expect(recovered.firstPending.single.record.idempotencyKey,
          record.idempotencyKey);
      expect(recovered.secondPending.single.record.idempotencyKey,
          record.idempotencyKey);
    });

    // **Validates: Requirements RF-08.4–5, RF-12.2–5, RF-12.8,
    // RNF-03.5, RNF-05.2–4, RNF-06.3, RNF-06.9–11**
    test('reopening preserves a digest-divergent row and canonical image',
        () async {
      final record = _record(sequence: 1, token: 'a');
      await _insertRecord(openDatabase, record);
      final canonical = File(
        '${(await _namespace(sandbox)).path}${Platform.pathSeparator}'
        '${record.image.relativeName}',
      );
      const divergentBytes = <int>[3, 2, 1];
      await canonical.writeAsBytes(divergentBytes);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );

      expect(recovered.first.health, QueueHealth.degraded);
      expect(recovered.second.health, QueueHealth.degraded);
      expect(recovered.second.pendingCount, 1);
      expect(recovered.second.attentionCount, 1);
      expect(recovered.secondPending.single.record.image.sha256,
          record.image.sha256);
      expect(await canonical.readAsBytes(), divergentBytes);
    });

    // **Validates: Requirements RF-12.2–5, RF-12.8, RNF-03.5,
    // RNF-05.2–4, RNF-06.3, RNF-06.9–11**
    test('reopening preserves a deleting collision and degrades safely',
        () async {
      const codec = E2DurableImageNameCodec();
      final record = _record(sequence: 1, token: 'a');
      await _insertRecord(openDatabase, record);
      final namespace = await _namespace(sandbox);
      final canonical = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${record.image.relativeName}',
      );
      final marker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: record.image.relativeName,
          operationToken: _opaqueToken('b'),
        )}',
      );
      await canonical.writeAsBytes(const <int>[0, 0, 0]);
      await marker.writeAsBytes(const <int>[9, 9, 9]);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );

      for (final snapshot in <QueueSnapshot>[
        recovered.first,
        recovered.second,
      ]) {
        expect(snapshot.health, QueueHealth.degraded);
        expect(snapshot.pendingCount, 1);
        expect(snapshot.attentionCount, 1);
      }
      expect(await canonical.readAsBytes(), <int>[0, 0, 0]);
      expect(await marker.readAsBytes(), <int>[9, 9, 9]);
    });

    // **Validates: Requirements RF-12.3, RF-12.8, RNF-03.5,
    // RNF-05.3, RNF-06.3, RNF-06.9–11**
    test('repeated recovery converges after mixed pre-commit crash artifacts',
        () async {
      final namespace = await _namespace(sandbox);
      final staging = File(
        '${namespace.path}${Platform.pathSeparator}'
        'e2s_${_opaqueToken('a')}.staging',
      );
      final orphan = File(
        '${namespace.path}${Platform.pathSeparator}'
        'e2i_${_opaqueToken('b')}.jpg',
      );
      const codec = E2DurableImageNameCodec();
      final deleting = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: 'e2i_${_opaqueToken('c')}.jpg',
          operationToken: _opaqueToken('d'),
        )}',
      );
      await staging.writeAsBytes(const <int>[1]);
      await orphan.writeAsBytes(const <int>[2]);
      await deleting.writeAsBytes(const <int>[3]);

      final recovered = await _reopenTwice(
        sandbox: sandbox,
        databaseOpener: openDatabase,
      );

      expect(recovered.first.health, QueueHealth.ready);
      expect(recovered.second.health, QueueHealth.ready);
      expect(recovered.first.pendingCount, 0);
      expect(recovered.second.pendingCount, 0);
      expect(recovered.firstPending, isEmpty);
      expect(recovered.secondPending, isEmpty);
      expect(await staging.exists(), isFalse);
      expect(await orphan.exists(), isFalse);
      expect(await deleting.exists(), isFalse);
    });
  });
}

Future<void> _insertRecord(
  Future<QueueDatabase> Function() opener,
  QueueRecordProjection record,
) async {
  final database = await opener();
  try {
    await database.database.insert(
      e2QueueTable,
      const QueueRecordMapper().toInsertMap(record),
    );
  } finally {
    await database.close();
  }
}

Future<Directory> _namespace(Directory root) async {
  final namespace = Directory(
    '${root.path}${Platform.pathSeparator}$e2DurableImageNamespace',
  );
  await namespace.create(recursive: true);
  return namespace;
}

Future<
    ({
      QueueSnapshot first,
      QueueSnapshot second,
      List<ReconstructedPendingOccurrence> firstPending,
      List<ReconstructedPendingOccurrence> secondPending,
    })> _reopenTwice({
  required Directory sandbox,
  required QueueDatabaseOpener databaseOpener,
}) async {
  Future<
      ({
        QueueSnapshot snapshot,
        List<ReconstructedPendingOccurrence> pending,
      })> reopen() async {
    final queue = CoordinatedPersistentOccurrenceQueue(
      imageStore: PrivateDurableImageStore.at(sandbox),
      databaseOpener: databaseOpener,
    );
    try {
      final snapshot = await queue.bootstrap();
      final pending = await queue.listPending();
      return (snapshot: snapshot, pending: pending);
    } finally {
      await queue.close();
    }
  }

  final first = await reopen();
  final second = await reopen();
  expect(second.pending.map((item) => item.record.idempotencyKey),
      first.pending.map((item) => item.record.idempotencyKey));
  return (
    first: first.snapshot,
    second: second.snapshot,
    firstPending: first.pending,
    secondPending: second.pending,
  );
}

final class _BlockingRecovery implements QueueBootstrapRecovery {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  final List<String> events = <String>[];

  @override
  Future<QueueRecoveryResult> recover(
    QueueDatabase database,
    DurableImageStore imageStore,
  ) async {
    events.add('recovery-start');
    started.complete();
    await release.future;
    events.add('recovery-end');
    return QueueRecoveryResult(records: const <QueueRecordProjection>[]);
  }
}

final class _RecordingMutationDriver implements QueueMutationDriver {
  _RecordingMutationDriver({
    this.blockPersistence = false,
    this.blockRemoval = false,
  });

  final bool blockPersistence;
  final bool blockRemoval;
  final Completer<void> persistenceStarted = Completer<void>();
  final Completer<void> releasePersistence = Completer<void>();
  final Completer<void> removalStarted = Completer<void>();
  final Completer<void> releaseRemoval = Completer<void>();
  final List<String> events = <String>[];
  final QueueRecordMapper _mapper = const QueueRecordMapper();

  @override
  Future<OccurrenceAcceptanceResult> persist(
    QueueDatabase database,
    DurableImageStore imageStore,
    InMemoryOccurrence occurrence,
  ) async {
    events.add('persist-start');
    if (!persistenceStarted.isCompleted) {
      persistenceStarted.complete();
    }
    await database.database.insert(
      e2QueueTable,
      _mapper.toInsertMap(
        _recordFromOccurrence(
          occurrence,
          token: occurrence.idempotencyKey.startsWith('2') ? '2' : '1',
        ),
      ),
    );
    if (blockPersistence) {
      await releasePersistence.future;
    }
    events.add('persist-end');
    return const OccurrencePersisted(QueueSnapshot.initializing());
  }

  @override
  Future<QueueRemovalResult> remove(
    QueueDatabase database,
    DurableImageStore imageStore,
    String idempotencyKey,
  ) async {
    events.add('remove-start');
    final removed = await database.database.delete(
      e2QueueTable,
      where: '${QueueRecordColumns.idempotencyKey} = ?',
      whereArgs: <Object>[idempotencyKey],
    );
    if (!removalStarted.isCompleted) {
      removalStarted.complete();
    }
    if (blockRemoval) {
      await releaseRemoval.future;
    }
    events.add('remove-end');
    return removed == 0
        ? const QueueOccurrenceNotFound(QueueSnapshot.initializing())
        : const QueueOccurrenceRemoved(QueueSnapshot.initializing());
  }
}

final class _FakeDurableImageStore implements DurableImageStore {
  _FakeDurableImageStore({this.failedSweepOperations = 0});

  final int failedSweepOperations;
  Set<String> lastReferencedNames = <String>{};

  @override
  Future<DurableImageSweepResult> sweep(
    Set<String> referencedCanonicalNames,
  ) async {
    lastReferencedNames = Set<String>.unmodifiable(referencedCanonicalNames);
    return DurableImageSweepResult(
      removedStaging: 0,
      removedDeleting: 0,
      removedCanonical: 0,
      restoredDeleting: 0,
      failedOperations: failedSweepOperations,
    );
  }

  @override
  Future<void> delete(PersistedImageProjection image) async {}

  @override
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  ) async =>
      const CompletedDurableImageDeletion();

  @override
  Future<DurableImageIntegrity> inspect(PersistedImageProjection image) async =>
      DurableImageIntegrity.valid;

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) =>
      Stream<List<int>>.value(List<int>.filled(image.byteLength, 0));

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) {
    throw UnimplementedError();
  }

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) {
    throw UnimplementedError();
  }
}

String _opaqueToken(String character) =>
    List<String>.filled(32, character).join();

QueueRecordProjection _record({
  required int sequence,
  required String token,
  String? relativeName,
}) {
  const bytes = <int>[0, 0, 0];
  return QueueRecordProjection(
    queueSequence: sequence,
    idempotencyKey: '${token}23e4567-e89b-42d3-a456-426614174000',
    detectedAtIso8601: '2025-01-02T03:04:05.000Z',
    latitude: -23.5505,
    longitude: -46.6333,
    accuracyMeters: null,
    speedKmh: null,
    confidence: 1,
    defectClass: 'pothole',
    image: PersistedImageProjection(
      relativeName: relativeName ?? 'e2i_${token.padRight(32, '0')}.jpg',
      mimeType: 'image/jpeg',
      byteLength: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      width: 2,
      height: 1,
      quality: 85,
    ),
  );
}

QueueRecordProjection _recordFromOccurrence(
  InMemoryOccurrence occurrence, {
  required String token,
}) {
  final template = _record(sequence: 0, token: token);
  return QueueRecordProjection(
    queueSequence: 0,
    idempotencyKey: occurrence.idempotencyKey,
    detectedAtIso8601: occurrence.detectedAtIso8601,
    latitude: occurrence.latitude,
    longitude: occurrence.longitude,
    accuracyMeters: occurrence.accuracyMeters,
    speedKmh: occurrence.speedKmh,
    confidence: occurrence.confidence,
    defectClass: occurrence.defectClass,
    image: template.image,
  );
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

final class _OwnedImage implements OwnedPreparedImage {
  const _OwnedImage();

  @override
  Future<void> dispose() async {}
}

Future<void> _pumpEventQueue() => Future<void>.delayed(Duration.zero);

InMemoryOccurrence _persistableOccurrence(List<int> bytes) {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
    detectedAt: DateTime.utc(2025, 4, 12, 14, 30),
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      accuracyMeters: 4.5,
      speedMetersPerSecond: 8,
    ),
    image: _PreparedImageLease(bytes),
  );
}

final class _PreparedImageLease implements PreparedImageLease {
  _PreparedImageLease(List<int> bytes) : _bytes = List<int>.unmodifiable(bytes);

  final List<int> _bytes;

  @override
  bool get hasOwnership => true;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: _bytes.length,
        width: 2,
        height: 1,
        quality: 85,
      );

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(_bytes);

  @override
  PreparedImageLease promoteOwnership() => this;

  @override
  Future<void> withdrawOwnership() async {}

  @override
  Future<void> dispose() async {}
}

final class _InMemoryDurableImageStore implements DurableImageStore {
  static const _relativeName = 'e2i_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg';

  List<int>? _canonicalBytes;
  int stageCalls = 0;
  int publishCalls = 0;

  List<int> get canonicalBytes =>
      List<int>.unmodifiable(_canonicalBytes ?? const <int>[]);

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) async {
    stageCalls++;
    final bytes = <int>[];
    await for (final chunk in source.openRead()) {
      bytes.addAll(chunk);
    }
    return _InMemoryDurableImageStaging(
      store: this,
      bytes: bytes,
      metadata: source.metadata,
    );
  }

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) =>
      throw UnimplementedError();

  @override
  Future<void> delete(PersistedImageProjection image) async {
    _canonicalBytes = null;
  }

  @override
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  ) async {
    _canonicalBytes = null;
    return const CompletedDurableImageDeletion();
  }

  @override
  Future<DurableImageIntegrity> inspect(PersistedImageProjection image) async =>
      _canonicalBytes == null
          ? DurableImageIntegrity.missing
          : DurableImageIntegrity.valid;

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) {
    final bytes = _canonicalBytes;
    if (bytes == null) {
      return Stream<List<int>>.error(StateError('Missing canonical image.'));
    }
    return Stream<List<int>>.value(bytes);
  }

  @override
  Future<DurableImageSweepResult> sweep(
    Set<String> referencedCanonicalNames,
  ) async =>
      const DurableImageSweepResult(
        removedStaging: 0,
        removedDeleting: 0,
        removedCanonical: 0,
        restoredDeleting: 0,
        failedOperations: 0,
      );
}

final class _InMemoryDurableImageStaging implements DurableImageStaging {
  _InMemoryDurableImageStaging({
    required this.store,
    required List<int> bytes,
    required this.metadata,
  }) : _bytes = List<int>.unmodifiable(bytes);

  final _InMemoryDurableImageStore store;
  final List<int> _bytes;
  final PreparedImageMetadata metadata;
  var _published = false;

  @override
  Future<PersistedImageProjection> publishWithoutOverwrite() async {
    if (_published || store._canonicalBytes != null) {
      throw StateError('Canonical image already exists.');
    }
    _published = true;
    store.publishCalls++;
    store._canonicalBytes = _bytes;
    return PersistedImageProjection(
      relativeName: _InMemoryDurableImageStore._relativeName,
      mimeType: metadata.mimeType,
      byteLength: metadata.byteLength,
      sha256: sha256.convert(_bytes).toString(),
      width: metadata.width,
      height: metadata.height,
      quality: metadata.quality,
    );
  }

  @override
  Future<void> discard() async {}
}
