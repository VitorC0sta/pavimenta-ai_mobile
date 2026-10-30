import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streaming_multipart_encoder.dart';

const String _boundary = 'TestBoundary0123456789';

StreamingMultipartEncoder _encoder([String boundary = _boundary]) =>
    StreamingMultipartEncoder(boundaryGenerator: () => boundary);

MultipartFilePart _file(
  List<List<int>> chunks, {
  int? length,
  String name = 'image',
  String filename = 'occurrence.jpg',
  String contentType = 'image/jpeg',
}) =>
    MultipartFilePart(
      name,
      filename: filename,
      contentType: contentType,
      length: length ?? chunks.fold<int>(0, (sum, chunk) => sum + chunk.length),
      source: Stream<List<int>>.fromIterable(chunks),
    );

Future<List<int>> _collect(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return bytes;
}

Matcher _failure(MultipartEncodingFailure failure) =>
    isA<MultipartEncodingException>()
        .having((error) => error.failure, 'failure', failure);

void main() {
  // **Validates: Requirements RF-14, RNF-01.8–12, RNF-06.4–5**
  group('StreamingMultipartEncoder bytes', () {
    test('writes delimiters, CRLF, headers, UTF-8 text and file bytes',
        () async {
      final body = _encoder().encode(<MultipartPart>[
        const MultipartTextPart('idempotencyKey', 'abc'),
        const MultipartTextPart('defectClass', 'buraco ção'),
        _file(<List<int>>[
          <int>[0xFF, 0xD8],
          <int>[0x00, 0xFF, 0xD9],
        ]),
      ]);

      final bytes = await _collect(body.open());
      final expected = <int>[
        ...ascii.encode(
          '--$_boundary\r\n'
          'Content-Disposition: form-data; name="idempotencyKey"\r\n'
          '\r\n'
          'abc\r\n'
          '--$_boundary\r\n'
          'Content-Disposition: form-data; name="defectClass"\r\n'
          '\r\n',
        ),
        ...utf8.encode('buraco ção'),
        ...ascii.encode(
          '\r\n'
          '--$_boundary\r\n'
          'Content-Disposition: form-data; name="image"; '
          'filename="occurrence.jpg"\r\n'
          'Content-Type: image/jpeg\r\n'
          '\r\n',
        ),
        0xFF,
        0xD8,
        0x00,
        0xFF,
        0xD9,
        ...ascii.encode('\r\n--$_boundary--\r\n'),
      ];

      expect(bytes, expected);
      expect(body.contentLength, expected.length);
      expect(body.boundary, _boundary);
      expect(body.contentType, 'multipart/form-data; boundary=$_boundary');
    });

    test('is deterministic for a fixed boundary', () async {
      List<MultipartPart> parts() => <MultipartPart>[
            const MultipartTextPart('latitude', '-23.5'),
            _file(<List<int>>[
              <int>[1, 2, 3],
            ]),
          ];

      final first = await _collect(_encoder().encode(parts()).open());
      final second = await _collect(_encoder().encode(parts()).open());

      expect(first, second);
    });

    test(
        'Content-Length equals emitted bytes for multibyte text and an '
        'empty file', () async {
      final body = _encoder().encode(<MultipartPart>[
        const MultipartTextPart('note', '日本 😀 é'),
        const MultipartTextPart('empty', ''),
        _file(const <List<int>>[]),
      ]);

      expect(await _collect(body.open()), hasLength(body.contentLength));
    });
  });

  group('StreamingMultipartEncoder streaming', () {
    test('does not read the source before open and forwards chunks lazily',
        () async {
      var listened = false;
      final source = StreamController<List<int>>(
        onListen: () => listened = true,
      );
      final body = _encoder().encode(<MultipartPart>[
        MultipartFilePart(
          'image',
          filename: 'occurrence.jpg',
          contentType: 'image/jpeg',
          length: 4,
          source: source.stream,
        ),
      ]);
      expect(listened, isFalse);

      final received = <List<int>>[];
      final done = Completer<void>();
      body.open().listen(received.add, onDone: done.complete);

      source.add(<int>[1, 2]);
      await pumpEventQueue();
      expect(listened, isTrue);
      // The first file chunk is already forwarded before the source finishes.
      expect(received.any((chunk) => _sameBytes(chunk, <int>[1, 2])), isTrue);
      expect(done.isCompleted, isFalse);

      source.add(<int>[3, 4]);
      await source.close();
      await done.future;

      expect(
        received.fold<int>(0, (sum, chunk) => sum + chunk.length),
        body.contentLength,
      );
    });

    test('opening the body twice is rejected', () {
      final body = _encoder().encode(<MultipartPart>[
        const MultipartTextPart('a', 'b'),
      ]);
      body.open();

      expect(
        body.open,
        throwsA(_failure(MultipartEncodingFailure.bodyAlreadyConsumed)),
      );
    });

    test('a file shorter than declared ends with a sanitized mismatch',
        () async {
      final body = _encoder().encode(<MultipartPart>[
        _file(<List<int>>[
          <int>[1, 2],
        ], length: 3),
      ]);

      await expectLater(
        _collect(body.open()),
        throwsA(_failure(MultipartEncodingFailure.fileLengthMismatch)),
      );
    });

    test('a file longer than declared never forwards the excess bytes',
        () async {
      final body = _encoder().encode(<MultipartPart>[
        _file(<List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ], length: 3),
      ]);
      final received = <int>[];
      Object? error;

      try {
        await for (final chunk in body.open()) {
          received.addAll(chunk);
        }
      } catch (caught) {
        error = caught;
      }

      expect(error, _failure(MultipartEncodingFailure.fileLengthMismatch));
      expect(received, isNot(contains(3)));
      expect(received.length, lessThan(body.contentLength));
    });

    test('a failing source is reported without the raw exception', () async {
      final body = _encoder().encode(<MultipartPart>[
        MultipartFilePart(
          'image',
          filename: 'occurrence.jpg',
          contentType: 'image/jpeg',
          length: 1,
          source: Stream<List<int>>.error(
            StateError('/data/user/0/private/secret.jpg'),
          ),
        ),
      ]);

      Object? error;
      try {
        await _collect(body.open());
      } catch (caught) {
        error = caught;
      }

      expect(error, _failure(MultipartEncodingFailure.fileSourceFailure));
      expect(error.toString(), isNot(contains('secret')));
      expect(error.toString(), isNot(contains('/data')));
    });
  });

  group('StreamingMultipartEncoder validation', () {
    test('default boundary is secure-random, valid and changes per encoding',
        () {
      final encoder = StreamingMultipartEncoder();
      final parts = <MultipartPart>[const MultipartTextPart('a', 'b')];

      final first = encoder.encode(parts).boundary;
      final second = encoder.encode(parts).boundary;

      expect(StreamingMultipartEncoder.isValidBoundary(first), isTrue);
      expect(first.length, lessThanOrEqualTo(70));
      expect(first, isNot(second));
    });

    test('rejects unsafe boundaries', () {
      for (final boundary in <String>[
        '',
        'a' * 71,
        'has space',
        'quote"',
        'semi;colon',
        'line\r\nbreak',
        'çedilha',
      ]) {
        expect(
          () => _encoder(boundary).encode(<MultipartPart>[
            const MultipartTextPart('a', 'b'),
          ]),
          throwsA(_failure(MultipartEncodingFailure.invalidBoundary)),
          reason: 'boundary ${jsonEncode(boundary)}',
        );
      }
      expect(StreamingMultipartEncoder.isValidBoundary('a' * 70), isTrue);
    });

    test('rejects empty part lists', () {
      expect(
        () => _encoder().encode(const <MultipartPart>[]),
        throwsA(_failure(MultipartEncodingFailure.noParts)),
      );
    });

    test(
        'rejects part names, filenames and content types with CR/LF, quotes '
        'or non-ASCII', () {
      for (final name in <String>['', 'a"b', 'a\r\nb', 'a\\b', 'nã']) {
        expect(
          () =>
              _encoder().encode(<MultipartPart>[MultipartTextPart(name, 'v')]),
          throwsA(_failure(MultipartEncodingFailure.invalidPartName)),
        );
      }
      for (final filename in <String>['', 'a"b.jpg', 'a\nb.jpg', 'ç.jpg']) {
        expect(
          () => _encoder().encode(<MultipartPart>[
            _file(const <List<int>>[], filename: filename),
          ]),
          throwsA(_failure(MultipartEncodingFailure.invalidFilename)),
        );
      }
      for (final type in <String>[
        '',
        'image',
        'image/jpeg\r\nX-Injected: 1',
        'image/jpeg; q=1',
      ]) {
        expect(
          () => _encoder().encode(<MultipartPart>[
            _file(const <List<int>>[], contentType: type),
          ]),
          throwsA(_failure(MultipartEncodingFailure.invalidContentType)),
        );
      }
    });

    test(
        'rejects negative declared lengths, unpaired surrogates and text '
        'containing the delimiter', () {
      expect(
        () => _encoder().encode(<MultipartPart>[
          _file(const <List<int>>[], length: -1),
        ]),
        throwsA(_failure(MultipartEncodingFailure.invalidDeclaredLength)),
      );
      expect(
        () => _encoder().encode(<MultipartPart>[
          const MultipartTextPart('a', 'x\uD800y'),
        ]),
        throwsA(_failure(MultipartEncodingFailure.invalidTextValue)),
      );
      expect(
        () => _encoder().encode(<MultipartPart>[
          const MultipartTextPart('a', 'x\r\n--$_boundary--'),
        ]),
        throwsA(_failure(MultipartEncodingFailure.boundaryCollision)),
      );
    });

    test('renderings never reveal values, filenames or bytes', () {
      final body = _encoder().encode(<MultipartPart>[
        const MultipartTextPart('latitude', '-23.55'),
        _file(<List<int>>[
          <int>[1],
        ], filename: 'occurrence.jpg'),
      ]);

      expect(body.toString(), isNot(contains('-23.55')));
      expect(
        const MultipartTextPart('latitude', '-23.55').toString(),
        isNot(contains('-23.55')),
      );
      expect(
        _file(const <List<int>>[], filename: 'occurrence.jpg').toString(),
        isNot(contains('occurrence.jpg')),
      );
      expect(
        const MultipartEncodingException(
          MultipartEncodingFailure.fileLengthMismatch,
        ).toString(),
        'MultipartEncodingException(fileLengthMismatch)',
      );
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
