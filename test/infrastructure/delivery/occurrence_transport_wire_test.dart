import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_transport_result.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/http_occurrence_transport.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_transport_limits.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streamed_http_client_adapter.dart';

// Task 67.6: the E4 transport observed from the outside, first through a
// fake `http.Client` and then through a controlled loopback `HttpServer`.
// Every value below is explicitly fictitious.
const String _key = '423e4567-e89b-42d3-a456-426614174000';
const String _secret = 'fakeprefix.fake-secret-for-tests-only';
const String _secretHost = 'secret-host.invalid';

const OccurrenceTransportLimits _shortLimits = OccurrenceTransportLimits(
  attemptTimeout: Duration(milliseconds: 500),
  bodyDrainTimeout: Duration(milliseconds: 300),
  maxDrainedBodyBytes: 1024,
);

/// A JPEG-shaped payload (SOI, filler, EOI) of exactly [length] bytes.
List<int> _jpegOf(int length) {
  final bytes = List<int>.generate(length, (i) => (i * 7) % 251);
  bytes[0] = 0xFF;
  bytes[1] = 0xD8;
  bytes[2] = 0xFF;
  bytes[length - 2] = 0xFF;
  bytes[length - 1] = 0xD9;
  return bytes;
}

Stream<List<int>> _chunked(List<int> bytes, {int size = 16 * 1024}) =>
    Stream<List<int>>.fromIterable(<List<int>>[
      for (var i = 0; i < bytes.length; i += size)
        bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
    ]);

OccurrenceUploadRequest _request({
  required Uri baseUrl,
  required Stream<List<int>> image,
  required int imageLength,
  String secret = _secret,
  double? speedKmh = 0,
}) =>
    OccurrenceUploadRequest.fromConfiguration(
      configuration: DeliveryConfiguration(
        revision: 1,
        baseUrl: baseUrl,
        credential: NonPrintableSecret(secret),
      ),
      idempotencyKey: _key,
      payload: DeliveryOccurrencePayload(
        detectedAtIso8601: '2025-01-02T03:04:05.000Z',
        latitude: -23.5505,
        longitude: -46.6333,
        speedKmh: speedKmh,
        confidence: 1.0,
        defectClass: 'pothole',
        image: DeliveryImageRef(
          byteLength: imageLength,
          opaqueHandle: Object(),
        ),
      ),
      imageStream: image,
    );

OccurrenceUploadRequest _simpleRequest(
  Uri baseUrl, {
  List<int>? jpeg,
  String secret = _secret,
  double? speedKmh = 0,
}) {
  final bytes = jpeg ?? _jpegOf(64);
  return _request(
    baseUrl: baseUrl,
    image: _chunked(bytes),
    imageLength: bytes.length,
    secret: secret,
    speedKmh: speedKmh,
  );
}

/// One multipart part, with binary-safe (latin1) content.
final class _Part {
  _Part(this.headers, this.content);

  final String headers;
  final String content;

  String get name => RegExp('name="([^"]*)"').firstMatch(headers)!.group(1)!;
}

List<_Part> _parseMultipart(String contentType, List<int> body) {
  final boundary =
      RegExp('boundary=([^;]+)').firstMatch(contentType)!.group(1)!;
  final text = latin1.decode(body);
  final segments = text.split('--$boundary');
  expect(segments.first, isEmpty);
  expect(segments.last, '--\r\n');
  return <_Part>[
    for (final segment in segments.sublist(1, segments.length - 1))
      () {
        final raw = segment.substring(2); // leading CRLF
        final split = raw.indexOf('\r\n\r\n');
        final content = raw.substring(split + 4);
        expect(content.endsWith('\r\n'), isTrue);
        return _Part(
          raw.substring(0, split),
          content.substring(0, content.length - 2),
        );
      }(),
  ];
}

// ---------------------------------------------------------------------------
// Fake client
// ---------------------------------------------------------------------------

/// Drains the request like a real client, records it, then answers or throws.
final class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this._respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _respond;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  final List<List<int>> bodies = <List<int>>[];
  bool closed = false;

  static _ScriptedClient status(int status) => _ScriptedClient(
        (request) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          status,
        ),
      );

  static _ScriptedClient failing(Object error) =>
      _ScriptedClient((request) async => throw error);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.finalize()) {
      builder.add(chunk);
    }
    bodies.add(builder.takeBytes());
    return _respond(request);
  }

  @override
  void close() => closed = true;
}

// ---------------------------------------------------------------------------
// Loopback server
// ---------------------------------------------------------------------------

final class _Seen {
  _Seen(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, List<String>> headers;
  final List<int> body;

  String get contentType => headers['content-type']!.single;
}

typedef _Handler = Future<void> Function(HttpRequest request);

final class _LocalServer {
  _LocalServer._(this._server);

  final HttpServer _server;
  final List<_Seen> seen = <_Seen>[];
  int arrived = 0;
  int active = 0;
  int maxActive = 0;
  _Handler handler = (request) async {
    await request.drain<void>();
    request.response.statusCode = HttpStatus.created;
    await request.response.close();
  };

  static Future<_LocalServer> start() async {
    final server = _LocalServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._serve);
    return server;
  }

  int get port => _server.port;
  Uri get baseUrl => Uri.parse('http://127.0.0.1:$port');

  Future<void> _serve(HttpRequest request) async {
    arrived++;
    active++;
    if (active > maxActive) {
      maxActive = active;
    }
    try {
      await handler(request);
    } on Object {
      // The client abandoned the exchange.
    } finally {
      active--;
    }
  }

  Future<void> close() => _server.close(force: true);
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not reached in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  // **Validates: Requirements RF-13.2–16, RF-14, RF-15–18, RNF-02.1–10,
  // RNF-03.7–10, RNF-04.2, RNF-05.5**
  group('task 67.6 with a fake client', () {
    test('sends exactly POST {BASE_URL}/api/v1/occurrences with one credential',
        () async {
      final client = _ScriptedClient.status(201);
      final transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter(client),
      );

      final result = await transport.send(
        _simpleRequest(Uri.parse('https://api.example.test')),
      );

      expect(result, const TransportHttpResponse(201));
      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(),
          'https://api.example.test/api/v1/occurrences');
      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 0);
      expect(
        request.headers.keys.map((k) => k.toLowerCase()).toSet(),
        <String>{'authorization', 'content-type'},
      );
      expect(request.headers['Authorization'], 'ApiKey $_secret');
      expect(request.contentLength, client.bodies.single.length);
    });

    test('a trailing slash in BASE_URL does not duplicate the path', () async {
      final client = _ScriptedClient.status(201);
      final transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter(client),
      );

      await transport.send(
        _simpleRequest(Uri.parse('https://api.example.test/')),
      );

      expect(client.requests.single.url.toString(),
          'https://api.example.test/api/v1/occurrences');
    });

    test('transmits the canonical multipart parts, in order, with the image',
        () async {
      final jpeg = _jpegOf(5000);
      final client = _ScriptedClient.status(201);
      final transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter(client),
      );

      await transport.send(
        _simpleRequest(
          Uri.parse('https://api.example.test'),
          jpeg: jpeg,
          speedKmh: 42.5,
        ),
      );

      final parts = _parseMultipart(
        client.requests.single.headers['Content-Type']!,
        client.bodies.single,
      );
      expect(parts.map((p) => p.name), <String>[
        'idempotencyKey',
        'latitude',
        'longitude',
        'confidence',
        'defectClass',
        'detectedAt',
        'speedKmh',
        'image',
      ]);
      expect(parts.first.content, _key);
      expect(parts[1].content, '-23.5505');
      expect(parts[4].content, 'pothole');
      expect(parts[5].content, '2025-01-02T03:04:05.000Z');
      expect(parts[6].content, '42.5');
      expect(parts.last.headers, contains('filename="occurrence.jpg"'));
      expect(parts.last.headers, contains('Content-Type: image/jpeg'));
      expect(latin1.encode(parts.last.content), jpeg);
    });

    test('omits speedKmh when it is unknown', () async {
      final client = _ScriptedClient.status(201);
      final transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter(client),
      );

      await transport.send(
        _simpleRequest(Uri.parse('https://api.example.test'), speedKmh: null),
      );

      final parts = _parseMultipart(
        client.requests.single.headers['Content-Type']!,
        client.bodies.single,
      );
      expect(parts.map((p) => p.name), isNot(contains('speedKmh')));
    });

    test('reports every HTTP status verbatim as a response', () async {
      const statuses = <int>[
        200, 201, 202, 204, 301, 302, 303, 307, 308, //
        400, 401, 403, 404, 408, 409, 413, 415, 422, 429, //
        500, 502, 503, 504,
      ];
      for (final status in statuses) {
        final transport = HttpOccurrenceTransport(
          StreamedHttpClientAdapter(_ScriptedClient.status(status)),
        );

        expect(
          await transport.send(
            _simpleRequest(Uri.parse('https://api.example.test')),
          ),
          TransportHttpResponse(status),
          reason: 'status $status',
        );
      }
    });

    test('classifies errors before the headers by type only', () async {
      final cases = <Object, OccurrenceTransportResult>{
        const SocketException('Failed host lookup: $_secretHost'):
            const TransportNetworkFailure(),
        const HandshakeException('bad certificate'):
            const TransportNetworkFailure(),
        http.ClientException('reset', Uri.parse('https://$_secretHost')):
            const TransportNetworkFailure(),
        TimeoutException('too slow'): const TransportTimeout(),
        http.RequestAbortedException(Uri.parse('https://$_secretHost')):
            const TransportCancelled(),
        StateError('unexpected $_secretHost'): const TransportLocalFailure(),
      };
      for (final entry in cases.entries) {
        final transport = HttpOccurrenceTransport(
          StreamedHttpClientAdapter(_ScriptedClient.failing(entry.key)),
        );

        final result = await transport.send(
          _simpleRequest(Uri.parse('https://api.example.test')),
        );

        expect(result, entry.value, reason: entry.key.runtimeType.toString());
        expect('$result', isNot(contains(_secretHost)));
        expect('$result', isNot(contains(_secret)));
      }
    });

    test('a status survives a response body that fails', () async {
      final client = _ScriptedClient(
        (request) async => http.StreamedResponse(
          Stream<List<int>>.error(const SocketException('reset')),
          503,
        ),
      );
      final transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter(client),
      );

      expect(
        await transport.send(
          _simpleRequest(Uri.parse('https://api.example.test')),
        ),
        const TransportHttpResponse(503),
      );
    });

    test('an invalid destination or credential never reaches the client',
        () async {
      final client = _ScriptedClient.status(201);
      final transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter(client),
      );
      final rejected = <OccurrenceUploadRequest>[
        _simpleRequest(Uri.parse('https://api.example.test/other')),
        _simpleRequest(Uri.parse('https://api.example.test/?a=b')),
        _simpleRequest(Uri.parse('https://user:pw@api.example.test')),
        _simpleRequest(Uri.parse('ftp://api.example.test')),
        _simpleRequest(
          Uri.parse('https://api.example.test'),
          secret: 'has space',
        ),
        _simpleRequest(
          Uri.parse('https://api.example.test'),
          secret: 'non-ascii-\u00E7',
        ),
      ];

      for (final request in rejected) {
        expect(await transport.send(request), const TransportLocalFailure());
      }
      expect(client.requests, isEmpty);
    });

    test('an invalid persisted occurrence never reaches the client', () async {
      final client = _ScriptedClient.status(201);
      final transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter(client),
      );
      final notJpeg = List<int>.filled(64, 0x41);

      final result = await transport.send(
        _simpleRequest(Uri.parse('https://api.example.test'), jpeg: notJpeg),
      );

      expect(result, const TransportLocalFailure());
      expect(client.requests, isEmpty);
    });

    test('dispose leaves an injected client open', () async {
      final client = _ScriptedClient.status(201);
      final transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter(client),
      );

      await transport.dispose();

      expect(client.closed, isFalse);
    });
  });

  group('task 67.6 against a loopback server', () {
    late _LocalServer server;
    late HttpOccurrenceTransport transport;
    final extraServers = <_LocalServer>[];

    setUp(() async {
      server = await _LocalServer.start();
      transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter.io(),
        limits: _shortLimits,
      );
    });

    tearDown(() async {
      await transport.dispose();
      await server.close();
      for (final extra in extraServers) {
        await extra.close();
      }
      extraServers.clear();
    });

    /// Handler that records the full body, then answers with [status].
    _Handler recordAndAnswer(int status, {void Function(HttpResponse)? tweak}) {
      return (request) async {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in request) {
          builder.add(chunk);
        }
        final headers = <String, List<String>>{};
        request.headers.forEach((name, values) => headers[name] = values);
        server.seen.add(
          _Seen(request.method, request.uri, headers, builder.takeBytes()),
        );
        final response = request.response..statusCode = status;
        tweak?.call(response);
        await response.close();
      };
    }

    test('delivers one POST to the exact path with the exact credential',
        () async {
      final jpeg = _jpegOf(300 * 1024);
      server.handler = recordAndAnswer(HttpStatus.created);

      final result = await transport.send(
        _simpleRequest(server.baseUrl, jpeg: jpeg),
      );

      expect(result, const TransportHttpResponse(201));
      final seen = server.seen.single;
      expect(seen.method, 'POST');
      expect(seen.uri.toString(), '/api/v1/occurrences');
      expect(seen.headers['authorization'], <String>['ApiKey $_secret']);
      for (final forbidden in <String>[
        'cookie',
        'x-api-key',
        'proxy-authorization',
      ]) {
        expect(seen.headers, isNot(contains(forbidden)));
      }
      expect(seen.headers['authorization']!.single, isNot(contains('Bearer')));
      expect(seen.contentType, startsWith('multipart/form-data; boundary='));
      expect(seen.headers['content-length'], <String>['${seen.body.length}']);
      expect(seen.headers, isNot(contains('transfer-encoding')));
    });

    test('transmits the multipart fields and the exact image bytes', () async {
      final jpeg = _jpegOf(300 * 1024);
      server.handler = recordAndAnswer(HttpStatus.created);

      await transport.send(_simpleRequest(server.baseUrl, jpeg: jpeg));

      final seen = server.seen.single;
      final parts = _parseMultipart(seen.contentType, seen.body);
      expect(parts.map((p) => p.name), <String>[
        'idempotencyKey',
        'latitude',
        'longitude',
        'confidence',
        'defectClass',
        'detectedAt',
        'speedKmh',
        'image',
      ]);
      expect(
        parts.take(7).map((p) => p.content),
        <String>[
          _key,
          '-23.5505',
          '-46.6333',
          '1.0',
          'pothole',
          '2025-01-02T03:04:05.000Z',
          '0.0',
        ],
      );
      expect(latin1.encode(parts.last.content), jpeg);
    });

    test('a cookie set by the server is never replayed', () async {
      server.handler = recordAndAnswer(
        HttpStatus.created,
        tweak: (response) => response.headers.add('set-cookie', 'sid=abc'),
      );

      await transport.send(_simpleRequest(server.baseUrl));
      await transport.send(_simpleRequest(server.baseUrl));

      expect(server.seen, hasLength(2));
      for (final seen in server.seen) {
        expect(seen.headers, isNot(contains('cookie')));
      }
    });

    test('maps every status of the matrix to a response', () async {
      const statuses = <int>[
        200, 201, 202, 204, 400, 401, 403, 404, 408, 409, 413, 415, 422, //
        429, 500, 502, 503, 504,
      ];
      for (final status in statuses) {
        server.handler = recordAndAnswer(status);

        expect(
          await transport.send(_simpleRequest(server.baseUrl)),
          TransportHttpResponse(status),
          reason: 'status $status',
        );
      }
      expect(server.seen, hasLength(statuses.length));
    });

    test('never follows a redirect, not even to the same origin', () async {
      final other = await _LocalServer.start();
      extraServers.add(other);
      const redirects = <int>[301, 302, 303, 307, 308];
      for (final status in redirects) {
        server.handler = recordAndAnswer(
          status,
          tweak: (response) => response.headers.set(
            HttpHeaders.locationHeader,
            status.isEven
                ? '${other.baseUrl}/api/v1/occurrences'
                : '/api/v1/occurrences',
          ),
        );

        expect(
          await transport.send(_simpleRequest(server.baseUrl)),
          TransportHttpResponse(status),
          reason: 'status $status',
        );
      }
      // One request per attempt; the other origin was never contacted.
      expect(server.seen, hasLength(redirects.length));
      expect(other.arrived, 0);
    });

    test('times out when the server never sends headers', () async {
      server.handler = (request) => request.drain<void>();

      final stopwatch = Stopwatch()..start();
      final result = await transport.send(_simpleRequest(server.baseUrl));

      expect(result, const TransportTimeout());
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(transport.pendingAttemptCount, 0);
    });

    test('times out when the upload itself stalls', () async {
      final controller = StreamController<List<int>>();
      controller.add(<int>[0xFF, 0xD8, 0xFF, 0xE0]); // then silence
      server.handler = (request) => request.drain<void>();

      final result = await transport.send(
        _request(
          baseUrl: server.baseUrl,
          image: controller.stream,
          imageLength: 4096,
        ),
      );

      expect(result, const TransportTimeout());
    });

    test('keeps the status when the response body is larger than the limit',
        () async {
      server.handler = (request) async {
        await request.drain<void>();
        final response = request.response..statusCode = HttpStatus.conflict;
        final chunk = List<int>.filled(64 * 1024, 0x41);
        try {
          for (var i = 0; i < 64; i++) {
            response.add(chunk);
            await response.flush();
          }
          await response.close();
        } on Object {
          // The client abandoned the body.
        }
      };

      final stopwatch = Stopwatch()..start();
      final result = await transport.send(_simpleRequest(server.baseUrl));

      expect(result, const TransportHttpResponse(409));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('keeps the status when the response body trickles slowly', () async {
      server.handler = (request) async {
        await request.drain<void>();
        final response = request.response
          ..statusCode = HttpStatus.serviceUnavailable;
        try {
          for (var i = 0; i < 200; i++) {
            response.add(<int>[0x41]);
            await response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          await response.close();
        } on Object {
          // The client abandoned the body.
        }
      };

      final stopwatch = Stopwatch()..start();
      final result = await transport.send(_simpleRequest(server.baseUrl));

      expect(result, const TransportHttpResponse(503));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('refused connection is a network failure', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();
      final patient = HttpOccurrenceTransport(
        StreamedHttpClientAdapter.io(),
        // Windows retries a refused loopback connection for about a second.
        limits: const OccurrenceTransportLimits(
          attemptTimeout: Duration(seconds: 20),
        ),
      );
      addTearDown(patient.dispose);

      final result = await patient.send(
        _simpleRequest(Uri.parse('http://127.0.0.1:$deadPort')),
      );

      expect(result, const TransportNetworkFailure());
    });

    test('a connection dropped before the headers is a network failure',
        () async {
      server.handler = (request) async {
        await request.drain<void>();
        final socket = await request.response.detachSocket(
          writeHeaders: false,
        );
        socket.destroy();
      };

      final result = await transport.send(_simpleRequest(server.baseUrl));

      expect(result, const TransportNetworkFailure());
      expect('$result', isNot(contains('127.0.0.1')));
    });

    test('cancelling during a stalled upload yields TransportCancelled',
        () async {
      final controller = StreamController<List<int>>();
      controller.add(<int>[0xFF, 0xD8, 0xFF, 0xE0]);
      server.handler = (request) => request.drain<void>();
      final patient = HttpOccurrenceTransport(
        StreamedHttpClientAdapter.io(),
        limits: const OccurrenceTransportLimits(
          attemptTimeout: Duration(seconds: 20),
        ),
      );
      addTearDown(patient.dispose);

      final result = patient.send(
        _request(
          baseUrl: server.baseUrl,
          image: controller.stream,
          imageLength: 4096,
        ),
      );
      await _until(() => patient.pendingAttemptCount == 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await patient.cancelActive();

      expect(await result, const TransportCancelled());
      expect(patient.pendingAttemptCount, 0);
    });

    test('cancelling also cancels an attempt that waits its turn', () async {
      final patient = HttpOccurrenceTransport(
        StreamedHttpClientAdapter.io(),
        limits: const OccurrenceTransportLimits(
          attemptTimeout: Duration(seconds: 20),
        ),
      );
      addTearDown(patient.dispose);
      server.handler = (request) => request.drain<void>(); // never answers

      final first = patient.send(_simpleRequest(server.baseUrl));
      await _until(() => server.arrived == 1);
      final second = patient.send(_simpleRequest(server.baseUrl));
      await _until(() => patient.pendingAttemptCount == 2);
      expect(server.maxActive, 1);

      await patient.cancelActive();

      expect(await first, const TransportCancelled());
      expect(await second, const TransportCancelled());
      expect(server.arrived, 1);
    });

    test('a cancellation that came late does not affect the next attempt',
        () async {
      server.handler = recordAndAnswer(HttpStatus.created);

      expect(
        await transport.send(_simpleRequest(server.baseUrl)),
        const TransportHttpResponse(201),
      );
      await transport.cancelActive();

      expect(
        await transport.send(_simpleRequest(server.baseUrl)),
        const TransportHttpResponse(201),
      );
    });

    test('uploads one at a time through the transport', () async {
      final release = Completer<void>();
      server.handler = (request) async {
        await request.drain<void>();
        if (server.arrived == 1) {
          await release.future;
        }
        request.response.statusCode = HttpStatus.created;
        await request.response.close();
      };
      final patient = HttpOccurrenceTransport(
        StreamedHttpClientAdapter.io(),
        limits: const OccurrenceTransportLimits(
          attemptTimeout: Duration(seconds: 20),
        ),
      );
      addTearDown(patient.dispose);

      final first = patient.send(_simpleRequest(server.baseUrl));
      final second = patient.send(_simpleRequest(server.baseUrl));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.arrived, 1);
      release.complete();

      expect(await first, const TransportHttpResponse(201));
      expect(await second, const TransportHttpResponse(201));
      expect(server.maxActive, 1);
    });

    test('rendered results never reveal the credential or the address',
        () async {
      server.handler = recordAndAnswer(HttpStatus.unauthorized);

      final result = await transport.send(_simpleRequest(server.baseUrl));

      expect('$result', isNot(contains(_secret)));
      expect('$result', isNot(contains('127.0.0.1')));
      expect('$result', isNot(contains('${server.port}')));
    });
  });
}
