import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/operation/operation_controller.dart';
import 'package:pavimenta_ai_mobile/operation/operation_screen.dart';
import 'package:pavimenta_ai_mobile/operation/operation_state.dart';
import 'package:pavimenta_ai_mobile/operation/operation_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('E1 permission retry coordination', () {
    // **Validates: Requirements 03.6, 03.7, 06.3, 06.4, 20.1–7**
    test('camera denial retries camera only and deduplicates repeated taps',
        () async {
      final harness = _PermissionHarness(
        cameraOutcomes: [OperationalCameraFailure.permissionDenied, null],
        locationOutcomes: [null],
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.startOperationalLifecycle();
      expect(harness.controller.state.cameraStatus,
          OperationCameraStatus.permissionDenied);
      expect(harness.controller.state.locationStatus,
          OperationLocationStatus.ready);
      expect(harness.controller.state.canRegister, isFalse);
      expect(harness.camera.captureCount, 0);

      final retryGate = Completer<void>();
      harness.camera.nextAcquireGate = retryGate;
      final firstRetry = harness.controller.retryCameraReadiness();
      final repeatedRetry = harness.controller.retryCameraReadiness();
      await Future<void>.delayed(Duration.zero);

      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 1);
      expect(harness.controller.state.cameraStatus,
          OperationCameraStatus.initializing);
      expect(harness.controller.state.locationStatus,
          OperationLocationStatus.ready);
      expect(harness.controller.state.canRegister, isFalse);

      retryGate.complete();
      await Future.wait([firstRetry, repeatedRetry]);
      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 1);
      expect(
          harness.controller.state.cameraStatus, OperationCameraStatus.ready);
      expect(harness.controller.state.canRegister, isTrue);
      await _expectNoReadinessLoop(harness);
    });

    // **Validates: Requirements 03.6, 03.7, 06.3, 06.4, 20.1–7**
    test('location denial retries GPS only and deduplicates repeated taps',
        () async {
      final harness = _PermissionHarness(
        cameraOutcomes: [null],
        locationOutcomes: [OperationalLocationFailure.permissionDenied, null],
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.startOperationalLifecycle();
      expect(
          harness.controller.state.cameraStatus, OperationCameraStatus.ready);
      expect(harness.controller.state.locationStatus,
          OperationLocationStatus.permissionDenied);
      expect(harness.controller.state.canRegister, isFalse);

      final retryGate = Completer<void>();
      harness.location.nextAcquireGate = retryGate;
      final firstRetry = harness.controller.retryLocationReadiness();
      final repeatedRetry = harness.controller.retryLocationReadiness();
      await Future<void>.delayed(Duration.zero);

      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 2);
      expect(
          harness.controller.state.cameraStatus, OperationCameraStatus.ready);
      expect(harness.controller.state.locationStatus,
          OperationLocationStatus.initializing);

      retryGate.complete();
      await Future.wait([firstRetry, repeatedRetry]);
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 2);
      expect(harness.controller.state.locationStatus,
          OperationLocationStatus.ready);
      expect(harness.controller.state.canRegister, isTrue);
      await _expectNoReadinessLoop(harness);
    });

    // **Validates: Requirements 03.6, 03.7, 20.1–7, RNF-04.2**
    test('both denials recover independently without concurrent requests',
        () async {
      final harness = _PermissionHarness(
        cameraOutcomes: [OperationalCameraFailure.permissionDenied, null],
        locationOutcomes: [OperationalLocationFailure.permissionDenied, null],
        emitPermissionLifecycle: true,
      );
      addTearDown(harness.controller.dispose);

      await harness.controller.startOperationalLifecycle();
      expect(harness.controller.generation, 0);
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 1);
      expect(harness.controller.state.cameraStatus,
          OperationCameraStatus.permissionDenied);
      expect(harness.controller.state.locationStatus,
          OperationLocationStatus.permissionDenied);
      expect(harness.camera.captureCount, 0);

      final cameraGate = Completer<void>();
      harness.camera.nextAcquireGate = cameraGate;
      final cameraRetry = harness.controller.retryCameraReadiness();
      final blockedLocationRetry = harness.controller.retryLocationReadiness();
      await Future<void>.delayed(Duration.zero);

      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 1);
      expect(harness.controller.state.locationStatus,
          OperationLocationStatus.permissionDenied);
      cameraGate.complete();
      await Future.wait([cameraRetry, blockedLocationRetry]);

      expect(
          harness.controller.state.cameraStatus, OperationCameraStatus.ready);
      expect(harness.controller.state.locationStatus,
          OperationLocationStatus.permissionDenied);
      await harness.controller.retryLocationReadiness();
      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 2);
      expect(harness.controller.state.canRegister, isTrue);
      expect(harness.camera.captureCount, 0);
      await _expectNoReadinessLoop(harness);
    });
  });

  group('E1 permission-denial rendering', () {
    // **Validates: Requirements 03.6, 03.7, 05.1, 06.4, 20.3–7, RNF-04.2**
    testWidgets('camera denial keeps GPS card stable and gives retry guidance',
        (tester) async {
      final harness = _PermissionHarness(
        cameraOutcomes: [OperationalCameraFailure.permissionDenied, null],
        locationOutcomes: [null],
      );
      addTearDown(harness.controller.dispose);
      await _pumpScreen(tester, harness.controller);

      expect(find.text('Permissão de câmera negada'), findsOneWidget);
      expect(
        find.textContaining('Autorize a câmera quando o Android solicitar'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('retry-camera-button')), findsOneWidget);
      expect(_registerButton(tester).onPressed, isNull);
      final panelGap =
          tester.getTopLeft(find.byKey(const Key('location-panel'))).dy -
              tester.getTopLeft(find.byKey(const Key('camera-panel'))).dy;

      final retryGate = Completer<void>();
      addTearDown(() {
        if (!retryGate.isCompleted) {
          retryGate.complete();
        }
      });
      harness.camera.nextAcquireGate = retryGate;
      await tester.ensureVisible(find.byKey(const Key('retry-camera-button')));
      await tester.tap(find.byKey(const Key('retry-camera-button')));
      await tester.tap(find.byKey(const Key('retry-camera-button')));
      await tester.pump();

      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 1);
      expect(
        tester.getTopLeft(find.byKey(const Key('location-panel'))).dy -
            tester.getTopLeft(find.byKey(const Key('camera-panel'))).dy,
        panelGap,
      );
      expect(_registerButton(tester).onPressed, isNull);

      retryGate.complete();
      await tester.pump();
      await harness.controller.lifecycleSettled;
      await tester.pump();
      expect(harness.camera.acquireCount, 2);
      expect(harness.location.acquireCount, 1);
      expect(
        tester.getTopLeft(find.byKey(const Key('location-panel'))).dy -
            tester.getTopLeft(find.byKey(const Key('camera-panel'))).dy,
        panelGap,
      );
      expect(_registerButton(tester).onPressed, isNotNull);
      expect(harness.camera.captureCount, 0);
    });

    // **Validates: Requirements 03.7, 05.1, 06.3, 06.4, 20.2, 20.4, 20.7**
    testWidgets('GPS denial keeps surrounding layout stable and gives retry',
        (tester) async {
      final harness = _PermissionHarness(
        cameraOutcomes: [null],
        locationOutcomes: [OperationalLocationFailure.permissionDenied, null],
      );
      addTearDown(harness.controller.dispose);
      await _pumpScreen(tester, harness.controller);

      expect(find.text('Permissão de localização negada'), findsOneWidget);
      expect(
        find.textContaining(
            'Autorize a localização precisa quando o Android solicitar'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('retry-location-button')), findsOneWidget);
      expect(_registerButton(tester).onPressed, isNull);
      final panelGap =
          tester.getTopLeft(find.byKey(const Key('session-panel'))).dy -
              tester.getTopLeft(find.byKey(const Key('location-panel'))).dy;

      final retryGate = Completer<void>();
      addTearDown(() {
        if (!retryGate.isCompleted) {
          retryGate.complete();
        }
      });
      harness.location.nextAcquireGate = retryGate;
      await tester
          .ensureVisible(find.byKey(const Key('retry-location-button')));
      await tester.tap(find.byKey(const Key('retry-location-button')));
      await tester.tap(find.byKey(const Key('retry-location-button')));
      await tester.pump();

      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 2);
      expect(
        tester.getTopLeft(find.byKey(const Key('session-panel'))).dy -
            tester.getTopLeft(find.byKey(const Key('location-panel'))).dy,
        panelGap,
      );

      retryGate.complete();
      await tester.pump();
      await harness.controller.lifecycleSettled;
      await tester.pump();
      expect(harness.camera.acquireCount, 1);
      expect(harness.location.acquireCount, 2);
      expect(
        tester.getTopLeft(find.byKey(const Key('session-panel'))).dy -
            tester.getTopLeft(find.byKey(const Key('location-panel'))).dy,
        panelGap,
      );
      expect(_registerButton(tester).onPressed, isNotNull);
    });

    // **Validates: Requirements 03.6, 03.7, 05.1, 06.3, 06.4, 20.1–7, RNF-04.2**
    testWidgets('both permanent denials offer serialized Android settings',
        (tester) async {
      final settingsGate = Completer<bool>();
      addTearDown(() {
        if (!settingsGate.isCompleted) {
          settingsGate.complete(false);
        }
      });
      final harness = _PermissionHarness(
        cameraOutcomes: [
          OperationalCameraFailure.permissionDeniedPermanently,
        ],
        locationOutcomes: [
          OperationalLocationFailure.permissionDeniedPermanently,
        ],
        settingsResult: settingsGate,
      );
      addTearDown(harness.controller.dispose);
      await _pumpScreen(tester, harness.controller);

      expect(find.text('Permissão bloqueada'), findsNWidgets(2));
      expect(
        find.textContaining(
            'A permissão não pode mais ser solicitada pelo aplicativo'),
        findsNWidgets(2),
      );
      expect(
          find.byKey(const Key('open-camera-settings-button')), findsOneWidget);
      expect(find.byKey(const Key('open-location-settings-button')),
          findsOneWidget);
      expect(find.byKey(const Key('retry-camera-button')), findsNothing);
      expect(find.byKey(const Key('retry-location-button')), findsNothing);
      expect(_registerButton(tester).onPressed, isNull);

      await tester.ensureVisible(
        find.byKey(const Key('open-camera-settings-button')),
      );
      await tester.tap(find.byKey(const Key('open-camera-settings-button')));
      await tester.pump();
      expect(harness.appSettings.openCount, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('open-location-settings-button')),
            )
            .onPressed,
        isNull,
      );
      expect(
          find.textContaining('Ative a permissão necessária'), findsOneWidget);

      settingsGate.complete(true);
      await tester.pump();
      await harness.controller.lifecycleSettled;
      await tester.pump();
      expect(harness.appSettings.openCount, 1);
      expect(_registerButton(tester).onPressed, isNull);
      expect(harness.camera.captureCount, 0);
    });
  });
}

ElevatedButton _registerButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(
      find.byKey(const Key('register-pothole-button')),
    );

Future<void> _expectNoReadinessLoop(_PermissionHarness harness) async {
  final cameraCount = harness.camera.acquireCount;
  final locationCount = harness.location.acquireCount;
  final generation = harness.controller.generation;
  await Future<void>.delayed(const Duration(milliseconds: 30));
  expect(harness.camera.acquireCount, cameraCount);
  expect(harness.location.acquireCount, locationCount);
  expect(harness.controller.generation, generation);
}

Future<void> _pumpScreen(
  WidgetTester tester,
  OperationController<String> controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildOperationTheme(),
      home: OperationScreen<String>(
        controller: controller,
        previewBuilder: (context, preview) => ColoredBox(
          key: const Key('fake-camera-preview'),
          color: Colors.black,
          child: Text(preview),
        ),
        onOpenDiagnostic: (context) async {},
      ),
    ),
  );
  for (var pump = 0; pump < 15; pump++) {
    await tester.pump(const Duration(milliseconds: 2));
  }
}

final class _PermissionHarness {
  _PermissionHarness({
    required List<OperationalCameraFailure?> cameraOutcomes,
    required List<OperationalLocationFailure?> locationOutcomes,
    this.emitPermissionLifecycle = false,
    Completer<bool>? settingsResult,
  })  : camera = _PermissionCamera(cameraOutcomes),
        location = _PermissionLocation(locationOutcomes),
        appSettings = _AppSettings(settingsResult) {
    controller = OperationController<String>(
      candidateSource: const _UnusedSource(),
      postCandidateProcessor: const _UnusedProcessor(),
      camera: camera,
      location: location,
      screenAwake: const _Awake(),
      clock: const _Clock(),
      appSettings: appSettings,
    );
    camera.onPermissionPrompt = _emitPermissionLifecycle;
    location.onPermissionPrompt = _emitPermissionLifecycle;
  }

  final bool emitPermissionLifecycle;
  final _PermissionCamera camera;
  final _PermissionLocation location;
  final _AppSettings appSettings;
  late final OperationController<String> controller;

  Future<void> _emitPermissionLifecycle() async {
    if (!emitPermissionLifecycle) {
      return;
    }
    unawaited(
      controller.updateOperationalContext(
        lifecycleState: AppLifecycleState.inactive,
        isVisible: true,
        isForeground: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 10), () async {
        await controller.updateOperationalContext(
          lifecycleState: AppLifecycleState.resumed,
          isVisible: true,
          isForeground: true,
        );
      }),
    );
  }
}

final class _PermissionCamera implements OperationalCameraPort<String> {
  _PermissionCamera(this._outcomes);

  final List<OperationalCameraFailure?> _outcomes;
  Future<void> Function()? onPermissionPrompt;
  Completer<void>? nextAcquireGate;
  var acquireCount = 0;
  var captureCount = 0;
  var _ready = false;

  @override
  String? get previewHandle => _ready ? 'Preview traseiro' : null;

  @override
  Future<void> acquirePreview() async {
    acquireCount++;
    _ready = false;
    final gate = nextAcquireGate;
    nextAcquireGate = null;
    await gate?.future;
    final outcome = _outcomes.isEmpty ? null : _outcomes.removeAt(0);
    if (outcome != null) {
      await onPermissionPrompt?.call();
      throw OperationalCameraException(outcome);
    }
    _ready = true;
  }

  @override
  Future<void> release() async {
    _ready = false;
  }

  @override
  Future<TemporaryCapture> takePicture() async {
    captureCount++;
    return const _Capture();
  }
}

final class _PermissionLocation implements OperationalLocationPort {
  _PermissionLocation(this._outcomes);

  final List<OperationalLocationFailure?> _outcomes;
  Future<void> Function()? onPermissionPrompt;
  Completer<void>? nextAcquireGate;
  var acquireCount = 0;
  var _ready = false;

  @override
  LocationSnapshot? get latestValidSnapshot =>
      _ready ? const _Snapshot() : null;

  @override
  Future<void> acquireForegroundUpdates() async {
    acquireCount++;
    _ready = false;
    final gate = nextAcquireGate;
    nextAcquireGate = null;
    await gate?.future;
    final outcome = _outcomes.isEmpty ? null : _outcomes.removeAt(0);
    if (outcome != null) {
      await onPermissionPrompt?.call();
      throw OperationalLocationException(outcome);
    }
    _ready = true;
  }

  @override
  Future<void> release() async {
    _ready = false;
  }
}

final class _AppSettings implements AppSettingsPort {
  _AppSettings(Completer<bool>? result) : _result = result;

  final Completer<bool>? _result;
  var openCount = 0;

  @override
  Future<bool> open() async {
    openCount++;
    return _result == null ? true : _result.future;
  }
}

final class _Snapshot implements LocationSnapshot {
  const _Snapshot();

  @override
  double? get accuracyMeters => 4;

  @override
  GeoPoint get point => ImmutableGeoPoint(
        latitude: -23.5,
        longitude: -46.6,
      );

  @override
  double? get speedMetersPerSecond => 0;
}

final class _UnusedSource implements OccurrenceCandidateSource {
  const _UnusedSource();

  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) =>
      throw UnsupportedError('capture must remain disabled');
}

final class _UnusedProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  const _UnusedProcessor();

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) =>
      throw UnsupportedError('capture must remain disabled');
}

final class _Awake implements ScreenAwakePort {
  const _Awake();

  @override
  Future<void> setEnabled(bool enabled) async {}
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2025);
}

final class _Capture implements TemporaryCapture {
  const _Capture();

  @override
  Future<void> dispose() async {}
}
