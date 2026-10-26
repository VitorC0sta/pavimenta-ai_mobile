import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect;
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final inputs = any.combine2<_PersistenceOutcome, int, _PropertyInput>(
    any.choose(_PersistenceOutcome.values),
    any.positiveIntOrZero,
    (outcome, seed) => _PropertyInput(outcome: outcome, seed: seed),
  );

  // Feature: mvp-app-flutter, Property 17: Ownership exclusivo após aceite
  // **Validates: Requirements RF-11.8, RF-12.2, RF-12.10, RF-12.11,
  // RNF-06.3, RNF-06.9, RNF-06.10**
  Glados<_PropertyInput>(
    inputs,
    ExploreConfig(numRuns: 120),
  ).test(
    'transfers the canonical JPEG exclusively on acceptance and leaves no E2 reference after rejection',
    (_PropertyInput input) async {
      final sandbox = await Directory.systemTemp.createTemp('e2_property_17_');
      CoordinatedPersistentOccurrenceQueue? queue;

      try {
        Future<QueueDatabase> openDatabase() => QueueDatabase.open(
              factory: databaseFactoryFfi,
              path:
                  '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName',
            );
        final store = PrivateDurableImageStore.at(
          sandbox,
          tokenGenerator: _tokensFor(input.seed),
        );
        queue = CoordinatedPersistentOccurrenceQueue(
          imageStore: store,
          databaseOpener: openDatabase,
        );
        expect((await queue.bootstrap()).isReady, isTrue);

        final lease = _Lease(
          _jpeg(input.seed),
          width: 1 + input.seed % 8,
          height: 1 + (input.seed ~/ 8) % 8,
          quality:
              input.outcome == _PersistenceOutcome.invalidMetadata ? 84 : 85,
        );
        if (input.outcome == _PersistenceOutcome.inactiveLease) {
          await lease.withdrawOwnership();
        }

        final result = await queue.persist(_occurrence(input.seed, lease));
        final pending = await queue.listPending();
        final artifacts = await _e2Artifacts(sandbox);

        if (input.outcome == _PersistenceOutcome.accepted) {
          expect(result, isA<OccurrencePersisted>());
          expect(lease.hasOwnership, isFalse);
          expect(lease.withdrawCalls, 1);
          expect(pending, hasLength(1));

          final canonical = pending.single.record.image;
          expect(await store.inspect(canonical), DurableImageIntegrity.valid);
          expect(
            artifacts.map(_basename),
            <String>[canonical.relativeName],
            reason: 'only the queue-owned canonical JPEG may remain',
          );
          expect(
            const E2DurableImageNameCodec().isCanonicalName(
              canonical.relativeName,
            ),
            isTrue,
          );
        } else {
          expect(result, isNot(isA<OccurrencePersisted>()));
          expect(
            lease.hasOwnership,
            input.outcome == _PersistenceOutcome.invalidMetadata,
            reason: 'rejection must not revoke an active E1 lease',
          );
          expect(pending, isEmpty);
          expect(
            artifacts,
            isEmpty,
            reason: 'a rejected occurrence must not leave a referenced E2 JPEG',
          );
        }
      } finally {
        await queue?.close();
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      }
    },
  );
}

enum _PersistenceOutcome { accepted, invalidMetadata, inactiveLease }

final class _PropertyInput {
  const _PropertyInput({required this.outcome, required this.seed});

  final _PersistenceOutcome outcome;
  final int seed;
}

InMemoryOccurrence _occurrence(int seed, _Lease lease) =>
    const InMemoryOccurrenceFactory().createManual(
      idempotencyKey: _uuidFor(seed),
      detectedAt: DateTime.utc(2025, 1, 1).add(
        Duration(minutes: seed % 525600),
      ),
      location: ImmutableLocationSnapshot(
        point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
        accuracyMeters: 4.5,
        speedMetersPerSecond: 10,
      ),
      image: lease,
    );

List<int> _jpeg(int seed) {
  final width = 1 + seed % 8;
  final height = 1 + (seed ~/ 8) % 8;
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

E2OpaqueTokenGenerator _tokensFor(int seed) {
  var sequence = 0;
  return () {
    final value = (seed + sequence++) & 0xffffffffffffffff;
    return value.toRadixString(16).padLeft(32, '0');
  };
}

Future<List<File>> _e2Artifacts(Directory sandbox) async {
  final namespace = Directory(
    '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
  );
  if (!await namespace.exists()) {
    return <File>[];
  }

  final artifacts = <File>[];
  await for (final entity in namespace.list(followLinks: false)) {
    if (await FileSystemEntity.type(entity.path, followLinks: false) ==
        FileSystemEntityType.file) {
      artifacts.add(File(entity.path));
    }
  }
  return artifacts;
}

String _basename(File file) => file.path.replaceAll(r'\', '/').split('/').last;

final class _Lease implements PreparedImageLease {
  _Lease(
    List<int> bytes, {
    required this.width,
    required this.height,
    required this.quality,
  }) : _bytes = List<int>.unmodifiable(bytes);

  final List<int> _bytes;
  final int width;
  final int height;
  final int quality;
  var _hasOwnership = true;
  var withdrawCalls = 0;

  @override
  bool get hasOwnership => _hasOwnership;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: _bytes.length,
        width: width,
        height: height,
        quality: quality,
      );

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(_bytes);

  @override
  PreparedImageLease promoteOwnership() => this;

  @override
  Future<void> dispose() => withdrawOwnership();

  @override
  Future<void> withdrawOwnership() async {
    if (!_hasOwnership) {
      return;
    }
    withdrawCalls++;
    _hasOwnership = false;
  }
}
