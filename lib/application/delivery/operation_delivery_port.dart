import 'dart:async';

import '../../domain/delivery/delivery_presentation_state.dart';
import 'occurrence_delivery_coordinator.dart' as coordinator;
import 'occurrence_delivery_coordinator.dart'
    show DeliveryManualRetryResult, OccurrenceDeliveryCoordinator;

/// The only view of the delivery that the Operation controller receives
/// (design E4.3, E4.11, E4.13).
///
/// It offers an aggregate, sanitized projection and three minimal actions. It
/// exposes no queue, transport, configuration snapshot, credential, timer or
/// coordinator, and nothing in the projection identifies an occurrence.
abstract interface class OperationDeliveryPort {
  /// Current aggregate projection.
  DeliveryPresentationState get presentation;

  /// Changes of [presentation], without repeats. Closed when the delivery is
  /// disposed.
  Stream<DeliveryPresentationState> get presentations;

  /// Allows delivery after the local queue bootstrap is confirmed ready.
  /// Idempotent.
  void start();

  /// Notifies that the queue may hold a new pending occurrence. Coalesced.
  void onQueueChanged();

  /// Manual "try sending again". Never shortens a backoff.
  Future<DeliveryManualRetryResult> retryManually();
}

/// Process-wide app lifecycle as seen by the delivery (design E4.13).
///
/// It is held by the application shell, not by the Operation controller, so
/// that delivery follows only the global `resumed` state, independently of the
/// visible route, the camera, GPS, the wake lock and the Diagnostic.
abstract interface class DeliveryLifecyclePort {
  /// The app is `resumed`: attempts are allowed and one evaluation requested.
  void onAppResumed();

  /// The app left `resumed`: no new attempt starts and the one in flight is
  /// cancelled without losing the item. Camera, GPS and wake lock are not
  /// touched.
  Future<void> onAppLeftForeground();
}

/// [OperationDeliveryPort] over the single [OccurrenceDeliveryCoordinator].
///
/// Maps the coordinator phase to the presentation phase one to one and decides
/// `canRetry`: it is true only where a manual retry can produce a new
/// evaluation (an explicit pause, or items waiting for the next evaluation)
/// and false while waiting for a recoverable-failure backoff, which a manual
/// retry never shortens.
///
/// It does not own the coordinator: [dispose] only stops observing it.
final class CoordinatorOperationDelivery
    implements OperationDeliveryPort, DeliveryLifecyclePort {
  CoordinatorOperationDelivery(OccurrenceDeliveryCoordinator delivery)
      : _delivery = delivery,
        _presentation = _project(delivery.phase) {
    _subscription = delivery.phases.listen(_onPhase);
  }

  final OccurrenceDeliveryCoordinator _delivery;
  final StreamController<DeliveryPresentationState> _controller =
      StreamController<DeliveryPresentationState>.broadcast();
  late final StreamSubscription<coordinator.DeliveryPhase> _subscription;
  DeliveryPresentationState _presentation;
  bool _disposed = false;

  @override
  DeliveryPresentationState get presentation => _presentation;

  @override
  Stream<DeliveryPresentationState> get presentations => _controller.stream;

  @override
  void start() => _delivery.start();

  @override
  void onQueueChanged() => _delivery.onQueueChanged();

  @override
  Future<DeliveryManualRetryResult> retryManually() =>
      _delivery.retryManually();

  @override
  void onAppResumed() => _delivery.onAppResumed();

  @override
  Future<void> onAppLeftForeground() => _delivery.onAppLeftForeground();

  /// Stops observing the coordinator and closes [presentations]. Idempotent.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _subscription.cancel();
    await _controller.close();
  }

  void _onPhase(coordinator.DeliveryPhase phase) {
    if (_disposed) {
      return;
    }
    final next = _project(phase);
    if (next == _presentation) {
      return;
    }
    _presentation = next;
    _controller.add(next);
  }

  static DeliveryPresentationState _project(coordinator.DeliveryPhase phase) {
    final mapped = switch (phase) {
      coordinator.DeliveryPhase.configurationRequired =>
        DeliveryPhase.configurationRequired,
      coordinator.DeliveryPhase.idle => DeliveryPhase.idle,
      coordinator.DeliveryPhase.ready => DeliveryPhase.ready,
      coordinator.DeliveryPhase.sending => DeliveryPhase.sending,
      coordinator.DeliveryPhase.waitingBackoff => DeliveryPhase.waitingBackoff,
      coordinator.DeliveryPhase.pausedAuthentication =>
        DeliveryPhase.pausedAuthentication,
      coordinator.DeliveryPhase.pausedAccess => DeliveryPhase.pausedAccess,
      coordinator.DeliveryPhase.pausedUnexpected =>
        DeliveryPhase.pausedUnexpected,
      coordinator.DeliveryPhase.pausedLocalFailure =>
        DeliveryPhase.pausedLocalFailure,
      coordinator.DeliveryPhase.cleaning => DeliveryPhase.cleaning,
      coordinator.DeliveryPhase.queueUnavailable =>
        DeliveryPhase.queueUnavailable,
    };
    final canRetry = switch (mapped) {
      DeliveryPhase.ready ||
      DeliveryPhase.pausedAuthentication ||
      DeliveryPhase.pausedAccess ||
      DeliveryPhase.pausedUnexpected ||
      DeliveryPhase.pausedLocalFailure =>
        true,
      DeliveryPhase.configurationRequired ||
      DeliveryPhase.idle ||
      DeliveryPhase.sending ||
      DeliveryPhase.waitingBackoff ||
      DeliveryPhase.cleaning ||
      DeliveryPhase.queueUnavailable =>
        false,
    };
    return DeliveryPresentationState(phase: mapped, canRetry: canRetry);
  }
}
