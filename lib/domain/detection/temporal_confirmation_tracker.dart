import 'dart:math' as math;

import 'detection_frame.dart';

/// Temporal N-of-M confirmation over processed frames (E5.7 step 4).
///
/// Tracks keep only the last box geometry and a bounded window of hits; no
/// frame or box list is accumulated.
final class TemporalConfirmationTracker {
  TemporalConfirmationTracker({
    required this.requiredHits,
    required this.windowSize,
  }) {
    if (requiredHits < 1 || windowSize < requiredHits) {
      throw ArgumentError('Confirmation needs 1 <= requiredHits <= window.');
    }
  }

  /// A confirmed track ends after this many consecutive frames without a
  /// compatible box (RF-04.11). Technical constant.
  static const int suppressionMisses = 3;

  final int requiredHits;
  final int windowSize;

  final List<_Track> _tracks = <_Track>[];

  int get activeTrackCount => _tracks.length;

  /// Processes one frame of already filtered [boxes] and returns the tracks
  /// confirmed by it. Empty frames count in the window.
  List<ConfirmedDetection> process({
    required DateTime observedAt,
    required int imageWidth,
    required int imageHeight,
    required List<DetectionBox> boxes,
  }) {
    final candidates = <_PixelBox>[
      for (final box in boxes) _PixelBox.from(box, imageWidth, imageHeight),
    ];

    // Greedy association by the smallest center distance.
    final pairs = <_Pair>[];
    for (var t = 0; t < _tracks.length; t++) {
      final last = _tracks[t].lastBox;
      for (var b = 0; b < candidates.length; b++) {
        final distance = last.centerDistanceTo(candidates[b]);
        if (distance < math.max(last.largestSide, candidates[b].largestSide)) {
          pairs.add(_Pair(t, b, distance));
        }
      }
    }
    pairs.sort((a, b) => a.distance.compareTo(b.distance));
    final matchedTracks = <int>{};
    final matchedBoxes = <int, int>{};
    for (final pair in pairs) {
      if (matchedTracks.contains(pair.track) ||
          matchedBoxes.containsKey(pair.box)) {
        continue;
      }
      matchedTracks.add(pair.track);
      matchedBoxes[pair.box] = pair.track;
    }

    final trackHits = <int, _PixelBox>{
      for (final entry in matchedBoxes.entries)
        entry.value: candidates[entry.key],
    };
    for (var t = 0; t < _tracks.length; t++) {
      _tracks[t].advance(trackHits[t], windowSize);
    }
    for (var b = 0; b < candidates.length; b++) {
      if (!matchedBoxes.containsKey(b)) {
        _tracks.add(_Track(candidates[b]));
      }
    }

    final confirmations = <ConfirmedDetection>[];
    for (final track in _tracks) {
      if (!track.confirmed && track.hitCount >= requiredHits) {
        track.confirmed = true;
        confirmations.add(
          ConfirmedDetection(
            observedAt: observedAt,
            confidence: track.highestConfidence,
          ),
        );
      }
    }

    _tracks.removeWhere(
      (track) => track.confirmed
          ? track.consecutiveMisses >= suppressionMisses
          : track.hitCount == 0,
    );
    return confirmations;
  }

  void reset() => _tracks.clear();
}

final class _Track {
  _Track(_PixelBox first)
      : lastBox = first,
        _window = <double?>[first.confidence];

  _PixelBox lastBox;
  bool confirmed = false;
  int consecutiveMisses = 0;

  /// Confidence of the compatible box per processed frame, `null` for a
  /// miss; at most `windowSize` entries.
  final List<double?> _window;

  int get hitCount => _window.whereType<double>().length;

  double get highestConfidence => _window.whereType<double>().reduce(math.max);

  void advance(_PixelBox? hit, int windowSize) {
    _window.add(hit?.confidence);
    if (_window.length > windowSize) {
      _window.removeAt(0);
    }
    if (hit == null) {
      consecutiveMisses++;
    } else {
      consecutiveMisses = 0;
      lastBox = hit;
    }
  }
}

final class _PixelBox {
  const _PixelBox({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.confidence,
  });

  factory _PixelBox.from(DetectionBox box, int imageWidth, int imageHeight) =>
      _PixelBox(
        centerX: (box.left + box.right) / 2 * imageWidth,
        centerY: (box.top + box.bottom) / 2 * imageHeight,
        width: box.width * imageWidth,
        height: box.height * imageHeight,
        confidence: box.confidence,
      );

  final double centerX;
  final double centerY;
  final double width;
  final double height;
  final double confidence;

  double get largestSide => math.max(width, height);

  double centerDistanceTo(_PixelBox other) {
    final dx = centerX - other.centerX;
    final dy = centerY - other.centerY;
    return math.sqrt(dx * dx + dy * dy);
  }
}

final class _Pair {
  const _Pair(this.track, this.box, this.distance);

  final int track;
  final int box;
  final double distance;
}
