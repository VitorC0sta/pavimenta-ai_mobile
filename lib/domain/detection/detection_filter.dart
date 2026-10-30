import 'detection_frame.dart';
import 'pothole_model_descriptor.dart';

/// Keeps only valid pothole boxes at or above the confidence threshold and
/// at or below the maximum area (E5.7 step 3, RF-04.6, RF-04.12).
final class DetectionFilter {
  const DetectionFilter({
    required this.minimumConfidence,
    required this.maximumAreaRatio,
  });

  /// How far outside [0, 1] a normalized coordinate may be before the box is
  /// rejected. The plugin un-letterboxes with small rounding overshoots
  /// (checkpoint 76 saw -0.03 and 1.007); inside this margin the box is
  /// clamped to the frame.
  static const double coordinateTolerance = 0.05;

  final double minimumConfidence;
  final double maximumAreaRatio;

  /// Returns the accepted boxes, clamped to the frame, in input order.
  List<DetectionBox> apply(List<DetectionBox> boxes) => <DetectionBox>[
        for (final box in boxes)
          if (_accept(box) case final DetectionBox accepted) accepted,
      ];

  DetectionBox? _accept(DetectionBox box) {
    final contractClass = PotholeModelDescriptor.contractClassFor(
      classIndex: box.classIndex,
      className: box.className,
    );
    if (contractClass == null) {
      return null;
    }
    final confidence = box.confidence;
    if (!confidence.isFinite ||
        confidence < minimumConfidence ||
        confidence > 1) {
      return null;
    }
    final coordinates = <double>[box.left, box.top, box.right, box.bottom];
    for (final value in coordinates) {
      if (!value.isFinite ||
          value < -coordinateTolerance ||
          value > 1 + coordinateTolerance) {
        return null;
      }
    }

    final clamped = DetectionBox(
      classIndex: box.classIndex,
      className: box.className,
      confidence: confidence,
      left: _clamp(box.left),
      top: _clamp(box.top),
      right: _clamp(box.right),
      bottom: _clamp(box.bottom),
    );
    if (clamped.width <= 0 || clamped.height <= 0) {
      return null;
    }
    if (clamped.area > maximumAreaRatio) {
      return null;
    }
    return clamped;
  }

  static double _clamp(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);
}
