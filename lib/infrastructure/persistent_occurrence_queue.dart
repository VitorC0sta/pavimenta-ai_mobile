import 'dart:async';

import 'package:crypto/crypto.dart';

import '../application/e2_persistence_ports.dart';
import '../domain/in_memory_occurrence.dart';
import '../domain/persistent_occurrence.dart';
import 'durable_image_store.dart';
import 'image_artifacts.dart';
import 'queue_database.dart';
import 'queue_record_mapper.dart';

typedef QueueDatabaseOpener = Future<QueueDatabase> Function();
typedef E2QueueTechnicalLogger = void Function(String message);

/// A confirmed recovery result produced while the queue owns its single-writer
/// region. Complete records remain internal; observers receive aggregates only.
final class QueueRecoveryResult {
  QueueRecoveryResult({
    required Iterable<QueueRecordProjection> records,
    this.attentionCount = 0,
  })  : assert(attentionCount >= 0),
        records = List<QueueRecordProjection>.unmodifiable(records);

  final List<QueueRecordProjection> records;
  final int attentionCount;
}

/// Recovery boundary executed by the same coordinator as every queue mutation.
///
/// Task 41 performs the safe row-first namespace sweep. Integrity validation
/// and crash-state reconstruction are extended by the dedicated recovery task.
abstract interface class QueueBootstrapRecovery {
  Future<QueueRecoveryResult> recover(
    QueueDatabase database,
    DurableImageStore imageStore,
  );
}

final class InitialQueueBootstrapRecovery implements QueueBootstrapRecovery {
  const InitialQueueBootstrapRecovery({
    this.mapper = const QueueRecordMapper(),
  });

  final QueueRecordMapper mapper;

  @override
  Future<QueueRecoveryResult> recover(
    QueueDatabase database,
    DurableImageStore imageStore,
  ) async {
    final rows = await database.database.query(
      e2QueueTable,
      orderBy: QueueRecordColumns.queueSequence,
    );
    final records = rows.map(mapper.fromMap).toList(growable: false);

    // Rows are confirmed before filesystem reconciliation. Because recovery
    // owns the queue's critical section, no active mutation can have staging
    // mistaken for an orphan by this sweep. Invalid references deliberately do
    // not enter the sweep set: they must remain retained and degrade the queue,
    // rather than turning recovery into a destructive cleanup attempt.
    const nameCodec = E2DurableImageNameCodec();
    final referencedCanonicalNames = records
        .map((record) => record.image.relativeName)
        .where(nameCodec.isCanonicalName)
        .toSet();
    final sweep = await imageStore.sweep(referencedCanonicalNames);

    var attentionCount = sweep.failedOperations;
    for (final record in records) {
      if (!await _hasValidRecoveredImage(record, imageStore, nameCodec)) {
        // Retain the database row and every referenced artifact. A degraded
        // snapshot is the controlled signal for missing, corrupt, or divergent
        // data; recovery must never silently discard a pending occurrence.
        attentionCount++;
      }
    }
    return QueueRecoveryResult(
      records: records,
      attentionCount: attentionCount,
    );
  }
}

/// Mutation boundary called only while [CoordinatedPersistentOccurrenceQueue]
/// owns its single-writer region.
abstract interface class QueueMutationDriver {
  Future<OccurrenceAcceptanceResult> persist(
    QueueDatabase database,
    DurableImageStore imageStore,
    InMemoryOccurrence occurrence,
  );

  Future<QueueRemovalResult> remove(
    QueueDatabase database,
    DurableImageStore imageStore,
    String idempotencyKey,
  );
}

/// Implements task 42.1's read-only idempotency preflight.
///
/// It intentionally does not create staging files, promote a JPEG, insert a
/// row, or withdraw the E1 lease for a key that is not yet present. Those
/// steps belong to the later crash-consistent commit protocol. For an existing
/// key, every canonical occurrence field and image metadata field must match,
/// and both byte streams must have the digest and length claimed by the row.
final class PreflightQueueMutationDriver implements QueueMutationDriver {
  const PreflightQueueMutationDriver({
    this.mapper = const QueueRecordMapper(),
  });

  final QueueRecordMapper mapper;

  @override
  Future<OccurrenceAcceptanceResult> persist(
    QueueDatabase database,
    DurableImageStore imageStore,
    InMemoryOccurrence occurrence,
  ) async {
    final rows = await database.database.query(
      e2QueueTable,
      where: '${QueueRecordColumns.idempotencyKey} = ?',
      whereArgs: <Object>[occurrence.idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      // Task 42.2 will create a unique E2 staging file only after this
      // key-absence preflight. Do not create or modify any E2 artifact here.
      return const OccurrenceTransactionalFailure();
    }

    final source = occurrence.image;
    if (source is! PreparedImageLease || !source.hasOwnership) {
      return const OccurrenceInvalidData();
    }

    final record = mapper.fromMap(rows.single);
    final preparedDigest = await _digestStream(source.openRead());
    if (!_preparedBytesMatchMetadata(source.metadata, preparedDigest)) {
      return const OccurrenceImageFailure();
    }

    final durableIntegrity = await imageStore.inspect(record.image);
    if (durableIntegrity != DurableImageIntegrity.valid) {
      return const OccurrenceIdentityConflict();
    }

    final durableDigest =
        await _digestStream(imageStore.openRead(record.image));
    if (!_persistedBytesMatchRecord(record.image, durableDigest)) {
      return const OccurrenceIdentityConflict();
    }

    return _isEquivalent(
      occurrence: occurrence,
      preparedMetadata: source.metadata,
      preparedDigest: preparedDigest,
      record: record,
      durableDigest: durableDigest,
    )
        ? const OccurrenceAlreadyPersistedEquivalent(
            QueueSnapshot.initializing())
        : const OccurrenceIdentityConflict();
  }

  @override
  Future<QueueRemovalResult> remove(
    QueueDatabase database,
    DurableImageStore imageStore,
    String idempotencyKey,
  ) async {
    // Internal removal is intentionally deferred to its dedicated protocol.
    return const QueueOccurrenceRemovalFailed();
  }
}

final class CrashConsistentQueueMutationDriver implements QueueMutationDriver {
  const CrashConsistentQueueMutationDriver({
    this.mapper = const QueueRecordMapper(),
    this.preflight = const PreflightQueueMutationDriver(),
  });

  final QueueRecordMapper mapper;
  final PreflightQueueMutationDriver preflight;

  @override
  Future<OccurrenceAcceptanceResult> persist(
    QueueDatabase database,
    DurableImageStore imageStore,
    InMemoryOccurrence occurrence,
  ) async {
    // This must finish before a staging artifact is created. Existing keys use
    // the 42.1 comparison path and cannot alter their canonical JPEG or E1
    // lease: the caller still owns that duplicate occurrence.
    final preflightResult = await preflight.persist(
      database,
      imageStore,
      occurrence,
    );
    if (preflightResult is! OccurrenceTransactionalFailure) {
      return preflightResult;
    }

    final source = occurrence.image;
    if (source is! PreparedImageLease || !source.hasOwnership) {
      return const OccurrenceInvalidData();
    }

    DurableImageStaging? staging;
    PersistedImageProjection? publishedImage;
    var existingKeyFoundInTransaction = false;
    var transactionCommitted = false;
    try {
      // Staging exclusively copies, flushes, validates, and hashes before a
      // transaction begins; it never publishes a canonical image itself.
      staging = await imageStore.stage(source);
      await database.database.transaction((transaction) async {
        final rows = await transaction.query(
          e2QueueTable,
          where: '${QueueRecordColumns.idempotencyKey} = ?',
          whereArgs: <Object>[occurrence.idempotencyKey],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          existingKeyFoundInTransaction = true;
          return;
        }

        // The staging boundary confirms a free canonical destination and uses
        // a rename operation that rejects replacement before this insert.
        final image = await staging!.publishWithoutOverwrite();
        publishedImage = image;
        await transaction.insert(
          e2QueueTable,
          mapper.toInsertMap(
            QueueRecordProjection(
              queueSequence: 0,
              idempotencyKey: occurrence.idempotencyKey,
              detectedAtIso8601: occurrence.detectedAtIso8601,
              latitude: occurrence.latitude,
              longitude: occurrence.longitude,
              accuracyMeters: occurrence.accuracyMeters,
              speedKmh: occurrence.speedKmh,
              confidence: occurrence.confidence,
              defectClass: occurrence.defectClass,
              image: image,
            ),
          ),
        );
      });
      transactionCommitted = !existingKeyFoundInTransaction;

      if (existingKeyFoundInTransaction) {
        await staging.discard();
        // Resolve the row observed by the transactional recheck through the
        // same full comparison as the original preflight, without publishing.
        return preflight.persist(database, imageStore, occurrence);
      }

      final image = publishedImage;
      if (image == null ||
          !await _isCommittedPersistenceIntact(
            database: database,
            imageStore: imageStore,
            occurrence: occurrence,
            publishedImage: image,
          )) {
        // A committed row is never compensated here. Recovery owns any later
        // reconciliation; returning a non-acceptance preserves the E1 lease.
        return const OccurrenceTransactionalFailure();
      }

      // The queue becomes the owner only after the committed row and its
      // canonical JPEG have both been re-read and verified. The E1 lease is a
      // duplicate temporary artifact at this point, so cleanup cannot revoke
      // durable ownership. PrivatePreparedImage logs cleanup failures itself;
      // a throwing alternative lease is also non-fatal after durable commit.
      try {
        await source.withdrawOwnership();
      } catch (_) {
        // The committed queue record and canonical JPEG remain authoritative.
      }
      return const OccurrencePersisted(QueueSnapshot.initializing());
    } catch (_) {
      if (!transactionCommitted) {
        // This projection is assigned only after this operation successfully
        // publishes its own staging file. Therefore compensation can never
        // target a pre-existing destination that rejected publication.
        final imageToCompensate = publishedImage;
        if (imageToCompensate != null) {
          try {
            // PrivateDurableImageStore leaves a recognized canonical/deleting
            // artifact in place when deletion cannot complete, so recovery can
            // reconcile the orphan without risking an unrelated file.
            await imageStore.delete(imageToCompensate);
          } catch (_) {
            // Preserve the recognizable current-operation orphan for recovery.
          }
        }
        if (staging != null) {
          try {
            await staging.discard();
          } catch (_) {
            // Preserve the original controlled transaction failure.
          }
        }
      }
      return const OccurrenceTransactionalFailure();
    }
  }

  @override
  Future<QueueRemovalResult> remove(
    QueueDatabase database,
    DurableImageStore imageStore,
    String idempotencyKey,
  ) async {
    final rows = await database.database.query(
      e2QueueTable,
      where: '${QueueRecordColumns.idempotencyKey} = ?',
      whereArgs: <Object>[idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const QueueOccurrenceNotFound(QueueSnapshot.initializing());
    }

    final record = mapper.fromMap(rows.single);
    if (await imageStore.inspect(record.image) != DurableImageIntegrity.valid) {
      return const QueueOccurrenceRemovalFailed();
    }

    DurableImageDeletion? deletion;
    var committed = false;
    try {
      deletion = await imageStore.markForDeletion(record.image);
      await database.database.transaction((transaction) async {
        final revalidated = await transaction.query(
          e2QueueTable,
          where: '${QueueRecordColumns.idempotencyKey} = ?',
          whereArgs: <Object>[idempotencyKey],
          limit: 1,
        );
        if (revalidated.length != 1) {
          throw StateError('Removal record changed before commit.');
        }

        final current = mapper.fromMap(revalidated.single);
        if (current.image.relativeName != record.image.relativeName ||
            current.image.sha256 != record.image.sha256) {
          throw StateError('Removal image reference changed before commit.');
        }

        final deleted = await transaction.delete(
          e2QueueTable,
          where: '${QueueRecordColumns.idempotencyKey} = ? AND '
              '${QueueRecordColumns.imageRelativeName} = ? AND '
              '${QueueRecordColumns.imageSha256} = ?',
          whereArgs: <Object>[
            idempotencyKey,
            record.image.relativeName,
            record.image.sha256,
          ],
        );
        if (deleted != 1) {
          throw StateError('Removal record was not deleted.');
        }
      });
      committed = true;

      // A cleanup failure leaves only this recognized marker. Recovery can
      // retire it because the committed row no longer exists, so the removal
      // remains confirmed and must not be rolled back to a partial state.
      try {
        await deletion.finalizeAfterCommit();
      } catch (_) {}
      return const QueueOccurrenceRemoved(QueueSnapshot.initializing());
    } catch (_) {
      // Before commit the retained row and its `.deleting` marker are a
      // recoverable state; never delete or overwrite either from this path.
      if (committed) {
        return const QueueOccurrenceRemoved(QueueSnapshot.initializing());
      }
      return const QueueOccurrenceRemovalFailed();
    }
  }
}

Future<bool> _hasValidRecoveredImage(
  QueueRecordProjection record,
  DurableImageStore imageStore,
  E2DurableImageNameCodec nameCodec,
) async {
  final image = record.image;
  if (!nameCodec.isCanonicalName(image.relativeName)) {
    return false;
  }

  try {
    // openRead validates that the opaque name resolves to a direct canonical
    // file in the E2 namespace. The digest consumes it incrementally, so
    // recovery does not load all JPEGs into memory.
    final digest = await _digestStream(imageStore.openRead(image));
    return _persistedBytesMatchRecord(image, digest);
  } catch (_) {
    // Absence, an unsafe reference, and stream failures all mean this pending
    // record is not reconstructable. The caller retains it and exposes only
    // aggregate degraded health, never filesystem details.
    return false;
  }
}

Future<bool> _isCommittedPersistenceIntact({
  required QueueDatabase database,
  required DurableImageStore imageStore,
  required InMemoryOccurrence occurrence,
  required PersistedImageProjection publishedImage,
}) async {
  final rows = await database.database.query(
    e2QueueTable,
    where: '${QueueRecordColumns.idempotencyKey} = ?',
    whereArgs: <Object>[occurrence.idempotencyKey],
    limit: 1,
  );
  if (rows.length != 1) {
    return false;
  }

  final record = const QueueRecordMapper().fromMap(rows.single);
  if (!_recordMatchesCommittedOccurrence(
    record: record,
    occurrence: occurrence,
    publishedImage: publishedImage,
  )) {
    return false;
  }
  if (await imageStore.inspect(record.image) != DurableImageIntegrity.valid) {
    return false;
  }

  final durableDigest = await _digestStream(imageStore.openRead(record.image));
  return _persistedBytesMatchRecord(record.image, durableDigest);
}

bool _recordMatchesCommittedOccurrence({
  required QueueRecordProjection record,
  required InMemoryOccurrence occurrence,
  required PersistedImageProjection publishedImage,
}) {
  final image = record.image;
  return record.idempotencyKey == occurrence.idempotencyKey &&
      record.detectedAtIso8601 == occurrence.detectedAtIso8601 &&
      record.latitude == occurrence.latitude &&
      record.longitude == occurrence.longitude &&
      record.accuracyMeters == occurrence.accuracyMeters &&
      record.speedKmh == occurrence.speedKmh &&
      record.confidence == occurrence.confidence &&
      record.defectClass == occurrence.defectClass &&
      image.relativeName == publishedImage.relativeName &&
      image.mimeType == publishedImage.mimeType &&
      image.byteLength == publishedImage.byteLength &&
      image.sha256 == publishedImage.sha256 &&
      image.width == publishedImage.width &&
      image.height == publishedImage.height &&
      image.quality == publishedImage.quality;
}

bool _isEquivalent({
  required InMemoryOccurrence occurrence,
  required PreparedImageMetadata preparedMetadata,
  required _StreamDigest preparedDigest,
  required QueueRecordProjection record,
  required _StreamDigest durableDigest,
}) {
  final image = record.image;
  return occurrence.idempotencyKey == record.idempotencyKey &&
      occurrence.detectedAtIso8601 == record.detectedAtIso8601 &&
      occurrence.latitude == record.latitude &&
      occurrence.longitude == record.longitude &&
      occurrence.accuracyMeters == record.accuracyMeters &&
      occurrence.speedKmh == record.speedKmh &&
      occurrence.confidence == record.confidence &&
      occurrence.defectClass == record.defectClass &&
      preparedMetadata.mimeType == image.mimeType &&
      preparedMetadata.byteLength == image.byteLength &&
      preparedMetadata.width == image.width &&
      preparedMetadata.height == image.height &&
      preparedMetadata.quality == image.quality &&
      preparedDigest.byteLength == image.byteLength &&
      preparedDigest.sha256 == image.sha256 &&
      durableDigest.byteLength == image.byteLength &&
      durableDigest.sha256 == image.sha256 &&
      preparedDigest.sha256 == durableDigest.sha256;
}

bool _preparedBytesMatchMetadata(
  PreparedImageMetadata metadata,
  _StreamDigest digest,
) {
  return metadata.mimeType == 'image/jpeg' &&
      metadata.byteLength == digest.byteLength &&
      metadata.width >= 1 &&
      metadata.width <= 1280 &&
      metadata.height >= 1 &&
      metadata.height <= 720 &&
      metadata.quality == 85;
}

bool _persistedBytesMatchRecord(
  PersistedImageProjection image,
  _StreamDigest digest,
) =>
    digest.byteLength == image.byteLength && digest.sha256 == image.sha256;

Future<_StreamDigest> _digestStream(Stream<List<int>> stream) async {
  final receiver = _QueueDigestReceiver();
  final input = sha256.startChunkedConversion(receiver);
  var byteLength = 0;
  var completed = false;
  try {
    await for (final chunk in stream) {
      byteLength += chunk.length;
      input.add(chunk);
    }
    input.close();
    completed = true;
    return _StreamDigest(
      byteLength: byteLength,
      sha256: receiver.digest.toString(),
    );
  } finally {
    if (!completed) {
      input.close();
    }
  }
}

final class _StreamDigest {
  const _StreamDigest({required this.byteLength, required this.sha256});

  final int byteLength;
  final String sha256;
}

final class _QueueDigestReceiver implements Sink<Digest> {
  Digest? _value;

  Digest get digest {
    final value = _value;
    if (value == null) {
      throw StateError('Digest was not completed.');
    }
    return value;
  }

  @override
  void add(Digest data) {
    if (_value != null) {
      throw StateError('More than one digest was produced.');
    }
    _value = data;
  }

  @override
  void close() {}
}

/// Controlled public-read failure after bootstrap could not confirm the queue.
final class QueueUnavailableException implements Exception {
  const QueueUnavailableException();

  @override
  String toString() => 'QueueUnavailableException';
}

/// Keeps the application and Diagnostic route available when queue setup
/// fails, without exposing the E2-only removal protocol to composition code.
final class UnavailablePersistentOccurrenceQueue
    implements PersistentOccurrenceQueue, OccurrenceAcceptancePort {
  const UnavailablePersistentOccurrenceQueue();

  static const QueueSnapshot _snapshot = QueueSnapshot(
    health: QueueHealth.unavailable,
    pendingCount: 0,
  );

  @override
  Stream<QueueSnapshot> get snapshots => const Stream<QueueSnapshot>.empty();

  @override
  Future<QueueSnapshot> bootstrap() async => _snapshot;

  @override
  Future<QueueSnapshot> retryBootstrap() async => _snapshot;

  @override
  Future<OccurrenceAcceptanceResult> accept(
    InMemoryOccurrence occurrence,
  ) async =>
      const OccurrenceStorageUnavailable();

  @override
  Future<List<ReconstructedPendingOccurrence>> listPending() =>
      Future<List<ReconstructedPendingOccurrence>>.error(
        const QueueUnavailableException(),
      );

  @override
  Future<int> countPending() => Future<int>.error(
        const QueueUnavailableException(),
      );

  @override
  Future<OccurrenceAcceptanceResult> persist(
    InMemoryOccurrence occurrence,
  ) =>
      accept(occurrence);

  @override
  Future<QueueRemovalResult> removeInternal(String idempotencyKey) async =>
      const QueueOccurrenceRemovalFailed();

  @override
  Future<void> close() async {}
}

/// SQLite/filesystem queue coordinator with one asynchronous single-writer
/// region shared by bootstrap, retry, recovery, mutation, reads, and close.
final class CoordinatedPersistentOccurrenceQueue
    implements PersistentOccurrenceQueue, OccurrenceAcceptancePort {
  CoordinatedPersistentOccurrenceQueue({
    required DurableImageStore imageStore,
    QueueDatabaseOpener databaseOpener = _openProductionQueueDatabase,
    QueueBootstrapRecovery recovery = const InitialQueueBootstrapRecovery(),
    QueueMutationDriver mutationDriver =
        const CrashConsistentQueueMutationDriver(),
    QueueRecordMapper mapper = const QueueRecordMapper(),
    E2QueueTechnicalLogger logger = _discardLog,
  })  : _imageStore = imageStore,
        _databaseOpener = databaseOpener,
        _recovery = recovery,
        _mutationDriver = mutationDriver,
        _mapper = mapper,
        _logger = logger;

  final DurableImageStore _imageStore;
  final QueueDatabaseOpener _databaseOpener;
  final QueueBootstrapRecovery _recovery;
  final QueueMutationDriver _mutationDriver;
  final QueueRecordMapper _mapper;
  final E2QueueTechnicalLogger _logger;
  final _AsyncSingleWriter _singleWriter = _AsyncSingleWriter();
  final StreamController<QueueSnapshot> _snapshots =
      StreamController<QueueSnapshot>.broadcast(sync: true);

  QueueDatabase? _database;
  QueueSnapshot? _confirmedSnapshot;
  List<QueueRecordProjection> _confirmedRecords =
      const <QueueRecordProjection>[];
  Future<QueueSnapshot>? _bootstrapInFlight;
  Future<void>? _closeInFlight;
  bool _closeRequested = false;
  bool _closed = false;

  @override
  Stream<QueueSnapshot> get snapshots => _snapshots.stream;

  /// Initializes once and shares concurrent work. A confirmed unavailable
  /// result remains stable until [retryBootstrap] is requested explicitly.
  @override
  Future<QueueSnapshot> bootstrap() {
    if (_closeRequested || _closed) {
      return Future<QueueSnapshot>.error(StateError('Queue is closed.'));
    }

    final active = _bootstrapInFlight;
    if (active != null) {
      return active;
    }

    final current = _confirmedSnapshot;
    if (current != null) {
      return Future<QueueSnapshot>.value(current);
    }

    return _startBootstrap();
  }

  /// Retries only queue-owned initialization after a confirmed failure.
  ///
  /// No camera, location, lifecycle, or navigation callback participates in
  /// this boundary. Callers can therefore keep the operational resources and
  /// the preserved Diagnostic route independent from queue recovery.
  @override
  Future<QueueSnapshot> retryBootstrap() {
    if (_closeRequested || _closed) {
      return Future<QueueSnapshot>.error(StateError('Queue is closed.'));
    }

    final active = _bootstrapInFlight;
    if (active != null) {
      return active;
    }

    final current = _confirmedSnapshot;
    if (current == null) {
      return _startBootstrap();
    }
    if (current.health != QueueHealth.unavailable) {
      return Future<QueueSnapshot>.value(current);
    }

    return _startBootstrap();
  }

  Future<QueueSnapshot> _startBootstrap() {
    final operation = _performBootstrap();
    _bootstrapInFlight = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_bootstrapInFlight, operation)) {
          _bootstrapInFlight = null;
        }
      }),
    );
    return operation;
  }

  Future<QueueSnapshot> _performBootstrap() {
    _publish(const QueueSnapshot.initializing(), confirmed: false);
    return _singleWriter.run<QueueSnapshot>(() async {
      QueueDatabase? opened;
      try {
        final previous = _database;
        _database = null;
        if (previous != null) {
          await previous.close();
        }

        _throwIfClosing();
        opened = await _databaseOpener();
        _throwIfClosing();
        final recovered = await _recovery.recover(opened, _imageStore);
        _throwIfClosing();

        _database = opened;
        opened = null;
        _confirmedRecords = recovered.records;
        final snapshot = QueueSnapshot(
          health: recovered.attentionCount == 0
              ? QueueHealth.ready
              : QueueHealth.degraded,
          pendingCount: recovered.records.length,
          attentionCount: recovered.attentionCount,
        );
        _publish(snapshot, confirmed: true);
        return snapshot;
      } catch (error) {
        if (opened != null) {
          try {
            await opened.close();
          } catch (closeError) {
            _logFailure('bootstrap_close', closeError);
          }
        }
        _database = null;
        _confirmedRecords = const <QueueRecordProjection>[];
        const unavailable = QueueSnapshot(
          health: QueueHealth.unavailable,
          pendingCount: 0,
        );
        _publish(unavailable, confirmed: true);
        _logFailure('bootstrap', error);
        return unavailable;
      }
    });
  }

  @override
  Future<OccurrenceAcceptanceResult> accept(
    InMemoryOccurrence occurrence,
  ) =>
      persist(occurrence);

  @override
  Future<OccurrenceAcceptanceResult> persist(
    InMemoryOccurrence occurrence,
  ) async {
    if (!await _awaitOperationalBootstrap()) {
      return const OccurrenceStorageUnavailable();
    }

    try {
      return await _singleWriter.run<OccurrenceAcceptanceResult>(() async {
        _throwIfClosing();
        final database = _requireDatabase();
        final result = await _mutationDriver.persist(
          database,
          _imageStore,
          occurrence,
        );
        if (result case OccurrenceAlreadyPersistedEquivalent()) {
          // The mutation driver proved that the existing row and JPEG are
          // canonical equivalents. Reuse the already confirmed state rather
          // than publishing or recalculating a count: this is a confirmation,
          // not a new local acceptance.
          final snapshot =
              _confirmedSnapshot ?? await _refreshConfirmedSnapshot(database);
          return OccurrenceAlreadyPersistedEquivalent(snapshot);
        }

        final snapshot = await _refreshConfirmedSnapshot(
          database,
          publish: result is OccurrencePersisted,
        );
        return switch (result) {
          OccurrencePersisted() => OccurrencePersisted(snapshot),
          _ => result,
        };
      });
    } catch (error) {
      _logFailure('persist', error);
      return const OccurrenceTransactionalFailure();
    }
  }

  @override
  Future<List<ReconstructedPendingOccurrence>> listPending() async {
    await _requireOperationalBootstrap();
    try {
      return await _singleWriter
          .run<List<ReconstructedPendingOccurrence>>(() async {
        _throwIfClosing();
        final snapshot = await _refreshConfirmedSnapshot(_requireDatabase());
        if (snapshot.health == QueueHealth.unavailable) {
          throw const QueueUnavailableException();
        }
        return List<ReconstructedPendingOccurrence>.unmodifiable(
          _confirmedRecords.map(ReconstructedPendingOccurrence.new),
        );
      });
    } catch (error) {
      _logFailure('list', error);
      if (error is StateError) {
        rethrow;
      }
      throw const QueueUnavailableException();
    }
  }

  @override
  Future<int> countPending() async {
    await _requireOperationalBootstrap();
    try {
      return await _singleWriter.run<int>(() async {
        _throwIfClosing();
        final snapshot = await _refreshConfirmedSnapshot(_requireDatabase());
        if (snapshot.health == QueueHealth.unavailable) {
          throw const QueueUnavailableException();
        }
        return snapshot.pendingCount;
      });
    } catch (error) {
      _logFailure('count', error);
      if (error is StateError) {
        rethrow;
      }
      throw const QueueUnavailableException();
    }
  }

  @override
  Future<QueueRemovalResult> removeInternal(String idempotencyKey) async {
    if (!await _awaitOperationalBootstrap()) {
      return const QueueOccurrenceRemovalFailed();
    }

    try {
      return await _singleWriter.run<QueueRemovalResult>(() async {
        _throwIfClosing();
        final database = _requireDatabase();
        final result = await _mutationDriver.remove(
          database,
          _imageStore,
          idempotencyKey,
        );
        if (result is QueueOccurrenceRemoved) {
          // The mutation driver returns this result only after its SQLite
          // removal commits. Refreshing and publishing here therefore makes
          // the visible count move only with a confirmed removal.
          final snapshot = await _refreshConfirmedSnapshot(
            database,
            publish: true,
          );
          return QueueOccurrenceRemoved(snapshot);
        }

        final confirmedSnapshot = _confirmedSnapshot;
        if (result is QueueOccurrenceNotFound && confirmedSnapshot != null) {
          // A missing key is idempotent and cannot change confirmed rows.
          return QueueOccurrenceNotFound(confirmedSnapshot);
        }

        // Failures must retain the last confirmed aggregate. In particular,
        // never derive or publish a lower count from an unconfirmed removal.
        return result;
      });
    } catch (error) {
      _logFailure('remove', error);
      return const QueueOccurrenceRemovalFailed();
    }
  }

  @override
  Future<void> close() {
    final active = _closeInFlight;
    if (active != null) {
      return active;
    }
    if (_closed) {
      return Future<void>.value();
    }

    _closeRequested = true;
    final operation = _singleWriter.run<void>(() async {
      if (_closed) {
        return;
      }
      final database = _database;
      _database = null;
      if (database != null) {
        await database.close();
      }
      _confirmedRecords = const <QueueRecordProjection>[];
      _closed = true;
      await _snapshots.close();
    });
    _closeInFlight = operation;
    return operation;
  }

  Future<bool> _awaitOperationalBootstrap() async {
    if (_closeRequested || _closed) {
      return false;
    }

    // A retry can be active while the last confirmed snapshot is unavailable.
    // Public reads and mutations must wait for that retry's recovery to publish
    // its next confirmed snapshot instead of observing the stale failure.
    final activeBootstrap = _bootstrapInFlight;
    final QueueSnapshot snapshot;
    if (activeBootstrap != null) {
      snapshot = await activeBootstrap;
    } else {
      final current = _confirmedSnapshot;
      snapshot = current == null || current.health == QueueHealth.initializing
          ? await bootstrap()
          : current;
    }
    return snapshot.health == QueueHealth.ready ||
        snapshot.health == QueueHealth.degraded;
  }

  Future<void> _requireOperationalBootstrap() async {
    if (_closeRequested || _closed) {
      throw StateError('Queue is closed.');
    }
    if (!await _awaitOperationalBootstrap()) {
      throw const QueueUnavailableException();
    }
  }

  Future<QueueSnapshot> _refreshConfirmedSnapshot(
    QueueDatabase database, {
    bool publish = false,
  }) async {
    final rows = await database.database.query(
      e2QueueTable,
      orderBy: QueueRecordColumns.queueSequence,
    );
    _confirmedRecords = List<QueueRecordProjection>.unmodifiable(
      rows.map(_mapper.fromMap),
    );
    final attentionCount = _confirmedSnapshot?.attentionCount ?? 0;
    final snapshot = QueueSnapshot(
      health: attentionCount == 0 ? QueueHealth.ready : QueueHealth.degraded,
      pendingCount: _confirmedRecords.length,
      attentionCount: attentionCount,
    );
    if (publish) {
      _publish(snapshot, confirmed: true);
    } else {
      _confirmedSnapshot = snapshot;
    }
    return snapshot;
  }

  QueueDatabase _requireDatabase() {
    final database = _database;
    if (database == null) {
      throw const QueueUnavailableException();
    }
    return database;
  }

  void _publish(QueueSnapshot snapshot, {required bool confirmed}) {
    if (confirmed) {
      _confirmedSnapshot = snapshot;
    }
    if (!_snapshots.isClosed) {
      _snapshots.add(snapshot);
    }
  }

  void _throwIfClosing() {
    if (_closeRequested || _closed) {
      throw StateError('Queue is closed.');
    }
  }

  void _logFailure(String operation, Object error) {
    try {
      _logger(
        'E2_QUEUE_OPERATION_FAILED operation=$operation '
        'error=${error.runtimeType}',
      );
    } catch (_) {
      // Technical logging must never alter queue consistency.
    }
  }
}

/// FIFO asynchronous critical section whose tail always completes successfully,
/// so one failed operation cannot break serialization of later operations.
final class _AsyncSingleWriter {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final completion = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completion.complete(await operation());
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }
}

Future<QueueDatabase> _openProductionQueueDatabase() => QueueDatabase.open();

void _discardLog(String _) {}
