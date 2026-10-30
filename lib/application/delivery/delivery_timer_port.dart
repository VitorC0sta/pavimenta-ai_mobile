/// Handle of one armed delivery timer.
abstract interface class DeliveryTimerHandle {
  /// True until the timer fires or is cancelled.
  bool get isActive;

  /// Prevents the callback from running. Idempotent.
  void cancel();
}

/// Schedules a single wake-up at an absolute instant (design E4.3).
///
/// The coordinator keeps at most one active timer and cancels it when the app
/// leaves the foreground. The port knows no clock policy: implementations
/// compare [dueAt] with their own injected clock.
abstract interface class DeliveryTimerPort {
  /// Calls [onDue] once when [dueAt] is reached, or promptly when it already
  /// passed. Nothing runs after [DeliveryTimerHandle.cancel].
  DeliveryTimerHandle arm(DateTime dueAt, void Function() onDue);
}
