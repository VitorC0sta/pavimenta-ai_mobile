import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
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

  late Directory sandbox;
  late String databasePath;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e2_queue_integration_');
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

  // **Validates: Requirements RF-08.3–5, RF-11.8, RF-12.1–11,
  // RNF-03.5, RNF-05.1–5, RNF-06.2–3, RNF-06.9–11**
  group('task 48.9 real SQLite and sandbox integration', () {
    test('persists canonical mapper values and digest across queue reopening',
        () async {
      final bytes = _jpeg(width: 17, height: 11, red: 12);
      final occurrence = _occurrence(
        key: '123e4567-e89b-42d3-a456-426614174000',
        detectedAt: DateTime.parse('2025-01-02T03:04:05.678-03:00'),
        bytes: bytes,
        width: 17,
        height: 11,
        accuracyMeters: 0,
        speedMetersPerSecond: 0,
      );
      final queue = openQueue();
      addTearDown(queue.close);

      expect((await queue.bootstrap()).health, QueueHealth.ready);
      expect(await queue.persist(occurrence), isA<OccurrencePersisted>());
      final persisted = (await queue.listPending()).single.record;

      expect(persisted.queueSequence, 1);
      expect(persisted.idempotencyKey, occurrence.idempotencyKey);
      expect(persisted.detectedAtIso8601, occurrence.detectedAtIso8601);
      expect(persisted.accuracyMeters, 0);
      expect(persisted.speedKmh, 0);
      expect(persisted.image.sha256, sha256.convert(bytes).toString());
      expect(persisted.image.byteLength, bytes.length);
      expect(
        await PrivateDurableImageStore.at(sandbox)
            .openRead(persisted.image)
            .expand((chunk) => chunk)
            .toList(),
        bytes,
      );

      await queue.close();
      final reopened = openQueue();
      addTearDown(reopened.close);
      final snapshot = await reopened.bootstrap();
      final recovered = (await reopened.listPending()).single.record;

      expect(snapshot.health, QueueHealth.ready);
      expect(snapshot.pendingCount, 1);
      expect(recovered.queueSequence, persisted.queueSequence);
      expect(recovered.idempotencyKey, persisted.idempotencyKey);
      expect(recovered.detectedAtIso8601, persisted.detectedAtIso8601);
      expect(recovered.latitude, persisted.latitude);
      expect(recovered.longitude, persisted.longitude);
      expect(recovered.accuracyMeters, persisted.accuracyMeters);
      expect(recovered.speedKmh, persisted.speedKmh);
      expect(recovered.confidence, persisted.confidence);
      expect(recovered.defectClass, persisted.defectClass);
      expect(recovered.image.relativeName, persisted.image.relativeName);
      expect(recovered.image.sha256, persisted.image.sha256);
    });

    test('rolls back a real filesystem publication when SQLite insert fails',
        () async {
      final database = await openDatabase();
      await database.database.execute('''
CREATE TRIGGER reject_e2_insert
BEFORE INSERT ON $e2QueueTable
BEGIN SELECT RAISE(ABORT, 'injected insert failure'); END
''');
      await database.close();

      final lease = _Lease(_jpeg(width: 9, height: 7, red: 23), 9, 7);
      final queue = openQueue();
      addTearDown(queue.close);
      await queue.bootstrap();

      final result = await queue.persist(
        _occurrence(
          key: '223e4567-e89b-42d3-a456-426614174000',
          detectedAt: DateTime.utc(2025, 1, 2, 3, 4, 5),
          lease: lease,
        ),
      );

      expect(result, isA<OccurrenceTransactionalFailure>());
      expect(lease.hasOwnership, isTrue);
      expect(lease.withdrawCalls, 0);
      expect(await queue.countPending(), 0);
      expect(await _queueArtifacts(sandbox), isEmpty);
    });

    test('serializes concurrent equivalent writes with one row and JPEG',
        () async {
      final bytes = _jpeg(width: 13, height: 9, red: 44);
      final queue = openQueue();
      addTearDown(queue.close);
      await queue.bootstrap();

      final outcomes = await Future.wait<OccurrenceAcceptanceResult>(
        <Future<OccurrenceAcceptanceResult>>[
          queue.persist(
            _occurrence(
              key: '323e4567-e89b-42d3-a456-426614174000',
              detectedAt: DateTime.utc(2025, 2, 3, 4, 5, 6),
              bytes: bytes,
              width: 13,
              height: 9,
            ),
          ),
          queue.persist(
            _occurrence(
              key: '323e4567-e89b-42d3-a456-426614174000',
              detectedAt: DateTime.utc(2025, 2, 3, 4, 5, 6),
              bytes: bytes,
              width: 13,
              height: 9,
            ),
          ),
        ],
      );

      expect(outcomes.whereType<OccurrencePersisted>(), hasLength(1));
      expect(
        outcomes.whereType<OccurrenceAlreadyPersistedEquivalent>(),
        hasLength(1),
      );
      expect(await queue.countPending(), 1);
      final record = (await queue.listPending()).single.record;
      expect(record.image.sha256, sha256.convert(bytes).toString());
      expect(
          await _queueArtifacts(sandbox), <String>[record.image.relativeName]);
    });
  });
}

InMemoryOccurrence _occurrence({
  required String key,
  required DateTime detectedAt,
  List<int>? bytes,
  int? width,
  int? height,
  double? accuracyMeters,
  double? speedMetersPerSecond,
  _Lease? lease,
}) {
  final source = lease ?? _Lease(bytes!, width!, height!);
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: key,
    detectedAt: detectedAt,
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      accuracyMeters: accuracyMeters,
      speedMetersPerSecond: speedMetersPerSecond,
    ),
    image: source,
  );
}

List<int> _jpeg({required int width, required int height, required int red}) {
  final image = image_codec.Image(width: width, height: height);
  image.clear(image_codec.ColorRgb8(red, 32, 16));
  return image_codec.encodeJpg(image, quality: 85);
}

Future<List<String>> _queueArtifacts(Directory sandbox) async {
  final namespace = Directory(
    '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
  );
  if (!await namespace.exists()) {
    return const <String>[];
  }
  final names = <String>[];
  await for (final entry in namespace.list(followLinks: false)) {
    names.add(entry.uri.pathSegments.last);
  }
  names.sort();
  return names;
}

final class _Lease implements PreparedImageLease {
  _Lease(this.bytes, this.width, this.height);

  final List<int> bytes;
  final int width;
  final int height;
  var _hasOwnership = true;
  var withdrawCalls = 0;

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
    withdrawCalls++;
    _hasOwnership = false;
  }

  @override
  Future<void> dispose() => withdrawOwnership();
}
