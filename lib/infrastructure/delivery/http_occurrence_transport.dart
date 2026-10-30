import 'dart:async';

import '../../application/delivery/occurrence_transport_port.dart';
import '../../domain/delivery/occurrence_transport_result.dart';
import '../../domain/delivery/occurrence_upload_request.dart';
import 'bounded_occurrence_exchange.dart';
import 'occurrence_http_request_builder.dart';
import 'occurrence_multipart_preparer.dart';
import 'occurrence_transport_failure_classifier.dart';
import 'occurrence_transport_limits.dart';
import 'streamed_http_client_adapter.dart';
import 'streaming_multipart_encoder.dart';

/// E4 occurrence transport over `package:http` (design E4.3, E4.7, E4.8).
///
/// One [send] revalidates and encodes the occurrence, builds the single
/// authenticated request, and runs it through the bounded exchange. Every
/// outcome is a sanitized [OccurrenceTransportResult]; [send] never throws and
/// nothing here logs, so no header, address, body, request, or raw error can
/// reach a log or an error message from this class.
///
/// ## Cancellation
///
/// [cancelActive] and [dispose] cancel every attempt in progress through an
/// [OccurrenceCancellationToken]. Both are idempotent, safe with nothing
/// active, and never throw. An attempt cancelled before complete response
/// headers completes with [TransportCancelled]; once headers arrived the
/// status stays authoritative and cancelling only stops the body discard.
///
/// ## Credential references
///
/// The credential of an [OccurrenceUploadRequest] is read once to compose the
/// header, inside the scope of one attempt. This class stores only the
/// cancellation tokens of the attempts in progress, never a request, a header,
/// or the credential, and each token is removed when its attempt completes or
/// is cancelled. Dropping references lets the garbage collector reclaim the
/// values; the memory of the managed heap and the buffers of the HTTP client
/// are not zeroed, and nothing here claims otherwise.
final class HttpOccurrenceTransport implements OccurrenceTransportPort {
  /// Creates a transport over [adapter].
  ///
  /// [dispose] calls `adapter.close()`, which only closes a client the adapter
  /// created itself; an injected client stays with its owner.
  HttpOccurrenceTransport(
    StreamedHttpClientAdapter adapter, {
    OccurrenceTransportLimits limits = OccurrenceTransportLimits.standard,
    StreamingMultipartEncoder? encoder,
    OccurrenceMultipartPreparer preparer = const OccurrenceMultipartPreparer(),
    OccurrenceHttpRequestBuilder builder = const OccurrenceHttpRequestBuilder(),
  })  : _adapter = adapter,
        _exchange = BoundedOccurrenceExchange(adapter, limits: limits),
        _encoder = encoder ?? StreamingMultipartEncoder(),
        _preparer = preparer,
        _builder = builder;

  /// Creates a transport backed by the standard `dart:io` client of E4.
  factory HttpOccurrenceTransport.standard({
    OccurrenceTransportLimits limits = OccurrenceTransportLimits.standard,
  }) =>
      HttpOccurrenceTransport(
        StreamedHttpClientAdapter.io(
          inner: StreamedHttpClientAdapter.createStandardHttpClient(
            limits: limits,
          ),
        ),
        limits: limits,
      );

  final StreamedHttpClientAdapter _adapter;
  final BoundedOccurrenceExchange _exchange;
  final StreamingMultipartEncoder _encoder;
  final OccurrenceMultipartPreparer _preparer;
  final OccurrenceHttpRequestBuilder _builder;
  final Set<OccurrenceCancellationToken> _pending =
      <OccurrenceCancellationToken>{};
  bool _disposed = false;

  /// Number of attempts in progress (running or waiting their turn).
  int get pendingAttemptCount => _pending.length;

  @override
  Future<OccurrenceTransportResult> send(
      OccurrenceUploadRequest request) async {
    if (_disposed) {
      return const TransportCancelled();
    }
    final token = OccurrenceCancellationToken();
    _pending.add(token);
    try {
      return await _attempt(request, token);
    } on Object {
      // Nothing from the failure is kept: only the fixed category remains.
      return const TransportLocalFailure();
    } finally {
      _pending.remove(token);
    }
  }

  @override
  Future<void> cancelActive() async {
    // Copy first: cancelling never mutates the set, but a completing attempt
    // may remove its token meanwhile.
    for (final token in List<OccurrenceCancellationToken>.of(_pending)) {
      token.cancel();
    }
  }

  /// Cancels attempts in progress and releases the client when the adapter
  /// owns it. Idempotent; later [send] calls complete with
  /// [TransportCancelled] without touching the network.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await cancelActive();
    _adapter.close();
  }

  /// One attempt. The built request, and with it the credential header, only
  /// exists in this scope.
  Future<OccurrenceTransportResult> _attempt(
    OccurrenceUploadRequest request,
    OccurrenceCancellationToken token,
  ) async {
    PreparedOccurrenceMultipart? prepared;
    try {
      final preparation = await _preparer.prepare(request, _encoder);
      switch (preparation) {
        case OccurrenceMultipartPreparationRejected():
          return const TransportLocalFailure();
        case PreparedOccurrenceMultipart():
          prepared = preparation;
      }
      if (token.isCancelled) {
        return const TransportCancelled();
      }

      final OccurrenceHttpRequest httpRequest;
      try {
        httpRequest = _builder.build(
          baseUrl: request.baseUrl,
          credential: request.credential,
          body: prepared.body,
        );
      } on Object {
        return const TransportLocalFailure();
      }

      return await OccurrenceTransportFailureClassifier.run(
        () => _exchange.exchange(httpRequest, cancellation: token),
      );
    } finally {
      try {
        await prepared?.discard();
      } on Object {
        // Releasing the private image read reveals nothing and decides nothing.
      }
    }
  }
}
