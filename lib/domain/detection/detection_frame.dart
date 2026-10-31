/// Model lifecycle reported by the automatic detection adapter.
enum DetectionModelStatus { loading, loaded, failed }

/// One box reported by the model for a frame.
///
/// Coordinates are normalized to the full original frame. The plugin may
/// report values slightly outside [0, 1]; the detection filter decides how to
/// treat them.
final class DetectionBox {
  const DetectionBox({
    required this.classIndex,
    required this.className,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int classIndex;
  final String className;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;
}

/// Result of one processed frame. A frame without detections has no boxes.
///
/// The frame itself is never carried: only its size and the boxes.
final class DetectionFrame {
  DetectionFrame({
    required this.observedAt,
    required this.imageWidth,
    required this.imageHeight,
    required List<DetectionBox> boxes,
  }) : boxes = List<DetectionBox>.unmodifiable(boxes) {
    if (imageWidth <= 0 || imageHeight <= 0) {
      throw ArgumentError('Frame dimensions must be positive.');
    }
  }

  /// Clock value read when the result arrived.
  final DateTime observedAt;

  /// Original frame size in pixels.
  final int imageWidth;
  final int imageHeight;

  final List<DetectionBox> boxes;
}

/// A detection confirmed by the temporal rule, ready for the candidate path.
final class ConfirmedDetection {
  const ConfirmedDetection({
    required this.observedAt,
    required this.confidence,
  });

  /// Instant of the confirming frame.
  final DateTime observedAt;

  /// Highest confidence of the confirmed track inside the window.
  final double confidence;
}
