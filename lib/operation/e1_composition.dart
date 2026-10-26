import '../application/e1_ports.dart';
import '../application/post_candidate_processor.dart';
import '../candidate/occurrence_candidate_source.dart';
import '../domain/distance_calculator.dart';

/// Explicit E1 object graph assembled by the application composition root.
///
/// Concrete implementations are intentionally deferred to their owning tasks.
final class E1Composition<TPreview extends Object, TOccurrence> {
  const E1Composition({
    required this.candidateSource,
    required this.postCandidateProcessor,
    required this.camera,
    required this.location,
    required this.imagePreparer,
    required this.clock,
    required this.uuidGenerator,
    required this.distanceCalculator,
    required this.screenAwake,
  });

  final OccurrenceCandidateSource candidateSource;
  final PostCandidateProcessor<TOccurrence> postCandidateProcessor;
  final OperationalCameraPort<TPreview> camera;
  final OperationalLocationPort location;
  final ImagePreparer imagePreparer;
  final Clock clock;
  final UuidGenerator uuidGenerator;
  final DistanceCalculator distanceCalculator;
  final ScreenAwakePort screenAwake;
}
