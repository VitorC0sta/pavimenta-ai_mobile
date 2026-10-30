import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_http_request_builder.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streamed_http_client_adapter.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streaming_multipart_encoder.dart';

const String _fakeKey = 'fake-prefix.fake-secret';
const List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xD9];

/// Records the request it receives and drains its body, like a real client.
final class _RecordingClient extends http.BaseClient {
  http.BaseRequest? request;
  final List<int> receivedBody = <int>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    await for (final chunk in request.finalize()) {
      receivedBody.addAll(chunk);
    }
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      201,
      request: request,
    );
  }
}

EncodedMultipartBody _body() => StreamingMultipartEncoder(
      boundaryGenerator: () => 'test-boundary',
    ).encode(<MultipartPart>[
      const MultipartTextPart('defectClass', 'pothole'),
      MultipartFilePart(
        'image',
        filename: 'occurrence.jpg',
        contentType: 'image/jpeg',
        length: _jpeg.length,
        source: Stream<List<int>>.value(_jpeg),
      ),
    ]);

OccurrenceHttpRequest _build(
  String baseUrl, {
  String key = _fakeKey,
  EncodedMultipartBody? body,
}) =>
    const OccurrenceHttpRequestBuilder().build(
      baseUrl: Uri.parse(baseUrl),
      credential: NonPrintableSecret(key),
      body: body ?? _body(),
    );

Future<http.BaseRequest> _sendThroughFake(OccurrenceHttpRequest built) async {
  final client = _RecordingClient();
  final response = await StreamedHttpClientAdapter(client).send(
    method: built.method,
    uri: built.uri,
    headers: built.headers,
    contentLength: built.contentLength,
    body: built.body,
  );
  expect(response.statusCode, 201);
  return client.request!;
}

void main() {
  group('OccurrenceHttpRequestBuilder endpoint', () {
    test('appends exactly /api/v1/occurrences to the origin', () {
      final built = _build('https://api.example.invalid');

      expect(built.method, 'POST');
      expect(built.uri.toString(),
          'https://api.example.invalid/api/v1/occurrences');
    });

    test('accepts a trailing slash and keeps an explicit port', () {
      expect(
        _build('https://api.example.invalid/').uri.toString(),
        'https://api.example.invalid/api/v1/occurrences',
      );
      expect(
        _build('http://localhost:3000').uri.toString(),
        'http://localhost:3000/api/v1/occurrences',
      );
    });

    test('has no query, fragment, or user information', () {
      final uri = _build('https://api.example.invalid').uri;

      expect(uri.hasQuery, isFalse);
      expect(uri.hasFragment, isFalse);
      expect(uri.userInfo, isEmpty);
    });

    for (final invalid in <String>[
      'ftp://api.example.invalid',
      'https://api.example.invalid/base',
      'https://api.example.invalid/api/v1/occurrences',
      'https://api.example.invalid?x=1',
      'https://api.example.invalid#frag',
      'https://user:pass@api.example.invalid',
      '/relative',
    ]) {
      test('rejects the destination "$invalid" without echoing it', () {
        final body = _body();
        Object? error;
        try {
          _build(invalid, body: body);
        } catch (caught) {
          error = caught;
        }

        expect(
          error,
          isA<OccurrenceHttpRequestException>().having(
            (e) => e.failure,
            'failure',
            OccurrenceHttpRequestFailure.invalidDestination,
          ),
        );
        expect(error.toString(), isNot(contains('example')));
        // The body stays unopened, so it can still be opened once.
        expect(body.open, returnsNormally);
      });
    }
  });

  group('OccurrenceHttpRequestBuilder headers', () {
    test('sends exactly Authorization: ApiKey and the multipart type', () {
      final built = _build('https://api.example.invalid');

      expect(built.headers, <String, String>{
        'Authorization': 'ApiKey $_fakeKey',
        'Content-Type': 'multipart/form-data; boundary=test-boundary',
      });
      expect(built.contentLength, greaterThan(_jpeg.length));
    });

    test('headers are unmodifiable, so none can be added afterwards', () {
      final headers = _build('https://api.example.invalid').headers;

      expect(() => headers['Cookie'] = 'a=b', throwsUnsupportedError);
      expect(() => headers['X-API-Key'] = _fakeKey, throwsUnsupportedError);
    });

    for (final invalid in <String>[
      '',
      'has space.secret',
      'prefix.sec\r\nX-Injected: 1',
      'prefix.segredo-ç',
      'prefix.sec\tret',
    ]) {
      test('rejects an unsafe credential (${invalid.length} chars)', () {
        Object? error;
        try {
          // An empty value is rejected by NonPrintableSecret itself.
          _build('https://api.example.invalid', key: invalid);
        } catch (caught) {
          error = caught;
        }

        if (invalid.isEmpty) {
          expect(error, isA<ArgumentError>());
        } else {
          expect(
            error,
            isA<OccurrenceHttpRequestException>().having(
              (e) => e.failure,
              'failure',
              OccurrenceHttpRequestFailure.invalidCredential,
            ),
          );
        }
        expect(error.toString(), isNot(contains('prefix')));
      });
    }

    test('rendering never reveals the address, headers, or credential', () {
      final built = _build('https://api.example.invalid');

      expect(built.toString(), 'OccurrenceHttpRequest(<redacted>)');
      expect(built.toString(), isNot(contains(_fakeKey)));
    });
  });

  group('built request through the adapter with an injected client', () {
    test('reaches the client as POST to the exact endpoint', () async {
      final request = await _sendThroughFake(
        _build('https://api.example.invalid'),
      );

      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.example.invalid/api/v1/occurrences',
      );
      expect(request, isA<http.StreamedRequest>());
    });

    test('carries ApiKey auth and no Bearer, X-API-Key, or cookie', () async {
      final request = await _sendThroughFake(
        _build('https://api.example.invalid'),
      );

      expect(request.headers['authorization'], 'ApiKey $_fakeKey');
      expect(request.headers['x-api-key'], isNull);
      expect(request.headers['cookie'], isNull);
      expect(request.headers['proxy-authorization'], isNull);
      expect(
        request.headers.values.any((value) => value.contains('Bearer')),
        isFalse,
      );
      expect(
        request.headers.keys.map((key) => key.toLowerCase()).toSet(),
        <String>{'authorization', 'content-type'},
      );
    });

    test('disables redirects and declares the multipart length', () async {
      final built = _build('https://api.example.invalid');
      final request = await _sendThroughFake(built);

      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 0);
      expect(request.contentLength, built.contentLength);
    });

    test('transmits the multipart bytes of the declared length', () async {
      final built = _build('https://api.example.invalid');
      final client = _RecordingClient();

      await StreamedHttpClientAdapter(client).send(
        method: built.method,
        uri: built.uri,
        headers: built.headers,
        contentLength: built.contentLength,
        body: built.body,
      );

      expect(client.receivedBody, hasLength(built.contentLength));
      expect(
        latin1.decode(client.receivedBody),
        contains('--test-boundary--'),
      );
    });
  });

  group('built request over a real loopback socket', () {
    late HttpServer server;
    late Map<String, List<String>> receivedHeaders;
    late String receivedMethod;
    late String receivedPath;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      receivedHeaders = <String, List<String>>{};
      server.listen((request) async {
        receivedMethod = request.method;
        receivedPath = request.uri.toString();
        request.headers.forEach((name, values) {
          receivedHeaders[name] = values;
        });
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.created
          ..headers.set(HttpHeaders.setCookieHeader, 'sid=1');
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('server sees the exact method, path, and credential header', () async {
      final built = _build('http://127.0.0.1:${server.port}');
      final adapter = StreamedHttpClientAdapter.io();
      addTearDown(adapter.close);

      final response = await adapter.send(
        method: built.method,
        uri: built.uri,
        headers: built.headers,
        contentLength: built.contentLength,
        body: built.body,
      );
      await response.stream.drain<void>();

      expect(response.statusCode, HttpStatus.created);
      expect(receivedMethod, 'POST');
      expect(receivedPath, '/api/v1/occurrences');
      expect(receivedHeaders['authorization'], <String>['ApiKey $_fakeKey']);
      expect(receivedHeaders.containsKey('cookie'), isFalse);
      expect(receivedHeaders.containsKey('x-api-key'), isFalse);
    });
  });
}
