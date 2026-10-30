import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/delivery/occurrence_transport_result.dart';
import 'bounded_occurrence_exchange.dart';

/// Maps an error raised before complete response headers to a sanitized
/// [OccurrenceTransportResult] (design E4.8, E4.9).
///
/// Only the error type decides the outcome. The classifier never reads, keeps,
/// or renders the message, address, URI, header, credential, or stack trace of
/// the error, so nothing sensitive can reach a result or a log through it.
///
/// | Error | Result |
/// |---|---|
/// | [OccurrenceAttemptTimeoutException], [TimeoutException], connection timeout of `dart:io` | [TransportTimeout] |
/// | [http.RequestAbortedException] | [TransportCancelled] |
/// | [SocketException] (DNS, connect, reset), [TlsException], [HttpException], [http.ClientException] | [TransportNetworkFailure] |
/// | anything else (request assembly, image read, unexpected error) | [TransportLocalFailure] |
///
/// A complete HTTP response is never classified here: once headers arrive the
/// status is final and is reported as [TransportHttpResponse] by the caller.
abstract final class OccurrenceTransportFailureClassifier {
  /// Fixed prefix `dart:io` uses when `HttpClient.connectionTimeout` expires.
  /// Only the prefix is compared; the rest of that message carries the host.
  static const String _connectionTimeoutPrefix = 'HTTP connection timed out';

  /// Classifies [error], thrown before complete response headers.
  static OccurrenceTransportResult classify(Object error) {
    // Order matters: the abort and timeout types also derive from
    // `http.ClientException`/`IOException`, and the connection timeout is a
    // `SocketException`.
    if (error is OccurrenceAttemptTimeoutException ||
        error is TimeoutException) {
      return const TransportTimeout();
    }
    if (error is http.RequestAbortedException) {
      return const TransportCancelled();
    }
    if (error is SocketException &&
        error.message.startsWith(_connectionTimeoutPrefix)) {
      return const TransportTimeout();
    }
    if (error is SocketException ||
        error is TlsException ||
        error is HttpException ||
        error is http.ClientException) {
      return const TransportNetworkFailure();
    }
    return const TransportLocalFailure();
  }

  /// Runs [exchange] and reports its outcome without ever throwing.
  ///
  /// A returned status becomes [TransportHttpResponse], whatever its value.
  /// Any error is turned into a fixed failure by [classify].
  static Future<OccurrenceTransportResult> run(
    Future<int> Function() exchange,
  ) async {
    try {
      return TransportHttpResponse(await exchange());
    } on Object catch (error) {
      return classify(error);
    }
  }
}
