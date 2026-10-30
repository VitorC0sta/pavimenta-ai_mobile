import 'dart:async';

import '../../domain/delivery/delivery_backoff_policy.dart';
import '../../domain/delivery/delivery_configuration.dart';
import '../../domain/delivery/delivery_decision.dart';
import '../../domain/delivery/delivery_queue_head.dart';
import '../../domain/delivery/http_delivery_decision_policy.dart';
import '../../domain/delivery/occurrence_transport_result.dart';
import '../../domain/delivery/occurrence_upload_request.dart';
import '../e1_ports.dart';
import '../e2_persistence_ports.dart';
import 'delivery_configuration_change_port.dart';
import 'delivery_configuration_change_service.dart'
    show configurationClearablePauses;
import 'delivery_configuration_snapshot_port.dart';
import 'delivery_technical_logger.dart';
import 'delivery_timer_port.dart';
import 'occurrence_delivery_queue_port.dart';
import 'occurrence_transport_port.dart';

/// Aggregate phase of the delivery published to observers (design E4.11).
///
/// It carries no URL, key, status, identifier, coordinate, timestamp, file
/// name, path or digest.
enum DeliveryPhase {
  /// The destination or the credential is not configured.
  configurationRequired,

  /// Nothing is queued.
  idle,

  /// Items wait for the next evaluation.
  ready,

  /// One attempt is in flight.
  sending,

  /// The head waits for a recoverable-failure backoff.
  waitingBackoff,

  /// Paused: missing, malformed or rejected credential.
  pausedAuthentication,

  /// Paused: the device is not allowed.
  pausedAccess,

  /// Paused: the API answered with an unexpected response.
  pausedUnexpected,

  /// Paused: an item or the local storage could not be prepared.
  pausedLocalFailure,

  /// Finishing the local removal of a decided item.
  cleaning,

  /// The queue (or its control) could not be used.
  queueUnavailable,
}

/// Outcome of [OccurrenceDeliveryCoordinator.retryManually].
enum DeliveryManualRetryResult {
  /// An explicit pause was cleared and one evaluation was requested.
  resumed,

  /// There was no pause to clear; one evaluation was requested (a backoff is
  /// still respected by it).
  evaluationRequested,

  /// Nothing changed: the control could not be read or cleared, or the
  /// coordinator was disposed.
  notApplied,
}

/// Serial coordinator of the occurrence delivery (design E4.3, E4.6).
///
/// This is the skeleton of the coordinator. It guarantees the structural
/// properties that every later behavior builds on:
///
/// * **Single flight.** At most one evaluation, and therefore at most one
///   delivery attempt, is active at any time. No trigger can start a second
///   loop.
/// * **Coalesced notifications.** [start] and [onQueueChanged] only request an
///   evaluation. Any number of requests made while an evaluation is running
///   collapse into exactly one follow-up evaluation, which runs after the
///   current one ends.
/// * **Strict FIFO.** Every cycle asks the queue for the head
///   ([OccurrenceDeliveryQueuePort.nextHead]) and only ever works on it. The
///   coordinator never inspects, reorders, or skips later items, so a head
///   that is not eligible blocks the items behind it.
/// * **No database region held over the network.** The queue port returns an
///   immutable projection and the coordinator calls the transport only
///   outside of any queue call, so queue operations (including the persistence
///   of new occurrences) proceed while an upload is in flight.
///
/// An attempt starts only when the persisted control is running and the
/// configuration snapshot is available, and the snapshot revision is checked
/// again in the same synchronous step that opens the image and hands the
/// request to the transport.
///
/// One attempt runs in this order: persisted control, one configuration
/// snapshot (destination and credential of a single revision), the revision
/// check, the private JPEG stream, the transport, and the persisted decision.
/// The revision check, the opening of the image stream and the hand-off to the
/// transport happen in the same synchronous step.
///
/// Local failures stop the delivery with a persisted `localFailure` pause and
/// never reach the network: a head whose JPEG the queue found missing or
/// invalid, an image stream that cannot be opened, a transport that reports it
/// could not read the image or assemble the request, and a secure storage that
/// could not be read for the snapshot. The item is always preserved.
///
/// The outcome of an attempt follows the decision matrix of the design, using
/// the domain policies: `200`/`201` and `400`/`409`/`413`/`415` are recorded as
/// definitive and the item is removed; `401`/`403` and any other status pause
/// delivery; network failure, timeout and `5xx` record a recoverable failure
/// with the shared exponential backoff; a cancelled attempt records nothing.
/// A failed local removal keeps the recorded decision, records a cleanup
/// failure with its own backoff and never uses the network again. Technical
/// events go to the optional [DeliveryTechnicalLogger], which accepts only
/// closed values.
///
/// No automatic retry happens during a pause or a backoff (of a recoverable
/// failure or of a local cleanup): the evaluation ends, the item is preserved,
/// and the only wake-up is the single timer for the end of a backoff, so
/// nothing here can spin.
/// Only two explicit entries change that:
///
/// * [onConfigurationCorrected], after a confirmed save of the destination or
///   of the credential, clears only the pauses a correction can resolve
///   (`authentication`, `access`, `unexpectedResponse`), persistently;
/// * [retryManually] clears any explicit pause, including `localFailure`.
///
/// Neither of them touches the attempt counter, `next_attempt_at` or the
/// cleanup schedule, so a remote or cleanup backoff is never anticipated.
///
/// The coordinator reacts to these triggers, all of which only *request* a
/// coalesced evaluation: [start] (bootstrap), [onQueueChanged] (snapshot of a
/// new pending item), the due [DeliveryTimerPort] timer, a relevant
/// configuration change ([DeliveryConfigurationChangePort]) and
/// [onAppResumed]. At most one timer is armed, only for the due instant of a
/// backoff or of a local cleanup, only in the foreground, and only for an
/// instant in the future, so nothing here can spin.
///
/// A configuration change suspends the attempt that uses the old pair before
/// anything is written ([suspendForConfigurationChange]); removing the
/// destination or the credential never opens a connection and publishes
/// [DeliveryPhase.configurationRequired] on the next evaluation (when an item
/// is queued). An operational change that does not move the destination never
/// reaches the coordinator, so an existing pause is kept.
///
/// [onAppLeftForeground] stops new attempts, cancels the timer and asks the
/// transport to cancel the attempt in flight. Whatever the attempt would have
/// persisted afterwards is dropped, the item stays in the queue and its next
/// attempt reuses the same idempotency key.
///
/// A definitive remote decision is recorded before the local removal starts,
/// as the design requires, and the coordinator then moves on to the next head.
///
/// The coordinator imports no Flutter, SQLite, file system, or HTTP client
/// type. It never keeps the credential beyond one attempt and never reports
/// request, response, or exception data.
final class OccurrenceDeliveryCoordinator
    implements DeliveryConfigurationChangePort {
  OccurrenceDeliveryCoordinator({
    required OccurrenceDeliveryQueuePort queue,
    required DeliveryConfigurationSnapshotPort configuration,
    required OccurrenceTransportPort transport,
    required Clock clock,
    DeliveryTechnicalLogger? logger,
    DeliveryTimerPort? timer,
  })  : _queue = queue,
        _configuration = configuration,
        _transport = transport,
        _clock = clock,
        _logger = logger,
        _timer = timer;

  final OccurrenceDeliveryQueuePort _queue;
  final DeliveryConfigurationSnapshotPort _configuration;
  final OccurrenceTransportPort _transport;
  final Clock _clock;
  final DeliveryTechnicalLogger? _logger;
  final DeliveryTimerPort? _timer;

  bool _started = false;
  bool _disposed = false;

  /// Whether the app is `resumed`. Evaluations run only in the foreground.
  bool _foreground = true;

  /// Open configuration changes (between suspend and "changed"). While any is
  /// open no attempt starts.
  int _suspensions = 0;

  /// Bumped whenever the running attempt must be abandoned (leaving the
  /// foreground, suspending for a configuration change).
  int _epoch = 0;

  /// The [_epoch] the running evaluation started in.
  int _runEpoch = 0;

  /// An evaluation was requested and has not started yet.
  bool _evaluationRequested = false;

  /// The running evaluation loop, or `null` when idle.
  Future<void>? _activeLoop;

  /// The only armed timer, if any.
  DeliveryTimerHandle? _timerHandle;
  int _timerGeneration = 0;

  DeliveryPhase _phase = DeliveryPhase.idle;
  final StreamController<DeliveryPhase> _phases =
      StreamController<DeliveryPhase>.broadcast();

  /// Whether an evaluation loop is running (an attempt may be in flight).
  bool get isEvaluating => _activeLoop != null;

  /// Current aggregate phase.
  DeliveryPhase get phase => _phase;

  /// Changes of [phase], without repeats. Closed by [dispose].
  Stream<DeliveryPhase> get phases => _phases.stream;

  /// Whether the running evaluation must stop and persist nothing more.
  bool get _stale =>
      _disposed || !_foreground || _suspensions > 0 || _epoch != _runEpoch;

  bool get _canRun =>
      _started && !_disposed && _foreground && _suspensions == 0;

  /// Allows evaluations and requests the first one (bootstrap confirmed).
  /// Idempotent.
  void start() {
    if (_disposed) {
      return;
    }
    _started = true;
    _requestEvaluation();
  }

  /// Notifies that the queue may have a new or changed head.
  ///
  /// Coalesced with every other pending request. Ignored before [start] (the
  /// first evaluation looks at the queue anyway) and after [dispose].
  void onQueueChanged() {
    if (!_started) {
      return;
    }
    _requestEvaluation();
  }

  /// The app is `resumed` again: allows attempts and requests one coalesced
  /// evaluation, which reads queue, control and configuration anew and still
  /// respects any pause or backoff.
  void onAppResumed() {
    if (_disposed) {
      return;
    }
    _foreground = true;
    _requestEvaluation();
  }

  /// The app left `resumed` (`inactive`, `paused`, `hidden`, `detached`).
  ///
  /// No new attempt starts, the timer is cancelled and the attempt in flight
  /// is cancelled in the transport. Nothing the abandoned attempt would have
  /// persisted is written, and the item stays queued with the same
  /// idempotency key. Camera, GPS and wake lock are not touched.
  Future<void> onAppLeftForeground() async {
    if (_disposed) {
      return;
    }
    _foreground = false;
    _epoch++;
    _evaluationRequested = false;
    _cancelTimer();
    if (_phase == DeliveryPhase.sending) {
      _publish(DeliveryPhase.ready);
    }
    if (_activeLoop != null) {
      await _cancelTransport();
    }
  }

  /// Suspends the attempt that uses the old configuration, before a new
  /// value is written ([DeliveryConfigurationChangePort]).
  ///
  /// It cancels the request in flight and the preparation under way, and
  /// completes only when the running evaluation has ended, which can no longer
  /// open a socket, persist an outcome or take a snapshot. No attempt starts
  /// until [onConfigurationChanged] is called.
  @override
  Future<void> suspendForConfigurationChange() async {
    if (_disposed) {
      return;
    }
    _suspensions++;
    _epoch++;
    _evaluationRequested = false;
    _cancelTimer();
    final loop = _activeLoop;
    if (loop != null) {
      await _cancelTransport();
      await loop;
    }
  }

  /// Ends one suspension and requests one immediate, coalesced evaluation.
  /// It never waits for the evaluation.
  @override
  void onConfigurationChanged() {
    if (_disposed) {
      return;
    }
    if (_suspensions > 0) {
      _suspensions--;
    }
    _requestEvaluation();
  }

  /// Reacts to a confirmed correction of the destination or of the credential.
  ///
  /// Clears the persisted pause only when its reason is one a correction can
  /// resolve ([configurationClearablePauses]); a `localFailure` pause, a
  /// running control and an unreadable control are left as they are. The
  /// attempt counter, the backoff and the cleanup schedule are never touched.
  /// Then one coalesced evaluation is requested, which still respects any
  /// backoff. A failure of the clearing leaves the pause and still requests
  /// the evaluation. Ignored after [dispose].
  Future<void> onConfigurationCorrected() async {
    if (_disposed) {
      return;
    }
    try {
      final control = await _queue.readControl();
      if (_disposed) {
        return;
      }
      if (control is DeliveryControlPaused &&
          configurationClearablePauses.contains(control.reason)) {
        await _queue.resume();
      }
    } on Object {
      // The caught object is discarded; the pause simply stays.
    }
    onQueueChanged();
  }

  /// Manual "try sending again".
  ///
  /// Clears only an explicit pause (`authentication`, `access`,
  /// `unexpectedResponse` or `localFailure`) and requests one coalesced
  /// evaluation. It never clears or shortens a backoff of a recoverable
  /// failure or of a local cleanup: the attempt counter and the next-attempt
  /// instants stay as they are, so a head still in backoff is not sent.
  Future<DeliveryManualRetryResult> retryManually() async {
    if (_disposed) {
      return DeliveryManualRetryResult.notApplied;
    }
    final DeliveryControl control;
    try {
      control = await _queue.readControl();
    } on Object {
      return DeliveryManualRetryResult.notApplied;
    }
    if (_disposed || control is DeliveryControlUnavailable) {
      return DeliveryManualRetryResult.notApplied;
    }
    var result = DeliveryManualRetryResult.evaluationRequested;
    if (control is DeliveryControlPaused) {
      final DeliveryMutationResult resumed;
      try {
        resumed = await _queue.resume();
      } on Object {
        return DeliveryManualRetryResult.notApplied;
      }
      if (_disposed || resumed != DeliveryMutationResult.applied) {
        return DeliveryManualRetryResult.notApplied;
      }
      result = DeliveryManualRetryResult.resumed;
    }
    onQueueChanged();
    return result;
  }

  /// Stops the coordinator for good.
  ///
  /// It cancels the transport attempt in flight, waits for the running
  /// evaluation to end, and guarantees that nothing is persisted or sent
  /// afterwards. The item being delivered stays in the queue; its next attempt
  /// reuses the same idempotency key. Idempotent.
  Future<void> dispose() async {
    if (_disposed) {
      await _activeLoop;
      return;
    }
    _disposed = true;
    _evaluationRequested = false;
    _cancelTimer();
    final loop = _activeLoop;
    if (loop != null) {
      await _cancelTransport();
      await loop;
    }
    if (!_phases.isClosed) {
      await _phases.close();
    }
  }

  /// Asks the transport to cancel the attempt in flight. Never throws.
  Future<void> _cancelTransport() async {
    try {
      await _transport.cancelActive();
    } on Object {
      // The caught object is discarded; the loop still ends on its own.
    }
  }

  void _requestEvaluation() {
    if (!_canRun) {
      return;
    }
    _evaluationRequested = true;
    _activeLoop ??= _runLoop();
  }

  void _publish(DeliveryPhase phase) {
    if (_disposed || phase == _phase) {
      return;
    }
    _phase = phase;
    _phases.add(phase);
  }

  void _publishControl(DeliveryControl control) {
    switch (control) {
      case DeliveryControlRunning():
        break;
      case DeliveryControlPaused(:final reason):
        _publish(_phaseForPause(reason));
      case DeliveryControlUnavailable():
        _publish(DeliveryPhase.queueUnavailable);
    }
  }

  static DeliveryPhase _phaseForPause(DeliveryPauseReason reason) {
    switch (reason) {
      case DeliveryPauseReason.authentication:
        return DeliveryPhase.pausedAuthentication;
      case DeliveryPauseReason.access:
        return DeliveryPhase.pausedAccess;
      case DeliveryPauseReason.unexpectedResponse:
        return DeliveryPhase.pausedUnexpected;
      case DeliveryPauseReason.localFailure:
        return DeliveryPhase.pausedLocalFailure;
    }
  }

  /// Arms the single timer for [dueAt], replacing any other. Only a future
  /// instant is armed, so a due-now head can never create a busy loop.
  void _armTimer(DateTime dueAt) {
    final timer = _timer;
    if (timer == null || _stale || !dueAt.isAfter(_clock.now())) {
      return;
    }
    _cancelTimer();
    final generation = _timerGeneration;
    try {
      final handle = timer.arm(dueAt, () {
        if (generation != _timerGeneration) {
          return;
        }
        _timerHandle = null;
        _requestEvaluation();
      });
      if (generation == _timerGeneration && handle.isActive) {
        _timerHandle = handle;
      }
    } on Object {
      // The caught object is discarded; the next trigger evaluates anyway.
    }
  }

  void _cancelTimer() {
    _timerGeneration++;
    final handle = _timerHandle;
    _timerHandle = null;
    if (handle == null) {
      return;
    }
    try {
      handle.cancel();
    } on Object {
      // The caught object is discarded; the generation already voids it.
    }
  }

  /// Runs evaluations while one is requested. Never reentered: the guard in
  /// [_requestEvaluation] makes this the only loop.
  Future<void> _runLoop() async {
    try {
      while (_evaluationRequested && _canRun) {
        _evaluationRequested = false;
        try {
          await _evaluate();
        } on Object {
          // The caught object is discarded. Ports do not throw by contract;
          // if one does, this evaluation ends without retrying by itself.
        }
      }
    } finally {
      _activeLoop = null;
    }
  }

  /// Delivers heads in FIFO order until one cannot be concluded now.
  ///
  /// It continues to the next head only after a head was removed locally, so
  /// the loop is bounded by the number of queued items and cannot spin.
  Future<void> _evaluate() async {
    _runEpoch = _epoch;
    // The evaluation recomputes the single timer from the queue state.
    _cancelTimer();
    while (!_stale) {
      final head = await _queue.nextHead(_clock.now());
      if (_stale) {
        return;
      }
      switch (head) {
        case final DeliveryHeadEligible eligible:
          if (!await _deliver(eligible)) {
            return;
          }
        case final DeliveryHeadPendingCleanup cleanup:
          // Cleanup of a recorded definitive decision comes before the pause
          // control, the configuration and any backoff, and never uses the
          // network.
          _publish(DeliveryPhase.cleaning);
          if (!await _cleanUp(cleanup)) {
            return;
          }
        case DeliveryQueueEmpty():
          // Idle: nothing to do until the next notification.
          _publish(DeliveryPhase.idle);
          return;
        case DeliveryHeadLocalIntegrityFailure():
          // The queue found the JPEG missing or invalid. The item is kept, no
          // configuration, image or socket is used, and later items must not
          // overtake it.
          await _pauseForLocalFailure(requireRunning: true);
          return;
        case DeliveryQueueUnavailable():
          _publish(DeliveryPhase.queueUnavailable);
          return;
        case DeliveryHeadInBackoff(:final nextAttemptAt):
          // No automatic retry during a backoff: the head is preserved, later
          // items must not overtake it, and the evaluation ends here. Only a
          // running delivery waits for the backoff with a timer.
          await _waitForBackoff(nextAttemptAt);
          return;
      }
    }
  }

  /// Publishes the wait for a recoverable-failure backoff and arms the single
  /// timer for its end, unless an explicit pause (or an unreadable control)
  /// stops the delivery anyway.
  Future<void> _waitForBackoff(DateTime nextAttemptAt) async {
    final control = await _queue.readControl();
    if (_stale) {
      return;
    }
    if (control is! DeliveryControlRunning) {
      _publishControl(control);
      return;
    }
    _publish(DeliveryPhase.waitingBackoff);
    _armTimer(nextAttemptAt);
  }

  /// Persists a pause caused by a local failure (JPEG, request assembly or
  /// credential storage). The item is untouched and the network is not used.
  ///
  /// With [requireRunning] the pause is written only if the persisted control
  /// is running, so a failure found while another pause is active neither
  /// overwrites that reason nor writes the same pause on every evaluation.
  /// The mutation result is not needed: when it is not applied the item is
  /// simply preserved and the next evaluation looks again.
  Future<void> _pauseForLocalFailure({bool requireRunning = false}) async {
    if (requireRunning) {
      final control = await _queue.readControl();
      if (_stale) {
        return;
      }
      if (control is! DeliveryControlRunning) {
        _publishControl(control);
        return;
      }
    }
    if (_stale) {
      return;
    }
    final result = await _queue
        .pause(PausedDeliveryDecision(DeliveryPauseReason.localFailure));
    if (result == DeliveryMutationResult.applied) {
      _publish(DeliveryPhase.pausedLocalFailure);
    } else {
      _publishReadyIfSending();
    }
  }

  /// An attempt ended without a persisted outcome (the pause or the failure
  /// record was not applied): the item is kept and waits for the next
  /// evaluation, so the aggregate state must not keep claiming an upload.
  void _publishReadyIfSending() {
    if (!_stale && _phase == DeliveryPhase.sending) {
      _publish(DeliveryPhase.ready);
    }
  }

  /// Finishes the local removal of a head whose definitive decision is
  /// recorded. Returns whether the item is gone, so the caller may continue.
  ///
  /// A cleanup that is not due yet, or that fails, ends the evaluation without
  /// touching the configuration, the image or the network. A failure is
  /// recorded with its own backoff and the recorded decision is kept.
  Future<bool> _cleanUp(DeliveryHeadPendingCleanup cleanup) async {
    final dueAt = cleanup.dueAt;
    if (dueAt != null && dueAt.isAfter(_clock.now())) {
      // Only the local cleanup is retried at this instant, never the network.
      _armTimer(dueAt);
      return false;
    }
    return _removeLocally(
      cleanup.head.idempotencyKey,
      cleanup.head.cleanupAttemptCount,
    );
  }

  /// Attempts [head] once. Returns whether it was concluded and removed, so
  /// the caller may continue with the next head.
  Future<bool> _deliver(DeliveryHeadEligible head) async {
    // Automatic delivery is stopped by a pause (or by an unreadable control).
    final control = await _queue.readControl();
    if (_stale) {
      return false;
    }
    if (control is! DeliveryControlRunning) {
      _publishControl(control);
      return false;
    }

    // One snapshot carries the destination and the credential of a single
    // revision. Only an available snapshot may lead to the image or a socket.
    final snapshot = await _configuration.readForAttempt();
    if (_stale) {
      return false;
    }
    if (snapshot is DeliverySecureStorageUnavailable) {
      // The credential could not be read: a controlled local stop.
      await _pauseForLocalFailure();
      return false;
    }
    if (snapshot is! DeliveryConfigurationAvailable) {
      // Missing or invalid destination/credential: nothing is opened or sent.
      _publish(
        snapshot is DeliveryCredentialInvalidFormat
            ? DeliveryPhase.pausedAuthentication
            : DeliveryPhase.configurationRequired,
      );
      return false;
    }
    final configuration = snapshot.configuration;

    // No await between the revision check, the image stream and the hand-off
    // to the transport: a configuration change cannot slip in between, and
    // the transport receives only a destination/credential pair that is still
    // current. A stale revision ends the evaluation without opening the image;
    // the change that made it stale requests the next evaluation, which takes
    // a new snapshot. The queue is not locked while `send` runs.
    if (_stale || !_configuration.isCurrent(configuration.revision)) {
      return false;
    }
    final Stream<List<int>> imageStream;
    try {
      // Single-subscription and lazy: the queue re-checks the head identity,
      // the image reference and the length when the transport reads it, and
      // reports a divergence as a stream error.
      imageStream = _queue.openImage(head);
    } on Object {
      // The caught object is discarded; the item is preserved.
      await _pauseForLocalFailure();
      return false;
    }
    final request = OccurrenceUploadRequest.forEligibleHead(
      configuration: configuration,
      eligible: head,
      imageStream: imageStream,
    );
    final OccurrenceTransportResult result;
    _publish(DeliveryPhase.sending);
    try {
      result = await _transport.send(request);
    } on Object {
      // The caught object is discarded; the item is preserved.
      if (!_stale) {
        _publish(DeliveryPhase.ready);
      }
      return false;
    }
    if (_stale) {
      // Abandoned (foreground lost, configuration change or dispose): nothing
      // is persisted and the item stays with its idempotency key.
      return false;
    }
    if (result is TransportCancelled) {
      _publish(DeliveryPhase.ready);
    }
    if (result is TransportLocalFailure) {
      // The JPEG could not be read or the request could not be assembled. No
      // remote decision exists, so the item stays for a later explicit retry
      // (a resend reuses the same idempotency key).
      await _pauseForLocalFailure();
      return false;
    }
    return _applyMatrix(head.head, result);
  }

  /// Applies the decision matrix (design E4.9) to the outcome of one attempt.
  /// Returns whether the item was concluded and removed, so the caller may
  /// continue with the next head.
  ///
  /// The classification is by status alone and reuses the domain policies:
  ///
  /// * definitive (`200`, `201`, `400`, `409`, `413`, `415`): the decision is
  ///   recorded, then the item is removed locally;
  /// * `401` and `403` and any other status: a persisted pause, item kept;
  /// * network failure, timeout and `5xx`: a recoverable failure with the next
  ///   attempt instant from the shared backoff, item kept;
  /// * cancellation: nothing is recorded (no remote failure was confirmed).
  Future<bool> _applyMatrix(
    DeliveryQueueHead head,
    OccurrenceTransportResult result,
  ) async {
    final DeliveryDecision decision;
    switch (result) {
      case TransportHttpResponse(:final statusCode):
        decision = HttpDeliveryDecisionPolicy.classify(statusCode);
      case TransportNetworkFailure():
        decision =
            const RecoverableDeliveryDecision(RecoverableFailureCause.network);
      case TransportTimeout():
        decision =
            const RecoverableDeliveryDecision(RecoverableFailureCause.timeout);
      case TransportCancelled():
      case TransportLocalFailure():
        return false;
    }
    switch (decision) {
      case DefinitiveDeliveryDecision(:final disposition):
        return _concludeDefinitive(head, disposition);
      case final PausedDeliveryDecision paused:
        return _pauseForRemoteDecision(paused);
      case RecoverableDeliveryDecision(:final cause):
        await _recordRecoverableFailure(head, cause);
        return false;
    }
  }

  /// Persists a definitive remote decision, then removes the item locally.
  ///
  /// A removal that fails keeps the recorded decision and schedules a local
  /// cleanup retry; the network is never used again for this item.
  Future<bool> _concludeDefinitive(
    DeliveryQueueHead head,
    DeliveryDisposition disposition,
  ) async {
    final recorded = await _queue.recordDefinitiveDecision(
      head.idempotencyKey,
      disposition,
    );
    if (_stale) {
      return false;
    }
    if (recorded != DeliveryMutationResult.applied) {
      _publish(DeliveryPhase.ready);
      return false;
    }
    _log((logger) => logger.definitiveRejection(disposition));
    return _removeLocally(head.idempotencyKey, head.cleanupAttemptCount);
  }

  /// Removes a decided item. On failure it records the cleanup failure and
  /// the next allowed cleanup instant, and reports that the item is not gone.
  Future<bool> _removeLocally(
    String idempotencyKey,
    int previousCleanupFailures,
  ) async {
    final removal = await _queue.completePendingLocalRemoval(idempotencyKey);
    if (_stale) {
      return false;
    }
    switch (removal) {
      case QueueOccurrenceRemoved():
      case QueueOccurrenceNotFound():
        return true;
      case QueueOccurrenceRemovalFailed():
        _log((logger) => logger.cleanupFailure());
        _publish(DeliveryPhase.cleaning);
        final calculatedAt = _clock.now().toUtc();
        final nextCleanupAt = calculatedAt.add(
          DeliveryBackoffPolicy.delayFor(previousCleanupFailures + 1),
        );
        await _queue.recordCleanupFailure(
          idempotencyKey,
          calculatedAt,
          nextCleanupAt,
        );
        _armTimer(nextCleanupAt);
        return false;
    }
  }

  /// Persists the pause of a status that needs an explicit resume. The item is
  /// kept and no backoff is recorded.
  Future<bool> _pauseForRemoteDecision(PausedDeliveryDecision paused) async {
    final statusCode = paused.unexpectedStatusCode;
    if (statusCode != null) {
      _log((logger) => logger.unexpectedResponse(statusCode));
    }
    final result = await _queue.pause(paused);
    if (result == DeliveryMutationResult.applied) {
      _publish(_phaseForPause(paused.reason));
    } else {
      _publishReadyIfSending();
    }
    return false;
  }

  /// Records one more consecutive recoverable failure and the next attempt
  /// instant. The item is kept at the head.
  Future<void> _recordRecoverableFailure(
    DeliveryQueueHead head,
    RecoverableFailureCause cause,
  ) async {
    _log((logger) => logger.recoverableFailure(cause));
    final calculatedAt = _clock.now().toUtc();
    final nextAttemptAt =
        calculatedAt.add(DeliveryBackoffPolicy.delayFor(head.attemptCount + 1));
    final result = await _queue.recordRecoverableFailure(
      head.idempotencyKey,
      calculatedAt,
      nextAttemptAt,
    );
    if (result == DeliveryMutationResult.applied) {
      _publish(DeliveryPhase.waitingBackoff);
      _armTimer(nextAttemptAt);
    } else {
      _publishReadyIfSending();
    }
  }

  /// Emits one fixed technical event. A failing logger never changes the
  /// delivery outcome.
  void _log(void Function(DeliveryTechnicalLogger logger) emit) {
    final logger = _logger;
    if (logger == null) {
      return;
    }
    try {
      emit(logger);
    } on Object {
      // The caught object is discarded.
    }
  }
}
