import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_multipart_mapper.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/persistent_delivery_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streaming_multipart_encoder.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Explicitly fictitious values; none is a real key, URL, or identifier.
const String _key = '323e4567-e89b-42d3-a456-426614174000';
const double _accuracyMeters = 7.25;

const List<String> _canonicalNames = <String>[
  'idempotencyKey',
  'latitude',
  'longitude',
  'confidence',
  'defectClass',
  'detectedAt',
  'speedKmh',
  'image',
];

/// One encoded attempt: ordered part names, text values, image bytes, and the
/// full body with its per-attempt boundary.
final class _Attempt {
  _Attempt(this.names, this.texts, this.image, this.body, this.boundary);

  final List<String> names;
  final Map<String, String> texts;
  final List<int> image;
  final List<int> body;
  final String boundary;

  /// Body text with the boundary neutralized (it may change per retry).
  String get logicalBody =>
      latin1.decode(body).replaceAll(boundary, '<boundary>');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e4_multipart_retry_');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<(CoordinatedPersistentOccurrenceQueue, PersistentDeliveryQueue)>
      readyQueue() async {
    final queue = CoordinatedPersistentOccurrenceQueue(
      imageStore: PrivateDurableImageStore.at(sandbox),
      databaseOpener: () => QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName',
      ),
    );
    addTearDown(queue.close);
    await queue.bootstrap();
    return (queue, PersistentDeliveryQueue(queue));
  }

  final configuration = DeliveryConfiguration(
    revision: 1,
    baseUrl: Uri.parse('https://example.invalid'),
    credential: NonPrintableSecret('fakeprefix.fake-secret-for-tests-only'),
  );
  const mapper = OccurrenceMultipartMapper();

  /// Builds and fully encodes one attempt exactly as the transport would.
  Future<_Attempt> attempt(
    PersistentDeliveryQueue delivery,
    DeliveryHeadEligible eligible,
    String boundary,
  ) async {
    final request = OccurrenceUploadRequest.forEligibleHead(
      configuration: configuration,
      eligible: eligible,
      imageStream: delivery.openImage(eligible),
    );
    final parts = mapper.partsFor(request);
    final names = parts.map((part) => part.name).toList();
    final texts = <String, String>{
      for (final part in parts.whereType<MultipartTextPart>())
        part.name: part.value,
    };
    final body = StreamingMultipartEncoder(boundaryGenerator: () => boundary)
        .encode(parts);
    final bytes = await body.open().expand((chunk) => chunk).toList();
    expect(bytes.length, body.contentLength);
    final image =
        (await delivery.openImage(eligible).expand((chunk) => chunk).toList());
    return _Attempt(names, texts, image, bytes, boundary);
  }

  final now = DateTime.utc(2025, 3, 4, 5, 6, 7);

  // **Validates: Requirements RF-08, RF-12.9–11, RF-14, RNF-01.8–12**
  group('task 66.3 persisted representation across retries', () {
    test('a retry reuses the same key, values, and JPEG bytes', () async {
      final jpeg = _jpeg(red: 40);
      final (queue, delivery) = await readyQueue();
      await queue.persist(_occurrence(bytes: jpeg, speedMetersPerSecond: 10));

      final first = await delivery.nextHead(now) as DeliveryHeadEligible;
      final firstAttempt = await attempt(delivery, first, 'AttemptOne');

      final due = now.add(const Duration(seconds: 30));
      expect(
        await delivery.recordRecoverableFailure(_key, now, due),
        DeliveryMutationResult.applied,
      );
      expect(await delivery.nextHead(now), isA<DeliveryHeadInBackoff>());

      final retry = await delivery.nextHead(due) as DeliveryHeadEligible;
      expect(retry.head.attemptCount, 1, reason: 'retry state did change');
      final retryAttempt = await attempt(delivery, retry, 'AttemptTwo');

      expect(retryAttempt.texts['idempotencyKey'], _key);
      expect(retryAttempt.names, firstAttempt.names);
      expect(retryAttempt.texts, firstAttempt.texts);
      expect(retryAttempt.image, jpeg);
      expect(firstAttempt.image, jpeg);
      expect(retryAttempt.body.length, firstAttempt.body.length);
      expect(retryAttempt.logicalBody, firstAttempt.logicalBody);
      expect(retryAttempt.texts['detectedAt'], '2025-01-02T03:04:05.000Z');
      expect(retryAttempt.texts['speedKmh'], '36.0');
    });

    test('includes a persisted zero speed and omits an absent speed', () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(_occurrence(bytes: _jpeg(red: 1)));
      final absent = await delivery.nextHead(now) as DeliveryHeadEligible;
      final withoutSpeed = await attempt(delivery, absent, 'NoSpeed');
      expect(withoutSpeed.names, isNot(contains('speedKmh')));
      expect(withoutSpeed.logicalBody, isNot(contains('speedKmh')));

      expect(await queue.removeInternal(_key), isA<QueueOccurrenceRemoved>());
      await queue.persist(
        _occurrence(bytes: _jpeg(red: 2), speedMetersPerSecond: 0),
      );
      final zero = await delivery.nextHead(now) as DeliveryHeadEligible;
      final withZero = await attempt(delivery, zero, 'ZeroSpeed');
      expect(withZero.texts['speedKmh'], '0.0');
      expect(withZero.names, _canonicalNames);
    });

    test('never maps highway, km, source, accuracy, digest, sequence, or retry',
        () async {
      final (queue, delivery) = await readyQueue();
      await queue.persist(
        _occurrence(bytes: _jpeg(red: 9), speedMetersPerSecond: 0),
      );
      final record = (await queue.listPending()).single.record;
      expect(record.accuracyMeters, _accuracyMeters);
      final due = now.add(const Duration(seconds: 5));
      await delivery.recordRecoverableFailure(_key, now, due);
      final eligible = await delivery.nextHead(due) as DeliveryHeadEligible;
      expect(eligible.head.attemptCount, 1);

      final result = await attempt(delivery, eligible, 'Forbidden');

      expect(result.names, _canonicalNames);
      expect(result.texts.values, isNot(contains(_accuracyMeters.toString())));
      final headers = result.logicalBody.replaceAll(
        latin1.decode(result.image),
        '<image>',
      );
      for (final forbidden in <String>[
        'highway',
        'km"',
        'source',
        'accuracy',
        'sha256',
        'digest',
        'sequence',
        'attempt',
        'backoff',
        'pause',
        record.image.sha256,
        record.image.relativeName,
      ]) {
        expect(headers, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}

InMemoryOccurrence _occurrence({
  required List<int> bytes,
  double? speedMetersPerSecond,
}) =>
    const InMemoryOccurrenceFactory().createManual(
      idempotencyKey: _key,
      detectedAt: DateTime.utc(2025, 1, 2, 3, 4, 5),
      location: ImmutableLocationSnapshot(
        point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
        accuracyMeters: _accuracyMeters,
        speedMetersPerSecond: speedMetersPerSecond,
      ),
      image: _Lease(bytes),
    );

List<int> _jpeg({required int red}) {
  final image = image_codec.Image(width: 8, height: 8);
  image.clear(image_codec.ColorRgb8(red, 32, 16));
  return image_codec.encodeJpg(image, quality: 85);
}

final class _Lease implements PreparedImageLease {
  _Lease(this.bytes);

  final List<int> bytes;
  var _hasOwnership = true;

  @override
  bool get hasOwnership => _hasOwnership;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: bytes.length,
        width: 8,
        height: 8,
        quality: 85,
      );

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(bytes);

  @override
  PreparedImageLease promoteOwnership() => this;

  @override
  Future<void> withdrawOwnership() async {
    _hasOwnership = false;
  }

  @override
  Future<void> dispose() => withdrawOwnership();
}
