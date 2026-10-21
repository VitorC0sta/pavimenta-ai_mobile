import 'dart:async';
import 'dart:io';

const String _defaultDiagnosticUrl =
    'https://e0-diagnostic.example.invalid/health';

enum DiagnosticHttpOutcome {
  reachable,
  responded,
  invalidConfiguration,
  incompleteResponse,
  timeout,
  tlsFailure,
  unavailable,
  cancelled,
}

class DiagnosticHttpResult {
  const DiagnosticHttpResult({
    required this.outcome,
    this.statusCode,
  });

  final DiagnosticHttpOutcome outcome;
  final int? statusCode;
}

/// Executes the deliberately small and restricted E0 HTTPS diagnostic.
class DiagnosticHttpClient {
  DiagnosticHttpClient({
    String configuredUrl = const String.fromEnvironment(
      'E0_DIAGNOSTIC_URL',
      defaultValue: _defaultDiagnosticUrl,
    ),
  }) : _configuredUrl = configuredUrl;

  static const Duration connectionTimeout = Duration(seconds: 4);
  static const Duration responseHeadersTimeout = Duration(seconds: 6);
  static const Duration responseBodyTimeout = Duration(seconds: 3);
  static const int maximumDiscardedBodyBytes = 8 * 1024;

  final String _configuredUrl;

  HttpClient? _activeClient;
  HttpClientRequest? _activeRequest;
  StreamSubscription<List<int>>? _activeResponseSubscription;
  Timer? _activeResponseTimer;
  Completer<_BodyDrainOutcome>? _activeBodyCompletion;
  int _operationId = 0;
  bool _isDisposed = false;

  Future<DiagnosticHttpResult> run() async {
    final destination = _validatedDestination();
    if (destination == null) {
      return const DiagnosticHttpResult(
        outcome: DiagnosticHttpOutcome.invalidConfiguration,
      );
    }
    if (_isDisposed || _activeClient != null) {
      return const DiagnosticHttpResult(
        outcome: DiagnosticHttpOutcome.cancelled,
      );
    }

    final operationId = ++_operationId;
    final client = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..idleTimeout = responseBodyTimeout
      ..autoUncompress = false;
    _activeClient = client;

    HttpClientRequest? request;
    try {
      request = await client.getUrl(destination);
      if (!_isCurrentOperation(operationId)) {
        request.abort();
        return const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.cancelled,
        );
      }

      _activeRequest = request;
      request.followRedirects = false;

      final response = await request.close().timeout(responseHeadersTimeout);
      if (!_isCurrentOperation(operationId)) {
        client.close(force: true);
        return const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.cancelled,
        );
      }

      _activeRequest = null;
      final statusCode = response.statusCode;
      final drainOutcome = await _discardResponseBody(
        response: response,
        client: client,
        request: request,
        operationId: operationId,
      );

      return switch (drainOutcome) {
        _BodyDrainOutcome.completed => DiagnosticHttpResult(
            outcome: statusCode >= 200 && statusCode < 300
                ? DiagnosticHttpOutcome.reachable
                : DiagnosticHttpOutcome.responded,
            statusCode: statusCode,
          ),
        _BodyDrainOutcome.excessive ||
        _BodyDrainOutcome.timedOut =>
          DiagnosticHttpResult(
            outcome: DiagnosticHttpOutcome.incompleteResponse,
            statusCode: statusCode,
          ),
        _BodyDrainOutcome.cancelled => DiagnosticHttpResult(
            outcome: DiagnosticHttpOutcome.cancelled,
            statusCode: statusCode,
          ),
      };
    } on TimeoutException {
      if (!_isCurrentOperation(operationId)) {
        return const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.cancelled,
        );
      }
      return const DiagnosticHttpResult(
        outcome: DiagnosticHttpOutcome.timeout,
      );
    } on TlsException {
      if (!_isCurrentOperation(operationId)) {
        return const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.cancelled,
        );
      }
      return const DiagnosticHttpResult(
        outcome: DiagnosticHttpOutcome.tlsFailure,
      );
    } on SocketException {
      if (!_isCurrentOperation(operationId)) {
        return const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.cancelled,
        );
      }
      return const DiagnosticHttpResult(
        outcome: DiagnosticHttpOutcome.unavailable,
      );
    } on HttpException {
      if (!_isCurrentOperation(operationId)) {
        return const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.cancelled,
        );
      }
      return const DiagnosticHttpResult(
        outcome: DiagnosticHttpOutcome.unavailable,
      );
    } catch (_) {
      if (!_isCurrentOperation(operationId)) {
        return const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.cancelled,
        );
      }
      return const DiagnosticHttpResult(
        outcome: DiagnosticHttpOutcome.unavailable,
      );
    } finally {
      if (identical(_activeRequest, request)) {
        _activeRequest = null;
      }
      if (identical(_activeClient, client)) {
        _clearActiveResponseTracking();
        _activeClient = null;
      }
      client.close(force: true);
    }
  }

  Uri? _validatedDestination() {
    final value = _configuredUrl.trim();
    if (value.isEmpty) {
      return null;
    }

    final destination = Uri.tryParse(value);
    if (destination == null ||
        !destination.isAbsolute ||
        destination.scheme != 'https' ||
        destination.host.isEmpty ||
        destination.userInfo.isNotEmpty ||
        destination.hasFragment) {
      return null;
    }

    final decodedPath = '/${destination.pathSegments.join('/')}';
    if (decodedPath == '/api/v1/occurrences' ||
        decodedPath == '/api/v1/occurrences/') {
      return null;
    }

    return destination;
  }

  Future<_BodyDrainOutcome> _discardResponseBody({
    required HttpClientResponse response,
    required HttpClient client,
    required HttpClientRequest request,
    required int operationId,
  }) {
    final completion = Completer<_BodyDrainOutcome>();
    _activeBodyCompletion = completion;
    var discardedBytes = 0;

    late final StreamSubscription<List<int>> subscription;
    late final Timer timer;

    void finish(_BodyDrainOutcome outcome, {bool abort = false}) {
      if (completion.isCompleted) {
        return;
      }
      if (abort) {
        request.abort();
        client.close(force: true);
      }
      completion.complete(outcome);
      if (outcome != _BodyDrainOutcome.completed) {
        unawaited(subscription.cancel());
      }
    }

    subscription = response.listen(
      (bytes) {
        if (!_isCurrentOperation(operationId)) {
          finish(_BodyDrainOutcome.cancelled, abort: true);
          return;
        }

        discardedBytes += bytes.length;
        if (discardedBytes > maximumDiscardedBodyBytes) {
          finish(_BodyDrainOutcome.excessive, abort: true);
        }
      },
      onError: (Object _, StackTrace __) {
        finish(_BodyDrainOutcome.excessive, abort: true);
      },
      onDone: () {
        finish(_BodyDrainOutcome.completed);
      },
      cancelOnError: true,
    );
    _activeResponseSubscription = subscription;

    timer = Timer(responseBodyTimeout, () {
      finish(_BodyDrainOutcome.timedOut, abort: true);
    });
    _activeResponseTimer = timer;

    return completion.future.whenComplete(() {
      timer.cancel();
      if (identical(_activeResponseSubscription, subscription)) {
        _activeResponseSubscription = null;
      }
      if (identical(_activeResponseTimer, timer)) {
        _activeResponseTimer = null;
      }
      if (identical(_activeBodyCompletion, completion)) {
        _activeBodyCompletion = null;
      }
    });
  }

  Future<void> cancelActive() async {
    ++_operationId;

    final completion = _activeBodyCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(_BodyDrainOutcome.cancelled);
    }

    _activeResponseTimer?.cancel();
    _activeResponseTimer = null;

    final subscription = _activeResponseSubscription;
    _activeResponseSubscription = null;

    _activeRequest?.abort();
    _activeRequest = null;

    _activeClient?.close(force: true);
    _activeClient = null;
    _activeBodyCompletion = null;

    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {
        // Cancellation is best effort; no transport detail leaves this class.
      }
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await cancelActive();
  }

  bool _isCurrentOperation(int operationId) {
    return !_isDisposed && operationId == _operationId;
  }

  void _clearActiveResponseTracking() {
    _activeResponseTimer?.cancel();
    _activeResponseTimer = null;
    final subscription = _activeResponseSubscription;
    _activeResponseSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _activeBodyCompletion = null;
  }
}

enum _BodyDrainOutcome {
  completed,
  excessive,
  timedOut,
  cancelled,
}
