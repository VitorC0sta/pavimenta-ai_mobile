import 'dart:async';

/// Observable completion signal for one Diagnostic route session.
///
/// The Operation route waits for [completed] after `Navigator.push` returns,
/// so it cannot reacquire camera, location, or wake lock while Diagnostic
/// cleanup is still running.
final class DiagnosticSessionDisposal {
  final Completer<void> _completion = Completer<void>();
  bool _completionWasRegistered = false;

  Future<void> get completed => _completion.future;

  bool get isCompleted => _completion.isCompleted;

  /// Registers the complete asynchronous cleanup of the Diagnostic session.
  ///
  /// Registration is idempotent because a route session has exactly one
  /// ownership handoff back to Operation.
  void completeAfter(Future<void> cleanup) {
    if (_completionWasRegistered) {
      return;
    }
    _completionWasRegistered = true;
    unawaited(_completeAfter(cleanup));
  }

  Future<void> _completeAfter(Future<void> cleanup) async {
    try {
      await cleanup;
      if (!_completion.isCompleted) {
        _completion.complete();
      }
    } catch (error, stackTrace) {
      if (!_completion.isCompleted) {
        _completion.completeError(error, stackTrace);
      }
    }
  }
}
