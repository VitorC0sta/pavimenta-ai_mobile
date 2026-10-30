import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_transport_result.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/bounded_occurrence_exchange.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_http_request_builder.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_multipart_preparer.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_transport_failure_classifier.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_transport_limits.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streamed_http_client_adapter.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streaming_multipart_encoder.dart';

const List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xD9];
const String _secretHost = 'secret-host.invalid';

OccurrenceHttpRequest _request(Uri baseUrl, {Stream<List<int>>? image}) =>
    const OccurrenceHttpRequestBuilder().build(
      baseUrl: baseUrl,
      credential: NonPrintableSecret('fake-prefix.fake-secret'),
      body: StreamingMultipartEncoder(
        boundaryGenerator: () => 'test-boundary',
      ).encode(<MultipartPart>[
        MultipartFilePart(
          'image',
          filename: 'occurrence.jpg',
          contentType: 'image/jpeg',
          length: _jpeg.length,
          source: image ?? Stream<List<int>>.value(_jpeg),
        ),
      ]),
    );

const OccurrenceTransportLimits _shortLimits = OccurrenceTransportLimits(
  attemptTimeout: Duration(milliseconds: 400),
  bodyDrainTimeout: Duration(milliseconds: 300),
  maxDrainedBodyBytes: 1024,
);

/// Client returning a response whose body misbehaves after the headers.
final class _FakeClient extends http.BaseClient {
  _FakeClient(this._respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Consume the request body like a real client would.
    await request.finalize().drain<void>();
    return _respond(request);
  }
}

/// A body stream whose cancellation throws.
Stream<List<int>> _bodyWithFailingCancel() {
  final controller = StreamController<List<int>>(
    onCancel: () => throw StateError('cancel failed: $_secretHost'),
  );
  controller.add(<int>[1, 2, 3]);
  return controller.stream;
}

void main() {
  group('OccurrenceTransportFailureClassifier.classify', () {
    test('maps timeouts to TransportTimeout', () {
      expect(
        OccurrenceTransportFailureClassifier.classify(
          const OccurrenceAttemptTimeoutException(),
        ),
        const TransportTimeout(),
      );
      expect(
        OccurrenceTransportFailureClassifier.classify(TimeoutException(null)),
        const TransportTimeout(),
      );
      expect(
        OccurrenceTransportFailureClassifier.classify(
          const SocketException(
            'HTTP connection timed out after 0:00:10.000000, '
            'host: $_secretHost, port: 443',
          ),
        ),
        const TransportTimeout(),
      );
    });

    test('maps an aborted request to TransportCancelled', () {
      expect(
        OccurrenceTransportFailureClassifier.classify(
          http.RequestAbortedException(Uri.parse('https://$_secretHost/x')),
        ),
        const TransportCancelled(),
      );
    });

    test('maps DNS, socket, TLS and protocol errors to TransportNetworkFailure',
        () {
      final errors = <Object>[
        const SocketException('Failed host lookup'),
        const SocketException('Connection refused'),
        http.ClientException('connection reset', Uri.parse('https://x.test')),
        const HandshakeException('bad certificate'),
        const CertificateException('untrusted'),
        const HttpException('connection closed before full header'),
      ];
      for (final error in errors) {
        expect(
          OccurrenceTransportFailureClassifier.classify(error),
          const TransportNetworkFailure(),
          reason: error.runtimeType.toString(),
        );
      }
    });

    test('maps local and unknown errors to TransportLocalFailure', () {
      final errors = <Object>[
        const OccurrenceHttpRequestException(
          OccurrenceHttpRequestFailure.invalidDestination,
        ),
        const OccurrenceImageRevalidationException(
          OccurrenceMultipartPreparationFailure.imageUnreadable,
        ),
        const FileSystemException('cannot read'),
        StateError('unexpected'),
      ];
      for (final error in errors) {
        expect(
          OccurrenceTransportFailureClassifier.classify(error),
          const TransportLocalFailure(),
          reason: error.runtimeType.toString(),
        );
      }
    });

    test('results never expose the error message', () {
      final result = OccurrenceTransportFailureClassifier.classify(
        const SocketException('failed for $_secretHost'),
      );

      expect(result.toString(), isNot(contains(_secretHost)));
    });
  });

  group('OccurrenceTransportFailureClassifier.run', () {
    test('reports any status as TransportHttpResponse', () async {
      for (final status in <int>[200, 302, 401, 503]) {
        expect(
          await OccurrenceTransportFailureClassifier.run(
            () async => status,
          ),
          TransportHttpResponse(status),
        );
      }
    });

    test('never throws', () async {
      expect(
        await OccurrenceTransportFailureClassifier.run(
          () => Future<int>.error(StateError('x')),
        ),
        const TransportLocalFailure(),
      );
    });
  });

  group('classification through the exchange', () {
    late StreamedHttpClientAdapter adapter;

    tearDown(() => adapter.close());

    Future<OccurrenceTransportResult> classified(
      OccurrenceHttpRequest request, {
      OccurrenceTransportLimits limits = _shortLimits,
    }) {
      final exchange = BoundedOccurrenceExchange(adapter, limits: limits);
      return OccurrenceTransportFailureClassifier.run(
        () => exchange.exchange(request),
      );
    }

    test('connection refused is a network failure', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      adapter = StreamedHttpClientAdapter.io();

      expect(
        await classified(
          _request(Uri.parse('http://127.0.0.1:$port')),
          // Windows retries a refused loopback connection for about a second.
          limits: const OccurrenceTransportLimits(
            attemptTimeout: Duration(seconds: 20),
          ),
        ),
        const TransportNetworkFailure(),
      );
    });

    test('a TLS handshake against a plain server is a network failure',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) {
        socket.add(<int>[0, 1, 2, 3]);
        socket.close();
      });
      adapter = StreamedHttpClientAdapter.io();

      expect(
        await classified(
            _request(Uri.parse('https://127.0.0.1:${server.port}'))),
        const TransportNetworkFailure(),
      );
    });

    test('a server that never answers is a timeout', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) => request.drain<void>().ignore());
      adapter = StreamedHttpClientAdapter.io();

      expect(
        await classified(
            _request(Uri.parse('http://127.0.0.1:${server.port}'))),
        const TransportTimeout(),
      );
    });

    test('a failing image stream is a local failure', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) => request.drain<void>().ignore());
      adapter = StreamedHttpClientAdapter.io();
      final image = Stream<List<int>>.error(
        const OccurrenceImageRevalidationException(
          OccurrenceMultipartPreparationFailure.imageUnreadable,
        ),
      );

      expect(
        await classified(
          _request(Uri.parse('http://127.0.0.1:${server.port}'), image: image),
        ),
        const TransportLocalFailure(),
      );
    });

    test('an aborted request reports cancellation, not a timeout', () async {
      adapter = StreamedHttpClientAdapter(
        _FakeClient((request) async {
          throw http.RequestAbortedException(request.url);
        }),
      );

      expect(
        await classified(_request(Uri.parse('https://$_secretHost'))),
        const TransportCancelled(),
      );
    });
  });

  group('status after the headers', () {
    late StreamedHttpClientAdapter adapter;

    Future<OccurrenceTransportResult> withBody(
      int status,
      Stream<List<int>> body,
    ) {
      adapter = StreamedHttpClientAdapter(
        _FakeClient(
          (request) async => http.StreamedResponse(body, status),
        ),
      );
      final exchange = BoundedOccurrenceExchange(adapter, limits: _shortLimits);
      return OccurrenceTransportFailureClassifier.run(
        () => exchange.exchange(_request(Uri.parse('https://$_secretHost'))),
      );
    }

    test('is kept when the body fails', () async {
      final body = Stream<List<int>>.error(
        http.RequestAbortedException(Uri.parse('https://$_secretHost')),
      );

      expect(await withBody(503, body), const TransportHttpResponse(503));
    });

    test('is kept when the body fails with a socket error', () async {
      final body = Stream<List<int>>.error(const SocketException('reset'));

      expect(await withBody(201, body), const TransportHttpResponse(201));
    });

    test('is kept when cancelling the body throws', () async {
      expect(
        await withBody(409, _bodyWithFailingCancel()),
        const TransportHttpResponse(409),
      );
    });

    test('is kept for a redirect status', () async {
      expect(
        await withBody(302, const Stream<List<int>>.empty()),
        const TransportHttpResponse(302),
      );
    });
  });
}
