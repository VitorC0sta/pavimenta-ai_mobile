import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_delivery_schema.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_record_mapper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const mapper = QueueRecordMapper();
  late Directory sandbox;
  late String databasePath;
  QueueDatabase? queueDatabase;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e2_queue_schema_');
    databasePath = '${sandbox.path}${Platform.pathSeparator}'
        '$e2QueueDatabaseName';
  });

  tearDown(() async {
    await queueDatabase?.close();
    queueDatabase = null;
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('E2 SQLite schema v1', () {
    // **Validates: Requirements RF-12.1–4, RF-12.7–8, RNF-03.5**
    test('creates the private version-one database and reopens without loss',
        () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;
      final inserted = await database.insert(
        e2QueueTable,
        mapper.toInsertMap(_record(imageRelativeName: 'opaque_a.jpg')),
      );

      expect(queueDatabase!.path, endsWith(e2QueueDatabaseName));
      expect(await database.getVersion(), e2QueueDatabaseVersion);
      expect(inserted, 1);

      await queueDatabase!.close();
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );

      final rows = await queueDatabase!.database.query(e2QueueTable);
      expect(rows, hasLength(1));
      expect(mapper.fromMap(rows.single).idempotencyKey,
          '123e4567-e89b-42d3-a456-426614174000');
    });

    // **Validates: Requirements RF-07.2–9, RF-08.1–5, RF-12.1–4**
    test('contains exactly the canonical E2 columns and no future fields',
        () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );

      final tableInfo = await queueDatabase!.database
          .rawQuery('PRAGMA table_info($e2QueueTable)');
      final columns = tableInfo
          .map((row) => row['name'])
          .whereType<String>()
          .toList(growable: false);

      expect(columns, QueueRecordColumns.all);
      for (final forbidden in <String>{
        'source',
        'highway',
        'km',
        'url',
        'baseUrl',
        'apiKey',
        'httpStatus',
        'attempts',
        'nextAttemptAt',
        'backoff',
        'paused',
      }) {
        expect(columns, isNot(contains(forbidden)));
      }
    });

    // **Validates: Requirements RF-07.2–9, RF-08.1–5, RF-12.7–8**
    test('rejects every invalid canonical value through database constraints',
        () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;
      final valid = mapper.toInsertMap(_record());
      final invalidChanges = <Map<String, Object?>>[
        {QueueRecordColumns.idempotencyKey: 'not-a-uuid'},
        {
          QueueRecordColumns.idempotencyKey:
              '123e4567-e89b-12d3-a456-426614174000'
        },
        {QueueRecordColumns.detectedAtIso8601: '2025-01-02T03:04:05.000'},
        {QueueRecordColumns.latitude: 90.01},
        {QueueRecordColumns.longitude: -180.01},
        {QueueRecordColumns.accuracyMeters: -0.01},
        {QueueRecordColumns.speedKmh: -0.01},
        {QueueRecordColumns.speedKmh: 300.01},
        // E5 schema v3 accepts model confidences in [0, 1] (task 79).
        {QueueRecordColumns.confidence: 1.01},
        {QueueRecordColumns.confidence: -0.01},
        {QueueRecordColumns.defectClass: 'crack'},
        {QueueRecordColumns.imageRelativeName: '../outside.jpg'},
        {QueueRecordColumns.imageRelativeName: r'nested\outside.jpg'},
        {QueueRecordColumns.imageMimeType: 'image/png'},
        {QueueRecordColumns.imageByteLength: 0},
        {
          QueueRecordColumns.imageByteLength: e2MaximumImageByteLength + 1,
        },
        {QueueRecordColumns.imageSha256: 'A' * 64},
        {QueueRecordColumns.imageSha256: 'a' * 63},
        {QueueRecordColumns.imageWidth: 0},
        {QueueRecordColumns.imageWidth: 1281},
        {QueueRecordColumns.imageHeight: 0},
        {QueueRecordColumns.imageHeight: 721},
        {QueueRecordColumns.imageQuality: 84},
      ];

      for (final change in invalidChanges) {
        expect(
          () => database.insert(e2QueueTable, <String, Object?>{
            ...valid,
            ...change,
          }),
          throwsA(isA<DatabaseException>()),
          reason: 'Expected constraint rejection for $change',
        );
      }
      expect(await database.query(e2QueueTable), isEmpty);

      await database.insert(e2QueueTable, valid);
      expect(
        () => database.insert(
          e2QueueTable,
          <String, Object?>{
            ...valid,
            QueueRecordColumns.imageRelativeName: 'different.jpg',
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => database.insert(
          e2QueueTable,
          <String, Object?>{
            ...valid,
            QueueRecordColumns.idempotencyKey:
                '223e4567-e89b-42d3-a456-426614174000',
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    // **Validates: Requirements RF-10.6–7, RF-12.1–2, RF-12.4**
    test('enforces exact JPEG metadata and integer image boundaries', () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;
      final valid = mapper.toInsertMap(_record());

      await database.insert(e2QueueTable, <String, Object?>{
        ...valid,
        QueueRecordColumns.imageRelativeName: 'minimum.jpg',
        QueueRecordColumns.imageByteLength: 1,
        QueueRecordColumns.imageWidth: 1,
        QueueRecordColumns.imageHeight: 1,
      });
      await database.insert(e2QueueTable, <String, Object?>{
        ...valid,
        QueueRecordColumns.idempotencyKey:
            '223e4567-e89b-42d3-a456-426614174000',
        QueueRecordColumns.imageRelativeName: 'maximum.jpg',
      });

      expect(await database.query(e2QueueTable), hasLength(2));

      final invalidImageChanges = <Map<String, Object?>>[
        {QueueRecordColumns.imageRelativeName: ''},
        {QueueRecordColumns.imageMimeType: 'IMAGE/JPEG'},
        {QueueRecordColumns.imageByteLength: 1.5},
        {QueueRecordColumns.imageSha256: '${'a' * 63}g'},
        {QueueRecordColumns.imageWidth: 1.5},
        {QueueRecordColumns.imageHeight: 1.5},
        {QueueRecordColumns.imageQuality: 85.5},
      ];

      for (var index = 0; index < invalidImageChanges.length; index++) {
        final change = invalidImageChanges[index];
        expect(
          () => database.insert(e2QueueTable, <String, Object?>{
            ...valid,
            QueueRecordColumns.idempotencyKey:
                '323e4567-e89b-42d3-a456-${index.toString().padLeft(12, '0')}',
            QueueRecordColumns.imageRelativeName: 'invalid_$index.jpg',
            ...change,
          }),
          throwsA(isA<DatabaseException>()),
          reason: 'Expected defensive image constraint rejection for $change',
        );
      }
      expect(await database.query(e2QueueTable), hasLength(2));
    });

    // **Validates: Requirements RF-08.1–5, RF-12.3–4, RNF-05.1–3**
    test(
        'round-trips all values, offsets, null versus zero, and sequence order',
        () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;
      final first = _record(
        idempotencyKey: '123e4567-e89b-42d3-a456-426614174000',
        imageRelativeName: 'opaque_a.jpg',
        detectedAtIso8601: '2025-01-02T03:04:05.678-03:00',
      );
      final second = _record(
        idempotencyKey: '223E4567-E89B-42D3-A456-426614174000',
        imageRelativeName: 'opaque_b.jpg',
        detectedAtIso8601: '2025-01-02T06:04:05.678Z',
        accuracyMeters: 0,
        speedKmh: 0,
      );

      await database.insert(e2QueueTable, mapper.toInsertMap(first));
      await database.insert(e2QueueTable, mapper.toInsertMap(second));
      final rows = await database.query(
        e2QueueTable,
        orderBy: QueueRecordColumns.queueSequence,
      );
      final reconstructed = rows.map(mapper.fromMap).toList();

      _expectSameCanonicalValues(reconstructed[0], first, expectedSequence: 1);
      _expectSameCanonicalValues(reconstructed[1], second, expectedSequence: 2);
      expect(reconstructed[0].accuracyMeters, isNull);
      expect(reconstructed[0].speedKmh, isNull);
      expect(reconstructed[1].accuracyMeters, 0);
      expect(reconstructed[1].speedKmh, 0);
      expect(reconstructed.map((record) => record.queueSequence), [1, 2]);

      await database.delete(
        e2QueueTable,
        where: '${QueueRecordColumns.queueSequence} = ?',
        whereArgs: <Object>[2],
      );
      await database.insert(
        e2QueueTable,
        mapper.toInsertMap(
          _record(
            idempotencyKey: '323e4567-e89b-42d3-a456-426614174000',
            imageRelativeName: 'opaque_c.jpg',
          ),
        ),
      );
      final sequences = await database.query(
        e2QueueTable,
        columns: <String>[QueueRecordColumns.queueSequence],
        orderBy: QueueRecordColumns.queueSequence,
      );
      expect(
        sequences.map((row) => row[QueueRecordColumns.queueSequence]),
        <int>[1, 3],
      );
    });

    // **Validates: Requirements RF-12.3, RF-12.7–8, RNF-05.3**
    test('refuses a future schema version without resetting its data',
        () async {
      final futureDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: e2QueueDatabaseVersion + 1,
          onCreate: (database, version) async {
            await database.execute(
              'CREATE TABLE futureMarker (value TEXT NOT NULL)',
            );
            await database.insert('futureMarker', <String, Object?>{
              'value': 'preserve-me',
            });
          },
          singleInstance: false,
        ),
      );
      await futureDatabase.close();

      await expectLater(
        QueueDatabase.open(
          factory: databaseFactoryFfi,
          path: databasePath,
        ),
        throwsA(isA<UnsupportedQueueSchemaVersion>()),
      );

      final verificationDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(verificationDatabase.close);
      expect(
          await verificationDatabase.getVersion(), e2QueueDatabaseVersion + 1);
      expect(
        await verificationDatabase.query('futureMarker'),
        <Map<String, Object?>>[
          <String, Object?>{'value': 'preserve-me'},
        ],
      );
      final tables = await verificationDatabase.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(tables.map((row) => row['name']), isNot(contains(e2QueueTable)));
    });
  });

  group('E4 additive schema v2', () {
    // **Validates: Requirements RF-12.9–11, RF-15.10–12, RNF-05, RNF-06.2–5**
    test('creates the E4 structures on a fresh database', () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;

      expect(await database.getVersion(), e2QueueDatabaseVersion);
      expect(await _tableNames(database), containsAll(_e4Tables));
      expect(await _count(database, e4AcceptedAnchorTable), 0);
      expect(await _count(database, e4DeliveryControlTable), 0);
      expect(
        (await database.rawQuery('PRAGMA table_info($e2QueueTable)'))
            .map((row) => row['name']),
        QueueRecordColumns.all,
      );
    });

    // **Validates: Requirements RF-09, RF-12.9–11, RNF-05, RNF-06.9–11**
    test(
        'migrates a real v1 database keeping rows and JPEGs and seeding '
        'the anchor with the greatest sequence', () async {
      final jpeg = File('${sandbox.path}${Platform.pathSeparator}opaque_a.jpg');
      await jpeg.writeAsBytes(<int>[0xff, 0xd8, 0xff, 0xd9]);
      final v1 = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, version) => createE2QueueSchemaV1(database),
          singleInstance: false,
        ),
      );
      await v1.insert(
        e2QueueTable,
        mapper.toInsertMap(_record(imageRelativeName: 'opaque_a.jpg')),
      );
      await v1.insert(
        e2QueueTable,
        mapper.toInsertMap(
          _record(
            idempotencyKey: '123e4567-e89b-42d3-a456-426614174001',
            detectedAtIso8601: '2025-01-02T03:05:00.000Z',
            imageRelativeName: 'opaque_b.jpg',
          ),
        ),
      );
      final rowsBefore = await v1.query(
        e2QueueTable,
        orderBy: QueueRecordColumns.queueSequence,
      );
      await v1.close();

      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;

      expect(await database.getVersion(), e2QueueDatabaseVersion);
      expect(await _tableNames(database), containsAll(_e4Tables));
      expect(
        await database.query(
          e2QueueTable,
          orderBy: QueueRecordColumns.queueSequence,
        ),
        rowsBefore,
      );
      expect(await jpeg.exists(), isTrue);
      expect(await _count(database, e4DeliveryStateTable), 0);
      expect(await _count(database, e4DeliveryControlTable), 0);
      expect(
        await database.query(e4AcceptedAnchorTable),
        <Map<String, Object?>>[
          <String, Object?>{
            'singleton_id': 1,
            'queue_sequence': 2,
            'detected_at': '2025-01-02T03:05:00.000Z',
            'latitude': -23.55052,
            'longitude': -46.633308,
          },
        ],
      );

      // The anchor outlives its source row.
      await database.delete(e2QueueTable);
      expect(await _count(database, e4AcceptedAnchorTable), 1);
    });

    // **Validates: Requirements RF-12.9–11, RNF-05**
    test('migrating an empty v1 database leaves the anchor empty', () async {
      final v1 = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, version) => createE2QueueSchemaV1(database),
          singleInstance: false,
        ),
      );
      await v1.close();

      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );

      expect(
          await queueDatabase!.database.getVersion(), e2QueueDatabaseVersion);
      expect(await _count(queueDatabase!.database, e4AcceptedAnchorTable), 0);
    });

    // **Validates: Requirements RF-15.10–12, RF-16, RNF-06.2–5**
    test('constrains the pause control and the singleton anchor', () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;

      Future<void> insertControl(Map<String, Object?> values) =>
          database.insert(e4DeliveryControlTable, <String, Object?>{
            'singleton_id': 1,
            'updated_at': '2025-01-02T03:04:05.000Z',
            ...values,
          });

      await expectLater(
        insertControl(<String, Object?>{'pause_reason': 'bogus'}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        insertControl(<String, Object?>{
          'pause_reason': 'access',
          'unexpected_status': 418,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await insertControl(<String, Object?>{
        'pause_reason': 'unexpectedResponse',
        'unexpected_status': 302,
      });
      await expectLater(
        database.insert(e4DeliveryControlTable, <String, Object?>{
          'singleton_id': 2,
          'pause_reason': 'none',
          'updated_at': '2025-01-02T03:04:05.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert(e4AcceptedAnchorTable, <String, Object?>{
          'singleton_id': 2,
          'queue_sequence': 1,
          'detected_at': '2025-01-02T03:04:05.000Z',
          'latitude': 0.0,
          'longitude': 0.0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    // **Validates: Requirements RF-12.9–11, RNF-06.2–5**
    test('enforces foreign keys on every open and cascades delivery state',
        () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      expect(
        await queueDatabase!.database.rawQuery('PRAGMA foreign_keys'),
        <Map<String, Object?>>[
          <String, Object?>{'foreign_keys': 1},
        ],
      );
      await queueDatabase!.close();
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;
      expect(
        await database.rawQuery('PRAGMA foreign_keys'),
        <Map<String, Object?>>[
          <String, Object?>{'foreign_keys': 1},
        ],
      );
      await expectLater(
        database.insert(e4DeliveryStateTable, <String, Object?>{
          'idempotency_key': '123e4567-e89b-42d3-a456-426614174000',
          'attempt_count': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await database.insert(
        e2QueueTable,
        mapper.toInsertMap(_record(imageRelativeName: 'opaque_a.jpg')),
      );
      await database.insert(e4DeliveryStateTable, <String, Object?>{
        'idempotency_key': '123e4567-e89b-42d3-a456-426614174000',
        'attempt_count': 1,
      });
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      await database.delete(e2QueueTable);

      expect(await _count(database, e4DeliveryStateTable), 0);
    });

    // **Validates: Requirements RF-12.9–11, RNF-05, RNF-06.2–5**
    test('removes only orphan delivery state, idempotently', () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;
      const keptKey = '123e4567-e89b-42d3-a456-426614174000';
      const orphanKey = '223e4567-e89b-42d3-a456-426614174000';
      await database.insert(
        e2QueueTable,
        mapper.toInsertMap(_record(imageRelativeName: 'opaque_a.jpg')),
      );
      await database.insert(e4DeliveryStateTable, <String, Object?>{
        'idempotency_key': keptKey,
        'attempt_count': 2,
      });
      // Simulates a row left behind by a connection without enforcement.
      await database.execute('PRAGMA foreign_keys = OFF');
      await database.insert(e4DeliveryStateTable, <String, Object?>{
        'idempotency_key': orphanKey,
        'attempt_count': 1,
      });
      await database.execute('PRAGMA foreign_keys = ON');
      final pendingBefore = await database.query(e2QueueTable);

      expect(
        await removeOrphanDeliveryStates(database, pendingTable: e2QueueTable),
        1,
      );
      expect(
        await removeOrphanDeliveryStates(database, pendingTable: e2QueueTable),
        0,
      );

      final remaining = await database.query(e4DeliveryStateTable);
      expect(remaining.map((row) => row['idempotency_key']), [keptKey]);
      expect(remaining.single['attempt_count'], 2);
      expect(await database.query(e2QueueTable), pendingBefore);
    });

    // **Validates: Requirements RF-12.9–11, RNF-05, RNF-06.9–11**
    test('bootstrap recovery drops orphan delivery state and is repeatable',
        () async {
      queueDatabase = await QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final database = queueDatabase!.database;
      await database.execute('PRAGMA foreign_keys = OFF');
      await database.insert(e4DeliveryStateTable, <String, Object?>{
        'idempotency_key': '223e4567-e89b-42d3-a456-426614174000',
        'attempt_count': 1,
      });
      await database.execute('PRAGMA foreign_keys = ON');
      final store = PrivateDurableImageStore.at(sandbox);

      for (var run = 0; run < 2; run++) {
        final result = await const InitialQueueBootstrapRecovery()
            .recover(queueDatabase!, store);
        expect(result.records, isEmpty);
        expect(await _count(database, e4DeliveryStateTable), 0);
      }
    });
  });
}

const List<String> _e4Tables = <String>[
  e4DeliveryStateTable,
  e4DeliveryControlTable,
  e4AcceptedAnchorTable,
];

Future<List<Object?>> _tableNames(Database database) async {
  final rows = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name']).toList(growable: false);
}

Future<int> _count(Database database, String table) async {
  final rows = await database.rawQuery('SELECT COUNT(*) AS c FROM $table');
  return rows.single['c']! as int;
}

QueueRecordProjection _record({
  String idempotencyKey = '123e4567-e89b-42d3-a456-426614174000',
  String detectedAtIso8601 = '2025-01-02T03:04:05.678-03:00',
  double? accuracyMeters,
  double? speedKmh,
  String imageRelativeName = 'opaque.jpg',
}) {
  return QueueRecordProjection(
    queueSequence: 999,
    idempotencyKey: idempotencyKey,
    detectedAtIso8601: detectedAtIso8601,
    latitude: -23.55052,
    longitude: -46.633308,
    accuracyMeters: accuracyMeters,
    speedKmh: speedKmh,
    confidence: 1,
    defectClass: 'pothole',
    image: PersistedImageProjection(
      relativeName: imageRelativeName,
      mimeType: 'image/jpeg',
      byteLength: e2MaximumImageByteLength,
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      width: 1280,
      height: 720,
      quality: 85,
    ),
  );
}

void _expectSameCanonicalValues(
  QueueRecordProjection actual,
  QueueRecordProjection expected, {
  required int expectedSequence,
}) {
  expect(actual.queueSequence, expectedSequence);
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
