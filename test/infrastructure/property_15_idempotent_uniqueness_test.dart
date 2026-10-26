import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect;
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final scenarios = any.combine2<_Sequence, _RequestPair, _Scenario>(
    any.choose(_Sequence.values),
    any.choose(_RequestPair.values),
    (sequence, requests) => _Scenario(sequence: sequence, requests: requests),
  );
  final inputs = any.combine2<_Scenario, int, _PropertyInput>(
    scenarios,
    any.positiveIntOrZero,
    (scenario, seed) => _PropertyInput(scenario: scenario, seed: seed),
  );

  // Feature: mvp-app-flutter, Property 15: Unicidade idempotente
  // **Validates: Requirements RF-08.3, RF-08.4, RF-12.4, RNF-05.3**
  Glados<_PropertyInput>(
    inputs,
    ExploreConfig(numRuns: 120),
  ).test(
    'retains exactly one canonical first pending occurrence for equivalent and conflicting requests',
    (_PropertyInput input) async {
      final sandbox = await Directory.systemTemp.createTemp('e2_property_15_');
      CoordinatedPersistentOccurrenceQueue? queue;

      try {
        Future<QueueDatabase> openDatabase() => QueueDatabase.open(
              factory: databaseFactoryFfi,
              path:
                  '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName',
            );
        final store = PrivateDurableImageStore.at(
          sandbox,
          tokenGenerator: () => _opaqueToken(input.seed),
        );
        queue = CoordinatedPersistentOccurrenceQueue(
          imageStore: store,
          databaseOpener: openDatabase,
        );
        expect((await queue.bootstrap()).isReady, isTrue);

        final first = _candidate(input.seed);
        final second = switch (input.scenario.requests) {
          _RequestPair.equivalent => _candidate(input.seed),
          _RequestPair.imageConflict => _candidate(
              input.seed,
              imageSeed: input.seed + 1,
            ),
          _RequestPair.metadataConflict => _candidate(
              input.seed,
              detectedAtOffset: const Duration(seconds: 1),
            ),
        };

        final results = switch (input.scenario.sequence) {
          _Sequence.serialized => <OccurrenceAcceptanceResult>[
              await queue.persist(first.occurrence),
              await queue.persist(second.occurrence),
            ],
          _Sequence.concurrent => await Future.wait<OccurrenceAcceptanceResult>(
              <Future<OccurrenceAcceptanceResult>>[
                queue.persist(first.occurrence),
                queue.persist(second.occurrence),
              ],
            ),
        };

        expect(results.whereType<OccurrencePersisted>(), hasLength(1));
        if (input.scenario.requests == _RequestPair.equivalent) {
          expect(
            results.whereType<OccurrenceAlreadyPersistedEquivalent>(),
            hasLength(1),
          );
        } else {
          expect(results.whereType<OccurrenceIdentityConflict>(), hasLength(1));
        }

        expect(await queue.countPending(), 1);
        final pending = await queue.listPending();
        expect(pending, hasLength(1));
        final retained = pending.single.record;
        final retainedBytes = await store
            .openRead(retained.image)
            .expand((chunk) => chunk)
            .toList();

        final retainedFirst = _matches(retained, first);
        final retainedSecond = _matches(retained, second);
        expect(retainedFirst || retainedSecond, isTrue);
        expect(
          sha256.convert(retainedBytes).toString(),
          retained.image.sha256,
        );
        expect(
          retainedBytes,
          retainedFirst ? first.bytes : second.bytes,
          reason: 'an existing canonical JPEG must never be overwritten',
        );

        if (input.scenario.sequence == _Sequence.serialized) {
          expect(retainedFirst, isTrue);
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

enum _Sequence { serialized, concurrent }

enum _RequestPair { equivalent, imageConflict, metadataConflict }

final class _Scenario {
  const _Scenario({required this.sequence, required this.requests});

  final _Sequence sequence;
  final _RequestPair requests;
}

final class _PropertyInput {
  const _PropertyInput({required this.scenario, required this.seed});

  final _Scenario scenario;
  final int seed;
}

final class _Candidate {
  const _Candidate({required this.occurrence, required this.bytes});

  final InMemoryOccurrence occurrence;
  final List<int> bytes;
}

_Candidate _candidate(
  int seed, {
  int? imageSeed,
  Duration detectedAtOffset = Duration.zero,
}) {
  final width = 1 + seed % 8;
  final height = 1 + (seed ~/ 8) % 8;
  final bytes = _jpeg(seed: imageSeed ?? seed, width: width, height: height);
  final occurrence = const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: _uuidFor(seed),
    detectedAt: DateTime.utc(2025, 1, 1)
        .add(Duration(minutes: seed % 525600))
        .add(detectedAtOffset),
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      accuracyMeters: 4.5,
      speedMetersPerSecond: 10,
    ),
    image: _MemoryPreparedLease(bytes, width: width, height: height),
  );
  return _Candidate(occurrence: occurrence, bytes: bytes);
}

List<int> _jpeg({required int seed, required int width, required int height}) {
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

String _opaqueToken(int seed) => seed.toRadixString(16).padLeft(32, '0');

bool _matches(QueueRecordProjection record, _Candidate candidate) {
  final occurrence = candidate.occurrence;
  final image = occurrence.image as PreparedImageLease;
  final metadata = image.metadata;
  return record.idempotencyKey == occurrence.idempotencyKey &&
      record.detectedAtIso8601 == occurrence.detectedAtIso8601 &&
      record.latitude == occurrence.latitude &&
      record.longitude == occurrence.longitude &&
      record.accuracyMeters == occurrence.accuracyMeters &&
      record.speedKmh == occurrence.speedKmh &&
      record.confidence == occurrence.confidence &&
      record.defectClass == occurrence.defectClass &&
      record.image.mimeType == metadata.mimeType &&
      record.image.byteLength == metadata.byteLength &&
      record.image.sha256 == sha256.convert(candidate.bytes).toString() &&
      record.image.width == metadata.width &&
      record.image.height == metadata.height &&
      record.image.quality == metadata.quality;
}

final class _MemoryPreparedLease implements PreparedImageLease {
  _MemoryPreparedLease(
    List<int> bytes, {
    required this.width,
    required this.height,
  }) : _bytes = List<int>.unmodifiable(bytes);

  final List<int> _bytes;
  final int width;
  final int height;
  var _hasOwnership = true;

  @override
  bool get hasOwnership => _hasOwnership;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: _bytes.length,
        width: width,
        height: height,
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
