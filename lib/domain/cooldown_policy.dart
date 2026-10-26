import 'distance_calculator.dart';
import 'in_memory_occurrence.dart';
import 'location_snapshot.dart';
import 'persistent_occurrence.dart';

/// Immutable result of evaluating one candidate against the E1 cooldown.
final class CooldownDecision {
  const CooldownDecision._({
    required this.isAllowed,
    required this.isFirstOccurrence,
    required this.elapsed,
    required this.distanceMeters,
  });

  const CooldownDecision.firstOccurrence()
      : this._(
          isAllowed: true,
          isFirstOccurrence: true,
          elapsed: null,
          distanceMeters: null,
        );

  const CooldownDecision.allowed({
    required Duration elapsed,
    required double distanceMeters,
  }) : this._(
          isAllowed: true,
          isFirstOccurrence: false,
          elapsed: elapsed,
          distanceMeters: distanceMeters,
        );

  const CooldownDecision.blocked({
    required Duration elapsed,
    required double distanceMeters,
  }) : this._(
          isAllowed: false,
          isFirstOccurrence: false,
          elapsed: elapsed,
          distanceMeters: distanceMeters,
        );

  final bool isAllowed;
  final bool isFirstOccurrence;
  final Duration? elapsed;
  final double? distanceMeters;

  bool get isBlocked => !isAllowed;
}

/// Source-independent cooldown boundary used by the shared processor.
abstract interface class CandidateCooldown {
  CooldownDecision evaluate(DateTime attemptedAt, GeoPoint point);

  void commit(InMemoryOccurrence occurrence);
}

/// Restores the cooldown reference from the queue recovery confirmed by E2.
///
/// This boundary is separate from candidate evaluation so queue bootstrap can
/// restore state without being treated as a new occurrence acceptance.
abstract interface class CooldownReferenceRestorer {
  void restoreRecoveredPending(
    Iterable<ReconstructedPendingOccurrence> pending,
  );
}

/// In-memory E1 cooldown using elapsed time OR geographic distance.
///
/// Evaluation never changes the reference. The caller can advance it only by
/// committing an already-created, fully valid occurrence.
final class CooldownPolicy
    implements CandidateCooldown, CooldownReferenceRestorer {
  factory CooldownPolicy({
    DistanceCalculator distanceCalculator = const HaversineDistanceCalculator(),
    Duration minimumElapsed = const Duration(seconds: 5),
    double minimumDistanceMeters = 15,
  }) {
    if (minimumElapsed <= Duration.zero) {
      throw ArgumentError.value(
        minimumElapsed,
        'minimumElapsed',
        'must be positive',
      );
    }
    if (!minimumDistanceMeters.isFinite || minimumDistanceMeters <= 0) {
      throw ArgumentError.value(
        minimumDistanceMeters,
        'minimumDistanceMeters',
        'must be finite and positive',
      );
    }
    return CooldownPolicy._(
      distanceCalculator: distanceCalculator,
      minimumElapsed: minimumElapsed,
      minimumDistanceMeters: minimumDistanceMeters,
    );
  }

  CooldownPolicy._({
    required DistanceCalculator distanceCalculator,
    required this.minimumElapsed,
    required this.minimumDistanceMeters,
  }) : _distanceCalculator = distanceCalculator;

  final DistanceCalculator _distanceCalculator;
  final Duration minimumElapsed;
  final double minimumDistanceMeters;

  _CooldownReference? _lastCreated;

  @override
  CooldownDecision evaluate(DateTime attemptedAt, GeoPoint point) {
    final candidatePoint = ImmutableGeoPoint(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    final lastCreated = _lastCreated;
    if (lastCreated == null) {
      return const CooldownDecision.firstOccurrence();
    }

    final rawElapsed = attemptedAt.difference(lastCreated.detectedAt);
    final elapsed = rawElapsed.isNegative ? Duration.zero : rawElapsed;
    final distanceMeters = _distanceCalculator.metersBetween(
      lastCreated.point,
      candidatePoint,
    );
    if (!distanceMeters.isFinite || distanceMeters < 0) {
      throw StateError(
        'DistanceCalculator must return a finite, non-negative distance.',
      );
    }

    if (elapsed >= minimumElapsed || distanceMeters >= minimumDistanceMeters) {
      return CooldownDecision.allowed(
        elapsed: elapsed,
        distanceMeters: distanceMeters,
      );
    }
    return CooldownDecision.blocked(
      elapsed: elapsed,
      distanceMeters: distanceMeters,
    );
  }

  /// Advances cooldown only after a complete occurrence has been created.
  @override
  void commit(InMemoryOccurrence occurrence) {
    _lastCreated = _CooldownReference(
      detectedAt: occurrence.detectedAt,
      point: occurrence.location.point,
    );
  }

  /// Restores the last durable acceptance without treating recovery as a
  /// session creation. Queue sequence, rather than wall-clock order, is the
  /// authoritative acceptance order.
  @override
  void restoreRecoveredPending(
    Iterable<ReconstructedPendingOccurrence> pending,
  ) {
    ReconstructedPendingOccurrence? lastAccepted;
    for (final occurrence in pending) {
      final current = lastAccepted;
      if (current == null || occurrence.queueSequence > current.queueSequence) {
        lastAccepted = occurrence;
      }
    }

    if (lastAccepted == null) {
      _lastCreated = null;
      return;
    }

    _lastCreated = _CooldownReference(
      detectedAt: DateTime.parse(lastAccepted.detectedAtIso8601),
      point: ImmutableGeoPoint(
        latitude: lastAccepted.latitude,
        longitude: lastAccepted.longitude,
      ),
    );
  }
}

final class _CooldownReference {
  const _CooldownReference({
    required this.detectedAt,
    required this.point,
  });

  final DateTime detectedAt;
  final ImmutableGeoPoint point;
}
