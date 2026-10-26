import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect;
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  // Feature: mvp-app-flutter, Property 16: Contagem derivada da fila
  // **Validates: Requirements RF-05.5, RF-12.5, RF-12.9, RNF-05.4**
  Glados<int>(
    any.positiveIntOrZero,
    ExploreConfig(numRuns: 120),
  ).test(
    'publishes the confirmed-row count across acceptance, failures, recovery, and internal removal',
    (int seed) async {
      final sandbox = await Directory.systemTemp.createTemp('e2_property_16_');
      final databasePath =
          '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName';
      CoordinatedPersistentOccurrenceQueue? initialQueue;
      CoordinatedPersistentOccurrenceQueue? firstRecoveryQueue;
      CoordinatedPersistentOccurrenceQueue? repeatedRecoveryQueue;

      try {
        Future<QueueDatabase> openDatabase() => QueueDatabase.open(
              factory: databaseFactoryFfi,
              path: databasePath,
            );

        initialQueue = CoordinatedPersistentOccurrenceQueue(
          imageStore: PrivateDurableImageStore.at(
            sandbox,
            tokenGenerator: () => _opaqueToken(seed),
          ),
          databaseOpener: openDatabase,
          mutationDriver: _FailOnceMutationDriver(),
        );
        await _expectPublishedCount(
          initialQueue,
          databasePath: databasePath,
          expected: 0,
          snapshot: await initialQueue.bootstrap(),
        );

        final failedAcceptance =
            await initialQueue.persist(_occurrenceFor(seed));
        expect(failedAcceptance, isA<OccurrenceTransactionalFailure>());
        await _expectPublishedCount(
          initialQueue,
          databasePath: databasePath,
          expected: 0,
        );

        final accepted = _occurrenceFor(seed + 1);
        final persisted = await initialQueue.persist(accepted);
        expect(persisted, isA<OccurrencePersisted>());
        await _expectPublishedCount(
          initialQueue,
          databasePath: databasePath,
          expected: 1,
          snapshot: (persisted as OccurrencePersisted).snapshot,
        );

        final failedRemoval =
            await initialQueue.removeInternal(accepted.idempotencyKey);
        expect(failedRemoval, isA<QueueOccurrenceRemovalFailed>());
        await _expectPublishedCount(
          initialQueue,
          databasePath: databasePath,
          expected: 1,
        );

        await initialQueue.close();
        initialQueue = null;

        firstRecoveryQueue = CoordinatedPersistentOccurrenceQueue(
          imageStore: PrivateDurableImageStore.at(sandbox),
          databaseOpener: openDatabase,
        );
        await _expectPublishedCount(
          firstRecoveryQueue,
          databasePath: databasePath,
          expected: 1,
          snapshot: await firstRecoveryQueue.bootstrap(),
        );
        await firstRecoveryQueue.close();
        firstRecoveryQueue = null;

        repeatedRecoveryQueue = CoordinatedPersistentOccurrenceQueue(
          imageStore: PrivateDurableImageStore.at(sandbox),
          databaseOpener: openDatabase,
        );
        await _expectPublishedCount(
          repeatedRecoveryQueue,
          databasePath: databasePath,
          expected: 1,
          snapshot: await repeatedRecoveryQueue.bootstrap(),
        );

        final removed =
            await repeatedRecoveryQueue.removeInternal(accepted.idempotencyKey);
        expect(removed, isA<QueueOccurrenceRemoved>());
        await _expectPublishedCount(
          repeatedRecoveryQueue,
          databasePath: databasePath,
          expected: 0,
          snapshot: (removed as QueueOccurrenceRemoved).snapshot,
        );
      } finally {
        await initialQueue?.close();
        await firstRecoveryQueue?.close();
        await repeatedRecoveryQueue?.close();
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      }
    },
  );
}

Future<void> _expectPublishedCount(
  CoordinatedPersistentOccurrenceQueue queue, {
  required String databasePath,
  required int expected,
  QueueSnapshot? snapshot,
}) async {
  expect(snapshot?.pendingCount ?? await queue.countPending(), expected);
  expect(await queue.countPending(), expected);
  expect((await queue.listPending()).length, expected);
  expect(await _confirmedRowCount(databasePath), expected);
}

Future<int> _confirmedRowCount(String databasePath) async {
  final database = await QueueDatabase.open(
    factory: databaseFactoryFfi,
    path: databasePath,
  );
  try {
    return (await database.database.query(e2QueueTable)).length;
  } finally {
    await database.close();
  }
}

InMemoryOccurrence _occurrenceFor(int seed) {
  final width = 1 + seed % 8;
  final height = 1 + (seed ~/ 8) % 8;
  final bytes = _jpeg(seed: seed, width: width, height: height);

  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: _uuidFor(seed),
    detectedAt: DateTime.utc(2025, 1, 1).add(
      Duration(minutes: seed % 525600),
    ),
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(
        latitude: -90 + (seed % 180001) / 1000,
        longitude: -180 + (seed % 360001) / 1000,
      ),
      accuracyMeters: seed.isEven ? null : (seed % 5000) / 100,
      speedMetersPerSecond: seed.isEven ? 0 : 10,
    ),
    image: _MemoryPreparedLease(bytes, width: width, height: height),
  );
}

List<int> _jpeg({required int seed, required int width, required int height}) {
  final image = image_codec.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(
        x,
        y,
        (seed + x * 17).toUnsigned(8),
        (seed + y * 31).toUnsigned(8),
        (seed + x + y * 13).toUnsigned(8),
        255,
      );
    }
  }
  return image_codec.encodeJpg(image, quality: 85);
}

String _uuidFor(int seed) {
  const limit = 0x1000000000000;
  final suffix = (seed % limit).toRadixString(16).padLeft(12, '0');
  return '00000000-0000-4000-8000-$suffix';
}

String _opaqueToken(int seed) => seed.toRadixString(16).padLeft(32, '0');

final class _FailOnceMutationDriver implements QueueMutationDriver {
  _FailOnceMutationDriver({
    QueueMutationDriver delegate = const CrashConsistentQueueMutationDriver(),
  }) : _delegate = delegate;

  final QueueMutationDriver _delegate;
  var _failPersistence = true;
  var _failRemoval = true;

  @override
  Future<OccurrenceAcceptanceResult> persist(
    QueueDatabase database,
    DurableImageStore imageStore,
    InMemoryOccurrence occurrence,
  ) {
    if (_failPersistence) {
      _failPersistence = false;
      return Future<OccurrenceAcceptanceResult>.value(
        const OccurrenceTransactionalFailure(),
      );
    }
    return _delegate.persist(database, imageStore, occurrence);
  }

  @override
  Future<QueueRemovalResult> remove(
    QueueDatabase database,
    DurableImageStore imageStore,
    String idempotencyKey,
  ) {
    if (_failRemoval) {
      _failRemoval = false;
      return Future<QueueRemovalResult>.value(
        const QueueOccurrenceRemovalFailed(),
      );
    }
    return _delegate.remove(database, imageStore, idempotencyKey);
  }
}

final class _MemoryPreparedLease implements PreparedImageLease {
  _MemoryPreparedLease(
    List<int> bytes, {
    required this.width,
    required this.height,
  }) : _bytes = List<int>.unmodifiable(bytes);

  final List<int> _bytes;
  final int width;
  final int height;
  var _hasOwnership = true;

  @override
  bool get hasOwnership => _hasOwnership;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: _bytes.length,
        width: width,
        height: height,
        quality: 85,
      );

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(_bytes);

  @override
  PreparedImageLease promoteOwnership() => this;

  @override
  Future<void> dispose() => withdrawOwnership();

  @override
  Future<void> withdrawOwnership() async {
    _hasOwnership = false;
  }
}
