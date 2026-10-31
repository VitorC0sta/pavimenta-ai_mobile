import 'package:sqflite/sqflite.dart';

import 'queue_database.dart';
import 'queue_delivery_schema.dart';
import 'queue_record_mapper.dart';

/// Receives one fixed migration category. Nothing else reaches the sink: no
/// path, row, identifier or raw exception.
typedef QueueMigrationLogger = void Function(String category);

void discardQueueMigrationLog(String category) {}

/// Fixed categories of the v3 migration log (design E5.9).
abstract final class QueueMigrationLogCategory {
  static const String completed = 'queue_migration_v3_completed';
  static const String failed = 'queue_migration_v3_failed';
}

/// Raised when the rebuilt database fails a structural check before commit.
final class QueueMigrationCheckFailed implements Exception {
  const QueueMigrationCheckFailed(this.check);

  /// `foreign_key_check` or `integrity_check`.
  final String check;

  @override
  String toString() => 'Queue migration check failed: $check.';
}

const String _rebuiltTable = '${e2QueueTable}_v3';

/// Brings a v1 or v2 queue database to schema v3 before the regular open.
///
/// SQLite cannot alter a CHECK, so `pendingOccurrences` is rebuilt with the
/// 12-step procedure. `pendingOccurrences` is the parent of the E4 delivery
/// state with `ON DELETE CASCADE`; the rebuild therefore runs on a dedicated
/// connection with foreign keys off, in a single transaction. Any failure
/// rolls back and leaves the previous version readable. Image files are never
/// touched.
///
/// Does nothing when the database does not exist yet, is empty, or is already
/// at v3. A newer version is refused without changes.
///
/// [beforeCommit] runs inside the transaction right before commit; tests use
/// it to inject a failure.
Future<void> migrateQueueToSchemaV3({
  required DatabaseFactory factory,
  required String path,
  QueueMigrationLogger logger = discardQueueMigrationLog,
  Future<void> Function(Transaction transaction)? beforeCommit,
}) async {
  if (!await factory.databaseExists(path)) {
    return;
  }

  final database = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    // Outside any transaction: SQLite ignores the pragma inside one.
    await database.execute('PRAGMA foreign_keys = OFF');
    final version = await database.getVersion();
    if (version == 0 || version == e2QueueDatabaseVersion) {
      return;
    }
    if (version > e2QueueDatabaseVersion) {
      throw UnsupportedQueueSchemaVersion(
        found: version,
        supported: e2QueueDatabaseVersion,
      );
    }
    if (version != 1 && version != 2) {
      throw UnsupportedQueueSchemaVersion(
        found: version,
        supported: e2QueueDatabaseVersion,
      );
    }

    try {
      // sqflite opens the transaction with BEGIN IMMEDIATE.
      await database.transaction((transaction) async {
        if (version == 1) {
          await migrateQueueSchemaV1ToV2(
            transaction,
            pendingTable: e2QueueTable,
          );
        }
        await _rebuildPendingTable(transaction);
        await _requireConsistentDatabase(transaction);
        await transaction.execute(
          'PRAGMA user_version = $e2QueueDatabaseVersion',
        );
        await beforeCommit?.call(transaction);
      });
    } catch (_) {
      _safeLog(logger, QueueMigrationLogCategory.failed);
      rethrow;
    }
    _safeLog(logger, QueueMigrationLogCategory.completed);
  } finally {
    await database.close();
  }
}

Future<void> _rebuildPendingTable(Transaction transaction) async {
  await createQueuePendingTableV3(transaction, table: _rebuiltTable);

  const columns = QueueRecordColumns.all;
  final columnList = columns.join(', ');
  await transaction.execute('''
INSERT INTO $_rebuiltTable ($columnList)
SELECT $columnList FROM $e2QueueTable
ORDER BY ${QueueRecordColumns.queueSequence}
''');

  final previousSequence = await _sequenceOf(transaction, e2QueueTable);

  await transaction.execute('DROP TABLE $e2QueueTable');
  await transaction.execute(
    'ALTER TABLE $_rebuiltTable RENAME TO $e2QueueTable',
  );

  // Never reuse an emitted sequence: the cooldown anchor may point to a
  // sequence whose row was already removed.
  final maximumRow = await transaction.rawQuery(
    'SELECT MAX(${QueueRecordColumns.queueSequence}) AS value '
    'FROM $e2QueueTable',
  );
  final maximumSequence = (maximumRow.single['value'] as int?) ?? 0;
  final sequence =
      previousSequence > maximumSequence ? previousSequence : maximumSequence;
  if (sequence > 0) {
    await transaction.execute(
      "DELETE FROM sqlite_sequence WHERE name = '$e2QueueTable'",
    );
    await transaction.rawInsert(
      'INSERT INTO sqlite_sequence (name, seq) VALUES (?, ?)',
      <Object>[e2QueueTable, sequence],
    );
  }
}

Future<int> _sequenceOf(Transaction transaction, String table) async {
  final rows = await transaction.rawQuery(
    'SELECT seq FROM sqlite_sequence WHERE name = ?',
    <Object>[table],
  );
  if (rows.isEmpty) {
    return 0;
  }
  return rows.single['seq'] as int? ?? 0;
}

Future<void> _requireConsistentDatabase(Transaction transaction) async {
  final foreignKeyViolations =
      await transaction.rawQuery('PRAGMA foreign_key_check');
  if (foreignKeyViolations.isNotEmpty) {
    throw const QueueMigrationCheckFailed('foreign_key_check');
  }
  final integrity = await transaction.rawQuery('PRAGMA integrity_check');
  if (integrity.length != 1 || integrity.single.values.single != 'ok') {
    throw const QueueMigrationCheckFailed('integrity_check');
  }
}

void _safeLog(QueueMigrationLogger logger, String category) {
  try {
    logger(category);
  } catch (_) {
    // A failing log sink never changes the migration outcome.
  }
}
