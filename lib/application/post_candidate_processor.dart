import '../candidate/occurrence_candidate_source.dart';
import '../domain/cooldown_policy.dart';
import '../domain/in_memory_occurrence.dart';
import '../domain/location_snapshot.dart';
import '../infrastructure/image_artifacts.dart';
import 'e1_ports.dart';
import 'occurrence_acceptance_port.dart';

/// Generic outcome of processing a source-independent candidate.
sealed class CandidateResult<TOccurrence> {
  const CandidateResult();
}

/// A complete occurrence was created in memory.
final class CandidateCreated<TOccurrence> extends CandidateResult<TOccurrence> {
  const CandidateCreated(this.occurrence);

  final TOccurrence occurrence;
}

/// Both elapsed time and travelled distance remain below their limits.
final class CandidateBlockedByCooldown<TOccurrence>
    extends CandidateResult<TOccurrence> {
  const CandidateBlockedByCooldown({
    required this.elapsed,
    required this.distanceMeters,
  });

  final Duration elapsed;
  final double distanceMeters;
}

/// The candidate cannot enter the post-candidate sequence.
enum CandidatePrecondition {
  invalidCandidate,
  invalidLocation,
}

/// Processing stopped before image acquisition or occurrence creation.
final class CandidatePreconditionFailed<TOccurrence>
    extends CandidateResult<TOccurrence> {
  const CandidatePreconditionFailed(this.reason);

  final CandidatePrecondition reason;
}

/// The current lifecycle, route, or owner cancelled processing.
enum CandidateCancellation {
  lifecycleChanged,
  routeChanged,
  disposed,
}

/// Processing was cancelled without publishing a partial occurrence.
final class CandidateCancelled<TOccurrence>
    extends CandidateResult<TOccurrence> {
  const CandidateCancelled(this.reason);

  final CandidateCancellation reason;
}

/// Stage associated with a controlled technical failure.
enum CandidateFailureStage {
  imageAcquisition,
  imagePreparation,
  identityGeneration,
  occurrenceCreation,
  cleanup,
  durableAcceptance,
  unknown,
}

/// Processing failed in a controlled and source-independent way.
final class CandidateFailed<TOccurrence> extends CandidateResult<TOccurrence> {
  const CandidateFailed(this.stage);

  final CandidateFailureStage stage;
}

/// A durable queue already owns an equivalent occurrence, so this operation
/// must not be published as a new success or advance cooldown/session state.
final class CandidateAlreadyPersistedEquivalent<TOccurrence>
    extends CandidateResult<TOccurrence> {
  const CandidateAlreadyPersistedEquivalent();
}

/// Shared post-candidate boundary, independent of manual or future sources.
abstract interface class PostCandidateProcessor<TOccurrence> {
  Future<CandidateResult<TOccurrence>> process(CandidateInput candidate);
}

/// E1 implementation of the shared post-candidate sequence.
///
/// The processor knows only the normalized candidate. It validates and freezes
/// the snapshot before any side effect, applies cooldown before acquisition,
/// and transfers the prepared image to a complete occurrence only after every
/// mandatory step succeeds.
final class E1PostCandidateProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  const E1PostCandidateProcessor({
    required CandidateCooldown cooldown,
    required ImagePreparer imagePreparer,
    required UuidGenerator uuidGenerator,
    required OccurrenceAcceptancePort occurrenceAcceptancePort,
    InMemoryOccurrenceCreator occurrenceCreator =
        const InMemoryOccurrenceFactory(),
  })  : _cooldown = cooldown,
        _imagePreparer = imagePreparer,
        _uuidGenerator = uuidGenerator,
        _occurrenceAcceptancePort = occurrenceAcceptancePort,
        _occurrenceCreator = occurrenceCreator;

  final CandidateCooldown _cooldown;
  final ImagePreparer _imagePreparer;
  final UuidGenerator _uuidGenerator;
  final OccurrenceAcceptancePort _occurrenceAcceptancePort;
  final InMemoryOccurrenceCreator _occurrenceCreator;

  /// Durable-acceptance boundary executed after occurrence creation and before
  /// the cooldown commit.
  OccurrenceAcceptancePort get occurrenceAcceptancePort =>
      _occurrenceAcceptancePort;

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) async {
    if (!candidate.isProcessingCurrent) {
      return const CandidateCancelled(CandidateCancellation.lifecycleChanged);
    }
    if (!_hasValidCandidateFields(candidate)) {
      return const CandidatePreconditionFailed(
        CandidatePrecondition.invalidCandidate,
      );
    }

    final ImmutableLocationSnapshot location;
    try {
      location = ImmutableLocationSnapshot(
        point: candidate.location.point,
        accuracyMeters: candidate.location.accuracyMeters,
        speedMetersPerSecond: candidate.location.speedMetersPerSecond,
      );
    } catch (_) {
      return const CandidatePreconditionFailed(
        CandidatePrecondition.invalidLocation,
      );
    }

    if (!candidate.isProcessingCurrent) {
      return const CandidateCancelled(CandidateCancellation.lifecycleChanged);
    }

    final CooldownDecision cooldownDecision;
    try {
      cooldownDecision = _cooldown.evaluate(
        candidate.observedAt,
        location.point,
      );
    } catch (_) {
      return const CandidateFailed(CandidateFailureStage.unknown);
    }

    if (!candidate.isProcessingCurrent) {
      return const CandidateCancelled(CandidateCancellation.lifecycleChanged);
    }
    if (cooldownDecision.isBlocked) {
      return CandidateBlockedByCooldown(
        elapsed: cooldownDecision.elapsed!,
        distanceMeters: cooldownDecision.distanceMeters!,
      );
    }

    TemporaryCapture? capture;
    OwnedPreparedImage? preparedImage;
    var failureStage = CandidateFailureStage.imageAcquisition;

    try {
      if (!candidate.isProcessingCurrent) {
        return const CandidateCancelled(
          CandidateCancellation.lifecycleChanged,
        );
      }
      capture = await candidate.acquireImage();
      if (!candidate.isProcessingCurrent) {
        await capture.dispose();
        capture = null;
        return const CandidateCancelled(
          CandidateCancellation.lifecycleChanged,
        );
      }

      failureStage = CandidateFailureStage.imagePreparation;
      preparedImage = await _imagePreparer.prepare(capture);
      if (!candidate.isProcessingCurrent) {
        await _disposeArtifacts(
          capture: capture,
          preparedImage: preparedImage,
        );
        capture = null;
        preparedImage = null;
        return const CandidateCancelled(
          CandidateCancellation.lifecycleChanged,
        );
      }

      // Preparers own source retirement, but this application-level disposal
      // makes cleanup mandatory for every implementation and remains safe for
      // idempotent production leases.
      failureStage = CandidateFailureStage.cleanup;
      await capture.dispose();
      capture = null;
      if (!candidate.isProcessingCurrent) {
        await preparedImage.dispose();
        preparedImage = null;
        return const CandidateCancelled(
          CandidateCancellation.lifecycleChanged,
        );
      }

      failureStage = CandidateFailureStage.identityGeneration;
      final idempotencyKey = _uuidGenerator.newV4();
      if (!candidate.isProcessingCurrent) {
        await preparedImage.dispose();
        preparedImage = null;
        return const CandidateCancelled(
          CandidateCancellation.lifecycleChanged,
        );
      }

      failureStage = CandidateFailureStage.occurrenceCreation;
      final occurrence = _occurrenceCreator.create(
        idempotencyKey: idempotencyKey,
        detectedAt: candidate.observedAt,
        location: location,
        defectClass: candidate.defectClass,
        confidence: candidate.confidence,
        image: preparedImage,
      );
      if (!candidate.isProcessingCurrent) {
        await occurrence.image.dispose();
        preparedImage = null;
        return const CandidateCancelled(
          CandidateCancellation.lifecycleChanged,
        );
      }

      // Calling `accept` synchronously enters the final durable section. From
      // this point onward a lifecycle guard must not cancel the operation:
      // persistence must finish with either its own success or rollback before
      // the caller can discard its stale callback. Any lifecycle change before
      // this line was already handled by the guards and cleanup above.
      candidate.notifyPersistenceStarted();
      final durableAcceptance = await _occurrenceAcceptancePort.accept(
        occurrence,
      );
      if (durableAcceptance is OccurrencePersisted) {
        _cooldown.commit(occurrence);
        // The durable queue retired the E1 lease as part of its confirmed
        // transfer. The application must never dispose the queue-owned JPEG.
        preparedImage = null;
        return CandidateCreated(occurrence);
      }

      if (durableAcceptance is OccurrenceAlreadyPersistedEquivalent) {
        // This operation's lease is a duplicate of a JPEG already owned by
        // the queue. Dispose only this temporary lease, never the canonical
        // queue image, and do not expose a second success.
        failureStage = CandidateFailureStage.cleanup;
        await occurrence.image.dispose();
        preparedImage = null;
        return const CandidateAlreadyPersistedEquivalent();
      }

      failureStage = CandidateFailureStage.durableAcceptance;
      throw StateError('Durable acceptance was not confirmed.');
    } catch (_) {
      final cleanupSucceeded = await _disposeArtifacts(
        capture: capture,
        preparedImage: preparedImage,
      );
      return CandidateFailed(
        cleanupSucceeded ? failureStage : CandidateFailureStage.cleanup,
      );
    }
  }

  bool _hasValidCandidateFields(CandidateInput candidate) {
    return candidate.defectClass == InMemoryOccurrence.potholeDefectClass &&
        InMemoryOccurrence.isValidConfidence(candidate.confidence);
  }

  Future<bool> _disposeArtifacts({
    TemporaryCapture? capture,
    OwnedPreparedImage? preparedImage,
  }) async {
    var succeeded = true;
    try {
      await preparedImage?.dispose();
    } catch (_) {
      succeeded = false;
    }
    try {
      await capture?.dispose();
    } catch (_) {
      succeeded = false;
    }
    return succeeded;
  }
}
