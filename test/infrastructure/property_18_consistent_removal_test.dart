import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect;
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_record_mapper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final inputs = any.combine2<_RemovalInterruption, int, _PropertyInput>(
    any.choose(_RemovalInterruption.values),
    any.positiveIntOrZero,
    (interruption, seed) => _PropertyInput(
      interruption: interruption,
      seed: seed,
    ),
  );

  // Feature: mvp-app-flutter, Property 18: Remoção consistente
  // **Validates: Requirements RF-12.9, RNF-05.4, RNF-06.2, RNF-06.10**
  Glados<_PropertyInput>(
    inputs,
    ExploreConfig(numRuns: 120),
  ).test(
    'removes confirmed rows and canonical JPEGs, or restores an intact pending record after a pre-commit interruption',
    (_PropertyInput input) async {
      final sandbox = await Directory.systemTemp.createTemp('e2_property_18_');
      final fixture = _fixtureFor(input.seed);
      final databasePath =
          '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName';
      final namespace = Directory(
        '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
      );
      final canonical = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${fixture.record.image.relativeName}',
      );
      final marker = File(
        '${namespace.path}${Platform.pathSeparator}'
        '${const E2DurableImageNameCodec().deletingMarker(
          canonicalName: fixture.record.image.relativeName,
          operationToken: _opaqueToken(input.seed + 1),
        )}',
      );
      QueueDatabase? database;
      CoordinatedPersistentOccurrenceQueue? queue;

      try {
        await namespace.create(recursive: true);
        database = await _openDatabase(databasePath);

        switch (input.interruption) {
          case _RemovalInterruption.completed:
            await _insert(database, fixture.record);
            await canonical.writeAsBytes(fixture.bytes, flush: true);
            await database.close();
            database = null;

            queue = _queue(sandbox, databasePath);
            expect((await queue.bootstrap()).isReady, isTrue);
            final removal = await queue.removeInternal(
              fixture.record.idempotencyKey,
            );
            expect(removal, isA<QueueOccurrenceRemoved>());
            expect(await canonical.exists(), isFalse);
            expect(await marker.exists(), isFalse);
            await queue.close();
            queue = null;
          case _RemovalInterruption.beforeCommit:
            await _insert(database, fixture.record);
            await marker.writeAsBytes(fixture.bytes, flush: true);
            await database.close();
            database = null;
          case _RemovalInterruption.afterCommit:
            await marker.writeAsBytes(fixture.bytes, flush: true);
            await database.close();
            database = null;
        }

        final expectedPending =
            input.interruption == _RemovalInterruption.beforeCommit;
        await _recoverAndAssert(
          sandbox: sandbox,
          databasePath: databasePath,
          fixture: fixture,
          canonical: canonical,
          marker: marker,
          expectedPending: expectedPending,
        );
        await _recoverAndAssert(
          sandbox: sandbox,
          databasePath: databasePath,
          fixture: fixture,
          canonical: canonical,
          marker: marker,
          expectedPending: expectedPending,
        );
      } finally {
        await database?.close();
        await queue?.close();
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      }
    },
  );
}

Future<void> _recoverAndAssert({
  required Directory sandbox,
  required String databasePath,
  required _Fixture fixture,
  required File canonical,
  required File marker,
  required bool expectedPending,
}) async {
  final queue = _queue(sandbox, databasePath);
  try {
    final snapshot = await queue.bootstrap();
    final pending = await queue.listPending();

    expect(snapshot.isReady, isTrue);
    expect(snapshot.pendingCount, expectedPending ? 1 : 0);
    expect(pending, hasLength(expectedPending ? 1 : 0));
    expect(await marker.exists(), isFalse);

    if (expectedPending) {
      expect(pending.single.idempotencyKey, fixture.record.idempotencyKey);
      expect(await canonical.readAsBytes(), fixture.bytes);
      expect(await _rowCount(databasePath), 1);
    } else {
      expect(await canonical.exists(), isFalse);
      expect(await _rowCount(databasePath), 0);
    }
  } finally {
    await queue.close();
  }
}

CoordinatedPersistentOccurrenceQueue _queue(
  Directory sandbox,
  String databasePath,
) =>
    CoordinatedPersistentOccurrenceQueue(
      imageStore: PrivateDurableImageStore.at(sandbox),
      databaseOpener: () => _openDatabase(databasePath),
    );

Future<QueueDatabase> _openDatabase(String path) => QueueDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );

Future<void> _insert(
  QueueDatabase database,
  QueueRecordProjection record,
) =>
    database.database.insert(
      e2QueueTable,
      const QueueRecordMapper().toInsertMap(record),
    );

Future<int> _rowCount(String path) async {
  final database = await _openDatabase(path);
  try {
    return (await database.database.query(e2QueueTable)).length;
  } finally {
    await database.close();
  }
}

_Fixture _fixtureFor(int seed) {
  final width = 1 + seed % 8;
  final height = 1 + (seed ~/ 8) % 8;
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
  final bytes = image_codec.encodeJpg(image, quality: 85);
  final token = _opaqueToken(seed);
  return _Fixture(
    bytes: bytes,
    record: QueueRecordProjection(
      queueSequence: 0,
      idempotencyKey: _uuidFor(seed),
      detectedAtIso8601: '2025-01-02T03:04:05.000Z',
      latitude: -23.5505,
      longitude: -46.6333,
      accuracyMeters: null,
      speedKmh: null,
      confidence: 1,
      defectClass: 'pothole',
      image: PersistedImageProjection(
        relativeName: 'e2i_$token.jpg',
        mimeType: 'image/jpeg',
        byteLength: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        width: width,
        height: height,
        quality: 85,
      ),
    ),
  );
}

String _uuidFor(int seed) {
  const limit = 0x1000000000000;
  final suffix = (seed % limit).toRadixString(16).padLeft(12, '0');
  return '00000000-0000-4000-8000-$suffix';
}

String _opaqueToken(int seed) =>
    (seed & 0xffffffffffffffff).toRadixString(16).padLeft(32, '0');

enum _RemovalInterruption { completed, beforeCommit, afterCommit }

final class _PropertyInput {
  const _PropertyInput({required this.interruption, required this.seed});

  final _RemovalInterruption interruption;
  final int seed;
}

final class _Fixture {
  const _Fixture({required this.bytes, required this.record});

  final List<int> bytes;
  final QueueRecordProjection record;
}
