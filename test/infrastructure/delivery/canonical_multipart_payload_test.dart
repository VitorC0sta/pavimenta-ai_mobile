import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_multipart_mapper.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_multipart_preparer.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streaming_multipart_encoder.dart';

// Explicitly fictitious values; none is a real key, URL, or identifier.
const String _key = '523e4567-e89b-42d3-a456-426614174000';
const String _boundary = 'CanonicalBoundary66';

const List<String> _textNames = <String>[
  'idempotencyKey',
  'latitude',
  'longitude',
  'confidence',
  'defectClass',
  'detectedAt',
];

const List<String> _forbiddenNames = <String>[
  'highway',
  'km',
  'source',
  'accuracyMeters',
  'sha256',
  'digest',
  'sequence',
  'attemptCount',
  'nextAttemptAt',
  'pause',
];

/// JPEG-like bytes that also contain CR/LF and a boundary look-alike, which
/// must travel untouched inside the file part.
List<int> _jpeg() => <int>[
      0xFF,
      0xD8,
      0xFF,
      ...ascii.encode('\r\n--$_boundary\r\nname="speedKmh"\r\n'),
      ...List<int>.generate(300, (index) => index % 256),
      0xFF,
      0xD9,
    ];

List<List<int>> _chunked(List<int> bytes, int size) => <List<int>>[
      for (var start = 0; start < bytes.length; start += size)
        bytes.sublist(
          start,
          start + size > bytes.length ? bytes.length : start + size,
        ),
    ];

OccurrenceUploadRequest _request(
  List<int> jpeg,
  List<List<int>> chunks, {
  double? speedKmh,
  double confidence = 1.0,
  String detectedAt = '2026-10-14T12:30:45.123-03:00',
}) =>
    OccurrenceUploadRequest(
      baseUrl: Uri.parse('https://example.invalid'),
      credential: NonPrintableSecret('fakeprefix.fake-secret-for-tests-only'),
      configurationRevision: 2,
      idempotencyKey: _key,
      payload: DeliveryOccurrencePayload(
        detectedAtIso8601: detectedAt,
        latitude: -23.5505,
        longitude: -46.6333,
        speedKmh: speedKmh,
        confidence: confidence,
        defectClass: 'pothole',
        image: DeliveryImageRef(
          byteLength: jpeg.length,
          opaqueHandle: Object(),
        ),
      ),
      imageStream: Stream<List<int>>.fromIterable(chunks),
    );

StreamingMultipartEncoder _encoder([String boundary = _boundary]) =>
    StreamingMultipartEncoder(boundaryGenerator: () => boundary);

const OccurrenceMultipartMapper _mapper = OccurrenceMultipartMapper();

Future<List<List<int>>> _emittedChunks(EncodedMultipartBody body) =>
    body.open().toList();

List<int> _flatten(List<List<int>> chunks) =>
    chunks.expand((chunk) => chunk).toList();

/// One parsed part: header lines (ASCII) and raw body bytes.
final class _Parsed {
  _Parsed(this.headers, this.content);

  final List<String> headers;
  final List<int> content;

  String get name =>
      RegExp(r'name="([^"]*)"').firstMatch(headers.first)!.group(1)!;
}

/// Splits [bytes] on the exact delimiters, asserting the framing on the way.
///
/// Bytes map 1:1 to code units through latin1, so the arbitrary JPEG content
/// is carried unchanged.
List<_Parsed> _parse(List<int> bytes, String boundary) {
  final text = latin1.decode(bytes);
  final opening = '--$boundary\r\n';
  final closing = '\r\n--$boundary--\r\n';
  expect(text.startsWith(opening), isTrue, reason: 'opening delimiter');
  expect(text.endsWith(closing), isTrue, reason: 'closing delimiter + CRLF');
  final inner = text.substring(
    opening.length,
    text.length - closing.length,
  );
  final parts = <_Parsed>[];
  var rest = inner;
  while (true) {
    final headerEnd = rest.indexOf('\r\n\r\n');
    expect(headerEnd, greaterThanOrEqualTo(0), reason: 'header terminator');
    final headers = rest.substring(0, headerEnd).split('\r\n');
    final afterHeaders = rest.substring(headerEnd + 4);
    final isFile = headers.first.contains('filename=');
    final next = '\r\n--$boundary\r\n';
    // The file content may contain a delimiter look-alike, so the size of the
    // file part is taken from the final delimiter (the file is always last).
    final contentEnd =
        isFile ? afterHeaders.length : afterHeaders.indexOf(next);
    if (isFile || contentEnd < 0) {
      parts.add(_Parsed(headers, latin1.encode(afterHeaders)));
      break;
    }
    parts.add(
        _Parsed(headers, latin1.encode(afterHeaders.substring(0, contentEnd))));
    rest = afterHeaders.substring(contentEnd + next.length);
  }
  return parts;
}

void main() {
  // **Validates: Requirements RF-10, RF-14, RF-17.6, RNF-01.8–12, RNF-03.7,9–10, RNF-04.2, RNF-06.4–5,10–12**
  group('task 66.5 canonical multipart payload', () {
    test('full body equals the expected bytes and Content-Length', () async {
      final jpeg = _jpeg();
      final body = _mapper.encode(
        _request(jpeg, _chunked(jpeg, 64), speedKmh: 42.5),
        _encoder(),
      );

      final bytes = _flatten(await _emittedChunks(body));

      String field(String name, String value) => '--$_boundary\r\n'
          'Content-Disposition: form-data; name="$name"\r\n'
          '\r\n'
          '$value\r\n';
      final expected = <int>[
        ...ascii.encode(
          [
            field('idempotencyKey', _key),
            field('latitude', '-23.5505'),
            field('longitude', '-46.6333'),
            field('confidence', '1.0'),
            field('defectClass', 'pothole'),
            field('detectedAt', '2026-10-14T12:30:45.123-03:00'),
            field('speedKmh', '42.5'),
            '--$_boundary\r\n'
                'Content-Disposition: form-data; name="image"; '
                'filename="occurrence.jpg"\r\n'
                'Content-Type: image/jpeg\r\n'
                '\r\n',
          ].join(),
        ),
        ...jpeg,
        ...ascii.encode('\r\n--$_boundary--\r\n'),
      ];
      expect(bytes, expected);
      expect(body.contentLength, expected.length);
      expect(body.contentType, 'multipart/form-data; boundary=$_boundary');
    });

    test('part names, order, types, and headers follow RF-14', () async {
      final jpeg = _jpeg();
      final body = _mapper.encode(
        _request(jpeg, _chunked(jpeg, 100), speedKmh: 0),
        _encoder(),
      );
      final parts = _parse(_flatten(await _emittedChunks(body)), _boundary);

      expect(
        parts.map((part) => part.name),
        <String>[..._textNames, 'speedKmh', 'image'],
      );
      expect(
        parts.map((part) => part.name).toSet(),
        hasLength(parts.length),
        reason: 'no repeated part name',
      );
      for (final part in parts.take(parts.length - 1)) {
        expect(
            part.headers,
            <String>[
              'Content-Disposition: form-data; name="${part.name}"',
            ],
            reason: 'text part ${part.name} carries only a disposition header');
      }
      final image = parts.last;
      expect(image.headers, <String>[
        'Content-Disposition: form-data; name="image"; '
            'filename="occurrence.jpg"',
        'Content-Type: image/jpeg',
      ]);
      expect(image.content, jpeg);
      expect(image.content.take(2), <int>[0xFF, 0xD8]);
      expect(image.content.skip(image.content.length - 2), <int>[0xFF, 0xD9]);
    });

    test('required fields always present; speedKmh optional', () async {
      final jpeg = _jpeg();
      for (final speed in <double?>[null, 0, 300, 12.5]) {
        final body = _mapper.encode(
          _request(jpeg, _chunked(jpeg, 128), speedKmh: speed),
          _encoder(),
        );
        final parts = _parse(_flatten(await _emittedChunks(body)), _boundary);
        final names = parts.map((part) => part.name).toList();

        for (final required in <String>[..._textNames, 'image']) {
          expect(names, contains(required), reason: '$required, speed $speed');
        }
        if (speed == null) {
          expect(names, isNot(contains('speedKmh')));
          expect(names, hasLength(_textNames.length + 1));
        } else {
          final value = latin1.decode(
            parts.firstWhere((part) => part.name == 'speedKmh').content,
          );
          expect(value, speed.toString());
        }
      }
    });

    test('values are the persisted ones; manual confidence is exactly 1.0',
        () async {
      final jpeg = _jpeg();
      final body = _mapper.encode(
        _request(jpeg, <List<int>>[jpeg]),
        _encoder(),
      );
      final parts = _parse(_flatten(await _emittedChunks(body)), _boundary);
      String value(String name) => latin1.decode(
            parts.firstWhere((part) => part.name == name).content,
          );

      expect(value('idempotencyKey'), _key);
      expect(value('confidence'), '1.0');
      expect(value('defectClass'), 'pothole');
      expect(value('latitude'), '-23.5505');
      expect(value('longitude'), '-46.6333');
      expect(
        value('detectedAt'),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}T[\d:.]+(Z|[+-]\d{2}:\d{2})$')),
      );
    });

    test('omits highway, km, source, and every local-only field', () async {
      final jpeg = _jpeg();
      final body = _mapper.encode(
        _request(jpeg, _chunked(jpeg, 50), speedKmh: 10),
        _encoder(),
      );
      final bytes = _flatten(await _emittedChunks(body));
      final parts = _parse(bytes, _boundary);
      final names = parts.map((part) => part.name).toSet();
      for (final forbidden in _forbiddenNames) {
        expect(names, isNot(contains(forbidden)), reason: forbidden);
      }

      final nonImage = latin1.decode(
        _flatten(<List<int>>[
          for (final part in parts.where((part) => part.name != 'image')) ...[
            ascii.encode(part.headers.join('\n')),
            part.content,
          ],
        ]),
      );
      for (final forbidden in <String>['fakeprefix', 'secret', 'example']) {
        expect(nonImage, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('image chunks are forwarded one by one, unmerged and in order',
        () async {
      final jpeg = _jpeg();
      final sourceChunks = <List<int>>[
        jpeg.sublist(0, 1),
        jpeg.sublist(1, 7),
        const <int>[],
        jpeg.sublist(7, 200),
        jpeg.sublist(200),
      ];
      final body = _mapper.encode(
        _request(jpeg, sourceChunks),
        _encoder(),
      );

      final emitted = await _emittedChunks(body);

      final fileStart = emitted.indexWhere(
        (chunk) => _sameBytes(chunk, sourceChunks.first),
      );
      expect(fileStart, greaterThan(0));
      final nonEmpty = sourceChunks.where((chunk) => chunk.isNotEmpty).toList();
      for (var index = 0; index < nonEmpty.length; index++) {
        expect(
          _sameBytes(emitted[fileStart + index], nonEmpty[index]),
          isTrue,
          reason: 'image chunk $index',
        );
      }
      expect(
        _flatten(emitted).length,
        body.contentLength,
        reason: 'Content-Length counts every emitted byte',
      );
      expect(
        emitted.every((chunk) => chunk.length <= jpeg.length),
        isTrue,
        reason: 'no chunk holds more than the file',
      );
    });

    test('Content-Length is the same for any image chunking', () async {
      final jpeg = _jpeg();
      int? declared;
      List<int>? reference;
      for (final size in <int>[1, 3, 7, 64, jpeg.length]) {
        final body = _mapper.encode(
          _request(jpeg, _chunked(jpeg, size), speedKmh: 1),
          _encoder(),
        );
        final bytes = _flatten(await _emittedChunks(body));
        expect(bytes.length, body.contentLength, reason: 'chunk size $size');
        declared ??= body.contentLength;
        reference ??= bytes;
        expect(body.contentLength, declared, reason: 'chunk size $size');
        expect(bytes, reference, reason: 'chunk size $size');
      }
    });

    test('Content-Length grows by the exact size of the optional speed part',
        () {
      final jpeg = _jpeg();
      final without =
          _mapper.encode(_request(jpeg, <List<int>>[jpeg]), _encoder());
      final withSpeed = _mapper.encode(
        _request(jpeg, <List<int>>[jpeg], speedKmh: 0),
        _encoder(),
      );

      final speedPart = ascii.encode(
        '--$_boundary\r\n'
        'Content-Disposition: form-data; name="speedKmh"\r\n'
        '\r\n'
        '0.0\r\n',
      );
      expect(withSpeed.contentLength - without.contentLength, speedPart.length);
    });

    test('attempts keep the same logical body with new boundary and chunks',
        () async {
      final jpeg = _jpeg();
      final firstBody = _mapper.encode(
        _request(jpeg, _chunked(jpeg, 16), speedKmh: 0),
        _encoder('AttemptOneBoundary'),
      );
      final secondBody = _mapper.encode(
        _request(jpeg, _chunked(jpeg, 97), speedKmh: 0),
        _encoder('AttemptTwoBoundaryLonger'),
      );
      final first = _flatten(await _emittedChunks(firstBody));
      final second = _flatten(await _emittedChunks(secondBody));

      expect(firstBody.boundary, isNot(secondBody.boundary));
      expect(
        latin1.decode(first).replaceAll('AttemptOneBoundary', '<b>'),
        latin1.decode(second).replaceAll('AttemptTwoBoundaryLonger', '<b>'),
      );
      final firstParts = _parse(first, 'AttemptOneBoundary');
      final secondParts = _parse(second, 'AttemptTwoBoundaryLonger');
      expect(
        firstParts.map((part) => part.name),
        secondParts.map((part) => part.name),
      );
      for (var index = 0; index < firstParts.length; index++) {
        expect(firstParts[index].headers, secondParts[index].headers);
        expect(firstParts[index].content, secondParts[index].content);
      }
      expect(
        secondBody.contentLength - firstBody.contentLength,
        (secondBody.boundary.length - firstBody.boundary.length) *
            (firstParts.length + 1),
        reason: 'only the delimiter length differs',
      );
    });

    test('default encoder yields a fresh valid boundary for each attempt',
        () async {
      final jpeg = _jpeg();
      final encoder = StreamingMultipartEncoder();
      final first = _mapper.encode(
        _request(jpeg, _chunked(jpeg, 32)),
        encoder,
      );
      final second = _mapper.encode(
        _request(jpeg, _chunked(jpeg, 32)),
        encoder,
      );

      expect(first.boundary, isNot(second.boundary));
      for (final body in <EncodedMultipartBody>[first, second]) {
        final bytes = _flatten(await _emittedChunks(body));
        expect(bytes.length, body.contentLength);
        expect(_parse(bytes, body.boundary).last.content, jpeg);
      }
    });

    test('the preparer path emits the same bytes as the direct mapper',
        () async {
      final jpeg = _jpeg();
      final direct = _flatten(
        await _emittedChunks(
          _mapper.encode(
            _request(jpeg, _chunked(jpeg, 5), speedKmh: 33),
            _encoder(),
          ),
        ),
      );

      final prepared = await const OccurrenceMultipartPreparer().prepare(
        _request(jpeg, _chunked(jpeg, 5), speedKmh: 33),
        _encoder(),
      ) as PreparedOccurrenceMultipart;
      final viaPreparer = _flatten(await _emittedChunks(prepared.body));

      expect(viaPreparer, direct);
      expect(viaPreparer.length, prepared.body.contentLength);
    });

    test('renderings of body and parts do not expose payload or bytes', () {
      final jpeg = _jpeg();
      final request = _request(jpeg, <List<int>>[jpeg], speedKmh: 7);
      final body = _mapper.encode(request, _encoder());

      final rendered = <String>[
        body.toString(),
        ..._mapper
            .partsFor(
              _request(jpeg, <List<int>>[jpeg], speedKmh: 7),
            )
            .map((part) => part.toString()),
      ].join(' ');
      for (final forbidden in <String>[
        _key,
        '-23.5505',
        'pothole',
        'occurrence.jpg',
        'fakeprefix',
      ]) {
        expect(rendered, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
