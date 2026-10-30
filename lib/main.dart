import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'application/delivery/operation_delivery_port.dart'
    show DeliveryLifecyclePort;
import 'application/e1_ports.dart';
import 'application/e2_persistence_ports.dart';
import 'application/e3_storage_ports.dart';
import 'application/post_candidate_processor.dart';
import 'candidate/manual_candidate_source.dart';
import 'candidate/occurrence_candidate_source.dart';
import 'domain/configuration_validators.dart';
import 'domain/cooldown_policy.dart';
import 'domain/distance_calculator.dart';
import 'domain/operational_configuration.dart';
import 'e0/camera_diagnostic.dart';
import 'e0/diagnostic_http_client.dart';
import 'e0/e0_controller.dart';
import 'e0/e0_screen.dart';
import 'e0/location_diagnostic.dart';
import 'infrastructure/device_credential_store.dart';
import 'infrastructure/durable_image_store.dart';
import 'infrastructure/operational_app_settings.dart';
import 'infrastructure/operational_camera.dart';
import 'infrastructure/operational_configuration_store.dart';
import 'infrastructure/operational_location.dart';
import 'infrastructure/private_image_store.dart';
import 'infrastructure/private_jpeg_image_preparer.dart';
import 'infrastructure/persistent_occurrence_queue.dart';
import 'infrastructure/screen_awake.dart';
import 'infrastructure/shared_preferences_store.dart';
import 'infrastructure/system_clock.dart';
import 'infrastructure/uuid_v4_generator.dart';
import 'operation/diagnostic_session_disposal.dart';
import 'operation/e1_composition.dart';
import 'operation/operation_controller.dart';
import 'operation/operation_screen.dart';
import 'operation/operation_theme.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_screen.dart';

/// Assembles the E1 boundaries explicitly without a DI or state framework.
E1Composition<TPreview, TOccurrence>
    composeE1<TPreview extends Object, TOccurrence>({
  required OccurrenceCandidateSource candidateSource,
  required PostCandidateProcessor<TOccurrence> postCandidateProcessor,
  required OperationalCameraPort<TPreview> camera,
  required OperationalLocationPort location,
  required ImagePreparer imagePreparer,
  required Clock clock,
  required UuidGenerator uuidGenerator,
  required DistanceCalculator distanceCalculator,
  required ScreenAwakePort screenAwake,
}) {
  return E1Composition<TPreview, TOccurrence>(
    candidateSource: candidateSource,
    postCandidateProcessor: postCandidateProcessor,
    camera: camera,
    location: location,
    imagePreparer: imagePreparer,
    clock: clock,
    uuidGenerator: uuidGenerator,
    distanceCalculator: distanceCalculator,
    screenAwake: screenAwake,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final imageStore = await PrivateImageStore.create();
  await imageStore.sweepRecognizedOrphans();
  final preferences = await SharedPreferencesStore.create();
  final configurationRepository =
      SharedPreferencesOperationalConfigurationStore(preferences: preferences);
  final initialConfiguration =
      await _loadInitialOperationalConfiguration(configurationRepository);
  final credentialStore = DeviceCredentialStore();
  final queueRuntime = await _createQueueRuntime();
  final camera = OperationalCamera(imageStore: imageStore);
  final location = OperationalLocation();
  const clock = SystemClock();
  // One delivery graph for the whole process, built over the one E2 queue. It
  // does not exist when the local queue could not be created.
  final coordinatedQueue = queueRuntime.coordinatedQueue;
  final delivery = coordinatedQueue == null
      ? null
      : DeliveryComposition.create(
          queue: coordinatedQueue,
          configurationRepository: configurationRepository,
          credentialStore: credentialStore,
          buildVariant: kDebugMode
              ? ConfigurationBuildVariant.debug
              : ConfigurationBuildVariant.release,
          clock: clock,
          logSink: kDebugMode ? debugPrint : null,
        );
  const uuidGenerator = UuidV4Generator();
  const distanceCalculator = HaversineDistanceCalculator();
  const screenAwake = WakelockPlusScreenAwake();
  final imagePreparer = PrivateJpegImagePreparer(store: imageStore);
  final cooldown = CooldownPolicy(
    distanceCalculator: distanceCalculator,
    minimumElapsed: initialConfiguration.cooldown,
    minimumDistanceMeters: initialConfiguration.minimumDistanceMeters,
  );
  final processor = E1PostCandidateProcessor(
    cooldown: cooldown,
    imagePreparer: imagePreparer,
    uuidGenerator: uuidGenerator,
    occurrenceAcceptancePort: queueRuntime.acceptancePort,
  );
  final controller = OperationController<CameraController>(
    candidateSource: const ManualCandidateSource(),
    postCandidateProcessor: processor,
    camera: camera,
    location: location,
    screenAwake: screenAwake,
    clock: clock,
    queue: queueRuntime.queue,
    cooldownRestorer: cooldown,
    cooldownConfigurationUpdater: cooldown,
    appSettings: const OperationalAppSettings(),
    configurationRepository: configurationRepository,
    credentialStore: credentialStore,
    delivery: delivery?.operationDelivery,
  );

  runApp(
    PavimentaAiMobileApp<CameraController>(
      operationController: controller,
      previewBuilder: (context, preview) => CameraPreview(preview),
      settingsPageBuilder: (context) => _SettingsSession(
        configurationRepository: configurationRepository,
        credentialStore: credentialStore,
        deliveryChange: delivery?.configurationChangeGuard,
      ),
      deliveryLifecycle: delivery?.lifecycle,
      disposeResources: delivery?.dispose,
    ),
  );
}

Future<OperationalConfiguration> _loadInitialOperationalConfiguration(
  OperationalConfigurationRepository repository,
) async {
  try {
    return await repository.load();
  } catch (_) {
    return const OperationalConfiguration.defaults();
  }
}

Future<_QueueRuntime> _createQueueRuntime() async {
  try {
    final imageStore = await PrivateDurableImageStore.create();
    final queue = CoordinatedPersistentOccurrenceQueue(imageStore: imageStore);
    return _QueueRuntime(
      queue: queue,
      acceptancePort: queue,
      coordinatedQueue: queue,
    );
  } catch (_) {
    const queue = UnavailablePersistentOccurrenceQueue();
    return const _QueueRuntime(queue: queue, acceptancePort: queue);
  }
}

final class _QueueRuntime {
  const _QueueRuntime({
    required this.queue,
    required this.acceptancePort,
    this.coordinatedQueue,
  });

  final PersistentOccurrenceQueue queue;
  final OccurrenceAcceptancePort acceptancePort;

  /// The one durable queue, or `null` when only the unavailable stand-in exists.
  final CoordinatedPersistentOccurrenceQueue? coordinatedQueue;
}

typedef DiagnosticPageBuilder = Widget Function(
  BuildContext context,
  DiagnosticSessionDisposal disposal,
);
typedef SettingsPageBuilder = Widget Function(BuildContext context);

/// Application shell with Operation as home and the preserved E0 Diagnostic.
class PavimentaAiMobileApp<TPreview extends Object> extends StatefulWidget {
  const PavimentaAiMobileApp({
    required this.operationController,
    required this.previewBuilder,
    this.diagnosticPageBuilder,
    this.settingsPageBuilder,
    this.deliveryLifecycle,
    this.disposeResources,
    super.key,
  });

  final OperationController<TPreview> operationController;
  final OperationPreviewBuilder<TPreview> previewBuilder;
  final DiagnosticPageBuilder? diagnosticPageBuilder;
  final SettingsPageBuilder? settingsPageBuilder;

  /// Global lifecycle entry of the one delivery, or `null` when none is
  /// composed. The shell forwards `resumed` and every other state to it
  /// regardless of the visible route.
  final DeliveryLifecyclePort? deliveryLifecycle;

  /// Releases process-wide resources owned by the composition root (the
  /// delivery graph) when the application shell is disposed. Idempotent.
  final Future<void> Function()? disposeResources;

  @override
  State<PavimentaAiMobileApp<TPreview>> createState() =>
      _PavimentaAiMobileAppState<TPreview>();
}

class _PavimentaAiMobileAppState<TPreview extends Object>
    extends State<PavimentaAiMobileApp<TPreview>> with WidgetsBindingObserver {
  bool _diagnosticNavigationInProgress = false;
  bool _settingsNavigationInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The delivery starts allowed to run; a start outside `resumed` stops it.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _forwardLifecycleToDelivery(lifecycle);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _forwardLifecycleToDelivery(state);
  }

  /// Delivery follows only the global `resumed` state. It does not wait for
  /// the camera, GPS, wake lock or Diagnostic transitions of the controller.
  void _forwardLifecycleToDelivery(AppLifecycleState state) {
    final delivery = widget.deliveryLifecycle;
    if (delivery == null) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      delivery.onAppResumed();
    } else {
      unawaited(delivery.onAppLeftForeground());
    }
  }

  Future<void> _openDiagnostic(BuildContext context) async {
    if (_diagnosticNavigationInProgress || !mounted) {
      return;
    }
    _diagnosticNavigationInProgress = true;
    final disposal = DiagnosticSessionDisposal();
    try {
      await widget.operationController.suspendForDiagnostic();
      if (!mounted || !context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/diagnostic'),
          builder: (context) =>
              widget.diagnosticPageBuilder?.call(
                context,
                disposal,
              ) ??
              _E0Session(disposal: disposal),
        ),
      );
      await disposal.completed;
      if (!mounted) {
        return;
      }

      final lifecycle = WidgetsBinding.instance.lifecycleState ??
          widget.operationController.state.lifecycleState;
      await widget.operationController.updateOperationalContext(
        isCurrentRoute: true,
        lifecycleState: lifecycle,
        isVisible: lifecycle != AppLifecycleState.hidden &&
            lifecycle != AppLifecycleState.paused &&
            lifecycle != AppLifecycleState.detached,
        isForeground: lifecycle == AppLifecycleState.resumed ||
            lifecycle == AppLifecycleState.inactive,
      );
    } finally {
      _diagnosticNavigationInProgress = false;
    }
  }

  Future<void> _openSettings(BuildContext context) async {
    final pageBuilder = widget.settingsPageBuilder;
    if (_settingsNavigationInProgress || pageBuilder == null || !mounted) {
      return;
    }

    _settingsNavigationInProgress = true;
    try {
      await widget.operationController.suspendForSettings();
      if (!mounted || !context.mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/settings'),
          builder: pageBuilder,
        ),
      );
      await _reconcileOperationAfterRoute();
    } finally {
      _settingsNavigationInProgress = false;
    }
  }

  Future<void> _reconcileOperationAfterRoute() async {
    if (!mounted) {
      return;
    }
    await widget.operationController.refreshCooldownConfiguration();
    if (!mounted) {
      return;
    }
    await widget.operationController.refreshSendingConfigurationStatus();
    if (!mounted) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState ??
        widget.operationController.state.lifecycleState;
    await widget.operationController.updateOperationalContext(
      isCurrentRoute: true,
      lifecycleState: lifecycle,
      isVisible: lifecycle != AppLifecycleState.hidden &&
          lifecycle != AppLifecycleState.paused &&
          lifecycle != AppLifecycleState.detached,
      isForeground: lifecycle == AppLifecycleState.resumed ||
          lifecycle == AppLifecycleState.inactive,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.operationController.dispose();
    final disposeResources = widget.disposeResources;
    if (disposeResources != null) {
      unawaited(disposeResources());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pavimenta AI — Operação',
      theme: buildOperationTheme(),
      home: OperationScreen<TPreview>(
        controller: widget.operationController,
        previewBuilder: widget.previewBuilder,
        onOpenDiagnostic: _openDiagnostic,
        onOpenSettings:
            widget.settingsPageBuilder == null ? null : _openSettings,
      ),
    );
  }
}

/// Owns a fresh settings controller for each Configurações route entry.
class _SettingsSession extends StatefulWidget {
  const _SettingsSession({
    required this.configurationRepository,
    required this.credentialStore,
    this.deliveryChange,
  });

  final OperationalConfigurationRepository configurationRepository;
  final DeviceCredentialStatusPort credentialStore;
  final ConfigurationChangeGuard? deliveryChange;

  @override
  State<_SettingsSession> createState() => _SettingsSessionState();
}

class _SettingsSessionState extends State<_SettingsSession> {
  late final SettingsController _controller = SettingsController(
    configurationRepository: widget.configurationRepository,
    credentialStore: widget.credentialStore,
    deliveryChange: widget.deliveryChange,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsScreen(controller: _controller);
}

/// Creates a fresh preserved E0 session for every Diagnostic route entry.
class _E0Session extends StatefulWidget {
  const _E0Session({required this.disposal});

  final DiagnosticSessionDisposal disposal;

  @override
  State<_E0Session> createState() => _E0SessionState();
}

class _E0SessionState extends State<_E0Session> {
  late final E0Controller _controller;

  @override
  void initState() {
    super.initState();
    _controller = E0Controller(
      cameraDiagnostic: const CameraDiagnostic(),
      locationDiagnostic: LocationDiagnostic(),
      diagnosticHttpClient: DiagnosticHttpClient(),
    );
  }

  @override
  void dispose() {
    widget.disposal.completeAfter(_controller.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => E0Screen(controller: _controller);
}
