import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'occurrence_transport_limits.dart';

/// Thin adapter over `package:http` for the E4 occurrence transport
/// (design E4.3, E4.7).
///
/// It is the only place that builds a [http.StreamedRequest] and that owns or
/// receives the [http.Client]. It does not know the occurrence endpoint, the
/// credential header, attempt deadlines, or how a response is classified; the
/// E4 transport composes those on top of [send]. The only limit it applies
/// itself is the socket connection deadline of the client it creates. The Diagnostic (E0) HTTP client
/// is a separate `dart:io` implementation and is never reused here.
///
/// The body is forwarded as a stream with a declared length, so the JPEG is
/// never buffered as a whole and no temporary multipart file exists.
///
/// Redirects are disabled on every request: a `3xx` is returned as an ordinary
/// response and never followed, not even to the same origin.
final class StreamedHttpClientAdapter {
  /// Wraps an already configured [client] (for example a fake in tests).
  ///
  /// The caller keeps ownership: [close] never closes an injected client.
  StreamedHttpClientAdapter(http.Client client)
      : _client = client,
        _ownsClient = false;

  StreamedHttpClientAdapter._owning(http.Client client)
      : _client = client,
        _ownsClient = true;

  /// Creates an adapter backed by an [IOClient] it owns.
  ///
  /// [inner] lets the Android composition root pass a pre-configured
  /// `dart:io` [HttpClient]; it is used as given. When omitted,
  /// [createStandardHttpClient] supplies the E4 client.
  factory StreamedHttpClientAdapter.io({HttpClient? inner}) =>
      StreamedHttpClientAdapter._owning(
        IOClient(inner ?? createStandardHttpClient()),
      );

  /// Creates the `dart:io` client used by the E4 transport.
  ///
  /// It applies the connection deadline of [limits] and otherwise keeps the
  /// platform defaults: the system trust store validates every TLS
  /// certificate, with no `badCertificateCallback`, no custom
  /// `SecurityContext`, and no per-host exception. Plain `http` is not decided
  /// here: the E3 `BASE_URL` validation (debug-only `http://localhost:3000`)
  /// and the Android network security configuration already restrict it.
  static HttpClient createStandardHttpClient({
    OccurrenceTransportLimits limits = OccurrenceTransportLimits.standard,
  }) =>
      HttpClient()..connectionTimeout = limits.connectionTimeout;

  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;

  /// Sends one streamed request and completes when the response headers are
  /// available.
  ///
  /// [contentLength] is declared up front and must equal the bytes emitted by
  /// [body]. [body] is consumed once, with back-pressure. Errors from the
  /// client or from [body] complete the returned future with an error; callers
  /// must map them to a sanitized result and never log them.
  ///
  /// Completing [abortTrigger] aborts the request; the returned future then
  /// fails with [http.RequestAbortedException] if the headers had not arrived.
  Future<http.StreamedResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required int contentLength,
    required Stream<List<int>> body,
    Future<void>? abortTrigger,
  }) {
    final request = http.AbortableStreamedRequest(
      method,
      uri,
      abortTrigger: abortTrigger,
    )
      ..followRedirects = false
      ..maxRedirects = 0
      ..contentLength = contentLength;
    request.headers.addAll(headers);

    final response = _client.send(request);
    unawaited(_pump(request, body));
    return response;
  }

  /// Releases the client when this adapter owns it. Idempotent.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsClient) {
      _client.close();
    }
  }

  static Future<void> _pump(
    http.AbortableStreamedRequest request,
    Stream<List<int>> body,
  ) async {
    try {
      await request.sink.addStream(body);
    } catch (error, stackTrace) {
      request.sink.addError(error, stackTrace);
    } finally {
      await request.sink.close();
    }
  }
}
