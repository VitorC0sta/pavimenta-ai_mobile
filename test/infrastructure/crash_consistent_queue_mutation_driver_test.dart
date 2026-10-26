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
    sandbox = await Directory.systemTemp.createTemp('e2_commit_protocol_');
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

  // **Validates: Requirements RF-08.3–5, RF-11.8, RF-12.1–2, RF-12.7–8,
  // RF-12.10–11, RNF-03.5, RNF-05.1–5, RNF-06.3, RNF-06.9–11**
  test(
      'for a new key confirms the committed row and JPEG before withdrawing the E1 lease',
      () async {
    final events = <String>[];
    final store = _RecordingImageStore(events);
    final lease = _PreparedLease(
      const <int>[1, 2, 3],
      onWithdraw: () async {
        events.add('withdraw');
        expect(await database.database.query(e2QueueTable), hasLength(1));
        expect(store.canonicalPublished, isTrue);
        expect(store.inspectCalls, 1);
      },
    );
    final occurrence = _occurrence(lease);

    final result = await const CrashConsistentQueueMutationDriver().persist(
      database,
      store,
      occurrence,
    );

    expect(result, isA<OccurrencePersisted>());
    expect(events, <String>['stage', 'publish', 'withdraw']);
    expect(lease.withdrawCalls, 1);
    expect(lease.hasOwnership, isFalse);
    expect(store.stagingDiscarded, isFalse);
    expect(await database.database.query(e2QueueTable), hasLength(1));
    final record = const QueueRecordMapper()
        .fromMap((await database.database.query(e2QueueTable)).single);
    expect(record.idempotencyKey, occurrence.idempotencyKey);
    expect(record.image.relativeName, store.publishedImage.relativeName);
    expect(record.image.mimeType, store.publishedImage.mimeType);
    expect(record.image.byteLength, store.publishedImage.byteLength);
    expect(record.image.sha256, store.publishedImage.sha256);
    expect(record.image.width, store.publishedImage.width);
    expect(record.image.height, store.publishedImage.height);
    expect(record.image.quality, store.publishedImage.quality);
  });
}

InMemoryOccurrence _occurrence(PreparedImageLease image) {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
    detectedAt: DateTime.utc(2025, 4, 12, 14, 30),
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      accuracyMeters: 4.5,
      speedMetersPerSecond: 8,
    ),
    image: image,
  );
}

final class _RecordingImageStore implements DurableImageStore {
  _RecordingImageStore(this.events);

  final List<String> events;
  bool stagingDiscarded = false;
  bool canonicalPublished = false;
  int inspectCalls = 0;
  final PersistedImageProjection publishedImage = PersistedImageProjection(
    relativeName: 'e2i_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg',
    mimeType: 'image/jpeg',
    byteLength: 3,
    sha256: sha256.convert(<int>[1, 2, 3]).toString(),
    width: 1,
    height: 1,
    quality: 85,
  );

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) async {
    events.add('stage');
    return _RecordingStaging(this);
  }

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) =>
      throw UnimplementedError();

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
    return canonicalPublished
        ? DurableImageIntegrity.valid
        : DurableImageIntegrity.missing;
  }

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) =>
      Stream<List<int>>.value(const <int>[1, 2, 3]);

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

final class _RecordingStaging implements DurableImageStaging {
  _RecordingStaging(this._store);

  final _RecordingImageStore _store;
  var _published = false;

  @override
  Future<PersistedImageProjection> publishWithoutOverwrite() async {
    expect(_published, isFalse, reason: 'staging must only publish once');
    _published = true;
    _store.events.add('publish');
    _store.canonicalPublished = true;
    return _store.publishedImage;
  }

  @override
  Future<void> discard() async {
    _store.stagingDiscarded = true;
  }
}

final class _PreparedLease implements PreparedImageLease {
  _PreparedLease(this._bytes, {this.onWithdraw});

  final List<int> _bytes;
  final Future<void> Function()? onWithdraw;
  bool _owns = true;
  int withdrawCalls = 0;

  @override
  bool get hasOwnership => _owns;

  @override
  PreparedImageMetadata get metadata => const PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: 3,
        width: 1,
        height: 1,
        quality: 85,
      );

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(_bytes);

  @override
  PreparedImageLease promoteOwnership() => this;

  @override
  Future<void> withdrawOwnership() async {
    withdrawCalls++;
    await onWithdraw?.call();
    _owns = false;
  }

  @override
  Future<void> dispose() => withdrawOwnership();
}
