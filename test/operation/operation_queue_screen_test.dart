import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/operation/operation_controller.dart';
import 'package:pavimenta_ai_mobile/operation/operation_screen.dart';
import 'package:pavimenta_ai_mobile/operation/operation_state.dart';
import 'package:pavimenta_ai_mobile/operation/operation_theme.dart';

void main() {
  group('OperationScreen E2 queue indicators', () {
    // **Validates: Requirements 05.4, 05.5, 12.5, RNF-08.10, RNF-08.14**
    testWidgets(
        'shows zero and multiple pending aggregates separately from session count',
        (tester) async {
      for (final testCase in <(int, int)>[(0, 0), (4, 2)]) {
        final harness = _Harness(
          initialState: OperationState.initial(
            queueSnapshot: QueueSnapshot(
              health: QueueHealth.ready,
              pendingCount: testCase.$1,
            ),
          ).copyWith(sessionOccurrenceCount: testCase.$2),
        );
        addTearDown(harness.dispose);

        await _pumpScreen(tester, harness.controller);

        expect(find.byKey(const Key('queue-panel')), findsOneWidget);
        expect(find.text('Pendências: ${testCase.$1}'), findsOneWidget);
        expect(
          find.text('Buracos registrados: ${testCase.$2}'),
          findsOneWidget,
        );
        expect(find.text('Fila local pronta.'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    // **Validates: Requirements 05.5, 12.5, RNF-08.5, RNF-08.10, RNF-08.14**
    testWidgets(
        'uses sanitized aggregate queue errors without queue management controls',
        (tester) async {
      final harness = _Harness(
        initialState: OperationState.initial(
          queueSnapshot: const QueueSnapshot(
            health: QueueHealth.degraded,
            pendingCount: 3,
          ),
        ).copyWith(
          feedback: const OperationFeedback(
            kind: OperationFeedbackKind.error,
            message: 'Não foi possível salvar na fila local.',
          ),
        ),
      );
      addTearDown(harness.dispose);

      await _pumpScreen(tester, harness.controller);

      final queuePanel = find.byKey(const Key('queue-panel'));
      expect(find.text('Pendências: 3'), findsOneWidget);
      expect(find.text('Degradada'), findsOneWidget);
      expect(
        find.text('Atenção: a fila local precisa de recuperação.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Pendências: 3. Degradada. Atenção: a fila local precisa de recuperação.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Erro: Não foi possível salvar na fila local.'),
        findsOneWidget,
      );

      for (final sensitiveValue in <String>[
        '123e4567-e89b-42d3-a456-426614174000',
        '/data/user/0/pavimenta/e2_queue_images_v1/opaque.jpg',
        'e2_queue_images_v1',
        '-23.550500',
        '0123456789abcdef',
      ]) {
        expect(
          find.descendant(
            of: queuePanel,
            matching: find.textContaining(sensitiveValue),
          ),
          findsNothing,
        );
      }

      for (final unavailableControl in <String>[
        'Lista de pendências',
        'Remover pendência',
        'Configurações',
        'Enviar agora',
        'Enviar pendências',
        'Detecção automática ativa',
      ]) {
        expect(find.text(unavailableControl), findsNothing);
      }
      expect(find.byKey(const Key('retry-queue-button')), findsNothing);
    });

    // **Validates: Requirements 03.8, 05.3, 12.1, 12.2, RNF-04.2, RNF-04.3**
    testWidgets(
        'keeps E1 indicators responsive while local persistence is in progress',
        (tester) async {
      final harness = _Harness(
        initialState: _readyState().copyWith(
          processingStatus: OperationProcessingStatus.processing,
          isBusy: true,
          isPersisting: true,
        ),
      );
      addTearDown(harness.dispose);

      await _pumpScreen(tester, harness.controller);

      expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
      expect(find.text('GPS pronto'), findsOneWidget);
      expect(find.text('Salvando na fila local'), findsOneWidget);
      expect(
        find.text('Persistindo a ocorrência e a imagem na fila local.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('register-pothole-button')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('open-diagnostic-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // **Validates: Requirements 05.4, 05.5, 12.1, 12.5**
    testWidgets('describes completed registration as a local queue save',
        (tester) async {
      final harness = _Harness(
        initialState: _readyState().copyWith(
          processingStatus: OperationProcessingStatus.succeeded,
          sessionOccurrenceCount: 1,
          pendingCount: 1,
          feedback: const OperationFeedback(
            kind: OperationFeedbackKind.success,
            message: 'Buraco salvo na fila local.',
          ),
        ),
      );
      addTearDown(harness.dispose);

      await _pumpScreen(tester, harness.controller);

      expect(
          find.text('A ocorrência foi salva na fila local.'), findsOneWidget);
      expect(find.text('A ocorrência foi criada somente em memória.'),
          findsNothing);
      expect(find.text('Pendências: 1'), findsOneWidget);
      expect(find.text('Buracos registrados: 1'), findsOneWidget);
    });

    // **Validates: Requirements 03.6, 03.7, 03.11, 05.1, 05.5, 12.5, 20.6,
    // 20.7, 21.1–7, RNF-04.2–3**
    testWidgets(
        'retries only the unavailable queue and preserves E1 resources and navigation',
        (tester) async {
      final queue = _RetryQueue();
      final harness = _Harness(queue: queue);
      var diagnosticOpenCount = 0;
      addTearDown(harness.dispose);

      await _pumpScreen(
        tester,
        harness.controller,
        onOpenDiagnostic: (context) async {
          diagnosticOpenCount++;
        },
      );
      await tester.pumpAndSettle();

      expect(queue.bootstrapCalls, 1);
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);
      expect(find.text('Fila local indisponível.'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('register-pothole-button')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('open-diagnostic-button')));
      await tester.pump();
      expect(diagnosticOpenCount, 1);

      await tester.ensureVisible(find.byKey(const Key('retry-queue-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('retry-queue-button')));
      await tester.pump();
      expect(queue.retryCalls, 1);
      expect(find.text('Recuperando fila local.'), findsOneWidget);
      expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
      expect(find.text('GPS pronto'), findsOneWidget);
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);
      expect(find.byKey(const Key('open-diagnostic-button')), findsOneWidget);

      queue.completeRetry(const QueueSnapshot(
        health: QueueHealth.ready,
        pendingCount: 2,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pendências: 2'), findsOneWidget);
      expect(find.text('Fila local pronta.'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('register-pothole-button')),
            )
            .onPressed,
        isNotNull,
      );
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);
    });
  });
}

OperationState _readyState() => OperationState.initial(
      queueSnapshot: const QueueSnapshot(
        health: QueueHealth.ready,
        pendingCount: 0,
      ),
    ).copyWith(
      cameraStatus: OperationCameraStatus.ready,
      previewHandle: 'Preview traseiro',
      locationStatus: OperationLocationStatus.ready,
      locationSnapshot: ImmutableLocationSnapshot(
        point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
        accuracyMeters: 3.5,
        speedMetersPerSecond: 10,
      ),
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  OperationController<String> controller, {
  OpenDiagnostic? onOpenDiagnostic,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildOperationTheme(),
      home: OperationScreen<String>(
        controller: controller,
        previewBuilder: (context, preview) => ColoredBox(
          key: const Key('fake-camera-preview'),
          color: Colors.black,
          child: Center(child: Text(preview)),
        ),
        onOpenDiagnostic: onOpenDiagnostic ?? (context) async {},
      ),
    ),
  );
}

final class _Harness {
  _Harness({OperationState? initialState, PersistentOccurrenceQueue? queue}) {
    controller = OperationController<String>(
      candidateSource: const _Source(),
      postCandidateProcessor: const _Processor(),
      camera: camera,
      location: location,
      screenAwake: const _ScreenAwake(),
      clock: const _Clock(),
      initialState: initialState,
      queue: queue,
    );
  }

  final _Camera camera = _Camera();
  final _Location location = _Location();
  late final OperationController<String> controller;

  void dispose() => controller.dispose();
}

final class _RetryQueue implements PersistentOccurrenceQueue {
  final Completer<QueueSnapshot> _retry = Completer<QueueSnapshot>();
  var bootstrapCalls = 0;
  var retryCalls = 0;

  @override
  Stream<QueueSnapshot> get snapshots => const Stream<QueueSnapshot>.empty();

  @override
  Future<QueueSnapshot> bootstrap() async {
    bootstrapCalls++;
    return const QueueSnapshot(
      health: QueueHealth.unavailable,
      pendingCount: 0,
    );
  }

  @override
  Future<QueueSnapshot> retryBootstrap() {
    retryCalls++;
    return _retry.future;
  }

  void completeRetry(QueueSnapshot snapshot) => _retry.complete(snapshot);

  @override
  Future<OccurrenceAcceptanceResult> persist(
          InMemoryOccurrence occurrence) async =>
      const OccurrenceStorageUnavailable();

  @override
  Future<List<ReconstructedPendingOccurrence>> listPending() async =>
      const <ReconstructedPendingOccurrence>[];

  @override
  Future<AcceptedOccurrenceAnchor?> readAcceptedAnchor() async => null;

  @override
  Future<int> countPending() async => 0;

  @override
  Future<QueueRemovalResult> removeInternal(String idempotencyKey) async =>
      const QueueOccurrenceRemovalFailed();

  @override
  Future<void> close() async {}
}

final class _Source implements OccurrenceCandidateSource {
  const _Source();

  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) async =>
      CandidateInput(
        observedAt: seed.observedAt,
        location: seed.location,
        defectClass: 'pothole',
        confidence: 1,
        acquireImage: seed.acquireImage,
      );
}

final class _Processor implements PostCandidateProcessor<InMemoryOccurrence> {
  const _Processor();

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) async =>
      const CandidateBlockedByCooldown(
        elapsed: Duration(seconds: 1),
        distanceMeters: 1,
      );
}

final class _Camera implements OperationalCameraPort<String> {
  var acquireCount = 0;

  @override
  String? get previewHandle => 'Preview traseiro';

  @override
  Future<void> acquirePreview() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {}

  @override
  Future<TemporaryCapture> takePicture() => throw UnimplementedError();
}

final class _Location implements OperationalLocationPort {
  var acquireCount = 0;

  @override
  LocationSnapshot? get latestValidSnapshot => const _Snapshot();

  @override
  Future<void> acquireForegroundUpdates() async {
    acquireCount++;
  }

  @override
  Future<void> release() async {}
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

final class _Point implements GeoPoint {
  const _Point();

  @override
  double get latitude => -23.5505;

  @override
  double get longitude => -46.6333;
}

final class _ScreenAwake implements ScreenAwakePort {
  const _ScreenAwake();

  @override
  Future<void> setEnabled(bool enabled) async {}
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2025);
}
