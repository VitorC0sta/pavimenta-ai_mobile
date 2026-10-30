import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streamed_http_client_adapter.dart';

/// Records the request it receives and drains its body, like a real client.
final class _RecordingClient extends http.BaseClient {
  static const int statusCode = 201;

  http.BaseRequest? request;
  final List<int> receivedBody = <int>[];
  Object? bodyError;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    try {
      await for (final chunk in request.finalize()) {
        receivedBody.addAll(chunk);
      }
    } catch (error) {
      bodyError = error;
      rethrow;
    }
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      statusCode,
      request: request,
    );
  }

  @override
  void close() => closed = true;
}

final Uri _uri = Uri.parse('https://example.invalid/target');

void main() {
  group('StreamedHttpClientAdapter with an injected client', () {
    test('sends a streamed request with declared length and no redirects',
        () async {
      final client = _RecordingClient();
      final adapter = StreamedHttpClientAdapter(client);

      final response = await adapter.send(
        method: 'POST',
        uri: _uri,
        headers: const <String, String>{'x-test': 'value'},
        contentLength: 6,
        body: Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2, 3],
          <int>[4, 5, 6],
        ]),
      );

      final request = client.request!;
      expect(response.statusCode, 201);
      expect(request, isA<http.StreamedRequest>());
      expect(request.method, 'POST');
      expect(request.url, _uri);
      expect(request.headers['x-test'], 'value');
      expect(request.contentLength, 6);
      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 0);
      expect(client.receivedBody, <int>[1, 2, 3, 4, 5, 6]);
    });

    test('forwards chunks without joining them into one buffer', () async {
      final client = _RecordingClient();
      final chunks = <int>[];
      final body = Stream<List<int>>.fromIterable(<List<int>>[
        List<int>.filled(1000, 7),
        List<int>.filled(1000, 8),
      ]).map((chunk) {
        chunks.add(chunk.length);
        return chunk;
      });

      await StreamedHttpClientAdapter(client).send(
        method: 'POST',
        uri: _uri,
        headers: const <String, String>{},
        contentLength: 2000,
        body: body,
      );

      expect(chunks, <int>[1000, 1000]);
      expect(client.receivedBody, hasLength(2000));
    });

    test('surfaces a body failure as a send error', () async {
      final client = _RecordingClient();
      final adapter = StreamedHttpClientAdapter(client);

      final result = adapter.send(
        method: 'POST',
        uri: _uri,
        headers: const <String, String>{},
        contentLength: 3,
        body: Stream<List<int>>.multi((controller) {
          controller.add(<int>[1]);
          controller.addError(StateError('body failed'));
          controller.close();
        }),
      );

      await expectLater(result, throwsA(isA<StateError>()));
      expect(client.bodyError, isA<StateError>());
    });

    test('never closes an injected client, and close is idempotent', () {
      final client = _RecordingClient();
      final adapter = StreamedHttpClientAdapter(client);

      adapter.close();
      adapter.close();

      expect(client.closed, isFalse);
    });
  });

  group('StreamedHttpClientAdapter.io', () {
    late HttpServer server;
    late List<String> hits;

    setUp(() async {
      hits = <String>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        hits.add(request.uri.path);
        await request.drain<void>();
        if (request.uri.path == '/start') {
          request.response
            ..statusCode = HttpStatus.temporaryRedirect
            ..headers.set(HttpHeaders.locationHeader, '/followed');
        } else {
          request.response.statusCode = HttpStatus.created;
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('returns a 3xx as a response and does not follow it', () async {
      final adapter = StreamedHttpClientAdapter.io();
      addTearDown(adapter.close);

      final response = await adapter.send(
        method: 'POST',
        uri: Uri.parse('http://127.0.0.1:${server.port}/start'),
        headers: const <String, String>{},
        contentLength: 3,
        body: Stream<List<int>>.value(<int>[1, 2, 3]),
      );
      await response.stream.drain<void>();

      expect(response.statusCode, HttpStatus.temporaryRedirect);
      expect(hits, <String>['/start']);
    });

    test('streams a body to a real server', () async {
      final adapter = StreamedHttpClientAdapter.io();
      addTearDown(adapter.close);

      final response = await adapter.send(
        method: 'POST',
        uri: Uri.parse('http://127.0.0.1:${server.port}/other'),
        headers: const <String, String>{},
        contentLength: 4,
        body: Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ]),
      );
      await response.stream.drain<void>();

      expect(response.statusCode, HttpStatus.created);
      expect(hits, <String>['/other']);
    });
  });
}
