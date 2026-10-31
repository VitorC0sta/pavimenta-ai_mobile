import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;
import 'package:pavimenta_ai_mobile/domain/detection/detection_filter.dart';
import 'package:pavimenta_ai_mobile/domain/detection/detection_frame.dart';

import 'detection_test_support.dart';

const _filter = DetectionFilter(minimumConfidence: 0.35, maximumAreaRatio: 0.2);

void main() {
  // **Validates: Requirements RF-04.6, RF-04.12** (task 78.2)
  group('DetectionFilter', () {
    test('keeps a valid pothole box at or above the threshold', () {
      final atThreshold =
          potholeBox(centerX: 0.5, centerY: 0.5, confidence: 0.35);
      final above = potholeBox(centerX: 0.3, centerY: 0.6, confidence: 0.9);
      expect(_filter.apply(<DetectionBox>[atThreshold, above]), hasLength(2));
    });

    test('drops boxes below the threshold or with invalid confidence', () {
      for (final confidence in <double>[
        0.3499,
        0,
        -0.1,
        1.01,
        double.nan,
        double.infinity,
      ]) {
        expect(
          _filter.apply(<DetectionBox>[
            potholeBox(centerX: 0.5, centerY: 0.5, confidence: confidence),
          ]),
          isEmpty,
          reason: 'confidence $confidence',
        );
      }
    });

    test('drops other classes, by index or by name', () {
      expect(
        _filter.apply(<DetectionBox>[
          potholeBox(centerX: 0.5, centerY: 0.5, classIndex: 1),
          potholeBox(centerX: 0.5, centerY: 0.5, className: 'pothole'),
        ]),
        isEmpty,
      );
    });

    test('drops degenerate, non-finite or far out-of-frame coordinates', () {
      const boxes = <DetectionBox>[
        DetectionBox(
          classIndex: 0,
          className: 'buraco',
          confidence: 0.8,
          left: 0.5,
          top: 0.5,
          right: 0.5,
          bottom: 0.6,
        ),
        DetectionBox(
          classIndex: 0,
          className: 'buraco',
          confidence: 0.8,
          left: 0.6,
          top: 0.5,
          right: 0.4,
          bottom: 0.6,
        ),
        DetectionBox(
          classIndex: 0,
          className: 'buraco',
          confidence: 0.8,
          left: double.nan,
          top: 0.5,
          right: 0.6,
          bottom: 0.6,
        ),
        DetectionBox(
          classIndex: 0,
          className: 'buraco',
          confidence: 0.8,
          left: -0.2,
          top: 0.5,
          right: 0.1,
          bottom: 0.6,
        ),
      ];
      expect(_filter.apply(boxes), isEmpty);
    });

    test('clamps small plugin overshoots to the frame', () {
      const overshoot = DetectionBox(
        classIndex: 0,
        className: 'buraco',
        confidence: 0.7,
        left: 0.8,
        top: -0.0303,
        right: 1.0071,
        bottom: 0.1,
      );
      final accepted = _filter.apply(<DetectionBox>[overshoot]).single;
      expect(accepted.top, 0);
      expect(accepted.right, 1);
      expect(accepted.left, 0.8);
      expect(accepted.confidence, 0.7);
    });

    test('accepts exactly 20% of the frame and drops anything larger', () {
      const atLimit = DetectionBox(
        classIndex: 0,
        className: 'buraco',
        confidence: 0.8,
        left: 0,
        top: 0,
        right: 0.5,
        bottom: 0.4,
      );
      const larger = DetectionBox(
        classIndex: 0,
        className: 'buraco',
        confidence: 0.8,
        left: 0,
        top: 0,
        right: 0.5,
        bottom: 0.41,
      );
      expect(_filter.apply(<DetectionBox>[atLimit]), hasLength(1));
      expect(_filter.apply(<DetectionBox>[larger]), isEmpty);
    });
  });

  // **Validates: Requirements RF-04.6, RF-04.12** (task 78.6)
  Glados3<int, int, int>(
    any.intInRange(0, 1001),
    any.intInRange(0, 1001),
    any.intInRange(1, 1001),
    ExploreConfig(numRuns: 200),
  ).test('every kept box meets threshold, frame and area rules',
      (int confidence, int center, int size) {
    final box = potholeBox(
      centerX: center / 1000,
      centerY: 1 - center / 1000,
      width: size / 1000,
      height: size / 2000,
      confidence: confidence / 1000,
    );
    final kept = _filter.apply(<DetectionBox>[box]);
    for (final accepted in kept) {
      expect(accepted.confidence, greaterThanOrEqualTo(0.35));
      expect(accepted.left, inInclusiveRange(0, 1));
      expect(accepted.right, inInclusiveRange(0, 1));
      expect(accepted.top, inInclusiveRange(0, 1));
      expect(accepted.bottom, inInclusiveRange(0, 1));
      expect(accepted.area, lessThanOrEqualTo(0.2));
      expect(accepted.width, greaterThan(0));
      expect(accepted.height, greaterThan(0));
    }
    if (confidence < 350) {
      expect(kept, isEmpty);
    }
  });
}
