import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/detection/detection_parameters.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';

OperationalConfiguration _config({
  double threshold = 0.35,
  double fps = 5,
  int required = 2,
  int window = 3,
  double area = 0.20,
}) =>
    OperationalConfiguration(
      baseUrl: null,
      cooldown: const Duration(seconds: 5),
      minimumDistanceMeters: 15,
      confidenceThreshold: threshold,
      maximumInferenceFps: fps,
      confirmationRequiredFrames: required,
      confirmationWindowFrames: window,
      maximumBoxAreaRatio: area,
    );

void main() {
  // **Validates: Requirements RF-04.2–3, RF-04.8, RF-04.12** (task 78.1)
  group('OperationalConfiguration E5 fields', () {
    test('default to 2 of 3 frames and 20% area in code', () {
      const defaults = OperationalConfiguration.defaults();
      expect(defaults.confirmationRequiredFrames, 2);
      expect(defaults.confirmationWindowFrames, 3);
      expect(defaults.maximumBoxAreaRatio, 0.20);
      expect(OperationalConfiguration.currentStorageVersion, 1);
    });

    test('keep the defaults when built from the stored E3 fields only', () {
      const stored = OperationalConfiguration(
        baseUrl: null,
        cooldown: Duration(seconds: 5),
        minimumDistanceMeters: 15,
        confidenceThreshold: 0.4,
        maximumInferenceFps: 8,
      );
      expect(stored.confirmationRequiredFrames, 2);
      expect(stored.confirmationWindowFrames, 3);
      expect(stored.maximumBoxAreaRatio, 0.20);
    });
  });

  group('DetectionParameters', () {
    test('uses the saved threshold, FPS and code defaults', () {
      final parameters = DetectionParameters.fromConfiguration(_config());
      expect(parameters.minimumConfidence, 0.35);
      expect(parameters.framesPerSecond, 5);
      expect(parameters.fpsFallbackApplied, isFalse);
      expect(parameters.requiredHits, 2);
      expect(parameters.windowSize, 3);
      expect(parameters.maximumAreaRatio, 0.20);
    });

    test('accepts every integer FPS from 1 to 15', () {
      for (var fps = 1; fps <= 15; fps++) {
        final parameters = DetectionParameters.fromConfiguration(
          _config(fps: fps.toDouble()),
        );
        expect(parameters.framesPerSecond, fps);
        expect(parameters.fpsFallbackApplied, isFalse);
      }
    });

    test('falls back to 5 FPS outside the E5 domain', () {
      for (final fps in <double>[
        0,
        0.5,
        2.5,
        16,
        30,
        -1,
        double.nan,
        double.infinity,
      ]) {
        final parameters =
            DetectionParameters.fromConfiguration(_config(fps: fps));
        expect(parameters.framesPerSecond, 5, reason: 'fps $fps');
        expect(parameters.fpsFallbackApplied, isTrue, reason: 'fps $fps');
      }
    });

    test('falls back to the default threshold when the saved one is invalid',
        () {
      for (final threshold in <double>[-0.1, 1.1, double.nan]) {
        expect(
          DetectionParameters.fromConfiguration(_config(threshold: threshold))
              .minimumConfidence,
          OperationalConfiguration.defaultConfidenceThreshold,
        );
      }
    });

    test('rejects an inconsistent confirmation window or area in code', () {
      expect(
        () => DetectionParameters.fromConfiguration(_config(required: 0)),
        throwsArgumentError,
      );
      expect(
        () => DetectionParameters.fromConfiguration(
          _config(required: 4, window: 3),
        ),
        throwsArgumentError,
      );
      expect(
        () => DetectionParameters.fromConfiguration(_config(area: 0)),
        throwsArgumentError,
      );
      expect(
        () => DetectionParameters.fromConfiguration(_config(area: 1.5)),
        throwsArgumentError,
      );
    });

    test('compares by value', () {
      expect(
        DetectionParameters.fromConfiguration(_config()),
        DetectionParameters.fromConfiguration(_config()),
      );
      expect(
        DetectionParameters.fromConfiguration(_config()),
        isNot(DetectionParameters.fromConfiguration(_config(fps: 10))),
      );
    });
  });
}
