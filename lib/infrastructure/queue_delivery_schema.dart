import 'package:sqflite/sqflite.dart';

import '../domain/persistent_occurrence.dart';
import 'queue_record_mapper.dart';

/// Physical names of the additive E4 structures of schema v2.
///
/// These tables never change the canonical E2 `pendingOccurrences` table. They
/// hold per-occurrence delivery state, the single global pause control, and the
/// last-accepted-occurrence anchor that backs the cooldown rule.
const String e4DeliveryStateTable = 'occurrence_delivery_state';
const String e4DeliveryControlTable = 'occurrence_delivery_control';
const String e4AcceptedAnchorTable = 'accepted_occurrence_anchor';

/// Singleton row id shared by the control and anchor tables.
const int e4SingletonId = 1;

/// Creates the E4 structures of schema v2 without touching E2 data.
///
/// [pendingTable] is the E2 table that owns the occurrences. The delivery state
/// references its `idempotencyKey` (a `UNIQUE` column), so removing an
/// occurrence removes its state by cascade once foreign keys are enabled. The
/// anchor deliberately has no foreign key: it must outlive every pending row.
///
/// A row is absent from [e4DeliveryStateTable] until the first recoverable
/// failure (absence means zero attempts, eligible now, no decision). The
/// control and anchor tables start empty on a fresh database; an absent control
/// row means "not paused".
Future<void> createE4DeliverySchemaV2(
  DatabaseExecutor database, {
  required String pendingTable,
}) async {
  await database.execute('''
CREATE TABLE $e4DeliveryStateTable (
  idempotency_key TEXT NOT NULL COLLATE BINARY PRIMARY KEY
    REFERENCES $pendingTable(${QueueRecordColumns.idempotencyKey})
    ON DELETE CASCADE,
  attempt_count INTEGER NOT NULL DEFAULT 0
    CHECK (typeof(attempt_count) = 'integer' AND attempt_count >= 0),
  backoff_calculated_at TEXT,
  next_attempt_at TEXT,
  pending_local_disposition TEXT
    CHECK (
      pending_local_disposition IS NULL OR
      pending_local_disposition IN (
        'created',
        'alreadyExisting',
        'invalidContract',
        'conflict',
        'imageTooLarge',
        'unsupportedFormat'
      )
    ),
  cleanup_attempt_count INTEGER NOT NULL DEFAULT 0
    CHECK (
      typeof(cleanup_attempt_count) = 'integer' AND cleanup_attempt_count >= 0
    ),
  next_cleanup_at TEXT
)
''');

  await database.execute('''
CREATE TABLE $e4DeliveryControlTable (
  singleton_id INTEGER NOT NULL PRIMARY KEY
    CHECK (singleton_id = $e4SingletonId),
  pause_reason TEXT NOT NULL
    CHECK (
      pause_reason IN (
        'none',
        'authentication',
        'access',
        'unexpectedResponse',
        'localFailure'
      )
    ),
  unexpected_status INTEGER
    CHECK (
      unexpected_status IS NULL OR
      (typeof(unexpected_status) = 'integer' AND unexpected_status BETWEEN 100 AND 599)
    ),
  updated_at TEXT NOT NULL,
  CHECK ((pause_reason = 'unexpectedResponse') = (unexpected_status IS NOT NULL))
)
''');

  await database.execute('''
CREATE TABLE $e4AcceptedAnchorTable (
  singleton_id INTEGER NOT NULL PRIMARY KEY
    CHECK (singleton_id = $e4SingletonId),
  queue_sequence INTEGER NOT NULL
    CHECK (typeof(queue_sequence) = 'integer' AND queue_sequence >= 1),
  detected_at TEXT NOT NULL COLLATE BINARY,
  latitude REAL NOT NULL CHECK (latitude BETWEEN -90.0 AND 90.0),
  longitude REAL NOT NULL CHECK (longitude BETWEEN -180.0 AND 180.0)
)
''');
}

/// Seeds the anchor from the pending row with the greatest `queueSequence`.
///
/// Does nothing when the queue is empty or an anchor already exists, so it is
/// safe to run only inside the v1 to v2 migration transaction.
Future<void> seedAcceptedAnchorFromQueue(
  DatabaseExecutor database, {
  required String pendingTable,
}) async {
  await database.execute('''
INSERT OR IGNORE INTO $e4AcceptedAnchorTable (
  singleton_id, queue_sequence, detected_at, latitude, longitude
)
SELECT
  $e4SingletonId,
  ${QueueRecordColumns.queueSequence},
  ${QueueRecordColumns.detectedAtIso8601},
  ${QueueRecordColumns.latitude},
  ${QueueRecordColumns.longitude}
FROM $pendingTable
ORDER BY ${QueueRecordColumns.queueSequence} DESC
LIMIT 1
''');
}

/// Moves the singleton anchor to the occurrence just inserted.
///
/// Must run on the same transaction executor as the insert of the occurrence,
/// so the anchor and the accepted row commit or roll back together. Removals
/// never call this, and nothing deletes the anchor row.
Future<void> recordAcceptedAnchor(
  DatabaseExecutor database, {
  required int queueSequence,
  required String detectedAtIso8601,
  required double latitude,
  required double longitude,
}) async {
  await database.insert(
    e4AcceptedAnchorTable,
    <String, Object?>{
      'singleton_id': e4SingletonId,
      'queue_sequence': queueSequence,
      'detected_at': detectedAtIso8601,
      'latitude': latitude,
      'longitude': longitude,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

/// Reads the singleton anchor, or `null` when no occurrence was ever accepted.
Future<AcceptedOccurrenceAnchor?> loadAcceptedAnchor(
  DatabaseExecutor database,
) async {
  final rows = await database.query(
    e4AcceptedAnchorTable,
    where: 'singleton_id = ?',
    whereArgs: <Object>[e4SingletonId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  final row = rows.single;
  final queueSequence = row['queue_sequence'];
  final detectedAt = row['detected_at'];
  final latitude = row['latitude'];
  final longitude = row['longitude'];
  if (queueSequence is! int ||
      detectedAt is! String ||
      latitude is! num ||
      longitude is! num) {
    throw const FormatException('Invalid persisted accepted anchor.');
  }
  return AcceptedOccurrenceAnchor(
    queueSequence: queueSequence,
    detectedAtIso8601: detectedAt,
    latitude: latitude.toDouble(),
    longitude: longitude.toDouble(),
  );
}

/// Deletes delivery-state rows whose occurrence no longer exists.
///
/// With foreign keys enforced the cascade already prevents orphans; this
/// covers rows left by a connection that ran without enforcement. The single
/// statement is atomic and idempotent: a second run deletes nothing. It never
/// touches [pendingTable], the control or anchor tables, or image files.
/// Returns the number of removed rows.
Future<int> removeOrphanDeliveryStates(
  DatabaseExecutor database, {
  required String pendingTable,
}) {
  return database.rawDelete('''
DELETE FROM $e4DeliveryStateTable
WHERE NOT EXISTS (
  SELECT 1 FROM $pendingTable
  WHERE $pendingTable.${QueueRecordColumns.idempotencyKey} =
    $e4DeliveryStateTable.idempotency_key
)
''');
}

/// Purely additive v1 to v2 migration.
///
/// Must run inside the open/upgrade transaction owned by the database opener.
/// It only creates the E4 structures and seeds the anchor; it never drops,
/// recreates, or rewrites `pendingOccurrences`, and never touches image files.
Future<void> migrateQueueSchemaV1ToV2(
  DatabaseExecutor database, {
  required String pendingTable,
}) async {
  await createE4DeliverySchemaV2(database, pendingTable: pendingTable);
  await seedAcceptedAnchorFromQueue(database, pendingTable: pendingTable);
}
