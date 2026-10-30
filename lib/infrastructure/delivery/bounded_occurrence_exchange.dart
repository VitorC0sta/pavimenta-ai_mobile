import 'dart:async';

import 'package:http/http.dart' as http;

import 'occurrence_http_request_builder.dart';
import 'occurrence_transport_limits.dart';
import 'streamed_http_client_adapter.dart';

/// The attempt did not receive complete response headers within
/// [OccurrenceTransportLimits.attemptTimeout]. Carries no address, header, or
/// credential.
final class OccurrenceAttemptTimeoutException implements Exception {
  const OccurrenceAttemptTimeoutException();

  @override
  String toString() => 'OccurrenceAttemptTimeoutException()';
}

/// Idempotent cancellation signal of one occurrence attempt (design E4.8).
///
/// It carries no request, credential, address, or reason text. Cancelling it
/// any number of times has the effect of cancelling it once and never throws.
final class OccurrenceCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes (with no value and no error) once [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  /// Requests cancellation. Later calls do nothing.
  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  @override
  String toString() => 'OccurrenceCancellationToken()';
}

enum _AbortReason { timeout, cancellation }

/// Runs occurrence uploads one at a time under the E4 limits (design E4.8).
///
/// - Only one exchange is in flight; others wait in arrival order.
/// - The attempt deadline starts when the exchange starts and covers
///   connection, upload, and the wait for complete headers. When it expires the
///   request is aborted and [OccurrenceAttemptTimeoutException] is thrown.
/// - An [OccurrenceCancellationToken] cancelled before the headers arrive
///   aborts the request and throws [http.RequestAbortedException] (without an
///   address); a token already cancelled when the exchange starts opens no
///   socket.
/// - Once headers arrive, the status is final. The body is only discarded, up
///   to [OccurrenceTransportLimits.maxDrainedBodyBytes] and
///   [OccurrenceTransportLimits.bodyDrainTimeout]; any problem there is
///   swallowed and never changes the returned status. Cancelling then only
///   stops the discard early.
///
/// The exchange keeps no reference to the request, its headers, or the
/// credential beyond the call that uses them. The body is never retained,
/// inspected, or logged. Other failures from the adapter propagate unchanged
/// for the E4 classifier; they must not be logged.
final class BoundedOccurrenceExchange {
  BoundedOccurrenceExchange(
    this._adapter, {
    OccurrenceTransportLimits limits = OccurrenceTransportLimits.standard,
  }) : _limits = limits;

  final StreamedHttpClientAdapter _adapter;
  final OccurrenceTransportLimits _limits;
  Future<void> _tail = Future<void>.value();

  /// Sends [request] and returns the HTTP status once complete headers arrive.
  ///
  /// [cancellation] aborts the attempt while it waits its turn, connects,
  /// uploads, or waits for headers.
  Future<int> exchange(
    OccurrenceHttpRequest request, {
    OccurrenceCancellationToken? cancellation,
  }) =>
      _serialized(() => _run(request, cancellation));

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return previous.then((_) => action()).whenComplete(released.complete);
  }

  Future<int> _run(
    OccurrenceHttpRequest request,
    OccurrenceCancellationToken? cancellation,
  ) async {
    if (cancellation != null && cancellation.isCancelled) {
      // Nothing was opened for this attempt: no socket, no body read.
      throw http.RequestAbortedException();
    }

    final abort = Completer<void>();
    _AbortReason? reason;

    void requestAbort(_AbortReason cause) {
      reason ??= cause;
      if (!abort.isCompleted) {
        abort.complete();
      }
    }

    final deadline = Timer(
      _limits.attemptTimeout,
      () => requestAbort(_AbortReason.timeout),
    );
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled
            .then<void>((_) => requestAbort(_AbortReason.cancellation)),
      );
    }

    final http.StreamedResponse response;
    try {
      response = await _adapter.send(
        method: request.method,
        uri: request.uri,
        headers: request.headers,
        contentLength: request.contentLength,
        body: request.body,
        abortTrigger: abort.future,
      );
    } on Object {
      switch (reason) {
        case _AbortReason.timeout:
          throw const OccurrenceAttemptTimeoutException();
        case _AbortReason.cancellation:
          // Fixed error without an address: the original one is discarded.
          throw http.RequestAbortedException();
        case null:
          rethrow;
      }
    } finally {
      deadline.cancel();
    }

    // The status is read first and is final: nothing below may change it.
    final status = response.statusCode;
    try {
      await _discardBody(response.stream, stopEarly: abort.future);
    } on Object {
      // Draining or cancelling the body is best effort once headers arrived.
    }
    return status;
  }

  Future<void> _discardBody(
    Stream<List<int>> body, {
    required Future<void> stopEarly,
  }) async {
    final finished = Completer<void>();
    var received = 0;

    void finish() {
      if (!finished.isCompleted) {
        finished.complete();
      }
    }

    // A cancellation after the headers only stops the discard; the status is
    // already decided.
    unawaited(stopEarly.then<void>((_) => finish()));

    final StreamSubscription<List<int>> subscription;
    try {
      subscription = body.listen(
        (chunk) {
          received += chunk.length;
          if (received >= _limits.maxDrainedBodyBytes) {
            finish();
          }
        },
        onError: (Object _) => finish(),
        onDone: finish,
        cancelOnError: true,
      );
    } on Object {
      return;
    }

    final timer = Timer(_limits.bodyDrainTimeout, finish);
    await finished.future;
    timer.cancel();
    try {
      unawaited(
          subscription.cancel().then<void>((_) {}, onError: (Object _) {}));
    } on Object {
      // Releasing the body is best effort: the status is already decided.
    }
  }
}
