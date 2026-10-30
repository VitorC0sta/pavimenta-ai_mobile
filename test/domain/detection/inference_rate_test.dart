import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;
import 'package:pavimenta_ai_mobile/domain/detection/inference_fps_meter.dart';
import 'package:pavimenta_ai_mobile/domain/detection/inference_rate_gate.dart';

import 'detection_test_support.dart';

void main() {
  // **Validates: Requirements RF-04.3, RNF-04.5** (task 78.3)
  group('InferenceRateGate', () {
    test('uses 0.85 of the frame period as the minimum interval', () {
      expect(
        InferenceRateGate(framesPerSecond: 5).minimumInterval,
        const Duration(milliseconds: 170),
      );
      expect(
        InferenceRateGate(framesPerSecond: 10).minimumInterval,
        const Duration(milliseconds: 85),
      );
    });

    test('accepts the first frame and drops frames inside the interval', () {
      final gate = InferenceRateGate(framesPerSecond: 5);
      final start = detectionEpoch;
      expect(gate.tryAccept(start), isTrue);
      expect(
        gate.tryAccept(start.add(const Duration(milliseconds: 169))),
        isFalse,
      );
      expect(
        gate.tryAccept(start.add(const Duration(milliseconds: 170))),
        isTrue,
      );
    });

    test('measures from the last accepted frame, not the dropped ones', () {
      final gate = InferenceRateGate(framesPerSecond: 5);
      gate.tryAccept(detectionEpoch);
      gate.tryAccept(detectionEpoch.add(const Duration(milliseconds: 100)));
      expect(
        gate.tryAccept(detectionEpoch.add(const Duration(milliseconds: 171))),
        isTrue,
      );
    });

    test('accepts a frame after a backwards clock adjustment', () {
      final gate = InferenceRateGate(framesPerSecond: 5);
      gate.tryAccept(detectionEpoch);
      expect(
        gate.tryAccept(detectionEpoch.subtract(const Duration(minutes: 1))),
        isTrue,
      );
    });

    test('reset accepts the next frame immediately', () {
      final gate = InferenceRateGate(framesPerSecond: 5)
        ..tryAccept(detectionEpoch)
        ..reset();
      expect(
        gate.tryAccept(detectionEpoch.add(const Duration(milliseconds: 1))),
        isTrue,
      );
    });

    test('rejects a non-positive FPS', () {
      expect(() => InferenceRateGate(framesPerSecond: 0), throwsArgumentError);
    });
  });

  group('InferenceFpsMeter', () {
    test('reports frames over the last 2 seconds', () {
      final meter = InferenceFpsMeter();
      for (var i = 0; i < 10; i++) {
        meter.record(frameTime(i));
      }
      expect(meter.framesPerSecondAt(frameTime(9)), 5);
    });

    test('decays to zero when frames stop', () {
      final meter = InferenceFpsMeter()..record(detectionEpoch);
      expect(meter.framesPerSecondAt(detectionEpoch), 0.5);
      expect(
        meter.framesPerSecondAt(detectionEpoch.add(const Duration(seconds: 2))),
        0,
      );
    });

    test('reset clears the window', () {
      final meter = InferenceFpsMeter()
        ..record(detectionEpoch)
        ..reset();
      expect(meter.framesPerSecondAt(detectionEpoch), 0);
    });
  });

  // **Validates: Requirements RF-04.3, RNF-04.5** (task 78.6)
  Glados2<int, List<int>>(
    any.intInRange(1, 16),
    any.listWithLengthInRange(1, 60, any.intInRange(0, 400)),
    ExploreConfig(numRuns: 150),
  ).test('accepted frames are never closer than the minimum interval',
      (int fps, List<int> gapsMs) {
    final gate = InferenceRateGate(framesPerSecond: fps);
    final meter = InferenceFpsMeter();
    var now = detectionEpoch;
    DateTime? lastAccepted;
    for (final gap in gapsMs) {
      now = now.add(Duration(milliseconds: gap));
      if (gate.tryAccept(now)) {
        if (lastAccepted != null) {
          expect(
            now.difference(lastAccepted),
            greaterThanOrEqualTo(gate.minimumInterval),
          );
        }
        lastAccepted = now;
        meter.record(now);
      }
    }
    // The meter can never exceed the gate rate over its window.
    final ceiling = (InferenceFpsMeter.window.inMicroseconds /
                gate.minimumInterval.inMicroseconds)
            .floor() +
        1;
    expect(
      meter.framesPerSecondAt(now) * 2,
      lessThanOrEqualTo(ceiling.toDouble()),
    );
  });
}
