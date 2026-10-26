import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
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
  late QueueDatabase database;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e2_removal_protocol_');
    database = await _openDatabase(sandbox);
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {
      // A recovery queue can own and close the database in a crash-state test.
    }
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  // **Validates: Requirements RF-12.9, RF-12.11, RNF-03.5, RNF-05.4,
  // RNF-06.2, RNF-06.10–11**
  group('task 44.4 internal removal protocol', () {
    test('removes a confirmed record and treats a repeated key as idempotent',
        () async {
      final record = _record(token: 'a');
      await _insert(database, record);
      final store = _RemovalStore();
      const driver = CrashConsistentQueueMutationDriver();

      final removed = await driver.remove(
        database,
        store,
        record.idempotencyKey,
      );
      final repeated = await driver.remove(
        database,
        store,
        record.idempotencyKey,
      );

      expect(removed, isA<QueueOccurrenceRemoved>());
      expect(repeated, isA<QueueOccurrenceNotFound>());
      expect(await _rows(database), isEmpty);
      expect(store.canonicalPresent, isFalse);
      expect(store.deletingMarkerPresent, isFalse);
      expect(store.events, <String>['inspect', 'mark', 'finalize']);
    });

    test('leaves state untouched when the key is absent or image is invalid',
        () async {
      final missingStore = _RemovalStore();
      final missing = await const CrashConsistentQueueMutationDriver().remove(
        database,
        missingStore,
        _record(token: 'a').idempotencyKey,
      );

      final record = _record(token: 'b');
      await _insert(database, record);
      final invalidStore =
          _RemovalStore(integrity: DurableImageIntegrity.invalid);
      final invalid = await const CrashConsistentQueueMutationDriver().remove(
        database,
        invalidStore,
        record.idempotencyKey,
      );

      expect(missing, isA<QueueOccurrenceNotFound>());
      expect(missingStore.events, isEmpty);
      expect(invalid, isA<QueueOccurrenceRemovalFailed>());
      expect(invalidStore.events, <String>['inspect']);
      expect(await _rows(database), hasLength(1));
      expect(invalidStore.canonicalPresent, isTrue);
      expect(invalidStore.deletingMarkerPresent, isFalse);
    });

    test('retains the row and marker for failures before commit', () async {
      final cases = <(
        String name,
        Future<void> Function(
            QueueDatabase database, _RemovalStore store) configure,
      )>[
        (
          'marker rename',
          (_, store) async => store.failMarking = true,
        ),
        (
          'reference revalidation',
          (database, store) async {
            store.onMarked = () => database.database.update(
                  e2QueueTable,
                  <String, Object?>{
                    QueueRecordColumns.imageSha256: _digest(const <int>[9]),
                  },
                  where: '${QueueRecordColumns.idempotencyKey} = ?',
                  whereArgs: <Object>[_record(token: 'c').idempotencyKey],
                );
          },
        ),
        (
          'transactional delete',
          (database, _) => database.database.execute('''
CREATE TRIGGER reject_removal_delete
BEFORE DELETE ON $e2QueueTable
BEGIN SELECT RAISE(ABORT, 'injected_removal_delete_failure'); END
'''),
        ),
      ];

      for (final (name, configure) in cases) {
        await database.database.delete(e2QueueTable);
        final record = _record(token: 'c');
        await _insert(database, record);
        final store = _RemovalStore();
        await configure(database, store);

        final result = await const CrashConsistentQueueMutationDriver().remove(
          database,
          store,
          record.idempotencyKey,
        );

        expect(result, isA<QueueOccurrenceRemovalFailed>(), reason: name);
        expect(await _rows(database), hasLength(1), reason: name);
        if (name == 'marker rename') {
          expect(store.canonicalPresent, isTrue, reason: name);
          expect(store.deletingMarkerPresent, isFalse, reason: name);
        } else {
          expect(store.canonicalPresent, isFalse, reason: name);
          expect(store.deletingMarkerPresent, isTrue, reason: name);
        }
        if (name == 'transactional delete') {
          await database.database.execute('DROP TRIGGER reject_removal_delete');
        }
      }
    });

    test('confirms the database removal when post-commit marker cleanup fails',
        () async {
      final record = _record(token: 'd');
      await _insert(database, record);
      final store = _RemovalStore(failFinalization: true);

      final result = await const CrashConsistentQueueMutationDriver().remove(
        database,
        store,
        record.idempotencyKey,
      );

      expect(result, isA<QueueOccurrenceRemoved>());
      expect(await _rows(database), isEmpty);
      expect(store.canonicalPresent, isFalse);
      expect(store.deletingMarkerPresent, isTrue,
          reason: 'the recognized post-commit marker is recoverable');
      expect(store.events, <String>['inspect', 'mark', 'finalize']);
    });

    test(
        'recovers before and after commit, degrades collisions, and is repeatable',
        () async {
      const codec = E2DurableImageNameCodec();
      final beforeCommit = _record(token: 'e');
      final collision = _record(token: 'f');
      await _insert(database, beforeCommit);
      await _insert(database, collision);
      final namespace = await _namespace(sandbox);
      final beforeCommitMarker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: beforeCommit.image.relativeName,
          operationToken: _token('1'),
        )}',
      );
      final postCommitMarker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: 'e2i_${_token('2')}.jpg',
          operationToken: _token('3'),
        )}',
      );
      final collisionCanonical = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${collision.image.relativeName}',
      );
      final collisionMarker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${codec.deletingMarker(
          canonicalName: collision.image.relativeName,
          operationToken: _token('4'),
        )}',
      );
      await beforeCommitMarker.writeAsBytes(_bytes, flush: true);
      await postCommitMarker.writeAsBytes(_bytes, flush: true);
      await collisionCanonical.writeAsBytes(_bytes, flush: true);
      await collisionMarker.writeAsBytes(const <int>[9, 9, 9], flush: true);
      await database.close();

      final first = await _recover(sandbox);
      final second = await _recover(sandbox);
      final beforeCommitCanonical = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${beforeCommit.image.relativeName}',
      );

      for (final recovery in <_Recovery>[first, second]) {
        expect(recovery.snapshot.health, QueueHealth.degraded);
        expect(recovery.snapshot.pendingCount, 2);
        expect(recovery.snapshot.attentionCount, 1);
        expect(
          recovery.pending.map((item) => item.idempotencyKey),
          <String>[beforeCommit.idempotencyKey, collision.idempotencyKey],
        );
      }
      expect(await beforeCommitMarker.exists(), isFalse);
      expect(await beforeCommitCanonical.readAsBytes(), _bytes);
      expect(await postCommitMarker.exists(), isFalse,
          reason: 'a marker without a row completes the removal');
      expect(await collisionCanonical.readAsBytes(), _bytes);
      expect(await collisionMarker.readAsBytes(), const <int>[9, 9, 9]);
    });
  });
}

const List<int> _bytes = <int>[0, 0, 0];

Future<QueueDatabase> _openDatabase(Directory sandbox) => QueueDatabase.open(
      factory: databaseFactoryFfi,
      path: '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName',
    );

Future<void> _insert(QueueDatabase database, QueueRecordProjection record) =>
    database.database.insert(
      e2QueueTable,
      const QueueRecordMapper().toInsertMap(record),
    );

Future<List<Map<String, Object?>>> _rows(QueueDatabase database) =>
    database.database.query(e2QueueTable);

Future<Directory> _namespace(Directory sandbox) async {
  final namespace = Directory(
    '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
  );
  await namespace.create(recursive: true);
  return namespace;
}

Future<_Recovery> _recover(Directory sandbox) async {
  final queue = CoordinatedPersistentOccurrenceQueue(
    imageStore: PrivateDurableImageStore.at(sandbox),
    databaseOpener: () => _openDatabase(sandbox),
  );
  final snapshot = await queue.bootstrap();
  final pending = await queue.listPending();
  await queue.close();
  return _Recovery(snapshot: snapshot, pending: pending);
}

QueueRecordProjection _record({required String token}) {
  final image = PersistedImageProjection(
    relativeName: 'e2i_${_token(token)}.jpg',
    mimeType: 'image/jpeg',
    byteLength: _bytes.length,
    sha256: _digest(_bytes),
    width: 2,
    height: 1,
    quality: 85,
  );
  return QueueRecordProjection(
    queueSequence: 0,
    idempotencyKey: '${token}23e4567-e89b-42d3-a456-426614174000',
    detectedAtIso8601: '2025-01-02T03:04:05.000Z',
    latitude: -23.5505,
    longitude: -46.6333,
    accuracyMeters: null,
    speedKmh: null,
    confidence: 1,
    defectClass: 'pothole',
    image: image,
  );
}

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

String _token(String character) => List<String>.filled(32, character).join();

final class _Recovery {
  const _Recovery({required this.snapshot, required this.pending});

  final QueueSnapshot snapshot;
  final List<ReconstructedPendingOccurrence> pending;
}

final class _RemovalStore implements DurableImageStore {
  _RemovalStore({
    this.integrity = DurableImageIntegrity.valid,
    this.failFinalization = false,
  });

  final DurableImageIntegrity integrity;
  final bool failFinalization;
  final List<String> events = <String>[];
  bool canonicalPresent = true;
  bool deletingMarkerPresent = false;
  bool failMarking = false;
  Future<void> Function()? onMarked;

  @override
  Future<DurableImageIntegrity> inspect(PersistedImageProjection image) async {
    events.add('inspect');
    return integrity;
  }

  @override
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  ) async {
    events.add('mark');
    if (failMarking) {
      throw StateError('injected_marker_failure');
    }
    canonicalPresent = false;
    deletingMarkerPresent = true;
    await onMarked?.call();
    return _RemovalDeletion(this);
  }

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) =>
      throw UnimplementedError();

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) =>
      throw UnimplementedError();

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) =>
      Stream<List<int>>.value(_bytes);

  @override
  Future<void> delete(PersistedImageProjection image) =>
      throw UnimplementedError();

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

final class _RemovalDeletion implements DurableImageDeletion {
  const _RemovalDeletion(this._store);

  final _RemovalStore _store;

  @override
  Future<void> finalizeAfterCommit() async {
    _store.events.add('finalize');
    if (_store.failFinalization) {
      throw StateError('injected_marker_cleanup_failure');
    }
    _store.deletingMarkerPresent = false;
  }
}
