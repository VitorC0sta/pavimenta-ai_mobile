import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_multipart_preparer.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streaming_multipart_encoder.dart';

import '../../support/e4/fake_delivery_queue.dart';

// Explicitly fictitious values; none is a real key, URL, or identifier.
const String _key = '423e4567-e89b-42d3-a456-426614174000';
const String _secret = 'fakeprefix.fake-secret-for-tests-only';
const String _host = 'example.invalid';

final DeliveryConfiguration _configuration = DeliveryConfiguration(
  revision: 3,
  baseUrl: Uri.parse('https://$_host'),
  credential: NonPrintableSecret(_secret),
);

/// Smallest byte sequence with the JPEG SOI signature and EOI marker.
List<int> _jpegLike(int length) {
  final bytes = List<int>.filled(length, 0x11);
  bytes[0] = 0xFF;
  bytes[1] = 0xD8;
  bytes[2] = 0xFF;
  bytes[length - 2] = 0xFF;
  bytes[length - 1] = 0xD9;
  return bytes;
}

/// Image source that records how it is consumed.
final class _TrackedSource {
  _TrackedSource(this.chunks, {this.errorAfterChunks});

  final List<List<int>> chunks;
  final int? errorAfterChunks;
  bool listened = false;
  bool cancelled = false;
  int chunksPulled = 0;

  Stream<List<int>> get stream {
    late StreamController<List<int>> controller;
    var index = 0;
    // One chunk per microtask, honoring pause, like a file read on demand.
    void pump() {
      if (controller.isPaused || controller.isClosed) {
        return;
      }
      if (errorAfterChunks != null && index == errorAfterChunks) {
        controller.addError(StateError('/private/path/$_key.jpg'));
        controller.close();
        return;
      }
      if (index >= chunks.length) {
        controller.close();
        return;
      }
      chunksPulled++;
      controller.add(chunks[index++]);
      scheduleMicrotask(pump);
    }

    controller = StreamController<List<int>>(
      onListen: () {
        listened = true;
        scheduleMicrotask(pump);
      },
      onResume: () => scheduleMicrotask(pump),
      onCancel: () {
        cancelled = true;
      },
    );
    return controller.stream;
  }
}

List<List<int>> _chunked(List<int> bytes, int size) => <List<int>>[
      for (var start = 0; start < bytes.length; start += size)
        bytes.sublist(
          start,
          start + size > bytes.length ? bytes.length : start + size,
        ),
    ];

OccurrenceUploadRequest _request({
  required Stream<List<int>> image,
  required int byteLength,
  String idempotencyKey = _key,
  double latitude = -23.5505,
  double longitude = -46.6333,
  double confidence = 1.0,
  String defectClass = 'pothole',
  String detectedAt = '2025-01-02T03:04:05.000Z',
  double? speedKmh = 0,
}) =>
    OccurrenceUploadRequest.fromConfiguration(
      configuration: _configuration,
      idempotencyKey: idempotencyKey,
      payload: DeliveryOccurrencePayload(
        detectedAtIso8601: detectedAt,
        latitude: latitude,
        longitude: longitude,
        speedKmh: speedKmh,
        confidence: confidence,
        defectClass: defectClass,
        image: DeliveryImageRef(byteLength: byteLength, opaqueHandle: Object()),
      ),
      imageStream: image,
    );

StreamingMultipartEncoder _encoder() =>
    StreamingMultipartEncoder(boundaryGenerator: () => 'TestBoundary66');

const OccurrenceMultipartPreparer _preparer = OccurrenceMultipartPreparer();

Matcher _rejected(OccurrenceMultipartPreparationFailure failure) =>
    equals(OccurrenceMultipartPreparationRejected(failure));

void main() {
  // **Validates: Requirements RF-10, RF-14, RF-17.6, RNF-01.8–12, RNF-04.2**
  group('task 66.4 revalidation before the socket', () {
    test('a valid request streams the JPEG lazily into the counted body',
        () async {
      final jpeg = _jpegLike(64);
      final source = _TrackedSource(_chunked(jpeg, 8));

      final result = await _preparer.prepare(
        _request(image: source.stream, byteLength: jpeg.length),
        _encoder(),
      );

      expect(result, isA<PreparedOccurrenceMultipart>());
      expect(
        source.chunksPulled,
        lessThan(source.chunks.length),
        reason: 'only the signature is inspected before the body is opened',
      );
      final body = (result as PreparedOccurrenceMultipart).body;
      final bytes = await body.open().expand((chunk) => chunk).toList();
      expect(bytes.length, body.contentLength);
      expect(latin1.decode(bytes), contains(latin1.decode(jpeg)));
      expect(source.chunksPulled, source.chunks.length);
    });

    test('accepts exactly 2 MiB and rejects one byte more without reading',
        () async {
      const limit = OccurrenceMultipartPreparer.maximumImageByteLength;
      expect(limit, 2 * 1024 * 1024);
      final atLimit = _TrackedSource(_chunked(_jpegLike(limit), 64 * 1024));
      final accepted = await _preparer.prepare(
        _request(image: atLimit.stream, byteLength: limit),
        _encoder(),
      );
      expect(accepted, isA<PreparedOccurrenceMultipart>());
      await (accepted as PreparedOccurrenceMultipart).discard();
      expect(atLimit.cancelled, isTrue);

      final above = _TrackedSource(<List<int>>[_jpegLike(16)]);
      expect(
        await _preparer.prepare(
          _request(image: above.stream, byteLength: limit + 1),
          _encoder(),
        ),
        _rejected(OccurrenceMultipartPreparationFailure.imageTooLarge),
      );
      expect(above.listened, isFalse);
    });

    test('rejects invalid persisted metadata without opening the image',
        () async {
      final cases =
          <String, OccurrenceUploadRequest Function(Stream<List<int>>)>{
        'non-UUID key': (s) =>
            _request(image: s, byteLength: 16, idempotencyKey: 'not-a-uuid'),
        'latitude above 90': (s) =>
            _request(image: s, byteLength: 16, latitude: 90.5),
        'longitude NaN': (s) =>
            _request(image: s, byteLength: 16, longitude: double.nan),
        'confidence above 1': (s) =>
            _request(image: s, byteLength: 16, confidence: 1.5),
        'other defect class': (s) =>
            _request(image: s, byteLength: 16, defectClass: 'crack'),
        'detectedAt without offset': (s) => _request(
            image: s, byteLength: 16, detectedAt: '2025-01-02T03:04:05'),
        'detectedAt not a date': (s) => _request(
            image: s, byteLength: 16, detectedAt: '2025-13-45T99:04:05Z'),
        'negative speed': (s) =>
            _request(image: s, byteLength: 16, speedKmh: -0.1),
        'speed above 300': (s) =>
            _request(image: s, byteLength: 16, speedKmh: 300.5),
      };
      for (final entry in cases.entries) {
        final source = _TrackedSource(<List<int>>[_jpegLike(16)]);
        expect(
          await _preparer.prepare(entry.value(source.stream), _encoder()),
          _rejected(OccurrenceMultipartPreparationFailure.invalidMetadata),
          reason: entry.key,
        );
        expect(source.listened, isFalse, reason: entry.key);
      }

      final offset = _TrackedSource(<List<int>>[_jpegLike(16)]);
      final withOffset = await _preparer.prepare(
        _request(
          image: offset.stream,
          byteLength: 16,
          detectedAt: '2025-01-02T00:04:05.000-03:00',
          speedKmh: null,
        ),
        _encoder(),
      );
      expect(withOffset, isA<PreparedOccurrenceMultipart>());
      await (withOffset as PreparedOccurrenceMultipart).discard();
    });

    test('rejects a non-JPEG signature and releases the image read', () async {
      final png = <int>[0x89, 0x50, 0x4E, 0x47, ...List<int>.filled(12, 0)];
      final source = _TrackedSource(_chunked(png, 1));
      expect(
        await _preparer.prepare(
          _request(image: source.stream, byteLength: png.length),
          _encoder(),
        ),
        _rejected(OccurrenceMultipartPreparationFailure.imageNotJpeg),
      );
      expect(source.cancelled, isTrue);

      final tiny = _TrackedSource(<List<int>>[
        <int>[0xFF, 0xD8, 0xFF],
      ]);
      expect(
        await _preparer.prepare(
          _request(image: tiny.stream, byteLength: 3),
          _encoder(),
        ),
        _rejected(OccurrenceMultipartPreparationFailure.imageNotJpeg),
      );
      expect(tiny.listened, isFalse);
    });

    test('a failing or truncated image is a sanitized unreadable failure',
        () async {
      final failing = _TrackedSource(<List<int>>[], errorAfterChunks: 0);
      final failed = await _preparer.prepare(
        _request(image: failing.stream, byteLength: 16),
        _encoder(),
      );
      expect(
        failed,
        _rejected(OccurrenceMultipartPreparationFailure.imageUnreadable),
      );
      expect(failed.toString(), isNot(contains('path')));
      expect(failed.toString(), isNot(contains(_key)));

      final truncated = _TrackedSource(<List<int>>[
        <int>[0xFF, 0xD8],
      ]);
      expect(
        await _preparer.prepare(
          _request(image: truncated.stream, byteLength: 16),
          _encoder(),
        ),
        _rejected(OccurrenceMultipartPreparationFailure.imageUnreadable),
      );
    });

    test('an assembly failure is reported before the image is opened',
        () async {
      final source = _TrackedSource(<List<int>>[_jpegLike(16)]);
      expect(
        await _preparer.prepare(
          _request(image: source.stream, byteLength: 16),
          StreamingMultipartEncoder(boundaryGenerator: () => 'bad boundary'),
        ),
        _rejected(OccurrenceMultipartPreparationFailure.assemblyFailure),
      );
      expect(source.listened, isFalse);
    });

    test('a JPEG without end-of-image marker fails the body sanitized',
        () async {
      final bytes = _jpegLike(16)..[15] = 0x00;
      final source = _TrackedSource(_chunked(bytes, 4));
      final result = await _preparer.prepare(
        _request(image: source.stream, byteLength: bytes.length),
        _encoder(),
      );
      final body = (result as PreparedOccurrenceMultipart).body;
      await expectLater(
        body.open().drain<void>(),
        throwsA(
          isA<MultipartEncodingException>().having(
            (error) => error.failure,
            'failure',
            MultipartEncodingFailure.fileSourceFailure,
          ),
        ),
      );
    });

    test('rejections render only the category and keep the queued occurrence',
        () async {
      final queue = FakeDeliveryQueue();
      addTearDown(queue.close);
      final notJpeg = List<int>.filled(16, 0x42);
      queue.add(_key, notJpeg);
      final head = await queue.nextHead(DateTime.utc(2025)) as FakeHeadEligible;

      final result = await _preparer.prepare(
        _request(
          image: queue.openImage(head.occurrence.idempotencyKey),
          byteLength: notJpeg.length,
        ),
        _encoder(),
      );

      expect(
        result,
        _rejected(OccurrenceMultipartPreparationFailure.imageNotJpeg),
      );
      final rendered = result.toString();
      expect(rendered, 'OccurrenceMultipartPreparationRejected(imageNotJpeg)');
      for (final forbidden in <String>[_key, _secret, _host, 'B', '-23.5']) {
        expect(rendered, isNot(contains(forbidden)), reason: forbidden);
      }
      final kept = queue.pending.single;
      expect(kept.idempotencyKey, _key);
      expect(kept.imageBytes, notJpeg);
      expect(kept.attemptCount, 0);
      expect(kept.pendingLocalDisposition, isNull);
      expect(queue.removedKeys, isEmpty);
      expect(await queue.readControl(), FakePauseReason.none);
    });
  });
}
