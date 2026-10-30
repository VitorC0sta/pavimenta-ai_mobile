import 'fake_clock.dart';

/// Handle returned by [FakeDeliveryTimer.arm].
final class FakeTimerHandle {
  FakeTimerHandle._(this.dueAt, this._onDue);

  final DateTime dueAt;
  final void Function() _onDue;
  bool _active = true;

  bool get isActive => _active;

  void cancel() {
    _active = false;
  }
}

/// Manually driven timer: nothing fires unless the test advances time.
///
/// Test-local stand-in for the future `DeliveryTimerPort` (task 63.4). It is
/// intentionally independent of Flutter's fake async so tests stay explicit
/// about when a due instant is reached.
final class FakeDeliveryTimer {
  FakeDeliveryTimer(this._clock);

  final FakeClock _clock;
  final List<FakeTimerHandle> _armed = <FakeTimerHandle>[];

  int armCount = 0;
  int firedCount = 0;
  int cancelledCount = 0;

  /// Highest number of simultaneously active timers ever observed. The E4
  /// design allows at most one.
  int maxConcurrentActive = 0;

  /// Active timers ordered by due instant.
  List<FakeTimerHandle> get active => List<FakeTimerHandle>.unmodifiable(
        (_armed.where((timer) => timer.isActive).toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt))),
      );

  int get activeCount => active.length;

  FakeTimerHandle arm(DateTime dueAt, void Function() onDue) {
    final handle = FakeTimerHandle._(dueAt, onDue);
    _armed.add(handle);
    armCount++;
    if (activeCount > maxConcurrentActive) {
      maxConcurrentActive = activeCount;
    }
    return handle;
  }

  void cancel(FakeTimerHandle handle) {
    if (handle.isActive) {
      handle.cancel();
      cancelledCount++;
    }
    _armed.remove(handle);
  }

  /// Cancels every active timer.
  void cancelAll() {
    for (final handle in List<FakeTimerHandle>.of(_armed)) {
      cancel(handle);
    }
  }

  /// Advances the shared clock by [duration] and fires every timer that
  /// becomes due, in due order, with the clock at each due instant.
  /// Timers armed by a callback are honoured when due within the window.
  void advance(Duration duration) {
    final target = _clock.now().add(duration);
    while (true) {
      final due = active.where((timer) => !timer.dueAt.isAfter(target));
      if (due.isEmpty) {
        break;
      }
      _fire(due.first);
    }
    if (_clock.now().isBefore(target)) {
      _clock.set(target);
    }
  }

  /// Fires the earliest active timer, moving the clock to its due instant when
  /// that instant is still in the future. Returns false when none is armed.
  bool fireNext() {
    final timers = active;
    if (timers.isEmpty) {
      return false;
    }
    _fire(timers.first);
    return true;
  }

  void _fire(FakeTimerHandle handle) {
    _armed.remove(handle);
    handle._active = false;
    if (_clock.now().isBefore(handle.dueAt)) {
      _clock.set(handle.dueAt);
    }
    firedCount++;
    handle._onDue();
  }
}
