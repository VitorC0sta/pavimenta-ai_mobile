import '../operational_configuration.dart';

/// Effective detection values derived from [OperationalConfiguration].
///
/// This is the only E5 reader of the operational detection fields (E5.15);
/// the rest of the detection code receives these effective values.
final class DetectionParameters {
  const DetectionParameters._({
    required this.minimumConfidence,
    required this.framesPerSecond,
    required this.fpsFallbackApplied,
    required this.requiredHits,
    required this.windowSize,
    required this.maximumAreaRatio,
  });

  factory DetectionParameters.fromConfiguration(
    OperationalConfiguration configuration,
  ) {
    final savedFps = configuration.maximumInferenceFps;
    final fpsInDomain = savedFps.isFinite &&
        savedFps == savedFps.roundToDouble() &&
        savedFps >= minimumFps &&
        savedFps <= maximumFps;

    final savedThreshold = configuration.confidenceThreshold;
    final threshold =
        savedThreshold.isFinite && savedThreshold >= 0 && savedThreshold <= 1
            ? savedThreshold
            : OperationalConfiguration.defaultConfidenceThreshold;

    final required = configuration.confirmationRequiredFrames;
    final window = configuration.confirmationWindowFrames;
    if (required < 1 || window < required) {
      throw ArgumentError(
        'Confirmation needs 1 <= required frames <= window frames.',
      );
    }
    final areaRatio = configuration.maximumBoxAreaRatio;
    if (!areaRatio.isFinite || areaRatio <= 0 || areaRatio > 1) {
      throw ArgumentError('Maximum box area ratio must be in (0, 1].');
    }

    return DetectionParameters._(
      minimumConfidence: threshold,
      framesPerSecond: fpsInDomain ? savedFps.toInt() : fallbackFps,
      fpsFallbackApplied: !fpsInDomain,
      requiredHits: required,
      windowSize: window,
      maximumAreaRatio: areaRatio,
    );
  }

  /// FPS domain accepted by E5 (design D5).
  static const int minimumFps = 1;
  static const int maximumFps = 15;
  static const int fallbackFps = 5;

  /// Confidence threshold applied by the filter and passed to the plugin.
  final double minimumConfidence;

  /// Inference rate limit applied by the plugin and the rate gate.
  final int framesPerSecond;

  /// True when the saved FPS was outside 1–15 and [fallbackFps] is used.
  final bool fpsFallbackApplied;

  /// Frames with a compatible box needed to confirm a track.
  final int requiredHits;

  /// Number of most recent processed frames the confirmation looks at.
  final int windowSize;

  /// Largest accepted box area, as a fraction of the frame area.
  final double maximumAreaRatio;

  @override
  bool operator ==(Object other) =>
      other is DetectionParameters &&
      other.minimumConfidence == minimumConfidence &&
      other.framesPerSecond == framesPerSecond &&
      other.fpsFallbackApplied == fpsFallbackApplied &&
      other.requiredHits == requiredHits &&
      other.windowSize == windowSize &&
      other.maximumAreaRatio == maximumAreaRatio;

  @override
  int get hashCode => Object.hash(
        minimumConfidence,
        framesPerSecond,
        fpsFallbackApplied,
        requiredHits,
        windowSize,
        maximumAreaRatio,
      );
}
