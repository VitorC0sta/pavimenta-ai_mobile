import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory sandbox;
  late QueueDatabase database;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e2_fault_protocol_');
    database = await QueueDatabase.open(
      factory: databaseFactoryFfi,
      path: '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName',
    );
  });

  tearDown(() async {
    await database.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  // **Validates: Requirements RF-08.3–5, RF-11.8, RF-12.1–2, RF-12.4,
  // RF-12.7–8, RF-12.10–11, RNF-03.5, RNF-05.1–5, RNF-06.3, RNF-06.9–11**
  group('task 42.6 injected commit-protocol failures', () {
    test('preflight failure preserves the lease and creates no E2 artifact',
        () async {
      final lease = _Lease(const <int>[1, 2, 3]);
      await database.close();

      await expectLater(
        const CrashConsistentQueueMutationDriver().persist(
          database,
          _FaultStore(),
          _occurrence(lease),
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(lease.hasOwnership, isTrue);
      expect(lease.withdrawCalls, 0);
    });

    for (final phase in <_FaultPhase>[
      _FaultPhase.staging,
      _FaultPhase.copy,
      _FaultPhase.flush,
      _FaultPhase.hash,
      _FaultPhase.destination,
      _FaultPhase.rename,
    ]) {
      test('$phase failure rolls back staging without an acceptance', () async {
        final lease = _Lease(const <int>[1, 2, 3]);
        final store = _FaultStore(phase: phase);

        final result = await const CrashConsistentQueueMutationDriver().persist(
          database,
          store,
          _occurrence(lease),
        );

        expect(result, isA<OccurrenceTransactionalFailure>());
        expect(await _rows(database), isEmpty);
        expect(lease.hasOwnership, isTrue);
        expect(lease.withdrawCalls, 0);
        expect(store.canonical, isNull);
        expect(store.discardCalls,
            phase.index >= _FaultPhase.destination.index ? 1 : 0);
      });
    }

    test('insert and commit failures preserve the original row and lease',
        () async {
      for (final timing in <String>['BEFORE', 'AFTER']) {
        final lease = _Lease(const <int>[1, 2, 3]);
        await database.database.execute('''
CREATE TRIGGER reject_${timing.toLowerCase()}_insert
$timing INSERT ON $e2QueueTable
BEGIN SELECT RAISE(ABORT, 'injected_${timing.toLowerCase()}_failure'); END
''');

        final result = await const CrashConsistentQueueMutationDriver().persist(
          database,
          _FaultStore(),
          _occurrence(lease),
        );

        expect(result, isA<OccurrenceTransactionalFailure>(), reason: timing);
        expect(await _rows(database), isEmpty, reason: timing);
        expect(lease.hasOwnership, isTrue, reason: timing);
        await database.database.execute(
          'DROP TRIGGER reject_${timing.toLowerCase()}_insert',
        );
      }
    });

    test('post-insert recheck failure never accepts or withdraws its lease',
        () async {
      final lease = _Lease(const <int>[1, 2, 3]);
      final store = _FaultStore(phase: _FaultPhase.recheck);

      final result = await const CrashConsistentQueueMutationDriver().persist(
        database,
        store,
        _occurrence(lease),
      );

      expect(result, isA<OccurrenceTransactionalFailure>());
      expect(await _rows(database), hasLength(1));
      expect(store.canonical, isNotNull,
          reason: 'the committed state remains recoverable');
      expect(lease.hasOwnership, isTrue);
      expect(lease.withdrawCalls, 0);
    });

    test('lease withdrawal failure is non-fatal only after an intact commit',
        () async {
      final lease = _Lease(const <int>[1, 2, 3], failWithdrawal: true);
      final store = _FaultStore();

      final result = await const CrashConsistentQueueMutationDriver().persist(
        database,
        store,
        _occurrence(lease),
      );

      expect(result, isA<OccurrencePersisted>());
      expect(await _rows(database), hasLength(1));
      expect(store.canonical, isNotNull);
      expect(lease.withdrawCalls, 1);
      expect(lease.hasOwnership, isTrue,
          reason: 'cleanup failure cannot revoke the caller lease');
    });
  });

  // **Validates: Requirements RF-08.3–5, RF-12.1–2, RF-12.4, RF-12.7–8,
  // RF-12.10–11, RNF-03.5, RNF-05.1–5, RNF-06.9–11**
  test('same-key concurrency accepts once; same-sized different bytes conflict',
      () async {
    final store = _FaultStore();
    final queue = CoordinatedPersistentOccurrenceQueue(
      imageStore: store,
      databaseOpener: () async => database,
    );
    addTearDown(queue.close);
    await queue.bootstrap();

    final concurrent = await Future.wait(<Future<OccurrenceAcceptanceResult>>[
      queue.persist(_occurrence(_Lease(const <int>[1, 2, 3]))),
      queue.persist(_occurrence(_Lease(const <int>[1, 2, 3]))),
    ]);
    expect(concurrent.whereType<OccurrencePersisted>(), hasLength(1));
    expect(concurrent.whereType<OccurrenceAlreadyPersistedEquivalent>(),
        hasLength(1));
    expect(await queue.countPending(), 1);
    final original = (await queue.listPending()).single.record;

    final conflict = await queue.persist(
      _occurrence(_Lease(const <int>[3, 2, 1])),
    );
    expect(conflict, isA<OccurrenceIdentityConflict>());
    expect(await queue.countPending(), 1);
    final retained = (await queue.listPending()).single.record;
    expect(retained.image.relativeName, original.image.relativeName);
    expect(retained.image.sha256, original.image.sha256);
  });
}

enum _FaultPhase { staging, copy, flush, hash, destination, rename, recheck }

final class _FaultStore implements DurableImageStore {
  _FaultStore({this.phase});

  final _FaultPhase? phase;
  List<int>? canonical;
  int discardCalls = 0;

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) async {
    if (switch (phase) {
      _FaultPhase.staging ||
      _FaultPhase.copy ||
      _FaultPhase.flush ||
      _FaultPhase.hash =>
        true,
      _ => false,
    }) {
      throw StateError('injected_$phase');
    }
    final bytes = <int>[];
    await for (final chunk in source.openRead()) {
      bytes.addAll(chunk);
    }
    return _FaultStaging(this, bytes, source.metadata);
  }

  @override
  Future<DurableImageIntegrity> inspect(PersistedImageProjection image) async =>
      phase == _FaultPhase.recheck
          ? DurableImageIntegrity.missing
          : DurableImageIntegrity.valid;

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) =>
      Stream<List<int>>.value(canonical ?? const <int>[]);

  @override
  Future<void> delete(PersistedImageProjection image) async => canonical = null;

  @override
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  ) async =>
      const CompletedDurableImageDeletion();

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) =>
      throw UnimplementedError();

  @override
  Future<DurableImageSweepResult> sweep(Set<String> names) async =>
      const DurableImageSweepResult(
          removedStaging: 0,
          removedDeleting: 0,
          removedCanonical: 0,
          restoredDeleting: 0,
          failedOperations: 0);
}

final class _FaultStaging implements DurableImageStaging {
  _FaultStaging(this.store, this.bytes, this.metadata);

  final _FaultStore store;
  final List<int> bytes;
  final PreparedImageMetadata metadata;

  @override
  Future<PersistedImageProjection> publishWithoutOverwrite() async {
    if (store.phase == _FaultPhase.destination ||
        store.phase == _FaultPhase.rename) {
      throw StateError('injected_${store.phase}');
    }
    if (store.canonical != null) {
      throw StateError('no_overwrite');
    }
    store.canonical = List<int>.unmodifiable(bytes);
    return PersistedImageProjection(
      relativeName: 'e2i_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg',
      mimeType: metadata.mimeType,
      byteLength: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      width: metadata.width,
      height: metadata.height,
      quality: metadata.quality,
    );
  }

  @override
  Future<void> discard() async => store.discardCalls++;
}

final class _Lease implements PreparedImageLease {
  _Lease(this.bytes, {this.failWithdrawal = false});

  final List<int> bytes;
  final bool failWithdrawal;
  bool _owns = true;
  int withdrawCalls = 0;

  @override
  bool get hasOwnership => _owns;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
      mimeType: 'image/jpeg',
      byteLength: bytes.length,
      width: 2,
      height: 1,
      quality: 85);

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(bytes);

  @override
  PreparedImageLease promoteOwnership() => this;

  @override
  Future<void> withdrawOwnership() async {
    withdrawCalls++;
    if (failWithdrawal) throw StateError('injected_withdraw');
    _owns = false;
  }

  @override
  Future<void> dispose() => withdrawOwnership();
}

InMemoryOccurrence _occurrence(_Lease lease) =>
    const InMemoryOccurrenceFactory().createManual(
      idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
      detectedAt: DateTime.utc(2025, 4, 12, 14, 30),
      location: ImmutableLocationSnapshot(
          point: ImmutableGeoPoint(latitude: -23.5, longitude: -46.6),
          accuracyMeters: 4.5,
          speedMetersPerSecond: 10),
      image: lease,
    );

Future<List<Map<String, Object?>>> _rows(QueueDatabase database) =>
    database.database.query(e2QueueTable);
