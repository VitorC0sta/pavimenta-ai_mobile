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
import 'package:pavimenta_ai_mobile/infrastructure/queue_record_mapper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory sandbox;
  late QueueDatabase database;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e2_preflight_');
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

  group('task 42.1 idempotency preflight', () {
    // **Validates: Requirements RF-08.3–5, RF-12.1–2, RF-12.4, RF-12.7–8,
    // RF-12.10–11, RNF-03.5, RNF-05.1–5, RNF-06.9–11**
    test(
        'confirms an equivalent row only after comparing all valid fields and both JPEG streams',
        () async {
      final preparedBytes = <int>[1, 2, 3, 4];
      final occurrence = _occurrence(bytes: preparedBytes);
      final record = _recordFor(occurrence, preparedBytes);
      await _insert(database, record);
      final images = _FakeDurableImageStore(
        bytesByName: <String, List<int>>{
          record.image.relativeName: preparedBytes,
        },
      );

      final result = await const PreflightQueueMutationDriver().persist(
        database,
        images,
        occurrence,
      );

      expect(result, isA<OccurrenceAlreadyPersistedEquivalent>());
      expect(images.inspectCalls, 1);
      expect(images.openReadCalls, 1);
      expect(images.promoteCalls, 0);
      expect(await _rowCount(database), 1);
    });

    // **Validates: Requirements RF-08.3–5, RF-12.1–2, RF-12.4, RF-12.7–8,
    // RF-12.10–11, RNF-03.5, RNF-05.1–5, RNF-06.9–11**
    test(
        'rejects every mutable canonical field and image metadata difference without E2 creation',
        () async {
      final preparedBytes = <int>[1, 2, 3, 4];
      final occurrence = _occurrence(bytes: preparedBytes);
      final baseline = _recordFor(occurrence, preparedBytes);
      final variants = <String, QueueRecordProjection>{
        'detectedAtIso8601': _copyRecord(
          baseline,
          detectedAtIso8601: '2025-04-12T14:31:00.000Z',
        ),
        'latitude': _copyRecord(baseline, latitude: -23.5001),
        'longitude': _copyRecord(baseline, longitude: -46.6001),
        'accuracyMeters': _copyRecord(baseline, accuracyMeters: 5.5),
        'speedKmh': _copyRecord(baseline, speedKmh: 0),
        'image byte length': _copyRecord(
          baseline,
          image: _copyImage(baseline.image, byteLength: 3),
        ),
        'image width': _copyRecord(
          baseline,
          image: _copyImage(baseline.image, width: 3),
        ),
        'image height': _copyRecord(
          baseline,
          image: _copyImage(baseline.image, height: 2),
        ),
      };

      for (final entry in variants.entries) {
        await database.database.delete(e2QueueTable);
        await _insert(database, entry.value);
        final images = _FakeDurableImageStore(
          bytesByName: <String, List<int>>{
            entry.value.image.relativeName: preparedBytes,
          },
        );

        final result = await const PreflightQueueMutationDriver().persist(
          database,
          images,
          occurrence,
        );

        expect(result, isA<OccurrenceIdentityConflict>(), reason: entry.key);
        expect(images.promoteCalls, 0, reason: entry.key);
        expect(await _rowCount(database), 1, reason: entry.key);
      }
    });

    // **Validates: Requirements RF-12.1–2, RF-12.4, RF-12.7–8,
    // RF-12.10–11, RNF-03.5, RNF-05.1–5, RNF-06.9–11**
    test(
        'rejects same-sized prepared bytes with a different SHA-256 and a JPEG that disagrees with its row',
        () async {
      final storedBytes = <int>[1, 2, 3, 4];
      final differentSameSizeBytes = <int>[4, 3, 2, 1];
      final occurrence = _occurrence(bytes: differentSameSizeBytes);
      final record = _recordFor(occurrence, storedBytes);
      await _insert(database, record);

      final preparedMismatch =
          await const PreflightQueueMutationDriver().persist(
        database,
        _FakeDurableImageStore(
          bytesByName: <String, List<int>>{
            record.image.relativeName: storedBytes,
          },
        ),
        occurrence,
      );
      expect(preparedMismatch, isA<OccurrenceIdentityConflict>());

      final matchingOccurrence = _occurrence(bytes: storedBytes);
      final durableMismatch =
          await const PreflightQueueMutationDriver().persist(
        database,
        _FakeDurableImageStore(
          bytesByName: <String, List<int>>{
            record.image.relativeName: differentSameSizeBytes,
          },
        ),
        matchingOccurrence,
      );
      expect(durableMismatch, isA<OccurrenceIdentityConflict>());
      expect(await _rowCount(database), 1);
    });

    // **Validates: Requirements RF-12.1–2, RF-12.4, RF-12.7–8,
    // RNF-03.5, RNF-05.1–5**
    test('does not read or create an E2 image when the idempotency key is new',
        () async {
      final occurrence = _occurrence(bytes: <int>[1, 2, 3, 4]);
      final images = _FakeDurableImageStore(bytesByName: const {});

      final result = await const PreflightQueueMutationDriver().persist(
        database,
        images,
        occurrence,
      );

      expect(result, isA<OccurrenceTransactionalFailure>());
      expect(images.inspectCalls, 0);
      expect(images.openReadCalls, 0);
      expect(images.promoteCalls, 0);
      expect(await _rowCount(database), 0);
    });
  });
}

Future<void> _insert(
  QueueDatabase database,
  QueueRecordProjection record,
) =>
    database.database.insert(
      e2QueueTable,
      const QueueRecordMapper().toInsertMap(record),
    );

Future<int> _rowCount(QueueDatabase database) async {
  final rows = await database.database.query(e2QueueTable);
  return rows.length;
}

InMemoryOccurrence _occurrence({required List<int> bytes}) {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
    detectedAt: DateTime.utc(2025, 4, 12, 14, 30),
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5, longitude: -46.6),
      accuracyMeters: 4.5,
      speedMetersPerSecond: 10,
    ),
    image: _PreparedLease(bytes),
  );
}

QueueRecordProjection _recordFor(
  InMemoryOccurrence occurrence,
  List<int> bytes,
) {
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
    image: PersistedImageProjection(
      relativeName: 'e2i_00000000000000000000000000000000.jpg',
      mimeType: 'image/jpeg',
      byteLength: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      width: 2,
      height: 1,
      quality: 85,
    ),
  );
}

QueueRecordProjection _copyRecord(
  QueueRecordProjection source, {
  String? detectedAtIso8601,
  double? latitude,
  double? longitude,
  double? accuracyMeters,
  double? speedKmh,
  PersistedImageProjection? image,
}) {
  return QueueRecordProjection(
    queueSequence: source.queueSequence,
    idempotencyKey: source.idempotencyKey,
    detectedAtIso8601: detectedAtIso8601 ?? source.detectedAtIso8601,
    latitude: latitude ?? source.latitude,
    longitude: longitude ?? source.longitude,
    accuracyMeters: accuracyMeters ?? source.accuracyMeters,
    speedKmh: speedKmh ?? source.speedKmh,
    confidence: source.confidence,
    defectClass: source.defectClass,
    image: image ?? source.image,
  );
}

PersistedImageProjection _copyImage(
  PersistedImageProjection source, {
  int? byteLength,
  int? width,
  int? height,
}) {
  return PersistedImageProjection(
    relativeName: source.relativeName,
    mimeType: source.mimeType,
    byteLength: byteLength ?? source.byteLength,
    sha256: source.sha256,
    width: width ?? source.width,
    height: height ?? source.height,
    quality: source.quality,
  );
}

final class _PreparedLease implements PreparedImageLease {
  _PreparedLease(List<int> bytes) : _bytes = List<int>.unmodifiable(bytes);

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

final class _FakeDurableImageStore implements DurableImageStore {
  _FakeDurableImageStore({required this.bytesByName});

  final Map<String, List<int>> bytesByName;
  var inspectCalls = 0;
  var openReadCalls = 0;
  var promoteCalls = 0;

  @override
  Future<void> delete(PersistedImageProjection image) async {}

  @override
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  ) async =>
      const CompletedDurableImageDeletion();

  @override
  Future<DurableImageIntegrity> inspect(PersistedImageProjection image) async {
    inspectCalls++;
    return bytesByName.containsKey(image.relativeName)
        ? DurableImageIntegrity.valid
        : DurableImageIntegrity.missing;
  }

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) {
    openReadCalls++;
    final bytes = bytesByName[image.relativeName];
    if (bytes == null) {
      return Stream<List<int>>.error(StateError('Missing fake durable image.'));
    }
    return Stream<List<int>>.value(bytes);
  }

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) {
    throw UnimplementedError();
  }

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) async {
    promoteCalls++;
    throw UnimplementedError();
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
