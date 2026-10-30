import 'dart:async';
import 'dart:collection';

/// Test-local request model.
///
/// Stand-in for the future `OccurrenceUploadRequest` (task 63.1), which does
/// not exist yet. It carries only what the delivery scenarios need to assert
/// and never prints the credential.
final class FakeUploadRequest {
  FakeUploadRequest({
    required this.uri,
    required this.credential,
    required this.idempotencyKey,
    required List<int> imageBytes,
  }) : imageBytes = List<int>.unmodifiable(imageBytes);

  final Uri uri;
  final String credential;
  final String idempotencyKey;
  final List<int> imageBytes;

  @override
  String toString() => 'FakeUploadRequest(<redacted>)';
}

/// Test-local result model (stand-in for `OccurrenceTransportResult`).
sealed class FakeTransportResult {
  const FakeTransportResult();
}

/// Complete HTTP headers received; only the status code is carried.
final class FakeHttpResponse extends FakeTransportResult {
  const FakeHttpResponse(this.statusCode);

  final int statusCode;
}

final class FakeNetworkFailure extends FakeTransportResult {
  const FakeNetworkFailure();
}

final class FakeTransportTimeout extends FakeTransportResult {
  const FakeTransportTimeout();
}

final class FakeTransportCancelled extends FakeTransportResult {
  const FakeTransportCancelled();
}

final class FakeLocalAssemblyFailure extends FakeTransportResult {
  const FakeLocalAssemblyFailure();
}

/// Scripted transport that never opens a socket.
///
/// Each `send` consumes one scripted step in order. A send with no scripted
/// step fails loudly so a test cannot accidentally depend on an implicit
/// response (or on the real API).
final class FakeOccurrenceTransport {
  final Queue<_Step> _script = Queue<_Step>();
  final List<FakeUploadRequest> _requests = <FakeUploadRequest>[];

  Completer<FakeTransportResult>? _active;
  int _inFlight = 0;

  int cancelActiveCount = 0;
  int maxConcurrentSends = 0;

  List<FakeUploadRequest> get requests =>
      List<FakeUploadRequest>.unmodifiable(_requests);

  int get sendCount => _requests.length;
  int get inFlight => _inFlight;
  int get pendingScriptLength => _script.length;

  /// Scripts an immediate result for the next unscripted send.
  void respondWith(FakeTransportResult result) {
    _script.add(_Step.immediate(result));
  }

  /// Scripts a send that stays in flight until the returned completer is
  /// completed or [cancelActive] is called.
  Completer<FakeTransportResult> holdNext() {
    final completer = Completer<FakeTransportResult>();
    _script.add(_Step.held(completer));
    return completer;
  }

  Future<FakeTransportResult> send(FakeUploadRequest request) async {
    _requests.add(request);
    if (_script.isEmpty) {
      throw StateError('FakeOccurrenceTransport has no scripted result.');
    }
    final step = _script.removeFirst();
    _inFlight++;
    if (_inFlight > maxConcurrentSends) {
      maxConcurrentSends = _inFlight;
    }
    try {
      final immediate = step.result;
      if (immediate != null) {
        return immediate;
      }
      final held = step.completer!;
      _active = held;
      return await held.future;
    } finally {
      _inFlight--;
      _active = null;
    }
  }

  /// Completes the in-flight held send as cancelled, if any.
  Future<void> cancelActive() async {
    cancelActiveCount++;
    final active = _active;
    if (active != null && !active.isCompleted) {
      active.complete(const FakeTransportCancelled());
    }
  }
}

final class _Step {
  _Step.immediate(FakeTransportResult this.result) : completer = null;
  _Step.held(Completer<FakeTransportResult> this.completer) : result = null;

  final FakeTransportResult? result;
  final Completer<FakeTransportResult>? completer;
}
