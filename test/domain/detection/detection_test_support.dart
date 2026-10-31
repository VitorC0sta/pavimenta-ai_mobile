import 'package:pavimenta_ai_mobile/domain/detection/detection_frame.dart';

/// Pothole box from normalized center and size.
DetectionBox potholeBox({
  required double centerX,
  required double centerY,
  double width = 0.1,
  double height = 0.1,
  double confidence = 0.6,
  int classIndex = 0,
  String className = 'buraco',
}) =>
    DetectionBox(
      classIndex: classIndex,
      className: className,
      confidence: confidence,
      left: centerX - width / 2,
      top: centerY - height / 2,
      right: centerX + width / 2,
      bottom: centerY + height / 2,
    );

final DateTime detectionEpoch = DateTime.utc(2026, 10, 30, 12);

DateTime frameTime(int index, {int fps = 5}) => detectionEpoch.add(
      Duration(microseconds: index * Duration.microsecondsPerSecond ~/ fps),
    );
