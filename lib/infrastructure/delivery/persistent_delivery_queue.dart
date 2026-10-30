import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../application/delivery/occurrence_delivery_queue_port.dart';
import '../../application/e1_ports.dart';
import '../../application/e2_persistence_ports.dart';
import '../../domain/delivery/delivery_backoff_policy.dart';
import '../../domain/delivery/delivery_decision.dart';
import '../../domain/delivery/delivery_queue_head.dart';
import '../../domain/persistent_occurrence.dart';
import '../persistent_occurrence_queue.dart';
import '../queue_database.dart';
import '../queue_delivery_schema.dart';
import '../queue_record_mapper.dart';
import '../system_clock.dart';

/// SQLite/filesystem delivery queue (design E4.5/E4.6).
///
/// Every database or image access runs in the single-writer region owned by
/// [CoordinatedPersistentOccurrenceQueue], the same one used by bootstrap,
/// recovery, persistence, reads, and removal. The region is released before any
/// byte is streamed, so the network never keeps it locked.
///
/// This type exposes the head selection, the private JPEG read, the aggregate
/// summaries, the recoverable-failure record, the persisted global pause, and
/// the durable definitive-decision mark with its local-only removal of
/// [OccurrenceDeliveryQueuePort], and the persisted cleanup-failure record
/// with its bounded next-cleanup instant.
final class PersistentDeliveryQueue implements OccurrenceDeliveryQueuePort {
  PersistentDeliveryQueue(
    this._queue, {
    QueueRecordMapper mapper = const QueueRecordMapper(),
    Clock clock = const SystemClock(),
  })  : _mapper = mapper,
        _clock = clock;

  /// Saturation of the persisted attempt counter. The backoff delay reaches
  /// its ceiling long before this, so saturating changes no behavior and keeps
  /// the counter far from any integer overflow.
  static const int maximumAttemptCount = 1 << 30;

  final CoordinatedPersistentOccurrenceQueue _queue;
  final QueueRecordMapper _mapper;
  final Clock _clock;

  /// Selects the FIFO head as of [now].
  ///
  /// Only the lowest `queueSequence` is considered: a head in backoff is never
  /// overtaken by a later item. Persisted backoff instants are reconciled here
  /// (see [_selectHead]). Failures are reported as [DeliveryQueueUnavailable]
  /// without exception text.
  @override
  Future<DeliveryHeadResult> nextHead(DateTime now) async {
    try {
      return await _queue.runInSerialRegion<DeliveryHeadResult>(
        (database, imageStore) => _selectHead(database, imageStore, now),
      );
    } catch (_) {
      return const DeliveryQueueUnavailable();
    }
  }

  /// Opens the JPEG of [head] as a single-subscription stream.
  ///
  /// The head identity and image reference are rechecked against the current
  /// row inside the serial region on listen; the region is then released and
  /// the bytes are read outside it. Any mismatch, missing file, or length
  /// divergence is delivered as a stream error.
  @override
  Stream<List<int>> openImage(DeliveryHeadEligible head) async* {
    final reference = head.payload.image;
    final handle = reference.opaqueHandle;
    if (handle is! _PrivateImageHandle) {
      throw StateError('The image reference was not issued by this queue.');
    }

    final source = await _queue.runInSerialRegion<Stream<List<int>>>(
      (database, imageStore) async {
        final rows = await database.database.query(
          e2QueueTable,
          where: '${QueueRecordColumns.idempotencyKey} = ?',
          whereArgs: <Object>[head.head.idempotencyKey],
          limit: 1,
        );
        if (rows.length != 1) {
          throw StateError('The head is no longer queued.');
        }
        final image = _mapper.fromMap(rows.single).image;
        final expected = handle.image;
        if (image.relativeName != expected.relativeName ||
            image.sha256 != expected.sha256 ||
            image.byteLength != reference.byteLength ||
            image.byteLength != expected.byteLength) {
          throw StateError('The head image reference changed.');
        }
        return imageStore.openRead(image);
      },
    );

    var received = 0;
    await for (final chunk in source) {
      received += chunk.length;
      yield chunk;
    }
    if (received != reference.byteLength) {
      throw StateError('The image length diverged from the queue record.');
    }
  }

  /// Aggregate-only summaries, shared with the E2 queue snapshots.
  @override
  Stream<DeliveryQueueSummary> watchSummary() => _queue.snapshots;

  /// Records one more consecutive recoverable failure for [idempotencyKey].
  ///
  /// In one SQLite transaction inside the serial region, the state row is
  /// created (first failure) or its `attempt_count` is incremented, and
  /// `backoff_calculated_at` / `next_attempt_at` are replaced by the given
  /// instants in UTC. Nothing is changed when the result is not
  /// [DeliveryMutationResult.applied]. An item that already has a recorded
  /// definitive decision is never given a retry instant.
  ///
  /// Throws [ArgumentError] when [nextAttemptAt] is not after [calculatedAt]
  /// or the delay exceeds [DeliveryBackoffPolicy.maxDelay].
  @override
  Future<DeliveryMutationResult> recordRecoverableFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextAttemptAt,
  ) async {
    final delay = nextAttemptAt.difference(calculatedAt);
    if (delay <= Duration.zero || delay > DeliveryBackoffPolicy.maxDelay) {
      throw ArgumentError(
        'The backoff delay must be positive and not above the ceiling.',
      );
    }

    try {
      return await _queue.runInSerialRegion<DeliveryMutationResult>(
        (database, imageStore) => database.database
            .transaction<DeliveryMutationResult>((transaction) async {
          final occurrence = await transaction.query(
            e2QueueTable,
            columns: <String>[QueueRecordColumns.idempotencyKey],
            where: '${QueueRecordColumns.idempotencyKey} = ?',
            whereArgs: <Object>[idempotencyKey],
            limit: 1,
          );
          if (occurrence.isEmpty) {
            return DeliveryMutationResult.notFound;
          }

          final instants = <String, Object?>{
            'backoff_calculated_at': _formatInstant(calculatedAt),
            'next_attempt_at': _formatInstant(nextAttemptAt),
          };
          final state = await transaction.query(
            e4DeliveryStateTable,
            columns: <String>['attempt_count', 'pending_local_disposition'],
            where: 'idempotency_key = ?',
            whereArgs: <Object>[idempotencyKey],
            limit: 1,
          );
          if (state.isEmpty) {
            await transaction.insert(e4DeliveryStateTable, <String, Object?>{
              'idempotency_key': idempotencyKey,
              'attempt_count': 1,
              ...instants,
            });
            return DeliveryMutationResult.applied;
          }

          final previous = state.single['attempt_count'];
          if (previous is! int || previous < 0) {
            throw const FormatException('Invalid persisted attempt count.');
          }
          if (state.single['pending_local_disposition'] != null) {
            return DeliveryMutationResult.storageFailure;
          }
          await transaction.update(
            e4DeliveryStateTable,
            <String, Object?>{
              'attempt_count': previous >= maximumAttemptCount
                  ? maximumAttemptCount
                  : previous + 1,
              ...instants,
            },
            where: 'idempotency_key = ?',
            whereArgs: <Object>[idempotencyKey],
          );
          return DeliveryMutationResult.applied;
        }),
      );
    } catch (_) {
      return DeliveryMutationResult.storageFailure;
    }
  }

  /// Durably marks the definitive remote [disposition] of [idempotencyKey]
  /// before any local removal starts.
  ///
  /// In one SQLite transaction inside the serial region, the state row is
  /// created or updated with `pending_local_disposition`; the attempt counter
  /// is kept and the retry instants are cleared, since the item will never be
  /// sent again. The mark is permanent until the occurrence is removed (the
  /// state row then disappears by cascade): repeating the same disposition is
  /// an idempotent [DeliveryMutationResult.applied], while a different one is
  /// refused as [DeliveryMutationResult.storageFailure] and changes nothing.
  /// Neither the occurrence, its JPEG, nor the accepted anchor is touched.
  @override
  Future<DeliveryMutationResult> recordDefinitiveDecision(
    String idempotencyKey,
    DeliveryDisposition disposition,
  ) async {
    try {
      return await _queue.runInSerialRegion<DeliveryMutationResult>(
        (database, imageStore) => database.database
            .transaction<DeliveryMutationResult>((transaction) async {
          final occurrence = await transaction.query(
            e2QueueTable,
            columns: <String>[QueueRecordColumns.idempotencyKey],
            where: '${QueueRecordColumns.idempotencyKey} = ?',
            whereArgs: <Object>[idempotencyKey],
            limit: 1,
          );
          if (occurrence.isEmpty) {
            return DeliveryMutationResult.notFound;
          }

          final state = await transaction.query(
            e4DeliveryStateTable,
            columns: <String>['pending_local_disposition'],
            where: 'idempotency_key = ?',
            whereArgs: <Object>[idempotencyKey],
            limit: 1,
          );
          if (state.isEmpty) {
            await transaction.insert(e4DeliveryStateTable, <String, Object?>{
              'idempotency_key': idempotencyKey,
              'attempt_count': 0,
              'pending_local_disposition': disposition.name,
            });
            return DeliveryMutationResult.applied;
          }

          final recorded = state.single['pending_local_disposition'];
          if (recorded != null) {
            return recorded == disposition.name
                ? DeliveryMutationResult.applied
                : DeliveryMutationResult.storageFailure;
          }
          await transaction.update(
            e4DeliveryStateTable,
            <String, Object?>{
              'pending_local_disposition': disposition.name,
              'backoff_calculated_at': null,
              'next_attempt_at': null,
            },
            where: 'idempotency_key = ?',
            whereArgs: <Object>[idempotencyKey],
          );
          return DeliveryMutationResult.applied;
        }),
      );
    } catch (_) {
      return DeliveryMutationResult.storageFailure;
    }
  }

  /// Removes the row and JPEG of an item whose definitive decision was marked.
  ///
  /// Local only: it needs no destination, credential, or configuration and
  /// never touches the network, so it also finishes the removal after a
  /// restart. The mark is verified inside the serial region first; an item
  /// that exists without a mark is refused with [QueueOccurrenceRemovalFailed]
  /// and left intact. The removal itself is the E2 protocol (row and JPEG),
  /// run in the same serial region afterwards. Because the mark is never
  /// cleared before the row is deleted, nothing can invalidate the check in
  /// between. Removing an absent item is an idempotent
  /// [QueueOccurrenceNotFound]. The accepted anchor is never touched.
  ///
  /// While a recorded cleanup failure still defers the next attempt (see
  /// [recordCleanupFailure]), the call is refused with
  /// [QueueOccurrenceRemovalFailed] without touching the item, so a manual
  /// retry cannot anticipate the scheduled instant. A deadline that is
  /// unreadable or that a regressed clock left beyond the ceiling is
  /// reconciled as in [nextHead].
  @override
  Future<QueueRemovalResult> completePendingLocalRemoval(
    String idempotencyKey,
  ) async {
    try {
      final refused = await _queue.runInSerialRegion<bool>(
        (database, imageStore) async {
          final rows = await database.database.rawQuery(
            '''
SELECT
  s.pending_local_disposition AS mark,
  s.cleanup_attempt_count AS $_cleanupAttemptCount,
  s.next_cleanup_at AS $_nextCleanupAt
FROM $e2QueueTable AS p
LEFT JOIN $e4DeliveryStateTable AS s
  ON s.idempotency_key = p.${QueueRecordColumns.idempotencyKey}
WHERE p.${QueueRecordColumns.idempotencyKey} = ?
LIMIT 1
''',
            <Object>[idempotencyKey],
          );
          if (rows.isEmpty) {
            return false;
          }
          final row = rows.single;
          if (row['mark'] == null) {
            return true;
          }
          // A previous cleanup failure scheduled the next attempt: no caller,
          // including a manual retry, may run the removal before that instant.
          final dueAt = await _reconcileCleanupDeadline(
            database.database,
            idempotencyKey,
            _intOrZero(row, _cleanupAttemptCount),
            _clock.now(),
            row[_nextCleanupAt],
          );
          return dueAt != null;
        },
      );
      if (refused) {
        return const QueueOccurrenceRemovalFailed();
      }
      return await _queue.removeInternal(idempotencyKey);
    } catch (_) {
      return const QueueOccurrenceRemovalFailed();
    }
  }

  /// Records one more failed local cleanup of a decided item.
  ///
  /// In one SQLite transaction inside the serial region, `cleanup_attempt_count`
  /// is incremented (saturating at [maximumAttemptCount]) and `next_cleanup_at`
  /// is replaced by [nextCleanupAt] in UTC. The definitive disposition, the
  /// remote attempt count and retry instants, the occurrence, its JPEG and the
  /// accepted anchor are never touched, so the item stays decided and is never
  /// sent again.
  ///
  /// The change is refused as [DeliveryMutationResult.storageFailure], leaving
  /// everything intact, when the item has no recorded definitive decision or
  /// when its current cleanup deadline is still in the future relative to
  /// [calculatedAt]: a failure can only follow an attempt that was due, so
  /// such a call must not replace (and thereby anticipate or inflate) the
  /// scheduled deadline. A deadline further than
  /// [DeliveryBackoffPolicy.maxDelay] ahead can only be left by a clock that
  /// moved backwards and is replaced.
  ///
  /// Throws [ArgumentError] when [nextCleanupAt] is not after [calculatedAt]
  /// or the delay exceeds [DeliveryBackoffPolicy.maxDelay]. Callers compute
  /// the delay with [DeliveryBackoffPolicy.delayFor] over the cleanup attempt
  /// number.
  @override
  Future<DeliveryMutationResult> recordCleanupFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextCleanupAt,
  ) async {
    final delay = nextCleanupAt.difference(calculatedAt);
    if (delay <= Duration.zero || delay > DeliveryBackoffPolicy.maxDelay) {
      throw ArgumentError(
        'The cleanup delay must be positive and not above the ceiling.',
      );
    }

    try {
      return await _queue.runInSerialRegion<DeliveryMutationResult>(
        (database, imageStore) => database.database
            .transaction<DeliveryMutationResult>((transaction) async {
          final rows = await transaction.rawQuery(
            '''
SELECT
  s.pending_local_disposition AS mark,
  s.cleanup_attempt_count AS $_cleanupAttemptCount,
  s.next_cleanup_at AS $_nextCleanupAt
FROM $e2QueueTable AS p
LEFT JOIN $e4DeliveryStateTable AS s
  ON s.idempotency_key = p.${QueueRecordColumns.idempotencyKey}
WHERE p.${QueueRecordColumns.idempotencyKey} = ?
LIMIT 1
''',
            <Object>[idempotencyKey],
          );
          if (rows.isEmpty) {
            return DeliveryMutationResult.notFound;
          }

          final row = rows.single;
          if (row['mark'] == null) {
            return DeliveryMutationResult.storageFailure;
          }
          final previous = _intOrZero(row, _cleanupAttemptCount);
          final scheduled = _parseInstant(row[_nextCleanupAt]);
          if (scheduled != null &&
              calculatedAt.isBefore(scheduled) &&
              scheduled.difference(calculatedAt) <=
                  DeliveryBackoffPolicy.maxDelay) {
            return DeliveryMutationResult.storageFailure;
          }

          await transaction.update(
            e4DeliveryStateTable,
            <String, Object?>{
              'cleanup_attempt_count': previous >= maximumAttemptCount
                  ? maximumAttemptCount
                  : previous + 1,
              'next_cleanup_at': _formatInstant(nextCleanupAt),
            },
            where: 'idempotency_key = ?',
            whereArgs: <Object>[idempotencyKey],
          );
          return DeliveryMutationResult.applied;
        }),
      );
    } catch (_) {
      return DeliveryMutationResult.storageFailure;
    }
  }

  /// Reads the persisted global pause control.
  ///
  /// An absent row or `none` means automatic delivery is allowed. Any
  /// unreadable value is reported as [DeliveryControlUnavailable].
  @override
  Future<DeliveryControl> readControl() async {
    try {
      return await _queue.runInSerialRegion<DeliveryControl>(
        (database, imageStore) async {
          final rows = await database.database.query(
            e4DeliveryControlTable,
            where: 'singleton_id = ?',
            whereArgs: <Object>[e4SingletonId],
            limit: 1,
          );
          if (rows.isEmpty) {
            return const DeliveryControlRunning();
          }
          final reason = rows.single['pause_reason'];
          if (reason == _noPause) {
            return const DeliveryControlRunning();
          }
          final parsed = reason is String ? _pauseReasons[reason] : null;
          final status = rows.single['unexpected_status'];
          if (parsed == null || (status != null && status is! int)) {
            return const DeliveryControlUnavailable();
          }
          return DeliveryControlPaused(
            parsed,
            unexpectedStatusCode: status as int?,
          );
        },
      );
    } catch (_) {
      return const DeliveryControlUnavailable();
    }
  }

  /// Persists an automatic pause in the singleton control row.
  ///
  /// Only the closed reason and, for an unexpected response, its numeric HTTP
  /// status (100 to 599) are stored: never a body, header, URL, or exception.
  /// A status outside that range is rejected by the schema and reported as
  /// [DeliveryMutationResult.storageFailure]. The per-item attempt and backoff
  /// state is not touched, and a pause does not increment any backoff.
  @override
  Future<DeliveryMutationResult> pause(PausedDeliveryDecision pause) =>
      _writeControl(pause.reason.name, pause.unexpectedStatusCode);

  /// Clears the persisted pause, leaving attempt counters and backoff intact.
  @override
  Future<DeliveryMutationResult> resume() => _writeControl(_noPause, null);

  Future<DeliveryMutationResult> _writeControl(
    String reason,
    int? unexpectedStatus,
  ) async {
    try {
      return await _queue.runInSerialRegion<DeliveryMutationResult>(
        (database, imageStore) async {
          await database.database.insert(
            e4DeliveryControlTable,
            <String, Object?>{
              'singleton_id': e4SingletonId,
              'pause_reason': reason,
              'unexpected_status': unexpectedStatus,
              'updated_at': _formatInstant(_clock.now()),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          return DeliveryMutationResult.applied;
        },
      );
    } catch (_) {
      return DeliveryMutationResult.storageFailure;
    }
  }

  /// Reconciles the persisted backoff of a head that is still waiting.
  ///
  /// A waiting head must never be postponed beyond [DeliveryBackoffPolicy.maxDelay]
  /// from [now]. This happens when the wall clock moved backwards since
  /// `backoff_calculated_at`, or when the stored deadline is implausibly far.
  /// The already calculated delay (capped at the ceiling, or recomputed from the
  /// attempt count when it is unusable) is then re-anchored at [now] and
  /// persisted in a single statement before the serial region is released, so a
  /// later reopening observes the reconciled values and does not postpone the
  /// same period again.
  Future<DateTime> _reconcileWaitingBackoff(
    Database database,
    DeliveryQueueHead head,
    DateTime now,
    DateTime nextAttemptAt,
    DateTime? calculatedAt,
  ) async {
    final regressed = calculatedAt != null && now.isBefore(calculatedAt);
    final tooFar =
        nextAttemptAt.difference(now) > DeliveryBackoffPolicy.maxDelay;
    if (!regressed && !tooFar) {
      return nextAttemptAt;
    }

    final recorded =
        calculatedAt == null ? null : nextAttemptAt.difference(calculatedAt);
    final Duration delay;
    if (recorded != null && recorded > Duration.zero) {
      delay = recorded > DeliveryBackoffPolicy.maxDelay
          ? DeliveryBackoffPolicy.maxDelay
          : recorded;
    } else {
      delay = DeliveryBackoffPolicy.delayFor(
        head.attemptCount < 1 ? 1 : head.attemptCount,
      );
    }

    final reconciledNext = now.toUtc().add(delay);
    await database.update(
      e4DeliveryStateTable,
      <String, Object?>{
        'backoff_calculated_at': _formatInstant(now),
        'next_attempt_at': _formatInstant(reconciledNext),
      },
      where: 'idempotency_key = ?',
      whereArgs: <Object>[head.idempotencyKey],
    );
    return reconciledNext;
  }

  /// Resolves the effective deadline of a pending local cleanup as of [now].
  ///
  /// Returns `null` when the cleanup may run now: no deadline, an unreadable
  /// one (cleared durably so the corruption is repaired once), or one already
  /// reached. A deadline further than [DeliveryBackoffPolicy.maxDelay] from
  /// [now] can only come from a wall clock that moved backwards, so it is
  /// re-anchored at [now] with the delay of the recorded cleanup attempts and
  /// persisted in a single statement. The cleanup is therefore never postponed
  /// beyond the ceiling, and a later reopening sees the same value.
  Future<DateTime?> _reconcileCleanupDeadline(
    Database database,
    String idempotencyKey,
    int cleanupAttemptCount,
    DateTime now,
    Object? stored,
  ) async {
    final deadline = _parseInstant(stored);
    if (stored != null && deadline == null) {
      await database.update(
        e4DeliveryStateTable,
        <String, Object?>{'next_cleanup_at': null},
        where: 'idempotency_key = ?',
        whereArgs: <Object>[idempotencyKey],
      );
      return null;
    }
    if (deadline == null || !now.isBefore(deadline)) {
      return null;
    }
    if (deadline.difference(now) <= DeliveryBackoffPolicy.maxDelay) {
      return deadline;
    }

    final reconciled = now.toUtc().add(
          DeliveryBackoffPolicy.delayFor(
            cleanupAttemptCount < 1 ? 1 : cleanupAttemptCount,
          ),
        );
    await database.update(
      e4DeliveryStateTable,
      <String, Object?>{'next_cleanup_at': _formatInstant(reconciled)},
      where: 'idempotency_key = ?',
      whereArgs: <Object>[idempotencyKey],
    );
    return reconciled;
  }

  Future<DeliveryHeadResult> _selectHead(
    QueueDatabase database,
    DurableImageStore imageStore,
    DateTime now,
  ) async {
    final rows = await database.database.rawQuery('''
SELECT
  p.*,
  s.attempt_count AS $_attemptCount,
  s.backoff_calculated_at AS $_backoffCalculatedAt,
  s.next_attempt_at AS $_nextAttemptAt,
  s.pending_local_disposition AS $_disposition,
  s.cleanup_attempt_count AS $_cleanupAttemptCount,
  s.next_cleanup_at AS $_nextCleanupAt
FROM $e2QueueTable AS p
LEFT JOIN $e4DeliveryStateTable AS s
  ON s.idempotency_key = p.${QueueRecordColumns.idempotencyKey}
ORDER BY p.${QueueRecordColumns.queueSequence} ASC
LIMIT 1
''');
    if (rows.isEmpty) {
      return const DeliveryQueueEmpty();
    }

    final row = rows.single;
    final head = DeliveryQueueHead(
      idempotencyKey: _string(row, QueueRecordColumns.idempotencyKey),
      queueSequence: _int(row, QueueRecordColumns.queueSequence),
      // Absence of a state row means zero attempts.
      attemptCount: _intOrZero(row, _attemptCount),
      cleanupAttemptCount: _intOrZero(row, _cleanupAttemptCount),
    );

    // A confirmed remote decision precedes pause, backoff, configuration and
    // image integrity: only the local removal is left.
    final disposition = row[_disposition];
    if (disposition != null) {
      final parsed = disposition is String
          ? DeliveryDisposition.values.asNameMap()[disposition]
          : null;
      if (parsed == null) {
        throw const FormatException('Invalid persisted disposition.');
      }
      return DeliveryHeadPendingCleanup(
        head: head,
        disposition: parsed,
        dueAt: await _reconcileCleanupDeadline(
          database.database,
          head.idempotencyKey,
          head.cleanupAttemptCount,
          now,
          row[_nextCleanupAt],
        ),
      );
    }

    final storedNextAttempt = row[_nextAttemptAt];
    final nextAttemptAt = _parseInstant(storedNextAttempt);
    if (storedNextAttempt != null && nextAttemptAt == null) {
      // An unreadable deadline never postpones the attempt. The two instants
      // are cleared (the attempt count is kept) so the corruption is repaired
      // once, durably, instead of being re-evaluated on every selection.
      await database.database.update(
        e4DeliveryStateTable,
        <String, Object?>{
          'backoff_calculated_at': null,
          'next_attempt_at': null,
        },
        where: 'idempotency_key = ?',
        whereArgs: <Object>[head.idempotencyKey],
      );
    } else if (nextAttemptAt != null && now.isBefore(nextAttemptAt)) {
      final waitingUntil = await _reconcileWaitingBackoff(
        database.database,
        head,
        now,
        nextAttemptAt,
        _parseInstant(row[_backoffCalculatedAt]),
      );
      return DeliveryHeadInBackoff(head: head, nextAttemptAt: waitingUntil);
    }

    final QueueRecordProjection record;
    try {
      record = _mapper.fromMap(row);
    } on FormatException {
      return DeliveryHeadLocalIntegrityFailure(head: head);
    }
    if (await imageStore.inspect(record.image) != DurableImageIntegrity.valid) {
      return DeliveryHeadLocalIntegrityFailure(head: head);
    }

    return DeliveryHeadEligible(
      head: head,
      payload: DeliveryOccurrencePayload(
        detectedAtIso8601: record.detectedAtIso8601,
        latitude: record.latitude,
        longitude: record.longitude,
        speedKmh: record.speedKmh,
        confidence: record.confidence,
        defectClass: record.defectClass,
        image: DeliveryImageRef(
          byteLength: record.image.byteLength,
          opaqueHandle: _PrivateImageHandle(record.image),
        ),
      ),
    );
  }
}

/// Column aliases of the joined delivery state.
const String _attemptCount = 'state_attempt_count';
const String _backoffCalculatedAt = 'state_backoff_calculated_at';
const String _nextAttemptAt = 'state_next_attempt_at';

/// Persisted value of the control row when no pause is active.
const String _noPause = 'none';

final Map<String, DeliveryPauseReason> _pauseReasons =
    DeliveryPauseReason.values.asNameMap();

/// Persisted instants are always UTC ISO 8601.
String _formatInstant(DateTime value) => value.toUtc().toIso8601String();
const String _disposition = 'state_disposition';
const String _cleanupAttemptCount = 'state_cleanup_attempt_count';
const String _nextCleanupAt = 'state_next_cleanup_at';

/// Queue-private image reference. It never leaves the delivery boundary and
/// reveals nothing through [toString].
final class _PrivateImageHandle {
  const _PrivateImageHandle(this.image);

  final PersistedImageProjection image;

  @override
  String toString() => '_PrivateImageHandle(<redacted>)';
}

String _string(Map<String, Object?> row, String column) {
  final value = row[column];
  if (value is! String) {
    throw FormatException('Invalid persisted value for $column.');
  }
  return value;
}

int _int(Map<String, Object?> row, String column) {
  final value = row[column];
  if (value is! int) {
    throw FormatException('Invalid persisted value for $column.');
  }
  return value;
}

int _intOrZero(Map<String, Object?> row, String column) {
  final value = row[column];
  if (value == null) {
    return 0;
  }
  if (value is! int) {
    throw FormatException('Invalid persisted value for $column.');
  }
  return value;
}

DateTime? _parseInstant(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
