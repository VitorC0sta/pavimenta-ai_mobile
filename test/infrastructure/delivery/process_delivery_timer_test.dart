import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/process_delivery_timer.dart';

void main() {
  // **Validates: Requirements RF-16.2, RF-16.4, RNF-02, RNF-04.6**
  group('ProcessDeliveryTimer', () {
    late _Clock clock;
    late ProcessDeliveryTimer timer;

    setUp(() {
      clock = _Clock(DateTime.utc(2026, 1, 1, 12));
      timer = ProcessDeliveryTimer(clock: clock);
      addTearDown(timer.dispose);
    });

    test('fires once at the due instant and then becomes inactive', () async {
      final fired = Completer<void>();
      var calls = 0;
      final handle = timer.arm(
        clock.now().add(const Duration(milliseconds: 20)),
        () {
          calls++;
          fired.complete();
        },
      );

      expect(handle.isActive, isTrue);
      expect(timer.armedCount, 1);
      expect(calls, 0);

      await fired.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(calls, 1);
      expect(handle.isActive, isFalse);
      expect(timer.armedCount, 0);
    });

    test('an instant that already passed fires promptly, never synchronously',
        () async {
      final fired = Completer<void>();
      var calls = 0;
      timer.arm(clock.now().subtract(const Duration(minutes: 5)), () {
        calls++;
        fired.complete();
      });

      expect(calls, 0);
      await fired.future.timeout(const Duration(seconds: 2));
      expect(calls, 1);
    });

    test('cancel prevents the callback and is idempotent', () async {
      var calls = 0;
      final handle = timer.arm(
        clock.now().add(const Duration(milliseconds: 20)),
        () => calls++,
      );

      handle.cancel();
      handle.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(handle.isActive, isFalse);
      expect(calls, 0);
      expect(timer.armedCount, 0);
    });

    test('a failing callback is contained and does not rearm', () async {
      final done = Completer<void>();
      final handle = timer.arm(clock.now(), () {
        done.complete();
        throw StateError('callback failure');
      });

      await done.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(handle.isActive, isFalse);
      expect(timer.armedCount, 0);
    });

    test('dispose cancels every armed timer and refuses new ones', () async {
      var calls = 0;
      final first = timer.arm(
        clock.now().add(const Duration(milliseconds: 20)),
        () => calls++,
      );
      final second = timer.arm(
        clock.now().add(const Duration(milliseconds: 30)),
        () => calls++,
      );

      timer.dispose();
      timer.dispose();
      final late = timer.arm(clock.now(), () => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(first.isActive, isFalse);
      expect(second.isActive, isFalse);
      expect(late.isActive, isFalse);
      expect(calls, 0);
      expect(timer.armedCount, 0);
    });
  });
}

final class _Clock implements Clock {
  _Clock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
