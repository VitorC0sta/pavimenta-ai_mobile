import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/main.dart';
import 'package:pavimenta_ai_mobile/operation/diagnostic_session_disposal.dart';
import 'package:pavimenta_ai_mobile/operation/operation_controller.dart';
import 'package:pavimenta_ai_mobile/operation/operation_screen.dart';
import 'package:pavimenta_ai_mobile/operation/operation_state.dart';
import 'package:pavimenta_ai_mobile/operation/operation_theme.dart';

void main() {
  group('OperationScreen content and visual identity', () {
    // **Validates: Requirements 03.1, 03.2, 03.3, 05.1, 05.2, 05.4, RNF-08.1–14**
    testWidgets('shows manual mode, preview, GPS, counter, and palette',
        (tester) async {
      final harness = _ScreenHarness();
      harness.makeReady();
      addTearDown(harness.controller.dispose);

      await _pumpScreen(tester, harness.controller);

      expect(
        find.text('Modo manual — YOLO ainda não configurado'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
      expect(find.text('Registrar buraco'), findsOneWidget);
      expect(find.textContaining('Confirmação manual'), findsWidgets);
      expect(find.text('-23.550500'), findsOneWidget);
      expect(find.text('-46.633300'), findsOneWidget);
      expect(find.text('3.5 m'), findsOneWidget);
      expect(find.text('36.0 km/h'), findsOneWidget);
      expect(find.text('Buracos registrados: 0'), findsOneWidget);
      expect(find.text('Pendências: 0'), findsOneWidget);
      expect(find.text('Configuração para envio pendente'), findsOneWidget);
      expect(
        find.byKey(const Key('sending-configuration-panel')),
        findsOneWidget,
      );
      expect(find.text('Nenhum registro em processamento.'), findsOneWidget);

      final context = tester.element(find.byKey(const Key('operation-screen')));
      final theme = Theme.of(context);
      expect(theme.scaffoldBackgroundColor, OperationPalette.background);
      expect(theme.cardColor, OperationPalette.panel);
      expect(theme.colorScheme.primary, OperationPalette.accent);
      expect(theme.colorScheme.secondary, OperationPalette.success);
      expect(theme.colorScheme.error, OperationPalette.error);
      expect(theme.colorScheme.onSurface, OperationPalette.foreground);

      final banner = tester.widget<Container>(
        find.byKey(const Key('manual-mode-banner')),
      );
      final decoration = banner.decoration! as BoxDecoration;
      expect(decoration.color, OperationPalette.accent);

      final buttonStyle = theme.elevatedButtonTheme.style!;
      expect(
        buttonStyle.backgroundColor!.resolve(<WidgetState>{}),
        OperationPalette.accent,
      );
      expect(
        buttonStyle.foregroundColor!.resolve(<WidgetState>{}),
        OperationPalette.background,
      );

      expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
      expect(find.text('GPS pronto'), findsOneWidget);
      expect(find.text('Pronta'), findsNWidgets(2));
    });

    // **Validates: Requirements RF-05.6, RNF-02.6, RNF-05.5**
    testWidgets('shows only a sanitized ready sending configuration indicator',
        (tester) async {
      final state = OperationState.initial().copyWith(
        sendingConfigurationStatus: OperationSendingConfigurationStatus.ready,
      );
      final harness = _ScreenHarness(initialState: state);
      addTearDown(harness.controller.dispose);

      await _pumpScreen(tester, harness.controller);

      expect(
        find.text('Configuração para envio pronta'),
        findsOneWidget,
      );
      expect(
        find.text('Destino e credencial estão configurados para uso futuro.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Configuração para envio pronta. Destino e credencial estão configurados para uso futuro.',
        ),
        findsOneWidget,
      );
    });

    // **Validates: Requirements 05.3, 12.1, 12.2**
    testWidgets(
        'shows the local persistence stage while durable acceptance runs',
        (tester) async {
      final state = OperationState.initial().copyWith(
        processingStatus: OperationProcessingStatus.processing,
        isBusy: true,
        isPersisting: true,
      );
      final harness = _ScreenHarness(initialState: state);
      addTearDown(harness.controller.dispose);

      await _pumpScreen(tester, harness.controller);

      expect(find.text('Salvando na fila local'), findsOneWidget);
      expect(
        find.text('Persistindo a ocorrência e a imagem na fila local.'),
        findsOneWidget,
      );
      expect(find.text('Aguarde a conclusão do registro atual.'), findsNothing);
    });
    // **Validates: Requirements 05.5, 12.5**
    testWidgets('shows aggregate pending count and textual queue health',
        (tester) async {
      for (final testCase in <(QueueHealth, int, String, String)>[
        (
          QueueHealth.initializing,
          0,
          'Inicializando',
          'Recuperando fila local.',
        ),
        (QueueHealth.ready, 2, 'Pronta', 'Fila local pronta.'),
        (
          QueueHealth.degraded,
          3,
          'Degradada',
          'Atenção: a fila local precisa de recuperação.',
        ),
        (
          QueueHealth.unavailable,
          0,
          'Indisponível',
          'Fila local indisponível.',
        ),
      ]) {
        final harness = _ScreenHarness(
          initialState: OperationState.initial(
            queueSnapshot: QueueSnapshot(
              health: testCase.$1,
              pendingCount: testCase.$2,
            ),
          ),
        );
        addTearDown(harness.controller.dispose);

        await _pumpScreen(tester, harness.controller);

        expect(find.byKey(const Key('queue-panel')), findsOneWidget);
        expect(find.text('Pendências: ${testCase.$2}'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('queue-panel')),
            matching: find.text(testCase.$3),
          ),
          findsOneWidget,
        );
        expect(find.text(testCase.$4), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Pendências: ${testCase.$2}. ${testCase.$3}. ${testCase.$4}',
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    // **Validates: Requirements 03.6, 03.7, 03.8, 03.10, 05.3, RNF-04.3**
    testWidgets('enables only when ready and disables while busy',
        (tester) async {
      final processor = _CompleterProcessor();
      final harness = _ScreenHarness(processor: processor);
      addTearDown(harness.controller.dispose);

      await _pumpScreen(tester, harness.controller);
      ElevatedButton button() => tester.widget<ElevatedButton>(
            find.byKey(const Key('register-pothole-button')),
          );

      expect(button().onPressed, isNull);
      harness.makeReady();
      await tester.pump();
      expect(button().onPressed, isNotNull);

      await tester.ensureVisible(
        find.byKey(const Key('register-pothole-button')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-pothole-button')));
      await tester.pump();
      expect(button().onPressed, isNull);
      expect(find.text('Registrando…'), findsOneWidget);
      expect(
          find.text('Aguarde a conclusão do registro atual.'), findsOneWidget);

      processor.complete(
        const CandidateBlockedByCooldown(
          elapsed: Duration(seconds: 1),
          distanceMeters: 2,
        ),
      );
      await tester.pumpAndSettle();

      expect(button().onPressed, isNotNull);
      expect(
        find.textContaining(
          'Registro ignorado: tempo e distância ainda abaixo dos mínimos.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ignorado por cooldown'), findsOneWidget);
      expect(
        find.text('Nenhuma imagem, UUID ou ocorrência foi criada.'),
        findsOneWidget,
      );
      expect(harness.camera.captureCount, 0);
    });

    // **Validates: Requirements 03.14, 03.15, 03.16, 05.10, 05.11**
    testWidgets('identifies capture and image failures with controlled text',
        (tester) async {
      for (final testCase in <(CandidateFailureStage, String)>[
        (
          CandidateFailureStage.imageAcquisition,
          'Falha na captura: não foi possível obter a imagem.',
        ),
        (
          CandidateFailureStage.imagePreparation,
          'Falha na imagem: não foi possível preparar o JPEG.',
        ),
      ]) {
        final harness = _ScreenHarness(
          processor: _ImmediateProcessor(CandidateFailed(testCase.$1)),
        );
        harness.makeReady();

        await _pumpScreen(tester, harness.controller);
        await tester.ensureVisible(
          find.byKey(const Key('register-pothole-button')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('register-pothole-button')));
        await tester.pumpAndSettle();

        expect(find.textContaining(testCase.$2), findsOneWidget);
        expect(find.text('Falha controlada'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsWidgets);
        harness.controller.dispose();
      }
    });
  });

  group('OperationScreen accessibility and responsive layout', () {
    // **Validates: Requirements 20.3, 20.4, 20.5, 20.6, 20.7, RNF-04.2, RNF-08.10, RNF-08.13, RNF-08.14**
    testWidgets('keeps permission and lifecycle messages usable when narrow',
        (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final harness = _ScreenHarness();
      addTearDown(harness.controller.dispose);

      await tester.binding.setSurfaceSize(const Size(320, 480));
      await _pumpScreen(
        tester,
        harness.controller,
        textScaler: const TextScaler.linear(2),
      );

      harness.controller.publishCameraState(
        generation: harness.controller.generation,
        status: OperationCameraStatus.unavailable,
        message: 'Permissão de câmera negada.',
      );
      harness.controller.publishLocationState(
        generation: harness.controller.generation,
        status: OperationLocationStatus.permissionDeniedPermanently,
        message: 'Localização precisa bloqueada.',
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Permissão de câmera negada.'), findsOneWidget);
      expect(
        find.textContaining('registro manual ficará indisponível'),
        findsOneWidget,
      );
      expect(find.text('Localização precisa bloqueada.'), findsOneWidget);
      expect(
        find.textContaining('Abra as configurações do Android'),
        findsOneWidget,
      );

      await harness.controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.paused,
        isVisible: false,
        isForeground: false,
      );
      await tester.pump();
      expect(
        find.textContaining('novos registros estão bloqueados'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Modo de registro manual. Detecção automática indisponível.',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('register-pothole-button')),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel(
          RegExp('Registrar buraco por confirmação manual'),
        ),
        findsOneWidget,
      );

      await tester.binding.setSurfaceSize(const Size(1000, 800));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.byKey(const Key('location-panel'))).dx,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('camera-panel'))).dx,
        ),
      );
      semantics.dispose();
    });
  });

  group('Operation and Diagnostic navigation entry point', () {
    // **Validates: Requirements 00.4, 03.11**
    testWidgets('starts on Operation and exposes a labeled Diagnostic action',
        (tester) async {
      final harness = _ScreenHarness();
      addTearDown(harness.controller.dispose);

      await tester.pumpWidget(
        PavimentaAiMobileApp<String>(
          operationController: harness.controller,
          previewBuilder: (context, preview) => Text(preview),
          diagnosticPageBuilder: (context, disposal) => const Scaffold(
            body: Text('Diagnóstico E0 preservado'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('operation-screen')), findsOneWidget);
      expect(find.text('Operação'), findsOneWidget);
      expect(find.text('Abrir Diagnóstico'), findsOneWidget);
      expect(
        find.byKey(const Key('open-diagnostic-button')),
        findsOneWidget,
      );
      expect(find.text('Diagnóstico E0 preservado'), findsNothing);

      await tester.tap(find.byKey(const Key('open-diagnostic-button')));
      await tester.pumpAndSettle();

      expect(find.text('Diagnóstico E0 preservado'), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.text('Diagnóstico E0 preservado')),
        )?.settings.name,
        '/diagnostic',
      );
    });

    // **Validates: Requirements 00.4, 00.20, 03.11, 21.2, 21.6**
    testWidgets('opens Diagnostic only after Operation releases all resources',
        (tester) async {
      final harness = _ScreenHarness();
      var diagnosticBuilt = false;
      var resourcesReleasedBeforeBuild = false;
      addTearDown(harness.controller.dispose);

      await tester.pumpWidget(
        PavimentaAiMobileApp<String>(
          operationController: harness.controller,
          previewBuilder: (context, preview) => Text(preview),
          diagnosticPageBuilder: (context, disposal) {
            diagnosticBuilt = true;
            resourcesReleasedBeforeBuild =
                harness.screenAwake.calls.last == false &&
                    harness.location.releaseCount == 1 &&
                    harness.camera.releaseCompleted;
            return const Scaffold(body: Text('Sessão Diagnóstico exclusiva'));
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(harness.screenAwake.calls, [true]);
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);

      await tester.tap(find.byKey(const Key('open-diagnostic-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(harness.controller.state.isCurrentRoute, isFalse);
      expect(harness.controller.state.canRegister, isFalse);
      expect(harness.screenAwake.calls, [true, false]);
      expect(harness.location.releaseCount, 1);
      expect(harness.camera.releaseCount, 1);
      expect(harness.camera.releaseCompleted, isTrue);
      expect(diagnosticBuilt, isTrue);
      expect(resourcesReleasedBeforeBuild, isTrue);
      expect(find.text('Sessão Diagnóstico exclusiva'), findsOneWidget);
    });

    // **Validates: Requirements 00.20, 03.11, 21.2, 21.6**
    testWidgets(
        'waits for complete Diagnostic disposal before reacquiring Operation resources',
        (tester) async {
      final harness = _ScreenHarness();
      final cleanupGate = Completer<void>();
      final events = <String>[];
      addTearDown(() {
        if (!cleanupGate.isCompleted) {
          cleanupGate.complete();
        }
        harness.controller.dispose();
      });

      await tester.pumpWidget(
        PavimentaAiMobileApp<String>(
          operationController: harness.controller,
          previewBuilder: (context, preview) => Text(preview),
          diagnosticPageBuilder: (context, disposal) =>
              _ControlledDiagnosticPage(
            disposal: disposal,
            cleanupGate: cleanupGate,
            events: events,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-diagnostic-button')));
      await tester.pumpAndSettle();
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);
      expect(harness.screenAwake.calls, [true, false]);

      Navigator.of(
        tester.element(find.text('Diagnóstico controlado')),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(events, ['diagnostic-disposal-started']);
      expect(harness.controller.state.isCurrentRoute, isFalse);
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);
      expect(harness.screenAwake.calls, [true, false]);

      cleanupGate.complete();
      await tester.pump();
      await harness.controller.lifecycleSettled;
      await tester.pump();

      expect(
        events,
        ['diagnostic-disposal-started', 'diagnostic-disposal-completed'],
      );
      expect(harness.controller.state.isCurrentRoute, isTrue);
      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 2);
      expect(harness.screenAwake.calls, [true, false, true]);
    });

    // **Validates: Requirements 00.20, 21.2, 21.6**
    testWidgets('defers post-pop reacquisition until lifecycle is resumed',
        (tester) async {
      final harness = _ScreenHarness();
      final cleanupGate = Completer<void>();
      addTearDown(() {
        if (!cleanupGate.isCompleted) {
          cleanupGate.complete();
        }
        harness.controller.dispose();
      });

      await tester.pumpWidget(
        PavimentaAiMobileApp<String>(
          operationController: harness.controller,
          previewBuilder: (context, preview) => Text(preview),
          diagnosticPageBuilder: (context, disposal) =>
              _ControlledDiagnosticPage(
            disposal: disposal,
            cleanupGate: cleanupGate,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-diagnostic-button')));
      await tester.pumpAndSettle();

      Navigator.of(
        tester.element(find.text('Diagnóstico controlado')),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      cleanupGate.complete();
      await tester.pumpAndSettle();

      expect(harness.controller.state.isCurrentRoute, isTrue);
      expect(
        harness.controller.state.lifecycleState,
        AppLifecycleState.paused,
      );
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);
      expect(harness.screenAwake.calls, [true, false]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 2);
      expect(harness.screenAwake.calls, [true, false, true]);
    });
  });
}

final class _ControlledDiagnosticPage extends StatefulWidget {
  const _ControlledDiagnosticPage({
    required this.disposal,
    required this.cleanupGate,
    this.events,
  });

  final DiagnosticSessionDisposal disposal;
  final Completer<void> cleanupGate;
  final List<String>? events;

  @override
  State<_ControlledDiagnosticPage> createState() =>
      _ControlledDiagnosticPageState();
}

final class _ControlledDiagnosticPageState
    extends State<_ControlledDiagnosticPage> {
  @override
  void dispose() {
    widget.disposal.completeAfter(_disposeDiagnosticResources());
    super.dispose();
  }

  Future<void> _disposeDiagnosticResources() async {
    widget.events?.add('diagnostic-disposal-started');
    await widget.cleanupGate.future;
    widget.events?.add('diagnostic-disposal-completed');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('Diagnóstico controlado'));
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  OperationController<String> controller, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildOperationTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: OperationScreen<String>(
        controller: controller,
        previewBuilder: (context, preview) => ColoredBox(
          key: const Key('fake-camera-preview'),
          color: Colors.black,
          child: Center(child: Text(preview)),
        ),
        onOpenDiagnostic: (context) async {},
      ),
    ),
  );
}

final class _ScreenHarness {
  _ScreenHarness({
    PostCandidateProcessor<InMemoryOccurrence>? processor,
    OperationState? initialState,
  }) : processor = processor ??
            const _ImmediateProcessor(
              CandidateBlockedByCooldown(
                elapsed: Duration(seconds: 1),
                distanceMeters: 1,
              ),
            ) {
    controller = OperationController<String>(
      candidateSource: source,
      postCandidateProcessor: this.processor,
      camera: camera,
      location: location,
      screenAwake: screenAwake,
      clock: clock,
      initialState: initialState,
    );
  }

  final _FakeSource source = _FakeSource();
  final _FakeCamera camera = _FakeCamera();
  final _FakeLocation location = _FakeLocation();
  final _FakeScreenAwake screenAwake = _FakeScreenAwake();
  final _FakeClock clock = _FakeClock();
  final PostCandidateProcessor<InMemoryOccurrence> processor;
  late final OperationController<String> controller;

  void makeReady() {
    controller.publishCameraState(
      generation: controller.generation,
      status: OperationCameraStatus.ready,
    );
    controller.publishLocationState(
      generation: controller.generation,
      status: OperationLocationStatus.ready,
      snapshot: location.latestValidSnapshot,
    );
  }
}

final class _Point implements GeoPoint {
  const _Point();

  @override
  double get latitude => -23.5505;

  @override
  double get longitude => -46.6333;
}

final class _Snapshot implements LocationSnapshot {
  const _Snapshot();

  @override
  double? get accuracyMeters => 3.5;

  @override
  GeoPoint get point => const _Point();

  @override
  double? get speedMetersPerSecond => 10;
}

final class _FakeLocation implements OperationalLocationPort {
  var acquireCount = 0;
  var releaseCount = 0;

  @override
  LocationSnapshot? get latestValidSnapshot => const _Snapshot();

  @override
  Future<void> acquireForegroundUpdates() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }
}

final class _FakeCamera implements OperationalCameraPort<String> {
  var acquireCount = 0;
  var captureCount = 0;
  var releaseCount = 0;
  var releaseCompleted = false;

  @override
  String? get previewHandle => 'Preview traseiro';

  @override
  Future<void> acquirePreview() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
    releaseCompleted = true;
  }

  @override
  Future<TemporaryCapture> takePicture() async {
    captureCount++;
    return _FakeCapture();
  }
}

final class _FakeScreenAwake implements ScreenAwakePort {
  final List<bool> calls = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async {
    calls.add(enabled);
  }
}

final class _FakeClock implements Clock {
  @override
  DateTime now() => DateTime.parse('2025-05-06T07:08:09-03:00');
}

final class _FakeSource implements OccurrenceCandidateSource {
  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) async {
    return CandidateInput(
      observedAt: seed.observedAt,
      location: seed.location,
      defectClass: 'pothole',
      confidence: 1,
      acquireImage: seed.acquireImage,
    );
  }
}

final class _ImmediateProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  const _ImmediateProcessor(this.result);

  final CandidateResult<InMemoryOccurrence> result;

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) async {
    return result;
  }
}

final class _CompleterProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  final Completer<CandidateResult<InMemoryOccurrence>> _completer =
      Completer<CandidateResult<InMemoryOccurrence>>();

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) {
    return _completer.future;
  }

  void complete(CandidateResult<InMemoryOccurrence> result) {
    _completer.complete(result);
  }
}

final class _FakeCapture implements TemporaryCapture {
  @override
  Future<void> dispose() async {}
}
