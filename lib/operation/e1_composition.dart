import '../application/delivery/delivery_configuration_change_service.dart';
import '../application/delivery/exclusive_delivery_configuration_snapshot.dart';
import '../application/delivery/occurrence_delivery_coordinator.dart';
import '../application/delivery/operation_delivery_port.dart';
import '../application/e1_ports.dart';
import '../application/e3_storage_ports.dart';
import '../application/post_candidate_processor.dart';
import '../candidate/occurrence_candidate_source.dart';
import '../domain/configuration_validators.dart';
import '../domain/distance_calculator.dart';
import '../infrastructure/delivery/http_occurrence_transport.dart';
import '../infrastructure/delivery/persistent_delivery_queue.dart';
import '../infrastructure/delivery/process_delivery_timer.dart';
import '../infrastructure/device_credential_store.dart';
import '../infrastructure/persistent_occurrence_queue.dart';
import '../infrastructure/sanitized_delivery_technical_logger.dart';

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

/// Explicit E4 delivery object graph (design E4.3, E4.13).
///
/// It builds exactly one of each collaborator and shares them: the delivery
/// view of the E2 queue (and with it the one durable image store that queue
/// owns), the configuration snapshot, the HTTP transport, the sanitized
/// technical logger, the clock, the timer, and the coordinator. Configurações
/// and Operation receive only narrow ports:
///
/// * [operationDelivery]: the aggregate projection and the minimal actions;
/// * [configurationChangeGuard]: the E3 guard that applies a destination or
///   credential change through the same snapshot and coordinator.
///
/// Nothing here is a singleton or a service locator: the composition root
/// creates it once and passes the ports on explicitly. The graph opens no
/// connection by itself; the coordinator stays idle until
/// [OperationDeliveryPort.start].
final class DeliveryComposition {
  DeliveryComposition._({
    required OccurrenceDeliveryCoordinator coordinator,
    required CoordinatorOperationDelivery operationDelivery,
    required this.configurationChangeGuard,
    required HttpOccurrenceTransport transport,
    required ProcessDeliveryTimer timer,
  })  : _coordinator = coordinator,
        _operationDelivery = operationDelivery,
        _transport = transport,
        _timer = timer;

  /// Builds the graph over the one coordinated [queue].
  ///
  /// [transport] is for tests; production uses the standard E4 transport.
  factory DeliveryComposition.create({
    required CoordinatedPersistentOccurrenceQueue queue,
    required OperationalConfigurationRepository configurationRepository,
    required DeviceCredentialStore credentialStore,
    required ConfigurationBuildVariant buildVariant,
    required Clock clock,
    DeliveryTechnicalLogSink? logSink,
    HttpOccurrenceTransport? transport,
  }) {
    final deliveryQueue = PersistentDeliveryQueue(queue, clock: clock);
    final snapshot = ExclusiveDeliveryConfigurationSnapshot(
      configurationRepository: configurationRepository,
      credentialReader: credentialStore,
      buildVariant: buildVariant,
    );
    final deliveryTransport = transport ?? HttpOccurrenceTransport.standard();
    final timer = ProcessDeliveryTimer(clock: clock);
    final logger = logSink == null
        ? const SanitizedDeliveryTechnicalLogger.discarding()
        : SanitizedDeliveryTechnicalLogger(logSink);
    final coordinator = OccurrenceDeliveryCoordinator(
      queue: deliveryQueue,
      configuration: snapshot,
      transport: deliveryTransport,
      clock: clock,
      logger: logger,
      timer: timer,
    );
    return DeliveryComposition._(
      coordinator: coordinator,
      operationDelivery: CoordinatorOperationDelivery(coordinator),
      configurationChangeGuard: DeliveryConfigurationChangeService(
        snapshot: snapshot,
        queue: deliveryQueue,
        delivery: coordinator,
      ),
      transport: deliveryTransport,
      timer: timer,
    );
  }

  final OccurrenceDeliveryCoordinator _coordinator;
  final CoordinatorOperationDelivery _operationDelivery;
  final HttpOccurrenceTransport _transport;
  final ProcessDeliveryTimer _timer;
  Future<void>? _disposal;

  /// Aggregate projection and minimal actions for the Operation controller.
  OperationDeliveryPort get operationDelivery => _operationDelivery;

  /// Global app lifecycle entry of the same coordinator, for the shell.
  DeliveryLifecyclePort get lifecycle => _operationDelivery;

  /// E3 guard for Configurações, bound to the same snapshot and coordinator.
  final ConfigurationChangeGuard configurationChangeGuard;

  /// Stops the coordinator, the timer and the transport, in that order.
  /// Idempotent; every caller gets the same completion.
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    try {
      await _coordinator.dispose();
    } finally {
      _timer.dispose();
      await _operationDelivery.dispose();
      await _transport.dispose();
    }
  }
}
