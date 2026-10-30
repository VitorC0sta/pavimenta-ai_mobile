import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/bounded_occurrence_exchange.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_http_request_builder.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_transport_limits.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streamed_http_client_adapter.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streaming_multipart_encoder.dart';

const List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xD9];

OccurrenceHttpRequest _request(int port) =>
    const OccurrenceHttpRequestBuilder().build(
      baseUrl: Uri.parse('http://127.0.0.1:$port'),
      credential: NonPrintableSecret('fake-prefix.fake-secret'),
      body: StreamingMultipartEncoder(
        boundaryGenerator: () => 'test-boundary',
      ).encode(<MultipartPart>[
        MultipartFilePart(
          'image',
          filename: 'occurrence.jpg',
          contentType: 'image/jpeg',
          length: _jpeg.length,
          source: Stream<List<int>>.value(_jpeg),
        ),
      ]),
    );

const OccurrenceTransportLimits _shortLimits = OccurrenceTransportLimits(
  attemptTimeout: Duration(milliseconds: 400),
  bodyDrainTimeout: Duration(milliseconds: 300),
  maxDrainedBodyBytes: 1024,
);

void main() {
  group('OccurrenceTransportLimits.standard', () {
    test('matches the E4.8 technical configuration', () {
      const limits = OccurrenceTransportLimits.standard;

      expect(limits.connectionTimeout, const Duration(seconds: 10));
      expect(limits.attemptTimeout, const Duration(seconds: 45));
      expect(limits.bodyDrainTimeout, const Duration(seconds: 5));
      expect(limits.maxDrainedBodyBytes, 64 * 1024);
      expect(OccurrenceTransportLimits.maxConcurrentUploads, 1);
      expect(OccurrenceTransportLimits.maxRedirects, 0);
    });

    test('the default io client applies the 10 s connection timeout', () {
      final client = StreamedHttpClientAdapter.createStandardHttpClient();
      addTearDown(client.close);

      expect(client.connectionTimeout, const Duration(seconds: 10));
    });
  });

  group('BoundedOccurrenceExchange against a local server', () {
    late HttpServer server;
    late void Function(HttpRequest) onRequest;
    late BoundedOccurrenceExchange exchange;
    late StreamedHttpClientAdapter adapter;
    final open = <HttpRequest>[];

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        open.add(request);
        onRequest(request);
      });
      adapter = StreamedHttpClientAdapter.io();
      exchange = BoundedOccurrenceExchange(adapter, limits: _shortLimits);
    });

    tearDown(() async {
      adapter.close();
      await server.close(force: true);
      open.clear();
    });

    test('returns the status of a normal response', () async {
      onRequest = (request) async {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.created;
        await request.response.close();
      };

      expect(await exchange.exchange(_request(server.port)), 201);
    });

    test('times out when headers never arrive and aborts the request',
        () async {
      onRequest = (request) {
        // Read the upload but never answer.
        request.drain<void>();
      };

      await expectLater(
        exchange.exchange(_request(server.port)),
        throwsA(isA<OccurrenceAttemptTimeoutException>()),
      );
    });

    test('keeps the status when the body is larger than the drain limit',
        () async {
      onRequest = (request) async {
        await request.drain<void>();
        final response = request.response..statusCode = HttpStatus.conflict;
        final chunk = List<int>.filled(16 * 1024, 0x41);
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

      expect(await exchange.exchange(_request(server.port)), 409);
    });

    test('keeps the status when the body stalls past the drain deadline',
        () async {
      onRequest = (request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..add(<int>[1, 2, 3]);
        await request.response.flush();
        // Never closes: the body is slow forever.
      };

      final stopwatch = Stopwatch()..start();
      final status = await exchange.exchange(_request(server.port));

      expect(status, 500);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('runs one upload at a time, in arrival order', () async {
      final release = Completer<void>();
      onRequest = (request) async {
        await request.drain<void>();
        if (open.length == 1) {
          await release.future;
        }
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      };
      final longExchange = BoundedOccurrenceExchange(
        adapter,
        limits: const OccurrenceTransportLimits(
          attemptTimeout: Duration(seconds: 10),
        ),
      );

      final first = longExchange.exchange(_request(server.port));
      final second = longExchange.exchange(_request(server.port));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(open, hasLength(1));

      release.complete();
      expect(await first, 200);
      expect(await second, 200);
      expect(open, hasLength(2));
    });

    test('a failed exchange does not block the next one', () async {
      var calls = 0;
      onRequest = (request) async {
        calls++;
        if (calls == 1) {
          request.drain<void>();
          return;
        }
        await request.drain<void>();
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      };

      final first = exchange.exchange(_request(server.port));
      final second = exchange.exchange(_request(server.port));

      await expectLater(
        first,
        throwsA(isA<OccurrenceAttemptTimeoutException>()),
      );
      expect(await second, 200);
    });
  });
}
