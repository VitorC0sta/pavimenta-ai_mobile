import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'queue_delivery_schema.dart';
import 'queue_record_mapper.dart';
import 'queue_schema_v3_migration.dart';

const String e2QueueDatabaseName = 'e2_occurrence_queue_v1.db';

/// Schema v2 adds the E4 delivery structures; v1 stays the E2 layout. Schema
/// v3 (E5) only widens the `confidence` CHECK to model confidences in [0, 1].
const int e2QueueDatabaseVersion = 3;
const String e2QueueTable = 'pendingOccurrences';
const int e2MaximumImageByteLength = 2 * 1024 * 1024;

/// Raised when persisted data was created by a schema newer than this app.
final class UnsupportedQueueSchemaVersion implements Exception {
  const UnsupportedQueueSchemaVersion({
    required this.found,
    required this.supported,
  });

  final int found;
  final int supported;

  @override
  String toString() =>
      'Unsupported queue schema version: found $found, supported $supported.';
}

/// Raised when SQLite does not report `PRAGMA foreign_keys` as active, so the
/// delivery-state cascade could not be relied upon.
final class QueueForeignKeysUnavailable implements Exception {
  const QueueForeignKeysUnavailable();

  @override
  String toString() => 'SQLite foreign key enforcement is not active.';
}

/// Enables foreign key enforcement on [database] and validates that it is on.
///
/// SQLite scopes the pragma to the connection and ignores it inside a
/// transaction, so it must run on every connection from `onConfigure`.
Future<void> enableQueueForeignKeys(Database database) async {
  await database.execute('PRAGMA foreign_keys = ON');
  await verifyQueueForeignKeys(database);
}

/// Throws [QueueForeignKeysUnavailable] unless foreign keys are enforced.
Future<void> verifyQueueForeignKeys(Database database) async {
  final rows = await database.rawQuery('PRAGMA foreign_keys');
  if (rows.length != 1 || rows.single.values.single != 1) {
    throw const QueueForeignKeysUnavailable();
  }
}

/// Opens and owns the private SQLite database used by the E2 queue.
///
/// Production uses sqflite's private database directory. Tests can inject a
/// real SQLite factory and an isolated path without changing schema behavior.
final class QueueDatabase {
  QueueDatabase._(this.database, this.path);

  final Database database;
  final String path;

  static Future<QueueDatabase> open({
    DatabaseFactory? factory,
    String? path,
    QueueMigrationLogger migrationLogger = discardQueueMigrationLog,
  }) async {
    final selectedFactory = factory ?? databaseFactory;
    final selectedPath = path ??
        _appendPath(
          await selectedFactory.getDatabasesPath(),
          e2QueueDatabaseName,
        );

    // The v1/v2 to v3 rebuild runs before the regular open, on a dedicated
    // connection with foreign keys off (design E5.9). A failure propagates
    // and leaves the previous version untouched; the queue is then
    // unavailable with the E2 retry.
    await migrateQueueToSchemaV3(
      factory: selectedFactory,
      path: selectedPath,
      logger: migrationLogger,
    );

    final database = await selectedFactory.openDatabase(
      selectedPath,
      options: OpenDatabaseOptions(
        version: e2QueueDatabaseVersion,
        onConfigure: enableQueueForeignKeys,
        onOpen: verifyQueueForeignKeys,
        onCreate: (database, version) async {
          if (version != e2QueueDatabaseVersion) {
            throw UnsupportedQueueSchemaVersion(
              found: version,
              supported: e2QueueDatabaseVersion,
            );
          }
          await createQueuePendingTableV3(database);
          await createE4DeliverySchemaV2(
            database,
            pendingTable: e2QueueTable,
          );
        },
        // The pre-open migrator already brought v1 and v2 to v3. This callback
        // runs inside a transaction with foreign keys on, where rebuilding
        // pendingOccurrences would cascade-delete delivery states, so it never
        // migrates: reaching it means the pre-open step did not run.
        onUpgrade: (database, oldVersion, newVersion) async {
          throw UnsupportedQueueSchemaVersion(
            found: oldVersion,
            supported: e2QueueDatabaseVersion,
          );
        },
        // A newer schema is refused before any statement runs: the database
        // is never reset, downgraded or rewritten, and image files stay put.
        onDowngrade: (database, oldVersion, newVersion) async {
          throw UnsupportedQueueSchemaVersion(
            found: oldVersion,
            supported: e2QueueDatabaseVersion,
          );
        },
        singleInstance: false,
      ),
    );

    return QueueDatabase._(database, selectedPath);
  }

  Future<void> close() => database.close();
}

/// Creates only the canonical E2 v1 pending-occurrence table.
///
/// Kept for the v1 layout (manual confidence only); new databases use
/// [createQueuePendingTableV3].
Future<void> createE2QueueSchemaV1(DatabaseExecutor database) =>
    _createPendingTable(
      database,
      table: e2QueueTable,
      confidenceCheck: '${QueueRecordColumns.confidence} = 1.0',
    );

/// Creates the v3 pending-occurrence table: identical to v1 except that
/// `confidence` accepts any real value in [0, 1] (design E5.9).
Future<void> createQueuePendingTableV3(
  DatabaseExecutor database, {
  String table = e2QueueTable,
}) =>
    _createPendingTable(
      database,
      table: table,
      confidenceCheck: "typeof(${QueueRecordColumns.confidence}) = 'real' AND "
          '${QueueRecordColumns.confidence} BETWEEN 0.0 AND 1.0',
    );

Future<void> _createPendingTable(
  DatabaseExecutor database, {
  required String table,
  required String confidenceCheck,
}) async {
  await database.execute('''
CREATE TABLE $table (
  ${QueueRecordColumns.queueSequence} INTEGER PRIMARY KEY AUTOINCREMENT,
  ${QueueRecordColumns.idempotencyKey} TEXT NOT NULL COLLATE BINARY UNIQUE
    CHECK (
      length(${QueueRecordColumns.idempotencyKey}) = 36 AND
      length(replace(${QueueRecordColumns.idempotencyKey}, '-', '')) = 32 AND
      substr(${QueueRecordColumns.idempotencyKey}, 9, 1) = '-' AND
      substr(${QueueRecordColumns.idempotencyKey}, 14, 1) = '-' AND
      substr(${QueueRecordColumns.idempotencyKey}, 15, 1) = '4' AND
      substr(${QueueRecordColumns.idempotencyKey}, 19, 1) = '-' AND
      lower(substr(${QueueRecordColumns.idempotencyKey}, 20, 1)) IN ('8', '9', 'a', 'b') AND
      substr(${QueueRecordColumns.idempotencyKey}, 24, 1) = '-' AND
      lower(replace(${QueueRecordColumns.idempotencyKey}, '-', '')) NOT GLOB '*[^0-9a-f]*'
    ),
  ${QueueRecordColumns.detectedAtIso8601} TEXT NOT NULL COLLATE BINARY
    CHECK (
      instr(${QueueRecordColumns.detectedAtIso8601}, 'T') > 0 AND
      julianday(${QueueRecordColumns.detectedAtIso8601}) IS NOT NULL AND
      (
        substr(${QueueRecordColumns.detectedAtIso8601}, -1, 1) = 'Z' OR
        (
          substr(${QueueRecordColumns.detectedAtIso8601}, -6, 1) IN ('+', '-') AND
          substr(${QueueRecordColumns.detectedAtIso8601}, -5, 2) GLOB '[0-9][0-9]' AND
          substr(${QueueRecordColumns.detectedAtIso8601}, -3, 1) = ':' AND
          substr(${QueueRecordColumns.detectedAtIso8601}, -2, 2) GLOB '[0-9][0-9]' AND
          CAST(substr(${QueueRecordColumns.detectedAtIso8601}, -5, 2) AS INTEGER) BETWEEN 0 AND 23 AND
          CAST(substr(${QueueRecordColumns.detectedAtIso8601}, -2, 2) AS INTEGER) BETWEEN 0 AND 59
        )
      )
    ),
  ${QueueRecordColumns.latitude} REAL NOT NULL
    CHECK (${QueueRecordColumns.latitude} BETWEEN -90.0 AND 90.0),
  ${QueueRecordColumns.longitude} REAL NOT NULL
    CHECK (${QueueRecordColumns.longitude} BETWEEN -180.0 AND 180.0),
  ${QueueRecordColumns.accuracyMeters} REAL
    CHECK (${QueueRecordColumns.accuracyMeters} IS NULL OR ${QueueRecordColumns.accuracyMeters} >= 0.0),
  ${QueueRecordColumns.speedKmh} REAL
    CHECK (${QueueRecordColumns.speedKmh} IS NULL OR ${QueueRecordColumns.speedKmh} BETWEEN 0.0 AND 300.0),
  ${QueueRecordColumns.confidence} REAL NOT NULL
    CHECK ($confidenceCheck),
  ${QueueRecordColumns.defectClass} TEXT NOT NULL COLLATE BINARY
    CHECK (${QueueRecordColumns.defectClass} = 'pothole'),
  ${QueueRecordColumns.imageRelativeName} TEXT NOT NULL COLLATE BINARY UNIQUE
    CHECK (
      length(${QueueRecordColumns.imageRelativeName}) > 0 AND
      instr(${QueueRecordColumns.imageRelativeName}, '/') = 0 AND
      instr(${QueueRecordColumns.imageRelativeName}, char(92)) = 0 AND
      instr(${QueueRecordColumns.imageRelativeName}, '..') = 0
    ),
  ${QueueRecordColumns.imageMimeType} TEXT NOT NULL COLLATE BINARY
    CHECK (${QueueRecordColumns.imageMimeType} = 'image/jpeg'),
  ${QueueRecordColumns.imageByteLength} INTEGER NOT NULL
    CHECK (
      typeof(${QueueRecordColumns.imageByteLength}) = 'integer' AND
      ${QueueRecordColumns.imageByteLength} BETWEEN 1 AND $e2MaximumImageByteLength
    ),
  ${QueueRecordColumns.imageSha256} TEXT NOT NULL COLLATE BINARY
    CHECK (
      length(${QueueRecordColumns.imageSha256}) = 64 AND
      ${QueueRecordColumns.imageSha256} = lower(${QueueRecordColumns.imageSha256}) AND
      ${QueueRecordColumns.imageSha256} NOT GLOB '*[^0-9a-f]*'
    ),
  ${QueueRecordColumns.imageWidth} INTEGER NOT NULL
    CHECK (
      typeof(${QueueRecordColumns.imageWidth}) = 'integer' AND
      ${QueueRecordColumns.imageWidth} BETWEEN 1 AND 1280
    ),
  ${QueueRecordColumns.imageHeight} INTEGER NOT NULL
    CHECK (
      typeof(${QueueRecordColumns.imageHeight}) = 'integer' AND
      ${QueueRecordColumns.imageHeight} BETWEEN 1 AND 720
    ),
  ${QueueRecordColumns.imageQuality} INTEGER NOT NULL
    CHECK (
      typeof(${QueueRecordColumns.imageQuality}) = 'integer' AND
      ${QueueRecordColumns.imageQuality} = 85
    )
)
''');
}

String _appendPath(String directory, String name) {
  final separator = directory.contains('\\') ? '\\' : Platform.pathSeparator;
  if (directory.endsWith('/') || directory.endsWith('\\')) {
    return '$directory$name';
  }
  return '$directory$separator$name';
}
