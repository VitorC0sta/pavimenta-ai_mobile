import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;
import 'package:pavimenta_ai_mobile/domain/detection/detection_frame.dart';
import 'package:pavimenta_ai_mobile/domain/detection/temporal_confirmation_tracker.dart';

import 'detection_test_support.dart';

const _width = 1280;
const _height = 720;

TemporalConfirmationTracker _tracker() =>
    TemporalConfirmationTracker(requiredHits: 2, windowSize: 3);

final class _Run {
  _Run(this.tracker);

  final TemporalConfirmationTracker tracker;
  int _index = 0;

  List<ConfirmedDetection> frame(List<DetectionBox> boxes) => tracker.process(
        observedAt: frameTime(_index++),
        imageWidth: _width,
        imageHeight: _height,
        boxes: boxes,
      );

  List<ConfirmedDetection> empty() => frame(const <DetectionBox>[]);
}

void main() {
  // **Validates: Requirements RF-04.8–11** (task 78.4)
  group('TemporalConfirmationTracker', () {
    test('confirms on the second consecutive frame with the best confidence',
        () {
      final run = _Run(_tracker());
      expect(
        run.frame([potholeBox(centerX: 0.5, centerY: 0.7, confidence: 0.8)]),
        isEmpty,
      );
      final confirmed = run.frame(
        [potholeBox(centerX: 0.5, centerY: 0.7, confidence: 0.5)],
      ).single;
      expect(confirmed.confidence, 0.8);
      expect(confirmed.observedAt, frameTime(1));
    });

    test('confirms 2 of 3 with an empty frame in between', () {
      final run = _Run(_tracker());
      run.frame([potholeBox(centerX: 0.5, centerY: 0.7)]);
      expect(run.empty(), isEmpty);
      expect(run.frame([potholeBox(centerX: 0.5, centerY: 0.7)]), hasLength(1));
    });

    test('does not confirm hits further apart than the window', () {
      final run = _Run(_tracker());
      run.frame([potholeBox(centerX: 0.5, centerY: 0.7)]);
      run.empty();
      run.empty();
      expect(run.frame([potholeBox(centerX: 0.5, centerY: 0.7)]), isEmpty);
    });

    test('a confirmed track is suppressed until 3 frames without a box', () {
      final run = _Run(_tracker());
      final box = potholeBox(centerX: 0.5, centerY: 0.7);
      run.frame([box]);
      expect(run.frame([box]), hasLength(1));
      for (var i = 0; i < 5; i++) {
        expect(run.frame([box]), isEmpty, reason: 'still the same pothole');
      }
      run.empty();
      run.empty();
      expect(run.frame([box]), isEmpty, reason: '2 misses keep suppression');
      run.empty();
      run.empty();
      run.empty();
      expect(run.tracker.activeTrackCount, 0);
      run.frame([box]);
      expect(run.frame([box]), hasLength(1), reason: 'new pothole after reset');
    });

    test('follows jitter smaller than the larger box side', () {
      final run = _Run(_tracker());
      // 0.1 × 1280 = 128 px wide; move 100 px horizontally.
      run.frame([potholeBox(centerX: 0.5, centerY: 0.7)]);
      expect(
        run.frame([potholeBox(centerX: 0.5 + 100 / _width, centerY: 0.7)]),
        hasLength(1),
      );
    });

    test('the exact larger side is not compatible', () {
      final run = _Run(_tracker());
      run.frame([potholeBox(centerX: 0.25, centerY: 0.5)]);
      // Move exactly 128 px, the larger side of both boxes.
      expect(
        run.frame([potholeBox(centerX: 0.25 + 128 / _width, centerY: 0.5)]),
        isEmpty,
      );
    });

    test('measures distance in pixels of non-square frames', () {
      // Box 0.1 × 0.1 normalized is 128 × 72 px: the larger side is 128 px.
      final horizontal = _Run(_tracker());
      horizontal.frame([potholeBox(centerX: 0.4, centerY: 0.5)]);
      expect(
        horizontal.frame([potholeBox(centerX: 0.48, centerY: 0.5)]),
        hasLength(1),
        reason: '0.08 × 1280 = 102.4 px is below 128 px',
      );

      final vertical = _Run(_tracker());
      vertical.frame([potholeBox(centerX: 0.4, centerY: 0.3)]);
      expect(
        vertical.frame([potholeBox(centerX: 0.4, centerY: 0.47)]),
        hasLength(1),
        reason: '0.17 × 720 = 122.4 px is below 128 px',
      );

      final verticalFar = _Run(_tracker());
      verticalFar.frame([potholeBox(centerX: 0.4, centerY: 0.3)]);
      expect(
        verticalFar.frame([potholeBox(centerX: 0.4, centerY: 0.48)]),
        isEmpty,
        reason: '0.18 × 720 = 129.6 px is not below the 128 px side',
      );
    });

    test('uses the larger of the two boxes when sizes differ', () {
      final run = _Run(_tracker());
      run.frame([
        potholeBox(centerX: 0.5, centerY: 0.5, width: 0.02, height: 0.02),
      ]);
      // Small box 25.6 px, big box 0.2 × 1280 = 256 px; move 200 px.
      expect(
        run.frame([
          potholeBox(
            centerX: 0.5 + 200 / _width,
            centerY: 0.5,
            width: 0.2,
            height: 0.1,
          ),
        ]),
        hasLength(1),
      );
    });

    test('associates greedily by the smallest distance', () {
      final run = _Run(_tracker());
      run.frame([
        potholeBox(centerX: 0.30, centerY: 0.5, confidence: 0.9),
        potholeBox(centerX: 0.40, centerY: 0.5, confidence: 0.4),
      ]);
      final confirmed = run.frame([
        potholeBox(centerX: 0.31, centerY: 0.5, confidence: 0.5),
        potholeBox(centerX: 0.41, centerY: 0.5, confidence: 0.5),
      ]);
      expect(
        confirmed.map((c) => c.confidence).toList()..sort(),
        <double>[0.5, 0.9],
      );
    });

    test('two distant potholes confirm independently', () {
      final run = _Run(_tracker());
      final boxes = [
        potholeBox(centerX: 0.2, centerY: 0.7),
        potholeBox(centerX: 0.8, centerY: 0.7),
      ];
      run.frame(boxes);
      expect(run.frame(boxes), hasLength(2));
    });

    test('reset forgets every track', () {
      final run = _Run(_tracker());
      run.frame([potholeBox(centerX: 0.5, centerY: 0.7)]);
      run.tracker.reset();
      expect(run.tracker.activeTrackCount, 0);
      expect(run.frame([potholeBox(centerX: 0.5, centerY: 0.7)]), isEmpty);
    });

    test('rejects an inconsistent window', () {
      expect(
        () => TemporalConfirmationTracker(requiredHits: 0, windowSize: 3),
        throwsArgumentError,
      );
      expect(
        () => TemporalConfirmationTracker(requiredHits: 4, windowSize: 3),
        throwsArgumentError,
      );
    });
  });

  // **Validates: Requirements RF-04.8–11** (task 78.6)
  Glados2<List<bool>, List<int>>(
    any.listWithLengthInRange(1, 40, any.bool),
    any.listWithLengthInRange(40, 41, any.intInRange(35, 101)),
    ExploreConfig(numRuns: 200),
  ).test('a static pothole confirms only with 2 of the last 3 frames',
      (List<bool> presence, List<int> confidences) {
    final run = _Run(_tracker());
    var lastConfirmation = -1;
    for (var i = 0; i < presence.length; i++) {
      final boxes = presence[i]
          ? [
              potholeBox(
                centerX: 0.5,
                centerY: 0.7,
                confidence: confidences[i] / 100,
              ),
            ]
          : const <DetectionBox>[];
      final confirmed = run.frame(boxes);
      expect(confirmed.length, lessThanOrEqualTo(1));
      if (confirmed.isEmpty) {
        continue;
      }

      final windowStart = i >= 2 ? i - 2 : 0;
      final hits = <int>[
        for (var j = windowStart; j <= i; j++)
          if (presence[j]) j,
      ];
      expect(presence[i], isTrue, reason: 'confirmed on a frame with a box');
      expect(hits.length, greaterThanOrEqualTo(2));
      expect(
        confirmed.single.confidence,
        hits.map((j) => confidences[j] / 100).reduce((a, b) => a > b ? a : b),
      );
      // Suppression: a new confirmation needs 3 misses in between.
      if (lastConfirmation >= 0) {
        var longestGap = 0;
        var gap = 0;
        for (var j = lastConfirmation + 1; j < i; j++) {
          gap = presence[j] ? 0 : gap + 1;
          longestGap = gap > longestGap ? gap : longestGap;
        }
        expect(longestGap, greaterThanOrEqualTo(3));
      }
      lastConfirmation = i;
    }
    expect(run.tracker.activeTrackCount, lessThanOrEqualTo(1));
  });

  Glados<List<int>>(
    any.listWithLengthInRange(1, 30, any.intInRange(0, 4)),
    ExploreConfig(numRuns: 150),
  ).test('tracks stay bounded by the boxes of the recent frames',
      (List<int> boxesPerFrame) {
    final run = _Run(_tracker());
    for (var i = 0; i < boxesPerFrame.length; i++) {
      run.frame([
        for (var b = 0; b < boxesPerFrame[i]; b++)
          potholeBox(centerX: 0.1 + 0.25 * b + 0.01 * (i % 3), centerY: 0.5),
      ]);
      final recent = boxesPerFrame
          .sublist(i >= 2 ? i - 2 : 0, i + 1)
          .fold<int>(0, (sum, value) => sum + value);
      expect(run.tracker.activeTrackCount, lessThanOrEqualTo(recent));
    }
  });
}
