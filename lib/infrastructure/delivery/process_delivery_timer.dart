import 'dart:async';

import '../../application/delivery/delivery_timer_port.dart';
import '../../application/e1_ports.dart';

/// Process timer behind [DeliveryTimerPort] (design E4.3, E4.13).
///
/// Each [arm] creates one one-shot `dart:async` [Timer] for the distance
/// between [dueAt] and the injected [Clock], so nothing here polls, loops, or
/// reschedules itself. A [dueAt] that already passed fires promptly through a
/// zero-length timer, never synchronously inside [arm].
///
/// The timer lives only in the running Dart isolate: there is no worker, no
/// alarm, and no wake-up while the process is not running. The coordinator
/// cancels it when the app leaves the foreground.
///
/// [DeliveryTimerHandle.cancel] is idempotent and guarantees the callback does
/// not run afterwards. The callback runs at most once. An exception thrown by
/// the callback is discarded so it cannot escape into the zone. [dispose]
/// cancels every timer still armed, is idempotent, and makes later [arm] calls
/// return an inactive handle.
final class ProcessDeliveryTimer implements DeliveryTimerPort {
  ProcessDeliveryTimer({required Clock clock}) : _clock = clock;

  final Clock _clock;
  final Set<_ProcessDeliveryTimerHandle> _armed =
      <_ProcessDeliveryTimerHandle>{};
  bool _disposed = false;

  /// Number of timers that are armed and have neither fired nor been
  /// cancelled.
  int get armedCount => _armed.length;

  @override
  DeliveryTimerHandle arm(DateTime dueAt, void Function() onDue) {
    final handle = _ProcessDeliveryTimerHandle(_armed.remove);
    if (_disposed) {
      handle.cancel();
      return handle;
    }
    var delay = dueAt.difference(_clock.now());
    if (delay.isNegative) {
      delay = Duration.zero;
    }
    _armed.add(handle);
    handle.start(delay, onDue);
    return handle;
  }

  /// Cancels every armed timer. Idempotent.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final handle in List<_ProcessDeliveryTimerHandle>.of(_armed)) {
      handle.cancel();
    }
    _armed.clear();
  }
}

final class _ProcessDeliveryTimerHandle implements DeliveryTimerHandle {
  _ProcessDeliveryTimerHandle(this._release);

  final void Function(_ProcessDeliveryTimerHandle handle) _release;
  Timer? _timer;
  bool _active = true;

  @override
  bool get isActive => _active;

  void start(Duration delay, void Function() onDue) {
    _timer = Timer(delay, () {
      if (!_active) {
        return;
      }
      _finish();
      try {
        onDue();
      } on Object {
        // The caught object is discarded; the coordinator evaluates again on
        // its next trigger.
      }
    });
  }

  @override
  void cancel() {
    if (!_active) {
      return;
    }
    _finish();
  }

  void _finish() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _release(this);
  }
}
