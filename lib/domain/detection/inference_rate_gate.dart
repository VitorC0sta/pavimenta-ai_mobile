/// Defensive FPS limit on top of the plugin rate (E5.7 step 1, RF-04.3).
///
/// A frame arriving earlier than `tolerance × (1 / FPS)` after the last
/// accepted frame is dropped. Dropped frames are not queued or buffered.
final class InferenceRateGate {
  InferenceRateGate({required int framesPerSecond})
      : _minimumInterval = _intervalFor(framesPerSecond);

  static Duration _intervalFor(int framesPerSecond) {
    if (framesPerSecond <= 0) {
      throw ArgumentError.value(framesPerSecond, 'framesPerSecond');
    }
    return Duration(
      microseconds:
          (tolerance * Duration.microsecondsPerSecond / framesPerSecond)
              .round(),
    );
  }

  /// Technical constant, not exposed in Settings.
  static const double tolerance = 0.85;

  final Duration _minimumInterval;
  DateTime? _lastAccepted;

  Duration get minimumInterval => _minimumInterval;

  /// Returns true and records [at] when the frame may be processed.
  ///
  /// A timestamp earlier than the last accepted one means the wall clock was
  /// adjusted; the frame is accepted and becomes the new reference so the
  /// gate never stalls.
  bool tryAccept(DateTime at) {
    final last = _lastAccepted;
    if (last != null) {
      final elapsed = at.difference(last);
      if (!elapsed.isNegative && elapsed < _minimumInterval) {
        return false;
      }
    }
    _lastAccepted = at;
    return true;
  }

  void reset() => _lastAccepted = null;
}
