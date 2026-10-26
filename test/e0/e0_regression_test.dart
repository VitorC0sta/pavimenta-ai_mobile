import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/e0/camera_diagnostic.dart';
import 'package:pavimenta_ai_mobile/e0/diagnostic_http_client.dart';
import 'package:pavimenta_ai_mobile/e0/e0_controller.dart';
import 'package:pavimenta_ai_mobile/e0/e0_state.dart';
import 'package:pavimenta_ai_mobile/e0/location_diagnostic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Preserved E0 Diagnostic regression', () {
    // **Validates: Requirements 00.2, 00.6–10, 00.15, 00.20–22**
    test('keeps preview, serial permissions, GPS, and HTTPS available',
        () async {
      final events = <String>[];
      final camera = _FakeCameraDiagnostic(events);
      final location = _FakeLocationDiagnostic(
        events,
        const LocationDiagnosticResult.available(
          LocationDiagnosticReading(
            latitude: -23.5505,
            longitude: -46.6333,
            accuracyMeters: 3.5,
            speedMetersPerSecond: 4,
          ),
        ),
      );
      final http = _FakeHttpClient(
        const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.reachable,
          statusCode: 204,
        ),
      );
      final controller = E0Controller(
        cameraDiagnostic: camera,
        locationDiagnostic: location,
        diagnosticHttpClient: http,
      );
      addTearDown(controller.shutdown);

      await controller.handleLifecycleState(AppLifecycleState.resumed);

      expect(
        events,
        ['camera-discovery', 'camera-preview', 'location-start'],
      );
      expect(controller.state.permissionPhase,
          PermissionPhase.permissionsResolved);
      expect(controller.state.cameraStatus, CameraDiagnosticStatus.available);
      expect(controller.state.cameraController, same(camera.controller));
      expect(
          controller.state.locationStatus, LocationDiagnosticStatus.available);
      expect(controller.state.latitude, -23.5505);
      expect(controller.state.longitude, -46.6333);
      expect(controller.state.accuracyMeters, 3.5);
      expect(controller.state.speedMetersPerSecond, 4);

      await controller.runHttpsDiagnostic();
      expect(http.runCount, 1);
      expect(controller.state.httpsStatus, HttpsDiagnosticStatus.reachable);
      expect(controller.state.httpStatusCode, 204);
      expect(controller.state.httpsMessage, 'Destino de teste acessível.');
    });

    // **Validates: Requirements 00.7, 00.10, 00.12–15, 00.21**
    test('keeps E0 HTTPS validation restricted and controlled', () async {
      final invalidUrls = [
        '',
        '/health',
        'http://example.invalid/health',
        'https:///health',
        'https://user:secret@example.invalid/health',
        'https://example.invalid/health#fragment',
        'https://example.invalid/api/v1/occurrences',
      ];

      for (final url in invalidUrls) {
        final client = DiagnosticHttpClient(configuredUrl: url);
        final result = await client.run();
        expect(result.outcome, DiagnosticHttpOutcome.invalidConfiguration,
            reason: url);
        await client.dispose();
      }
    });

    // **Validates: Requirements 00.7–10, 00.15, 00.20–22**
    test('preserves controlled GPS/HTTPS messages and lifecycle cleanup',
        () async {
      final outcomes =
          <LocationDiagnosticOutcome, (LocationDiagnosticStatus, String)>{
        LocationDiagnosticOutcome.serviceDisabled: (
          LocationDiagnosticStatus.serviceDisabled,
          'Serviço de localização desativado.',
        ),
        LocationDiagnosticOutcome.permissionDenied: (
          LocationDiagnosticStatus.permissionDenied,
          'Permissão de localização negada.',
        ),
        LocationDiagnosticOutcome.permissionDeniedPermanently: (
          LocationDiagnosticStatus.permissionDeniedPermanently,
          'Permissão de localização negada permanentemente. Habilite-a nas configurações do Android.',
        ),
        LocationDiagnosticOutcome.reducedAccuracy: (
          LocationDiagnosticStatus.reducedAccuracy,
          'Localização precisa não autorizada.',
        ),
        LocationDiagnosticOutcome.positionUnavailable: (
          LocationDiagnosticStatus.positionUnavailable,
          'Posição indisponível.',
        ),
      };

      for (final entry in outcomes.entries) {
        final location = _FakeLocationDiagnostic(
          <String>[],
          LocationDiagnosticResult.withoutPosition(entry.key),
        );
        final http = _FakeHttpClient(
          const DiagnosticHttpResult(
            outcome: DiagnosticHttpOutcome.tlsFailure,
          ),
        );
        final controller = E0Controller(
          cameraDiagnostic: _NoRearCameraDiagnostic(),
          locationDiagnostic: location,
          diagnosticHttpClient: http,
        );

        await controller.handleLifecycleState(AppLifecycleState.resumed);
        expect(
            controller.state.cameraStatus, CameraDiagnosticStatus.noRearCamera);
        expect(controller.state.locationStatus, entry.value.$1,
            reason: entry.key.name);
        expect(controller.state.locationMessage, entry.value.$2,
            reason: entry.key.name);
        await controller.runHttpsDiagnostic();
        expect(controller.state.httpsStatus, HttpsDiagnosticStatus.tlsFailure);
        expect(
          controller.state.httpsMessage,
          'Falha na validação TLS do destino de teste.',
        );

        await controller.handleLifecycleState(AppLifecycleState.paused);
        expect(controller.state.cameraStatus, CameraDiagnosticStatus.paused);
        expect(
            controller.state.locationStatus, LocationDiagnosticStatus.paused);
        expect(location.stopCount, greaterThanOrEqualTo(1));
        expect(http.cancelCount, greaterThanOrEqualTo(1));
        await controller.shutdown();
      }
    });
  });
}

class _FakeCameraDiagnostic extends CameraDiagnostic {
  _FakeCameraDiagnostic(this.events);

  final List<String> events;
  late final CameraController controller;

  @override
  Future<List<CameraDescription>> enumerateAvailableCameras() async {
    events.add('camera-discovery');
    return [_backCamera];
  }

  @override
  Future<CameraController> initializePreviewController(
    CameraDescription backCamera,
  ) async {
    events.add('camera-preview');
    controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    controller.value = controller.value.copyWith(
      isInitialized: true,
      previewSize: const Size(1280, 720),
    );
    return controller;
  }
}

class _NoRearCameraDiagnostic extends CameraDiagnostic {
  @override
  Future<List<CameraDescription>> enumerateAvailableCameras() async => const [];
}

class _FakeLocationDiagnostic extends LocationDiagnostic {
  _FakeLocationDiagnostic(this.events, this.result);

  final List<String> events;
  final LocationDiagnosticResult result;
  var stopCount = 0;

  @override
  bool get isRunning => false;

  @override
  bool get isStarting => false;

  @override
  bool get permissionRequestNeedsReconciliation => false;

  @override
  Future<LocationDiagnosticResult> start({
    required LocationDiagnosticUpdate onUpdate,
    bool allowPermissionRequest = true,
  }) async {
    events.add('location-start');
    return result;
  }

  @override
  void markPermissionRequestReconciled() {}

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() => stop();
}

class _FakeHttpClient extends DiagnosticHttpClient {
  _FakeHttpClient(this.result);

  final DiagnosticHttpResult result;
  var runCount = 0;
  var cancelCount = 0;

  @override
  Future<DiagnosticHttpResult> run() async {
    runCount++;
    return result;
  }

  @override
  Future<void> cancelActive() async {
    cancelCount++;
  }

  @override
  Future<void> dispose() => cancelActive();
}

const CameraDescription _backCamera = CameraDescription(
  name: 'rear',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
