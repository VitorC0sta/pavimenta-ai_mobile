import '../../domain/detection/detection_frame.dart';
import '../../domain/detection/detection_parameters.dart';

/// Source of processed frames and model state, implemented by the plugin
/// adapter (E5.6). Frames arrive only while the preview is active.
abstract interface class AutomaticDetectionPort {
  /// One event per processed frame, including frames without boxes.
  Stream<DetectionFrame> get frames;

  Stream<DetectionModelStatus> get modelStatus;

  /// Applies threshold and FPS to the plugin.
  Future<void> applyParameters(DetectionParameters parameters);
}
