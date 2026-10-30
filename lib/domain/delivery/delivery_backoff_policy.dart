/// Deterministic exponential backoff shared by remote retry and local cleanup
/// retry (RF-17, design E4.10).
///
/// After consecutive failure number `n` (1-based) the delay is
/// `min(5 s × 3^(n - 1), 15 min)`: 5 s, 15 s, 45 s, 2 min 15 s, 6 min 45 s,
/// then 15 min forever. There is no jitter.
///
/// Pure and stateless: no clock, timer, storage, or I/O. Callers combine the
/// returned [Duration] with their own injected clock.
abstract final class DeliveryBackoffPolicy {
  /// Delay after the first failure.
  static const Duration baseDelay = Duration(seconds: 5);

  /// Upper bound of every delay.
  static const Duration maxDelay = Duration(minutes: 15);

  /// Multiplier applied for each additional consecutive failure.
  static const int growthFactor = 3;

  /// Returns the delay to wait after [failureCount] consecutive failures.
  ///
  /// [failureCount] is the number of the failure that just happened, so it
  /// must be at least 1. Any larger value is accepted and saturates at
  /// [maxDelay]; the computation multiplies at most until the ceiling is
  /// reached, so it can never overflow, whatever the input.
  ///
  /// Throws [ArgumentError] when [failureCount] is lower than 1.
  static Duration delayFor(int failureCount) {
    if (failureCount < 1) {
      throw ArgumentError.value(
        failureCount,
        'failureCount',
        'must be at least 1',
      );
    }
    var delayMicroseconds = baseDelay.inMicroseconds;
    for (var failure = 1; failure < failureCount; failure++) {
      delayMicroseconds *= growthFactor;
      if (delayMicroseconds >= maxDelay.inMicroseconds) {
        return maxDelay;
      }
    }
    return Duration(microseconds: delayMicroseconds);
  }
}
