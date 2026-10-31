import 'dart:collection';

/// Measures processed frames per second over a sliding window (E5.7 step 2).
///
/// Only timestamps of accepted frames are kept, and only inside the window.
final class InferenceFpsMeter {
  /// Technical constant, not exposed in Settings.
  static const Duration window = Duration(seconds: 2);

  final Queue<DateTime> _accepted = Queue<DateTime>();

  void record(DateTime at) {
    _accepted.addLast(at);
    _prune(at);
  }

  /// Frames per second over the window ending at [now].
  double framesPerSecondAt(DateTime now) {
    _prune(now);
    final count = _accepted.where((at) => !at.isAfter(now)).length;
    return count * Duration.microsecondsPerSecond / window.inMicroseconds;
  }

  void reset() => _accepted.clear();

  void _prune(DateTime now) {
    final start = now.subtract(window);
    while (_accepted.isNotEmpty && !_accepted.first.isAfter(start)) {
      _accepted.removeFirst();
    }
  }
}
