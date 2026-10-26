import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect;
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/cooldown_policy.dart';
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

  final inputs = any.combine2<_PersistencePath, List<int>, _PropertyInput>(
    any.choose(_PersistencePath.values),
    any.nonEmptyList(any.positiveIntOrZero),
    (path, bytes) => _PropertyInput(
      path: path,
      bytes: bytes.map((value) => value.toUnsigned(8)).toList(growable: false),
    ),
  );

  // Feature: mvp-app-flutter, Property 13: Aceite somente após persistência íntegra
  // **Validates: Requirements RF-12.1, RF-12.2, RF-12.7, RF-12.10,
  // RF-12.11, RNF-05.1, RNF-05.2**
  Glados<_PropertyInput>(
    inputs,
    ExploreConfig(numRuns: 120),
  ).test('publishes a new acceptance only after durable integrity',
      (_PropertyInput input) async {
    final sandbox = await Directory.systemTemp.createTemp('e2_property_13_');
    QueueDatabase? database;
    CoordinatedPersistentOccurrenceQueue? queue;

    try {
      database = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName',
      );
      final store = _PropertyImageStore(input.path);
      queue = CoordinatedPersistentOccurrenceQueue(
        imageStore: store,
        databaseOpener: () async => database!,
      );
      expect((await queue.bootstrap()).isReady, isTrue);

      final cooldown = _RecordingCooldown();
      final processor = E1PostCandidateProcessor(
        cooldown: cooldown,
        imagePreparer: _PropertyImagePreparer(input.bytes),
        uuidGenerator: const _FixedUuidGenerator(),
        occurrenceAcceptancePort: queue,
      );

      final result = await processor.process(_candidate());
      final rows = await database.database.query(e2QueueTable);

      if (input.path == _PersistencePath.intact) {
        expect(result, isA<CandidateCreated<InMemoryOccurrence>>());
        expect(cooldown.commitCount, 1);
        expect(await queue.countPending(), 1);
        expect(rows, hasLength(1));

        final record = const QueueRecordMapper().fromMap(rows.single);
        final image = store.publishedImage;
        final canonicalBytes = store.canonicalBytes;
        expect(image, isNotNull);
        expect(canonicalBytes, isNotNull);
        expect(record.idempotencyKey, _FixedUuidGenerator.value);
        expect(record.image.relativeName, image!.relativeName);
        expect(record.image.sha256, image.sha256);
        expect(record.image.byteLength, canonicalBytes!.length);
        expect(
          sha256.convert(canonicalBytes).toString(),
          record.image.sha256,
        );
        expect(await store.inspect(record.image), DurableImageIntegrity.valid);
      } else {
        expect(
          result,
          isA<CandidateFailed<InMemoryOccurrence>>().having(
            (failure) => failure.stage,
            'failure stage',
            CandidateFailureStage.durableAcceptance,
          ),
        );
        expect(cooldown.commitCount, 0);
        expect(await queue.countPending(), 0);
        expect(rows, isEmpty);
        expect(store.publishedImage, isNull);
        expect(store.canonicalBytes, isNull);
      }
    } finally {
      await queue?.close();
      if (queue == null) {
        await database?.close();
      }
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    }
  });
}

enum _PersistencePath { intact, stagingFailure, publicationFailure }

final class _PropertyInput {
  const _PropertyInput({required this.path, required this.bytes});

  final _PersistencePath path;
  final List<int> bytes;
}

CandidateInput _candidate() => CandidateInput(
      observedAt: DateTime.utc(2025, 4, 12, 14, 30),
      location: ImmutableLocationSnapshot(
        point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
        accuracyMeters: 4.5,
        speedMetersPerSecond: 8,
      ),
      defectClass: InMemoryOccurrence.potholeDefectClass,
      confidence: InMemoryOccurrence.manualConfidence,
      acquireImage: () async => const _Capture(),
    );

final class _Capture implements TemporaryCapture {
  const _Capture();

  @override
  Future<void> dispose() async {}
}

final class _RecordingCooldown implements CandidateCooldown {
  int commitCount = 0;

  @override
  void commit(InMemoryOccurrence occurrence) {
    commitCount++;
  }

  @override
  CooldownDecision evaluate(DateTime attemptedAt, GeoPoint point) =>
      const CooldownDecision.firstOccurrence();
}

final class _PropertyImagePreparer implements ImagePreparer {
  const _PropertyImagePreparer(this.bytes);

  final List<int> bytes;

  @override
  Future<OwnedPreparedImage> prepare(TemporaryCapture capture) async =>
      _PropertyLease(bytes);
}

final class _FixedUuidGenerator implements UuidGenerator {
  const _FixedUuidGenerator();

  static const String value = '123e4567-e89b-42d3-a456-426614174000';

  @override
  String newV4() => value;
}

final class _PropertyLease implements PreparedImageLease {
  _PropertyLease(List<int> bytes) : _bytes = List<int>.unmodifiable(bytes);

  final List<int> _bytes;
  var _hasOwnership = true;

  @override
  bool get hasOwnership => _hasOwnership;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: _bytes.length,
        width: 1,
        height: 1,
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

final class _PropertyImageStore implements DurableImageStore {
  _PropertyImageStore(this.path);

  static const _relativeName = 'e2i_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg';

  final _PersistencePath path;
  List<int>? canonicalBytes;
  PersistedImageProjection? publishedImage;

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) async {
    if (path == _PersistencePath.stagingFailure) {
      throw StateError('injected_staging_failure');
    }
    final bytes = <int>[];
    await for (final chunk in source.openRead()) {
      bytes.addAll(chunk);
    }
    return _PropertyStaging(this, bytes, source.metadata);
  }

  @override
  Future<DurableImageIntegrity> inspect(PersistedImageProjection image) async {
    final bytes = canonicalBytes;
    final published = publishedImage;
    if (bytes == null ||
        published == null ||
        image.relativeName != _relativeName) {
      return DurableImageIntegrity.missing;
    }
    return image.sha256 == sha256.convert(bytes).toString() &&
            image.byteLength == bytes.length &&
            image.sha256 == published.sha256
        ? DurableImageIntegrity.valid
        : DurableImageIntegrity.invalid;
  }

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) {
    final bytes = canonicalBytes;
    if (bytes == null || image.relativeName != _relativeName) {
      return Stream<List<int>>.error(StateError('missing_canonical_image'));
    }
    return Stream<List<int>>.value(bytes);
  }

  @override
  Future<void> delete(PersistedImageProjection image) async {
    canonicalBytes = null;
    publishedImage = null;
  }

  @override
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  ) async =>
      const CompletedDurableImageDeletion();

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) =>
      throw UnimplementedError();

  @override
  Future<DurableImageSweepResult> sweep(
          Set<String> referencedCanonicalNames) async =>
      const DurableImageSweepResult(
        removedStaging: 0,
        removedDeleting: 0,
        removedCanonical: 0,
        restoredDeleting: 0,
        failedOperations: 0,
      );
}

final class _PropertyStaging implements DurableImageStaging {
  _PropertyStaging(this._store, this._bytes, this._metadata);

  final _PropertyImageStore _store;
  final List<int> _bytes;
  final PreparedImageMetadata _metadata;

  @override
  Future<void> discard() async {}

  @override
  Future<PersistedImageProjection> publishWithoutOverwrite() async {
    if (_store.path == _PersistencePath.publicationFailure) {
      throw StateError('injected_publication_failure');
    }
    final image = PersistedImageProjection(
      relativeName: _PropertyImageStore._relativeName,
      mimeType: _metadata.mimeType,
      byteLength: _bytes.length,
      sha256: sha256.convert(_bytes).toString(),
      width: _metadata.width,
      height: _metadata.height,
      quality: _metadata.quality,
    );
    _store.canonicalBytes = List<int>.unmodifiable(_bytes);
    _store.publishedImage = image;
    return image;
  }
}
