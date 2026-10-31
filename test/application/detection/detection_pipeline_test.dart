import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;
import 'package:pavimenta_ai_mobile/application/detection/detection_pipeline.dart';
import 'package:pavimenta_ai_mobile/application/detection/model_preflight_port.dart';
import 'package:pavimenta_ai_mobile/domain/detection/detection_frame.dart';
import 'package:pavimenta_ai_mobile/domain/detection/detection_parameters.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';

import '../../domain/detection/detection_test_support.dart';

DetectionParameters _parameters({double threshold = 0.35, double fps = 5}) =>
    DetectionParameters.fromConfiguration(
      OperationalConfiguration(
        baseUrl: null,
        cooldown: const Duration(seconds: 5),
        minimumDistanceMeters: 15,
        confidenceThreshold: threshold,
        maximumInferenceFps: fps,
      ),
    );

DetectionFrame _frame(int index, List<DetectionBox> boxes, {int fps = 5}) =>
    DetectionFrame(
      observedAt: frameTime(index, fps: fps),
      imageWidth: 1280,
      imageHeight: 720,
      boxes: boxes,
    );

final _pothole = potholeBox(centerX: 0.5, centerY: 0.7, confidence: 0.6);

void main() {
  // **Validates: Requirements RF-04.2–6, RF-04.8–12, RNF-04.5** (task 78.5)
  group('DetectionPipeline', () {
    test('confirms a pothole seen in 2 accepted frames', () {
      final pipeline = DetectionPipeline(parameters: _parameters());
      expect(pipeline.process(_frame(0, [_pothole])).confirmations, isEmpty);
      final step = pipeline.process(_frame(1, [_pothole]));
      expect(step.accepted, isTrue);
      expect(step.confirmations.single.confidence, 0.6);
      expect(step.measuredFps, 1);
    });

    test('frames dropped by the gate do not count for confirmation', () {
      final pipeline = DetectionPipeline(parameters: _parameters());
      pipeline.process(_frame(0, [_pothole]));
      // 10 FPS arrivals against a 5 FPS limit: frame 1 arrives after 100 ms.
      final dropped = pipeline.process(_frame(1, [_pothole], fps: 10));
      expect(dropped.accepted, isFalse);
      expect(dropped.confirmations, isEmpty);
      expect(
        pipeline.process(_frame(2, [_pothole], fps: 10)).confirmations,
        hasLength(1),
      );
    });

    test('boxes below the threshold never reach the tracker', () {
      final pipeline =
          DetectionPipeline(parameters: _parameters(threshold: 0.7));
      for (var i = 0; i < 5; i++) {
        expect(
          pipeline.process(_frame(i, [_pothole])).confirmations,
          isEmpty,
        );
      }
    });

    test('empty frames are accepted and measured', () {
      final pipeline = DetectionPipeline(parameters: _parameters());
      for (var i = 0; i < 10; i++) {
        expect(pipeline.process(_frame(i, const [])).accepted, isTrue);
      }
      expect(pipeline.measuredFpsAt(frameTime(9)), 5);
      expect(
        pipeline.measuredFpsAt(frameTime(9).add(const Duration(seconds: 3))),
        0,
      );
    });

    test('changing parameters restarts tracks and applies the new rules', () {
      final pipeline = DetectionPipeline(parameters: _parameters());
      pipeline.process(_frame(0, [_pothole]));
      pipeline.applyParameters(_parameters(threshold: 0.5, fps: 10));
      expect(pipeline.parameters.framesPerSecond, 10);
      expect(
        pipeline.process(_frame(1, [_pothole], fps: 10)).confirmations,
        isEmpty,
        reason: 'the track of frame 0 was discarded',
      );
      expect(
        pipeline.process(_frame(2, [_pothole], fps: 10)).confirmations,
        hasLength(1),
        reason: '100 ms passes the 10 FPS gate',
      );
    });

    test('reset discards the pending track', () {
      final pipeline = DetectionPipeline(parameters: _parameters());
      pipeline.process(_frame(0, [_pothole]));
      pipeline.reset();
      expect(pipeline.process(_frame(1, [_pothole])).confirmations, isEmpty);
    });

    test('publishes confirmations and FPS from a frame stream', () async {
      final pipeline = DetectionPipeline(parameters: _parameters());
      final source = StreamController<DetectionFrame>();
      final confirmations = <ConfirmedDetection>[];
      final fps = <double>[];
      pipeline.confirmations.listen(confirmations.add);
      pipeline.measuredFps.listen(fps.add);

      await pipeline.start(source.stream);
      source
        ..add(_frame(0, [_pothole]))
        ..add(_frame(1, [_pothole]))
        ..add(_frame(1, [_pothole]));
      await pumpEventQueue();

      expect(confirmations, hasLength(1));
      expect(fps, <double>[0.5, 1], reason: 'the duplicate was dropped');

      await pipeline.stop();
      source.add(_frame(5, [_pothole]));
      source.add(_frame(6, [_pothole]));
      await pumpEventQueue();
      expect(confirmations, hasLength(1), reason: 'stopped pipeline is idle');

      await pipeline.close();
      await source.close();
      expect(() => pipeline.applyParameters(_parameters()), throwsStateError);
    });

    test('preflight reasons expose only fixed categories', () {
      expect(
        ModelUnavailableReason.values.map((reason) => reason.category),
        <String>[
          'model_metadata_mismatch',
          'model_load_failed',
          'model_load_timeout',
        ],
      );
      expect(ModelPreflightPort.timeout, const Duration(seconds: 15));
    });
  });

  // **Validates: Requirements RF-04.3, RF-04.8, RNF-04.5** (task 78.6)
  Glados2<List<int>, List<bool>>(
    any.listWithLengthInRange(2, 50, any.intInRange(20, 400)),
    any.listWithLengthInRange(50, 51, any.bool),
    ExploreConfig(numRuns: 150),
  ).test('jittered arrival never confirms from a single accepted frame',
      (List<int> gapsMs, List<bool> presence) {
    final pipeline = DetectionPipeline(parameters: _parameters());
    var now = detectionEpoch;
    final acceptedPresence = <bool>[];
    for (var i = 0; i < gapsMs.length; i++) {
      now = now.add(Duration(milliseconds: gapsMs[i]));
      final step = pipeline.process(
        DetectionFrame(
          observedAt: now,
          imageWidth: 1280,
          imageHeight: 720,
          boxes: presence[i] ? [_pothole] : const <DetectionBox>[],
        ),
      );
      if (!step.accepted) {
        expect(step.confirmations, isEmpty);
        continue;
      }
      acceptedPresence.add(presence[i]);
      if (step.confirmations.isNotEmpty) {
        final n = acceptedPresence.length;
        final window =
            acceptedPresence.sublist(n >= 3 ? n - 3 : 0).where((p) => p);
        expect(window.length, greaterThanOrEqualTo(2));
      }
    }
  });
}
