import 'dart:io';

import 'package:crypto/crypto.dart';
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

  // Feature: mvp-app-flutter, Property 14: Round-trip da fila
  // **Validates: Requirements RF-08.4, RF-12.2, RF-12.3, RF-12.4,
  // RNF-03.5, RNF-05.3**
  Glados<int>(
    any.positiveIntOrZero,
    ExploreConfig(numRuns: 120),
  ).test(
    'reconstructs every persisted canonical occurrence after reopening',
    (int seed) async {
      final sandbox = await Directory.systemTemp.createTemp('e2_property_14_');
      final databasePath =
          '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName';
      CoordinatedPersistentOccurrenceQueue? initialQueue;
      CoordinatedPersistentOccurrenceQueue? reopenedQueue;

      try {
        Future<QueueDatabase> openDatabase() => QueueDatabase.open(
              factory: databaseFactoryFfi,
              path: databasePath,
            );

        final initialStore = PrivateDurableImageStore.at(
          sandbox,
          tokenGenerator: () => _opaqueToken(seed),
        );
        initialQueue = CoordinatedPersistentOccurrenceQueue(
          imageStore: initialStore,
          databaseOpener: openDatabase,
        );
        expect((await initialQueue.bootstrap()).isReady, isTrue);

        final occurrence = _occurrenceFor(seed);
        expect(
            await initialQueue.persist(occurrence), isA<OccurrencePersisted>());
        final initiallyPending = await initialQueue.listPending();
        expect(initiallyPending, hasLength(1));
        final initiallyReconstructed = initiallyPending.single.record;

        await initialQueue.close();
        initialQueue = null;

        final reopenedStore = PrivateDurableImageStore.at(sandbox);
        reopenedQueue = CoordinatedPersistentOccurrenceQueue(
          imageStore: reopenedStore,
          databaseOpener: openDatabase,
        );
        final snapshot = await reopenedQueue.bootstrap();
        expect(snapshot.health, QueueHealth.ready);
        expect(snapshot.pendingCount, 1);
        expect(snapshot.attentionCount, 0);

        final reopenedPending = await reopenedQueue.listPending();
        expect(reopenedPending, hasLength(1));
        final reopened = reopenedPending.single.record;
        _expectSameCanonicalRecord(reopened, initiallyReconstructed);
        expect(await reopenedStore.inspect(reopened.image),
            DurableImageIntegrity.valid);
        expect(
          (await sha256.bind(reopenedStore.openRead(reopened.image)).first)
              .toString(),
          reopened.image.sha256,
        );
      } finally {
        await initialQueue?.close();
        await reopenedQueue?.close();
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      }
    },
  );
}

InMemoryOccurrence _occurrenceFor(int seed) {
  final width = 1 + seed % 8;
  final height = 1 + (seed ~/ 8) % 8;
  final hasAccuracy = seed % 3 != 0;
  final speedMetersPerSecond = switch (seed % 3) {
    0 => null,
    1 => 0.0,
    _ => 10.0,
  };
  final bytes = _jpeg(seed: seed, width: width, height: height);
  final location = ImmutableLocationSnapshot(
    point: ImmutableGeoPoint(
      latitude: -90 + (seed % 180001) / 1000,
      longitude: -180 + (seed % 360001) / 1000,
    ),
    accuracyMeters: hasAccuracy ? (seed % 5000) / 100 : null,
    speedMetersPerSecond: speedMetersPerSecond,
  );

  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: _uuidFor(seed),
    detectedAt: DateTime.utc(2025, 1, 1).add(
      Duration(minutes: seed % 525600),
    ),
    location: location,
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

void _expectSameCanonicalRecord(
  QueueRecordProjection actual,
  QueueRecordProjection expected,
) {
  expect(actual.queueSequence, expected.queueSequence);
  expect(actual.idempotencyKey, expected.idempotencyKey);
  expect(actual.detectedAtIso8601, expected.detectedAtIso8601);
  expect(actual.latitude, expected.latitude);
  expect(actual.longitude, expected.longitude);
  expect(actual.accuracyMeters, expected.accuracyMeters);
  expect(actual.speedKmh, expected.speedKmh);
  expect(actual.confidence, expected.confidence);
  expect(actual.defectClass, expected.defectClass);
  expect(actual.image.relativeName, expected.image.relativeName);
  expect(actual.image.mimeType, expected.image.mimeType);
  expect(actual.image.byteLength, expected.image.byteLength);
  expect(actual.image.sha256, expected.image.sha256);
  expect(actual.image.width, expected.image.width);
  expect(actual.image.height, expected.image.height);
  expect(actual.image.quality, expected.image.quality);
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
