import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_transport_result.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/http_occurrence_transport.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_transport_limits.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streamed_http_client_adapter.dart';

// Explicitly fictitious values; none is a real key, URL, or identifier.
const String _key = '423e4567-e89b-42d3-a456-426614174000';
const String _secret = 'fakeprefix.fake-secret-for-tests-only';
const List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xD9];

const OccurrenceTransportLimits _limits = OccurrenceTransportLimits(
  attemptTimeout: Duration(seconds: 10),
  bodyDrainTimeout: Duration(seconds: 10),
);

OccurrenceUploadRequest _request(int port) =>
    OccurrenceUploadRequest.fromConfiguration(
      configuration: DeliveryConfiguration(
        revision: 1,
        baseUrl: Uri.parse('http://127.0.0.1:$port'),
        credential: NonPrintableSecret(_secret),
      ),
      idempotencyKey: _key,
      payload: DeliveryOccurrencePayload(
        detectedAtIso8601: '2025-01-02T03:04:05.000Z',
        latitude: -23.5505,
        longitude: -46.6333,
        speedKmh: 0,
        confidence: 1.0,
        defectClass: 'pothole',
        image: DeliveryImageRef(
          byteLength: _jpeg.length,
          opaqueHandle: Object(),
        ),
      ),
      imageStream: Stream<List<int>>.value(_jpeg),
    );

void main() {
  // **Validates: Requirements RF-15–18, RNF-02.1–10, RNF-03.7–10**
  group('task 67.5 cancellation and credential references', () {
    late HttpServer server;
    late FutureOr<void> Function(HttpRequest) onRequest;
    late HttpOccurrenceTransport transport;
    final received = <Completer<void>>[];

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        received.add(Completer<void>()..complete());
        // A client abort or the forced server close in tearDown surfaces as an
        // HttpException inside the handler; that is expected test traffic.
        unawaited(
          Future<void>.sync(() => onRequest(request)).catchError((Object _) {}),
        );
      });
      transport = HttpOccurrenceTransport(
        StreamedHttpClientAdapter.io(),
        limits: _limits,
      );
    });

    tearDown(() async {
      await transport.dispose();
      await server.close(force: true);
      received.clear();
    });

    test('cancelActive with nothing active is safe and repeatable', () async {
      await transport.cancelActive();
      await transport.cancelActive();

      expect(transport.pendingAttemptCount, 0);
    });

    test('cancelling before headers yields TransportCancelled, repeatedly',
        () async {
      onRequest = (request) => request.drain<void>(); // never answers

      final result = transport.send(_request(server.port));
      while (received.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future.wait(<Future<void>>[
        transport.cancelActive(),
        transport.cancelActive(),
      ]);
      await transport.cancelActive();

      expect(await result, isA<TransportCancelled>());
      expect(transport.pendingAttemptCount, 0);
    });

    test('a cancellation after the headers keeps the HTTP status', () async {
      onRequest = (request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.conflict
          ..add(<int>[1, 2, 3]);
        await request.response.flush();
        // The body never ends.
      };

      final result = transport.send(_request(server.port));
      final settled = Completer<void>();
      unawaited(result.whenComplete(settled.complete));
      // The body stalls, so the attempt is still draining: cancel it now.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await transport.cancelActive();
      await settled.future.timeout(const Duration(seconds: 3));

      expect(await result, const TransportHttpResponse(409));
      expect(transport.pendingAttemptCount, 0);
    });

    test('dispose is idempotent and later sends do not reach the network',
        () async {
      onRequest = (request) => request.drain<void>();

      await transport.dispose();
      await transport.dispose();
      final result = await transport.send(_request(server.port));

      expect(result, isA<TransportCancelled>());
      expect(received, isEmpty);
    });

    test('results and the transport never render the credential', () async {
      onRequest = (request) async {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.created;
        await request.response.close();
      };

      final result = await transport.send(_request(server.port));
      final rendered = '$result ${NonPrintableSecret(_secret)}';

      expect(result, const TransportHttpResponse(201));
      expect(rendered, isNot(contains(_secret)));
      expect(transport.pendingAttemptCount, 0);
    });
  });
}
