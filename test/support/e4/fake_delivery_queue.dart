import 'dart:async';

import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';

/// Pause reasons mirrored from the E4 design (`occurrence_delivery_control`).
enum FakePauseReason {
  none,
  authentication,
  access,
  unexpectedResponse,
  localFailure,
}

/// Outcome of a fake queue mutation.
enum FakeMutationResult { applied, notFound }

/// Immutable view of one queued occurrence plus its E4 delivery state.
///
/// Test-local stand-in for the future queue head model (task 63.1). Only the
/// fields the delivery scenarios need exist; none reaches presentation.
final class FakeQueuedOccurrence {
  FakeQueuedOccurrence({
    required this.idempotencyKey,
    required this.queueSequence,
    required List<int>? imageBytes,
    this.attemptCount = 0,
    this.backoffCalculatedAt,
    this.nextAttemptAt,
    this.pendingLocalDisposition,
    this.cleanupAttemptCount = 0,
    this.nextCleanupAt,
  }) : imageBytes =
            imageBytes == null ? null : List<int>.unmodifiable(imageBytes);

  final String idempotencyKey;
  final int queueSequence;

  /// `null` simulates a missing or unreadable JPEG.
  final List<int>? imageBytes;
  final int attemptCount;
  final DateTime? backoffCalculatedAt;
  final DateTime? nextAttemptAt;
  final String? pendingLocalDisposition;
  final int cleanupAttemptCount;
  final DateTime? nextCleanupAt;

  FakeQueuedOccurrence _copyWith({
    int? attemptCount,
    DateTime? backoffCalculatedAt,
    DateTime? nextAttemptAt,
    String? pendingLocalDisposition,
    int? cleanupAttemptCount,
    DateTime? nextCleanupAt,
  }) =>
      FakeQueuedOccurrence(
        idempotencyKey: idempotencyKey,
        queueSequence: queueSequence,
        imageBytes: imageBytes,
        attemptCount: attemptCount ?? this.attemptCount,
        backoffCalculatedAt: backoffCalculatedAt ?? this.backoffCalculatedAt,
        nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
        pendingLocalDisposition:
            pendingLocalDisposition ?? this.pendingLocalDisposition,
        cleanupAttemptCount: cleanupAttemptCount ?? this.cleanupAttemptCount,
        nextCleanupAt: nextCleanupAt ?? this.nextCleanupAt,
      );

  @override
  String toString() => 'FakeQueuedOccurrence(<redacted>)';
}

/// Test-local head selection result (stand-in for `DeliveryHeadResult`).
sealed class FakeHeadResult {
  const FakeHeadResult();
}

final class FakeHeadUnavailable extends FakeHeadResult {
  const FakeHeadUnavailable();
}

final class FakeHeadEmpty extends FakeHeadResult {
  const FakeHeadEmpty();
}

final class FakeHeadEligible extends FakeHeadResult {
  const FakeHeadEligible(this.occurrence);

  final FakeQueuedOccurrence occurrence;
}

final class FakeHeadInBackoff extends FakeHeadResult {
  const FakeHeadInBackoff(this.occurrence, this.nextAttemptAt);

  final FakeQueuedOccurrence occurrence;
  final DateTime nextAttemptAt;
}

/// The head already has a confirmed remote decision; only local removal is
/// pending. [dueAt] is null when the cleanup may run now.
final class FakeHeadPendingCleanup extends FakeHeadResult {
  const FakeHeadPendingCleanup(this.occurrence, this.dueAt);

  final FakeQueuedOccurrence occurrence;
  final DateTime? dueAt;
}

final class FakeHeadLocalIntegrityFailure extends FakeHeadResult {
  const FakeHeadLocalIntegrityFailure(this.occurrence);

  final FakeQueuedOccurrence occurrence;
}

/// In-memory FIFO queue with E4 delivery state; no SQLite, no filesystem.
///
/// Time is always passed in by the caller (`nextHead(now)`), so the fake never
/// reads a clock itself.
final class FakeDeliveryQueue {
  FakeDeliveryQueue({this.imageChunkSize = 4}) {
    if (imageChunkSize < 1) {
      throw ArgumentError.value(imageChunkSize, 'imageChunkSize');
    }
  }

  /// Size of the chunks produced by [openImage], so tests exercise a stream
  /// rather than a single buffer.
  final int imageChunkSize;

  final List<FakeQueuedOccurrence> _entries = <FakeQueuedOccurrence>[];
  final StreamController<QueueSnapshot> _summary =
      StreamController<QueueSnapshot>.broadcast();

  int _nextSequence = 1;
  FakePauseReason _pauseReason = FakePauseReason.none;

  /// When false, [nextHead] reports the queue as unavailable.
  bool available = true;

  /// The next N [completePendingLocalRemoval] calls fail without changes.
  int failNextRemovals = 0;

  final List<String> removedKeys = <String>[];

  List<FakeQueuedOccurrence> get pending =>
      List<FakeQueuedOccurrence>.unmodifiable(_entries);

  QueueSnapshot get snapshot => QueueSnapshot(
        health: available ? QueueHealth.ready : QueueHealth.unavailable,
        pendingCount: _entries.length,
      );

  /// Adds one accepted occurrence at the tail and returns its view.
  FakeQueuedOccurrence add(String idempotencyKey, List<int>? imageBytes) {
    if (_entries.any((entry) => entry.idempotencyKey == idempotencyKey)) {
      throw StateError('Duplicate idempotency key in FakeDeliveryQueue.');
    }
    final entry = FakeQueuedOccurrence(
      idempotencyKey: idempotencyKey,
      queueSequence: _nextSequence++,
      imageBytes: imageBytes,
    );
    _entries.add(entry);
    _publish();
    return entry;
  }

  Future<FakeHeadResult> nextHead(DateTime now) async {
    if (!available) {
      return const FakeHeadUnavailable();
    }
    if (_entries.isEmpty) {
      return const FakeHeadEmpty();
    }
    final head = _entries.first;
    if (head.pendingLocalDisposition != null) {
      final dueAt = head.nextCleanupAt;
      return FakeHeadPendingCleanup(
        head,
        dueAt != null && now.isBefore(dueAt) ? dueAt : null,
      );
    }
    if (head.imageBytes == null) {
      return FakeHeadLocalIntegrityFailure(head);
    }
    final nextAttemptAt = head.nextAttemptAt;
    if (nextAttemptAt != null && now.isBefore(nextAttemptAt)) {
      return FakeHeadInBackoff(head, nextAttemptAt);
    }
    return FakeHeadEligible(head);
  }

  Stream<List<int>> openImage(String idempotencyKey) {
    final bytes = _find(idempotencyKey)?.imageBytes;
    if (bytes == null) {
      throw StateError('Image is not available in FakeDeliveryQueue.');
    }
    return Stream<List<int>>.fromIterable(<List<int>>[
      for (var start = 0; start < bytes.length; start += imageChunkSize)
        bytes.sublist(
          start,
          start + imageChunkSize > bytes.length
              ? bytes.length
              : start + imageChunkSize,
        ),
    ]);
  }

  Future<FakeMutationResult> recordRecoverableFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextAttemptAt,
  ) async =>
      _update(
        idempotencyKey,
        (entry) => entry._copyWith(
          attemptCount: entry.attemptCount + 1,
          backoffCalculatedAt: calculatedAt,
          nextAttemptAt: nextAttemptAt,
        ),
      );

  Future<FakeMutationResult> recordDefinitiveDecision(
    String idempotencyKey,
    String disposition,
  ) async =>
      _update(
        idempotencyKey,
        (entry) => entry._copyWith(pendingLocalDisposition: disposition),
      );

  Future<FakeMutationResult> recordCleanupFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextCleanupAt,
  ) async =>
      _update(
        idempotencyKey,
        (entry) => entry._copyWith(
          cleanupAttemptCount: entry.cleanupAttemptCount + 1,
          nextCleanupAt: nextCleanupAt,
        ),
      );

  /// Removes the occurrence and its delivery state together, reusing the
  /// production E2 removal result type.
  Future<QueueRemovalResult> completePendingLocalRemoval(
    String idempotencyKey,
  ) async {
    final entry = _find(idempotencyKey);
    if (entry == null) {
      return QueueOccurrenceNotFound(snapshot);
    }
    if (entry.pendingLocalDisposition == null) {
      throw StateError('No definitive decision was recorded for this item.');
    }
    if (failNextRemovals > 0) {
      failNextRemovals--;
      return const QueueOccurrenceRemovalFailed();
    }
    _entries.remove(entry);
    removedKeys.add(idempotencyKey);
    _publish();
    return QueueOccurrenceRemoved(snapshot);
  }

  Future<FakePauseReason> readControl() async => _pauseReason;

  Future<FakeMutationResult> pause(FakePauseReason reason) async {
    if (reason == FakePauseReason.none) {
      throw ArgumentError.value(reason, 'reason', 'use resume() instead');
    }
    _pauseReason = reason;
    return FakeMutationResult.applied;
  }

  Future<FakeMutationResult> resume() async {
    _pauseReason = FakePauseReason.none;
    return FakeMutationResult.applied;
  }

  /// Aggregate-only summaries, as the real queue publishes.
  Stream<QueueSnapshot> watchSummary() => _summary.stream;

  Future<void> close() => _summary.close();

  FakeQueuedOccurrence? _find(String idempotencyKey) {
    for (final entry in _entries) {
      if (entry.idempotencyKey == idempotencyKey) {
        return entry;
      }
    }
    return null;
  }

  FakeMutationResult _update(
    String idempotencyKey,
    FakeQueuedOccurrence Function(FakeQueuedOccurrence entry) change,
  ) {
    final index =
        _entries.indexWhere((entry) => entry.idempotencyKey == idempotencyKey);
    if (index < 0) {
      return FakeMutationResult.notFound;
    }
    _entries[index] = change(_entries[index]);
    return FakeMutationResult.applied;
  }

  void _publish() {
    if (!_summary.isClosed) {
      _summary.add(snapshot);
    }
  }
}
