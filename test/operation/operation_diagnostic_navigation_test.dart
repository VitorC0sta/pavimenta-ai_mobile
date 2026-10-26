import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/main.dart';
import 'package:pavimenta_ai_mobile/operation/diagnostic_session_disposal.dart';
import 'package:pavimenta_ai_mobile/operation/operation_controller.dart';

void main() {
  group('Operation and Diagnostic resource ownership', () {
    // **Validates: Requirements 00.4, 00.20, 03.10, 03.11, 21.2, 21.6**
    testWidgets('repeated taps open one Diagnostic session after full release',
        (tester) async {
      final harness = _NavigationHarness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp());
      await _settleRouteAndResources(tester);

      expect(harness.tracker.activeCameraOwner, 'operation-1');
      expect(harness.tracker.activeLocationOwner, 'operation-1');

      final button = find.byKey(const Key('open-diagnostic-button'));
      final onPressed = tester.widget<OutlinedButton>(button).onPressed!;
      onPressed();
      onPressed();
      onPressed();
      await _settleRouteAndResources(tester);

      expect(harness.diagnosticBuildCount, 1);
      expect(find.text('Diagnóstico sessão 1'), findsOneWidget);
      expect(harness.tracker.activeCameraOwner, 'diagnostic-1');
      expect(harness.tracker.activeLocationOwner, 'diagnostic-1');
      expect(harness.tracker.violations, isEmpty);
      expect(
        harness.tracker.events,
        [
          'camera+ operation-1',
          'camera-permission operation-1',
          'location+ operation-1',
          'location-permission operation-1',
          'stream+ operation-1',
          'stream- operation-1',
          'location- operation-1',
          'camera- operation-1',
          'camera+ diagnostic-1',
          'camera-permission diagnostic-1',
          'location+ diagnostic-1',
          'location-permission diagnostic-1',
          'stream+ diagnostic-1',
        ],
      );

      Navigator.of(
        tester.element(find.text('Diagnóstico sessão 1')),
      ).pop();
      await _settleRouteAndResources(tester);

      expect(harness.tracker.activeCameraOwner, 'operation-2');
      expect(harness.tracker.activeLocationOwner, 'operation-2');
      expect(harness.operationCamera.acquireCount, 2);
      expect(harness.operationCamera.releaseCount, 1);
      expect(harness.operationLocation.streamStartCount, 2);
      expect(harness.operationLocation.streamStopCount, 1);
      expect(harness.diagnosticDisposeCount, 1);
      expect(harness.tracker.violations, isEmpty);
      expect(
        harness.tracker.events,
        [
          'camera+ operation-1',
          'camera-permission operation-1',
          'location+ operation-1',
          'location-permission operation-1',
          'stream+ operation-1',
          'stream- operation-1',
          'location- operation-1',
          'camera- operation-1',
          'camera+ diagnostic-1',
          'camera-permission diagnostic-1',
          'location+ diagnostic-1',
          'location-permission diagnostic-1',
          'stream+ diagnostic-1',
          'stream- diagnostic-1',
          'location- diagnostic-1',
          'camera- diagnostic-1',
          'camera+ operation-2',
          'camera-permission operation-2',
          'location+ operation-2',
          'location-permission operation-2',
          'stream+ operation-2',
        ],
      );
    });

    // **Validates: Requirements 00.20, 03.11, 21.2, 21.6, RNF-04.1–3**
    testWidgets(
        'repeated routes use fresh sessions without duplicate permission or streams',
        (tester) async {
      final harness = _NavigationHarness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp());
      await _settleRouteAndResources(tester);

      for (var session = 1; session <= 2; session++) {
        await tester.tap(find.byKey(const Key('open-diagnostic-button')));
        await _settleRouteAndResources(tester);

        expect(find.text('Diagnóstico sessão $session'), findsOneWidget);
        expect(harness.tracker.activeCameraOwner, 'diagnostic-$session');
        expect(harness.tracker.activeLocationOwner, 'diagnostic-$session');

        Navigator.of(
          tester.element(find.text('Diagnóstico sessão $session')),
        ).pop();
        await _settleRouteAndResources(tester);

        expect(harness.tracker.activeCameraOwner, 'operation-${session + 1}');
        expect(
          harness.tracker.activeLocationOwner,
          'operation-${session + 1}',
        );
      }

      expect(harness.diagnosticBuildCount, 2);
      expect(harness.diagnosticDisposeCount, 2);
      expect(harness.operationCamera.acquireCount, 3);
      expect(harness.operationCamera.releaseCount, 2);
      expect(harness.operationLocation.acquireCount, 3);
      expect(harness.operationLocation.releaseCount, 2);
      expect(harness.operationLocation.streamStartCount, 3);
      expect(harness.operationLocation.streamStopCount, 2);
      expect(harness.tracker.maxConcurrentCameraOwners, 1);
      expect(harness.tracker.maxConcurrentLocationOwners, 1);
      expect(harness.tracker.maxConcurrentLocationStreams, 1);
      expect(harness.tracker.violations, isEmpty);

      for (final owner in [
        'operation-1',
        'diagnostic-1',
        'operation-2',
        'diagnostic-2',
        'operation-3',
      ]) {
        expect(
          harness.tracker.cameraPermissionEntries[owner],
          1,
          reason: 'camera permission authority duplicated for $owner',
        );
        expect(
          harness.tracker.locationPermissionEntries[owner],
          1,
          reason: 'location permission authority duplicated for $owner',
        );
        expect(
          harness.tracker.locationStreamStarts[owner],
          1,
          reason: 'location stream duplicated for $owner',
        );
      }
    });
  });
}

Future<void> _settleRouteAndResources(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

final class _NavigationHarness {
  _NavigationHarness() {
    operationCamera = _TrackedOperationCamera(tracker);
    operationLocation = _TrackedOperationLocation(
      tracker,
      () => operationCamera.currentOwner,
    );
    controller = OperationController<String>(
      candidateSource: const _UnusedCandidateSource(),
      postCandidateProcessor: const _UnusedProcessor(),
      camera: operationCamera,
      location: operationLocation,
      screenAwake: _FakeScreenAwake(),
      clock: const _FakeClock(),
    );
  }

  final _ResourceOwnershipTracker tracker = _ResourceOwnershipTracker();
  late final _TrackedOperationCamera operationCamera;
  late final _TrackedOperationLocation operationLocation;
  late final OperationController<String> controller;
  var diagnosticBuildCount = 0;
  var diagnosticDisposeCount = 0;

  Widget buildApp() {
    return PavimentaAiMobileApp<String>(
      operationController: controller,
      previewBuilder: (context, preview) => Text(preview),
      diagnosticPageBuilder: (context, disposal) {
        final session = ++diagnosticBuildCount;
        return _TrackedDiagnosticSession(
          session: session,
          disposal: disposal,
          tracker: tracker,
          onDisposed: () => diagnosticDisposeCount++,
        );
      },
    );
  }

  void dispose() {
    controller.dispose();
  }
}

final class _TrackedDiagnosticSession extends StatefulWidget {
  const _TrackedDiagnosticSession({
    required this.session,
    required this.disposal,
    required this.tracker,
    required this.onDisposed,
  });

  final int session;
  final DiagnosticSessionDisposal disposal;
  final _ResourceOwnershipTracker tracker;
  final VoidCallback onDisposed;

  @override
  State<_TrackedDiagnosticSession> createState() =>
      _TrackedDiagnosticSessionState();
}

final class _TrackedDiagnosticSessionState
    extends State<_TrackedDiagnosticSession> {
  late final String _owner = 'diagnostic-${widget.session}';

  @override
  void initState() {
    super.initState();
    widget.tracker.acquireCamera(_owner);
    widget.tracker.enterCameraPermissionAuthority(_owner);
    widget.tracker.acquireLocation(_owner);
    widget.tracker.enterLocationPermissionAuthority(_owner);
    widget.tracker.startLocationStream(_owner);
  }

  @override
  void dispose() {
    widget.onDisposed();
    widget.disposal.completeAfter(_releaseResources());
    super.dispose();
  }

  Future<void> _releaseResources() async {
    widget.tracker.stopLocationStream(_owner);
    widget.tracker.releaseLocation(_owner);
    widget.tracker.releaseCamera(_owner);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text('Diagnóstico sessão ${widget.session}'));
  }
}

final class _ResourceOwnershipTracker {
  final events = <String>[];
  final violations = <String>[];
  final cameraPermissionEntries = <String, int>{};
  final locationPermissionEntries = <String, int>{};
  final locationStreamStarts = <String, int>{};

  String? activeCameraOwner;
  String? activeLocationOwner;
  String? activeLocationStreamOwner;
  var maxConcurrentCameraOwners = 0;
  var maxConcurrentLocationOwners = 0;
  var maxConcurrentLocationStreams = 0;

  void acquireCamera(String owner) {
    final concurrentOwners = activeCameraOwner == null ? 1 : 2;
    if (activeCameraOwner != null) {
      violations.add('camera overlap: $activeCameraOwner -> $owner');
    }
    activeCameraOwner = owner;
    if (concurrentOwners > maxConcurrentCameraOwners) {
      maxConcurrentCameraOwners = concurrentOwners;
    }
    events.add('camera+ $owner');
  }

  void releaseCamera(String owner) {
    if (activeCameraOwner != owner) {
      violations.add('camera release by $owner, owned by $activeCameraOwner');
    }
    activeCameraOwner = null;
    events.add('camera- $owner');
  }

  void acquireLocation(String owner) {
    final concurrentOwners = activeLocationOwner == null ? 1 : 2;
    if (activeLocationOwner != null) {
      violations.add('location overlap: $activeLocationOwner -> $owner');
    }
    activeLocationOwner = owner;
    if (concurrentOwners > maxConcurrentLocationOwners) {
      maxConcurrentLocationOwners = concurrentOwners;
    }
    events.add('location+ $owner');
  }

  void releaseLocation(String owner) {
    if (activeLocationOwner != owner) {
      violations.add(
        'location release by $owner, owned by $activeLocationOwner',
      );
    }
    activeLocationOwner = null;
    events.add('location- $owner');
  }

  void enterCameraPermissionAuthority(String owner) {
    cameraPermissionEntries.update(owner, (count) => count + 1,
        ifAbsent: () => 1);
    events.add('camera-permission $owner');
  }

  void enterLocationPermissionAuthority(String owner) {
    locationPermissionEntries.update(owner, (count) => count + 1,
        ifAbsent: () => 1);
    events.add('location-permission $owner');
  }

  void startLocationStream(String owner) {
    final concurrentStreams = activeLocationStreamOwner == null ? 1 : 2;
    if (activeLocationStreamOwner != null) {
      violations.add(
        'stream overlap: $activeLocationStreamOwner -> $owner',
      );
    }
    activeLocationStreamOwner = owner;
    locationStreamStarts.update(owner, (count) => count + 1, ifAbsent: () => 1);
    if (concurrentStreams > maxConcurrentLocationStreams) {
      maxConcurrentLocationStreams = concurrentStreams;
    }
    events.add('stream+ $owner');
  }

  void stopLocationStream(String owner) {
    if (activeLocationStreamOwner != owner) {
      violations.add(
        'stream stop by $owner, owned by $activeLocationStreamOwner',
      );
    }
    activeLocationStreamOwner = null;
    events.add('stream- $owner');
  }
}

final class _TrackedOperationCamera implements OperationalCameraPort<String> {
  _TrackedOperationCamera(this.tracker);

  final _ResourceOwnershipTracker tracker;
  var acquireCount = 0;
  var releaseCount = 0;
  String? currentOwner;

  @override
  String? get previewHandle => currentOwner == null ? null : 'Preview';

  @override
  Future<void> acquirePreview() async {
    currentOwner = 'operation-${++acquireCount}';
    tracker.acquireCamera(currentOwner!);
    tracker.enterCameraPermissionAuthority(currentOwner!);
  }

  @override
  Future<void> release() async {
    releaseCount++;
    tracker.releaseCamera(currentOwner!);
    currentOwner = null;
  }

  @override
  Future<TemporaryCapture> takePicture() {
    throw UnsupportedError('Capture is outside this navigation test.');
  }
}

final class _TrackedOperationLocation implements OperationalLocationPort {
  _TrackedOperationLocation(this.tracker, this.owner);

  final _ResourceOwnershipTracker tracker;
  final String? Function() owner;
  var acquireCount = 0;
  var releaseCount = 0;
  var streamStartCount = 0;
  var streamStopCount = 0;
  String? currentOwner;

  @override
  LocationSnapshot? get latestValidSnapshot => const _Snapshot();

  @override
  Future<void> acquireForegroundUpdates() async {
    acquireCount++;
    currentOwner = owner();
    tracker.acquireLocation(currentOwner!);
    tracker.enterLocationPermissionAuthority(currentOwner!);
    tracker.startLocationStream(currentOwner!);
    streamStartCount++;
  }

  @override
  Future<void> release() async {
    releaseCount++;
    tracker.stopLocationStream(currentOwner!);
    tracker.releaseLocation(currentOwner!);
    streamStopCount++;
    currentOwner = null;
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
  double? get accuracyMeters => 3;

  @override
  GeoPoint get point => const _Point();

  @override
  double? get speedMetersPerSecond => 0;
}

final class _FakeScreenAwake implements ScreenAwakePort {
  @override
  Future<void> setEnabled(bool enabled) async {}
}

final class _FakeClock implements Clock {
  const _FakeClock();

  @override
  DateTime now() => DateTime.utc(2025);
}

final class _UnusedCandidateSource implements OccurrenceCandidateSource {
  const _UnusedCandidateSource();

  @override
  Future<CandidateInput> requestCandidate(CandidateSeed seed) {
    throw UnsupportedError('Registration is outside this navigation test.');
  }
}

final class _UnusedProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  const _UnusedProcessor();

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) {
    throw UnsupportedError('Registration is outside this navigation test.');
  }
}
