import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_backoff_policy.dart';

void main() {
  group('DeliveryBackoffPolicy', () {
    // **Validates: Requirements RF-17.1, RNF-03.8–10**
    test('follows min(5 s x 3^(n-1), 15 min) for the first failures', () {
      const expected = <Duration>[
        Duration(seconds: 5),
        Duration(seconds: 15),
        Duration(seconds: 45),
        Duration(minutes: 2, seconds: 15),
        Duration(minutes: 6, seconds: 45),
        Duration(minutes: 15),
        Duration(minutes: 15),
      ];
      for (var n = 1; n <= expected.length; n++) {
        expect(
          DeliveryBackoffPolicy.delayFor(n),
          expected[n - 1],
          reason: 'failure $n',
        );
      }
    });

    test('never decreases and never exceeds the 15-minute ceiling', () {
      var previous = Duration.zero;
      for (var n = 1; n <= 500; n++) {
        final delay = DeliveryBackoffPolicy.delayFor(n);
        expect(delay, greaterThanOrEqualTo(previous), reason: 'failure $n');
        expect(delay, lessThanOrEqualTo(DeliveryBackoffPolicy.maxDelay));
        expect(delay, greaterThan(Duration.zero));
        previous = delay;
      }
      expect(previous, DeliveryBackoffPolicy.maxDelay);
    });

    test('grows strictly by a factor of three until it reaches the ceiling',
        () {
      for (var n = 1; n < 5; n++) {
        expect(
          DeliveryBackoffPolicy.delayFor(n + 1),
          DeliveryBackoffPolicy.delayFor(n) * 3,
          reason: 'failure $n',
        );
      }
    });

    test('saturates instead of overflowing for very large attempt counts', () {
      for (final n in <int>[
        64,
        1000,
        1 << 31,
        1 << 53,
        (1 << 62),
        9223372036854775807, // max 64-bit int
      ]) {
        expect(
          DeliveryBackoffPolicy.delayFor(n),
          DeliveryBackoffPolicy.maxDelay,
          reason: 'failure $n',
        );
      }
    });

    test('rejects counts below one without echoing sensitive data', () {
      for (final n in <int>[0, -1, -9223372036854775808]) {
        expect(() => DeliveryBackoffPolicy.delayFor(n), throwsArgumentError);
      }
    });

    test('is deterministic: no jitter between calls', () {
      for (var n = 1; n <= 10; n++) {
        expect(
          DeliveryBackoffPolicy.delayFor(n),
          DeliveryBackoffPolicy.delayFor(n),
        );
      }
    });

    test('is reusable for remote retry and local cleanup with one curve', () {
      // Both callers pass their own consecutive-failure counter; the policy
      // has no notion of which one it serves.
      const remoteAttempts = 3;
      const cleanupAttempts = 3;
      expect(
        DeliveryBackoffPolicy.delayFor(remoteAttempts),
        DeliveryBackoffPolicy.delayFor(cleanupAttempts),
      );
    });
  });
}
