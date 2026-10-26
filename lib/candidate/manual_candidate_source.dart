import 'occurrence_candidate_source.dart';

/// Produces normalized candidates for explicit manual pothole confirmations.
///
/// This source preserves the observation data supplied by the operation
/// controller and forwards image acquisition without invoking it. The shared
/// post-candidate processor remains responsible for deciding whether and when
/// the image may be acquired.
final class ManualCandidateSource implements OccurrenceCandidateSource {
  const ManualCandidateSource();

  static const String defectClass = 'pothole';
  static const double confidence = 1.0;

  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) {
    return Future<CandidateInput>.value(
      CandidateInput(
        observedAt: seed.observedAt,
        location: seed.location,
        defectClass: defectClass,
        confidence: confidence,
        acquireImage: seed.acquireImage,
      ),
    );
  }
}
