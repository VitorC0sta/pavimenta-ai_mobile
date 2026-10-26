import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect;
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_record_mapper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final inputs = any.combine2<_RecoveryCrashState, int, _PropertyInput>(
    any.choose(_RecoveryCrashState.values),
    any.positiveIntOrZero,
    (state, seed) => _PropertyInput(state: state, seed: seed),
  );

  // Feature: mvp-app-flutter, Property 19: Recuperação idempotente
  // **Validates: Requirements RF-12.3, RF-12.8, RNF-05.3, RNF-06.3,
  // RNF-06.11**
  Glados<_PropertyInput>(
    inputs,
    ExploreConfig(numRuns: 120),
  ).test(
    'converges reachable crash artifacts without deleting retained rows or external files',
    (_PropertyInput input) async {
      final sandbox = await Directory.systemTemp.createTemp('e2_property_19_');
      final databasePath =
          '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName';
      final namespace = Directory(
        '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
      );
      final external = File(
        '${sandbox.path}${Platform.pathSeparator}outside-e2-namespace.bin',
      );
      QueueDatabase? database;

      try {
        final fixture = _fixtureFor(input.seed);
        await namespace.create(recursive: true);
        await external.writeAsBytes(fixture.externalBytes, flush: true);
        database = await _openDatabase(databasePath);
        await _createReachableCrashState(
          database: database,
          namespace: namespace,
          fixture: fixture,
          state: input.state,
          seed: input.seed,
        );
        await database.close();
        database = null;

        final first = await _recover(sandbox, databasePath);
        final second = await _recover(sandbox, databasePath);
        final expected = _expectedFor(input.state, fixture);

        expect(first, expected);
        expect(second, first,
            reason: 'a repeated recovery must retain the confirmed result');
        expect(
          await _directFileNames(namespace),
          expected.namespaceFiles,
          reason: 'recovery may touch only recognized E2 artifacts',
        );
        expect(
          await external.readAsBytes(),
          fixture.externalBytes,
          reason: 'files outside the E2 namespace must remain untouched',
        );
      } finally {
        await database?.close();
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      }
    },
  );
}

Future<void> _createReachableCrashState({
  required QueueDatabase database,
  required Directory namespace,
  required _Fixture fixture,
  required _RecoveryCrashState state,
  required int seed,
}) async {
  final canonical = File(
    '${namespace.path}${Platform.pathSeparator}'
    '${fixture.record.image.relativeName}',
  );
  final marker = File(
    '${namespace.path}${Platform.pathSeparator}'
    '${const E2DurableImageNameCodec().deletingMarker(
      canonicalName: fixture.record.image.relativeName,
      operationToken: _opaqueToken(seed + 1),
    )}',
  );
  final staging = File(
    '${namespace.path}${Platform.pathSeparator}'
    'e2s_${_opaqueToken(seed + 2)}.staging',
  );

  switch (state) {
    case _RecoveryCrashState.persistenceStaging:
      await staging.writeAsBytes(fixture.bytes, flush: true);
    case _RecoveryCrashState.persistenceCanonicalOrphan:
      await canonical.writeAsBytes(fixture.bytes, flush: true);
    case _RecoveryCrashState.removalBeforeCommit:
      await _insert(database, fixture.record);
      await marker.writeAsBytes(fixture.bytes, flush: true);
    case _RecoveryCrashState.removalAfterCommit:
      await marker.writeAsBytes(fixture.bytes, flush: true);
    case _RecoveryCrashState.confirmed:
      await _insert(database, fixture.record);
      await canonical.writeAsBytes(fixture.bytes, flush: true);
    case _RecoveryCrashState.missingCanonical:
      await _insert(database, fixture.record);
    case _RecoveryCrashState.divergentCanonical:
      await _insert(database, fixture.record);
      await canonical.writeAsBytes(fixture.divergentBytes, flush: true);
  }
}

Future<_RecoveredState> _recover(Directory sandbox, String databasePath) async {
  final queue = CoordinatedPersistentOccurrenceQueue(
    imageStore: PrivateDurableImageStore.at(sandbox),
    databaseOpener: () => _openDatabase(databasePath),
  );
  try {
    final snapshot = await queue.bootstrap();
    final pending = await queue.listPending();
    final namespace = Directory(
      '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
    );
    return _RecoveredState(
      health: snapshot.health,
      pendingKeys: pending.map((item) => item.idempotencyKey),
      attentionCount: snapshot.attentionCount,
      namespaceFiles: await _directFileNames(namespace),
    );
  } finally {
    await queue.close();
  }
}

Future<QueueDatabase> _openDatabase(String path) => QueueDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );

Future<void> _insert(
  QueueDatabase database,
  QueueRecordProjection record,
) =>
    database.database.insert(
      e2QueueTable,
      const QueueRecordMapper().toInsertMap(record),
    );

Future<List<String>> _directFileNames(Directory directory) async {
  if (!await directory.exists()) {
    return const <String>[];
  }

  final names = <String>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (await FileSystemEntity.type(entity.path, followLinks: false) ==
        FileSystemEntityType.file) {
      names.add(_basename(entity.path));
    }
  }
  names.sort();
  return names;
}

_RecoveredState _expectedFor(_RecoveryCrashState state, _Fixture fixture) {
  final retained = switch (state) {
    _RecoveryCrashState.removalBeforeCommit ||
    _RecoveryCrashState.confirmed ||
    _RecoveryCrashState.missingCanonical ||
    _RecoveryCrashState.divergentCanonical =>
      true,
    _ => false,
  };
  final degraded = switch (state) {
    _RecoveryCrashState.missingCanonical ||
    _RecoveryCrashState.divergentCanonical =>
      true,
    _ => false,
  };
  final canonicalRetained = switch (state) {
    _RecoveryCrashState.removalBeforeCommit ||
    _RecoveryCrashState.confirmed ||
    _RecoveryCrashState.divergentCanonical =>
      true,
    _ => false,
  };

  return _RecoveredState(
    health: degraded ? QueueHealth.degraded : QueueHealth.ready,
    pendingKeys:
        retained ? <String>[fixture.record.idempotencyKey] : const <String>[],
    attentionCount: degraded ? 1 : 0,
    namespaceFiles: canonicalRetained
        ? <String>[fixture.record.image.relativeName]
        : const <String>[],
  );
}

_Fixture _fixtureFor(int seed) {
  final width = 1 + seed % 8;
  final height = 1 + (seed ~/ 8) % 8;
  final bytes = _jpeg(seed, width, height);
  return _Fixture(
    bytes: bytes,
    divergentBytes: _jpeg(seed + 1, width, height),
    externalBytes: List<int>.unmodifiable(<int>[seed.toUnsigned(8), 0x5a]),
    record: QueueRecordProjection(
      queueSequence: 0,
      idempotencyKey: _uuidFor(seed),
      detectedAtIso8601: '2025-01-02T03:04:05.000Z',
      latitude: -23.5505,
      longitude: -46.6333,
      accuracyMeters: null,
      speedKmh: null,
      confidence: 1,
      defectClass: 'pothole',
      image: PersistedImageProjection(
        relativeName: 'e2i_${_opaqueToken(seed)}.jpg',
        mimeType: 'image/jpeg',
        byteLength: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        width: width,
        height: height,
        quality: 85,
      ),
    ),
  );
}

List<int> _jpeg(int seed, int width, int height) {
  final image = image_codec.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(
        x,
        y,
        (seed + x * 17).toUnsigned(8),
        (seed + y * 31).toUnsigned(8),
        (seed + x + y * 13).toUnsigned(8),
        255,
      );
    }
  }
  return image_codec.encodeJpg(image, quality: 85);
}

String _uuidFor(int seed) {
  const limit = 0x1000000000000;
  final suffix = (seed % limit).toRadixString(16).padLeft(12, '0');
  return '00000000-0000-4000-8000-$suffix';
}

String _opaqueToken(int seed) =>
    (seed & 0xffffffffffffffff).toRadixString(16).padLeft(32, '0');

String _basename(String path) => path.replaceAll(r'\', '/').split('/').last;

enum _RecoveryCrashState {
  persistenceStaging,
  persistenceCanonicalOrphan,
  removalBeforeCommit,
  removalAfterCommit,
  confirmed,
  missingCanonical,
  divergentCanonical,
}

final class _PropertyInput {
  const _PropertyInput({required this.state, required this.seed});

  final _RecoveryCrashState state;
  final int seed;
}

final class _Fixture {
  const _Fixture({
    required this.bytes,
    required this.divergentBytes,
    required this.externalBytes,
    required this.record,
  });

  final List<int> bytes;
  final List<int> divergentBytes;
  final List<int> externalBytes;
  final QueueRecordProjection record;
}

final class _RecoveredState {
  _RecoveredState({
    required this.health,
    required Iterable<String> pendingKeys,
    required this.attentionCount,
    required Iterable<String> namespaceFiles,
  })  : pendingKeys = List<String>.unmodifiable(pendingKeys),
        namespaceFiles = List<String>.unmodifiable(namespaceFiles);

  final QueueHealth health;
  final List<String> pendingKeys;
  final int attentionCount;
  final List<String> namespaceFiles;

  @override
  bool operator ==(Object other) =>
      other is _RecoveredState &&
      health == other.health &&
      _sameList(pendingKeys, other.pendingKeys) &&
      attentionCount == other.attentionCount &&
      _sameList(namespaceFiles, other.namespaceFiles);

  @override
  int get hashCode => Object.hash(
        health,
        Object.hashAll(pendingKeys),
        attentionCount,
        Object.hashAll(namespaceFiles),
      );

  @override
  String toString() =>
      '_RecoveredState(health: $health, pendingKeys: $pendingKeys, '
      'attentionCount: $attentionCount, namespaceFiles: $namespaceFiles)';
}

bool _sameList<T>(List<T> first, List<T> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
