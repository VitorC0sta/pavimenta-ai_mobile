import '../domain/location_snapshot.dart';
import '../infrastructure/image_artifacts.dart';

/// Deferred acquisition of the image associated with one candidate.
typedef CandidateImageAcquisition = Future<TemporaryCapture> Function();

/// Returns whether the operation that owns a candidate is still current.
///
/// The optional guard lets the application invalidate asynchronous work without
/// coupling candidate sources to Flutter lifecycle or navigation concepts.
typedef CandidateProcessingGuard = bool Function();

/// Announces that the post-candidate flow entered its durable acceptance step.
///
/// The callback is presentation-neutral: it carries no occurrence, queue, or
/// storage data and lets the application expose only an aggregate progress cue.
typedef CandidatePersistenceStarted = void Function();

/// Observation data supplied to a replaceable candidate source.
final class CandidateSeed {
  const CandidateSeed({
    required this.observedAt,
    required this.location,
    required this.acquireImage,
  });

  final DateTime observedAt;
  final LocationSnapshot location;
  final CandidateImageAcquisition acquireImage;
}

/// Source-independent candidate consumed by the shared post-candidate flow.
final class CandidateInput {
  const CandidateInput({
    required this.observedAt,
    required this.location,
    required this.defectClass,
    required this.confidence,
    required this.acquireImage,
    this.processingGuard,
    this.onPersistenceStarted,
  });

  final DateTime observedAt;
  final LocationSnapshot location;
  final String defectClass;
  final double confidence;
  final CandidateImageAcquisition acquireImage;
  final CandidateProcessingGuard? processingGuard;
  final CandidatePersistenceStarted? onPersistenceStarted;

  /// Whether the operation that owns this candidate may still produce effects.
  bool get isProcessingCurrent {
    final guard = processingGuard;
    if (guard == null) {
      return true;
    }
    try {
      return guard();
    } catch (_) {
      return false;
    }
  }

  /// Signals progress exactly when durable acceptance is about to begin.
  void notifyPersistenceStarted() {
    try {
      onPersistenceStarted?.call();
    } catch (_) {
      // Presentation notifications cannot affect durable acceptance.
    }
  }
}

/// Produces normalized candidates without exposing source or network identity.
abstract interface class OccurrenceCandidateSource {
  Future<CandidateInput> requestCandidate(CandidateSeed seed);
}
