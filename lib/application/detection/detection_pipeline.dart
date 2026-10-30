import 'dart:async';

import '../../domain/detection/detection_filter.dart';
import '../../domain/detection/detection_frame.dart';
import '../../domain/detection/detection_parameters.dart';
import '../../domain/detection/inference_fps_meter.dart';
import '../../domain/detection/inference_rate_gate.dart';
import '../../domain/detection/temporal_confirmation_tracker.dart';

/// Outcome of one frame through the pipeline.
final class DetectionStep {
  const DetectionStep({
    required this.accepted,
    required this.confirmations,
    required this.measuredFps,
  });

  /// False when the rate gate dropped the frame.
  final bool accepted;
  final List<ConfirmedDetection> confirmations;
  final double measuredFps;
}

/// Composes rate gate, FPS meter, filter and temporal confirmation (E5.7).
///
/// Frames are processed one at a time as they arrive; nothing is buffered.
/// Busy-controller discarding (step 5) belongs to the consumer.
final class DetectionPipeline {
  DetectionPipeline({required DetectionParameters parameters})
      : _parameters = parameters {
    _rebuild();
  }

  final InferenceFpsMeter _meter = InferenceFpsMeter();
  final StreamController<ConfirmedDetection> _confirmations =
      StreamController<ConfirmedDetection>.broadcast();
  final StreamController<double> _measuredFps =
      StreamController<double>.broadcast();

  DetectionParameters _parameters;
  late InferenceRateGate _gate;
  late DetectionFilter _filter;
  late TemporalConfirmationTracker _tracker;
  StreamSubscription<DetectionFrame>? _subscription;
  bool _closed = false;

  DetectionParameters get parameters => _parameters;

  Stream<ConfirmedDetection> get confirmations => _confirmations.stream;

  /// Measured FPS, published after each accepted frame.
  Stream<double> get measuredFps => _measuredFps.stream;

  /// Measured FPS over the window ending at [now], for a display that must
  /// decay when frames stop.
  double measuredFpsAt(DateTime now) => _meter.framesPerSecondAt(now);

  /// Runs one frame synchronously and returns its outcome.
  DetectionStep process(DetectionFrame frame) {
    if (!_gate.tryAccept(frame.observedAt)) {
      return DetectionStep(
        accepted: false,
        confirmations: const <ConfirmedDetection>[],
        measuredFps: _meter.framesPerSecondAt(frame.observedAt),
      );
    }
    _meter.record(frame.observedAt);
    final confirmations = _tracker.process(
      observedAt: frame.observedAt,
      imageWidth: frame.imageWidth,
      imageHeight: frame.imageHeight,
      boxes: _filter.apply(frame.boxes),
    );
    return DetectionStep(
      accepted: true,
      confirmations: List<ConfirmedDetection>.unmodifiable(confirmations),
      measuredFps: _meter.framesPerSecondAt(frame.observedAt),
    );
  }

  /// Consumes [frames] and publishes confirmations and measured FPS until
  /// [stop]. Any previous source is stopped first.
  Future<void> start(Stream<DetectionFrame> frames) async {
    _ensureOpen();
    await stop();
    reset();
    _subscription = frames.listen(_onFrame);
  }

  /// Stops consuming frames. Tracks, gate and meter are reset.
  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    reset();
  }

  /// Replaces the parameters and restarts the detection state.
  void applyParameters(DetectionParameters parameters) {
    _ensureOpen();
    _parameters = parameters;
    _rebuild();
  }

  /// Clears tracks, gate and meter (operational mode lost, route return).
  void reset() {
    _gate.reset();
    _meter.reset();
    _tracker.reset();
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    await stop();
    _closed = true;
    await _confirmations.close();
    await _measuredFps.close();
  }

  void _onFrame(DetectionFrame frame) {
    if (_closed) {
      return;
    }
    final step = process(frame);
    if (!step.accepted) {
      return;
    }
    _measuredFps.add(step.measuredFps);
    for (final confirmation in step.confirmations) {
      _confirmations.add(confirmation);
    }
  }

  void _rebuild() {
    _gate = InferenceRateGate(framesPerSecond: _parameters.framesPerSecond);
    _filter = DetectionFilter(
      minimumConfidence: _parameters.minimumConfidence,
      maximumAreaRatio: _parameters.maximumAreaRatio,
    );
    _tracker = TemporalConfirmationTracker(
      requiredHits: _parameters.requiredHits,
      windowSize: _parameters.windowSize,
    );
    _meter.reset();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('DetectionPipeline is closed.');
    }
  }
}
