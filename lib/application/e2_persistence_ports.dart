import '../domain/in_memory_occurrence.dart';
import '../domain/persistent_occurrence.dart';
import '../infrastructure/image_artifacts.dart';

/// Result of asking E2 to durably accept a complete occurrence.
sealed class OccurrenceAcceptanceResult {
  const OccurrenceAcceptanceResult();
}

/// A new row and its JPEG were durably confirmed.
final class OccurrencePersisted extends OccurrenceAcceptanceResult {
  const OccurrencePersisted(this.snapshot);

  final QueueSnapshot snapshot;
}

/// The same canonical occurrence and JPEG already exist.
final class OccurrenceAlreadyPersistedEquivalent
    extends OccurrenceAcceptanceResult {
  const OccurrenceAlreadyPersistedEquivalent(this.snapshot);

  final QueueSnapshot snapshot;
}

/// The idempotency key exists with different canonical data or image bytes.
final class OccurrenceIdentityConflict extends OccurrenceAcceptanceResult {
  const OccurrenceIdentityConflict();
}

/// The private durable storage cannot currently be used.
final class OccurrenceStorageUnavailable extends OccurrenceAcceptanceResult {
  const OccurrenceStorageUnavailable();
}

/// Mandatory occurrence data is invalid for the E2 canonical contract.
final class OccurrenceInvalidData extends OccurrenceAcceptanceResult {
  const OccurrenceInvalidData();
}

/// The prepared image could not be read, promoted, or validated.
final class OccurrenceImageFailure extends OccurrenceAcceptanceResult {
  const OccurrenceImageFailure();
}

/// The SQLite/filesystem commit protocol failed before durable acceptance.
final class OccurrenceTransactionalFailure extends OccurrenceAcceptanceResult {
  const OccurrenceTransactionalFailure();
}

/// Application boundary that confirms an occurrence only after durability.
abstract interface class OccurrenceAcceptancePort {
  Future<OccurrenceAcceptanceResult> accept(InMemoryOccurrence occurrence);
}

/// Internal result of consistent queue removal.
sealed class QueueRemovalResult {
  const QueueRemovalResult();
}

final class QueueOccurrenceRemoved extends QueueRemovalResult {
  const QueueOccurrenceRemoved(this.snapshot);

  final QueueSnapshot snapshot;
}

final class QueueOccurrenceNotFound extends QueueRemovalResult {
  const QueueOccurrenceNotFound(this.snapshot);

  final QueueSnapshot snapshot;
}

final class QueueOccurrenceRemovalFailed extends QueueRemovalResult {
  const QueueOccurrenceRemovalFailed();
}

/// Persistent queue contract used by application composition and bootstrap.
///
/// Removal is intentionally internal to the persistence boundary. E2 has no
/// production UI, controller, worker, timer, or network caller for it.
abstract interface class PersistentOccurrenceQueue {
  Stream<QueueSnapshot> get snapshots;

  /// Performs the initial queue bootstrap. Once a confirmed result exists,
  /// repeated calls only return it and never turn a failure into an implicit
  /// retry.
  Future<QueueSnapshot> bootstrap();

  /// Explicitly retries bootstrap after an unavailable result.
  ///
  /// Concurrent calls share the same queue-only execution. This boundary has
  /// no authority over operational camera/GPS resources or Diagnostic routing.
  Future<QueueSnapshot> retryBootstrap();

  Future<OccurrenceAcceptanceResult> persist(
    InMemoryOccurrence occurrence,
  );

  Future<List<ReconstructedPendingOccurrence>> listPending();

  /// Returns the durable last-accepted reference used to restore the cooldown,
  /// or `null` when nothing was ever accepted. It remains available after the
  /// last pending occurrence has been removed.
  Future<AcceptedOccurrenceAnchor?> readAcceptedAnchor();

  Future<int> countPending();

  Future<QueueRemovalResult> removeInternal(String idempotencyKey);

  Future<void> close();
}

/// Result of validating a durable JPEG against its canonical metadata.
enum DurableImageIntegrity { valid, missing, invalid }

/// Aggregate-only result of a namespace reconciliation.
///
/// Counts deliberately avoid exposing names, paths, digests, or occurrence
/// data to callers and logs.
final class DurableImageSweepResult {
  const DurableImageSweepResult({
    required this.removedStaging,
    required this.removedDeleting,
    required this.removedCanonical,
    required this.restoredDeleting,
    required this.failedOperations,
  });

  final int removedStaging;
  final int removedDeleting;
  final int removedCanonical;
  final int restoredDeleting;
  final int failedOperations;
}

/// Private durable-image boundary. Implementations resolve relative names only
/// inside their own namespace and never expose filesystem paths.
/// A validated, operation-exclusive E2 staging file. It cannot be published
/// until the queue has rechecked the idempotency key inside its SQLite
/// transaction. Discarding it never affects a canonical image.
abstract interface class DurableImageStaging {
  Future<PersistedImageProjection> publishWithoutOverwrite();

  Future<void> discard();
}

/// An operation-exclusive `.deleting` marker that can only be retired after
/// the SQLite removal transaction commits.
abstract interface class DurableImageDeletion {
  Future<void> finalizeAfterCommit();
}

/// Test-only and no-op implementations can use this when no marker exists.
final class CompletedDurableImageDeletion implements DurableImageDeletion {
  const CompletedDurableImageDeletion();

  @override
  Future<void> finalizeAfterCommit() async {}
}

abstract interface class DurableImageStore {
  /// Creates an exclusive staging artifact, copies, flushes, hashes, and
  /// validates the prepared JPEG without publishing a canonical image.
  Future<DurableImageStaging> stage(PreparedImageLease source);

  /// Legacy all-in-one promotion boundary retained for direct image-store use.
  /// Queue persistence uses [stage] so publication can occur within its
  /// database transaction.
  Future<PersistedImageProjection> promote(PreparedImageLease source);

  Stream<List<int>> openRead(PersistedImageProjection image);

  Future<DurableImageIntegrity> inspect(PersistedImageProjection image);

  Future<void> delete(PersistedImageProjection image);

  /// Moves one canonical JPEG to an operation-exclusive marker without
  /// replacing a destination. The returned marker is retired after commit.
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  );

  Future<DurableImageSweepResult> sweep(
    Set<String> referencedCanonicalNames,
  );
}
