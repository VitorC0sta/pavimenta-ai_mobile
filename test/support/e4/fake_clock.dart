import 'package:pavimenta_ai_mobile/application/e1_ports.dart';

/// Controllable implementation of the existing production [Clock] port.
///
/// The `Clock` contract itself is not redefined for E4: only the single
/// `now()` operation is implemented here. Existing tests keep their own
/// private clocks; this one adds `advance`/`set` for delivery scenarios.
final class FakeClock implements Clock {
  FakeClock(DateTime initial) : _now = initial;

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Moves the clock forward. Negative durations are rejected; use [set] to
  /// simulate a civil clock regression explicitly.
  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    _now = _now.add(duration);
  }

  /// Sets the current instant, including to an earlier one.
  void set(DateTime instant) {
    _now = instant;
  }
}
