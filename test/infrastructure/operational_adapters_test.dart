import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/post_candidate_processor.dart';
import 'package:pavimenta_ai_mobile/candidate/occurrence_candidate_source.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/operational_app_settings.dart';
import 'package:pavimenta_ai_mobile/infrastructure/operational_camera.dart';
import 'package:pavimenta_ai_mobile/infrastructure/operational_location.dart';
import 'package:pavimenta_ai_mobile/infrastructure/private_image_store.dart';
import 'package:pavimenta_ai_mobile/operation/operation_controller.dart';
import 'package:pavimenta_ai_mobile/operation/operation_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OperationalCamera adapter', () {
    // **Validates: Requirements 03.1, 03.5, 03.6, 20.1, 20.3, 20.6**
    test('selects the rear camera and captures into private E1 storage',
        () async {
      final sandbox = await Directory.systemTemp.createTemp('e1_camera_test_');
      addTearDown(() => sandbox.delete(recursive: true));
      final store = PrivateImageStore.at(sandbox);
      final pluginCapture = File('${sandbox.path}${Platform.pathSeparator}raw');
      await pluginCapture.writeAsBytes([1, 2, 3]);
      final front = _description('front', CameraLensDirection.front);
      final back = _description('back', CameraLensDirection.back);
      CameraController? selected;
      var initializeCount = 0;
      var captureCount = 0;
      var disposeCount = 0;

      final camera = OperationalCamera(
        imageStore: store,
        discoverCameras: () async => [front, back],
        createController: (description) {
          selected = CameraController(
            description,
            ResolutionPreset.medium,
            enableAudio: false,
          );
          return selected!;
        },
        initializeController: (_) async => initializeCount++,
        isControllerReady: (_) => true,
        takePicture: (controller) async {
          expect(controller, same(selected));
          captureCount++;
          return XFile(pluginCapture.path);
        },
        disposeController: (_) async => disposeCount++,
      );

      await camera.acquirePreview();
      expect(camera.previewHandle, same(selected));
      expect(selected!.description, back);
      expect(selected!.resolutionPreset, ResolutionPreset.medium);
      expect(selected!.enableAudio, isFalse);
      expect(initializeCount, 1);

      final capture = await camera.takePicture();
      expect(capture, isA<PrivateTemporaryCapture>());
      expect(captureCount, 1);
      expect(await pluginCapture.exists(), isFalse);
      expect((capture as PrivateTemporaryCapture).file.path,
          startsWith(store.namespaceDirectory.path));

      await capture.dispose();
      await camera.release();
      expect(camera.previewHandle, isNull);
      expect(disposeCount, 1);
    });

    // **Validates: Requirements 01.3, 03.6, 20.3, 20.6**
    test('reports no rear camera without constructing a controller', () async {
      final sandbox = await Directory.systemTemp.createTemp('e1_camera_test_');
      addTearDown(() => sandbox.delete(recursive: true));
      var factoryCalls = 0;
      final camera = OperationalCamera(
        imageStore: PrivateImageStore.at(sandbox),
        discoverCameras: () async => [
          _description('front', CameraLensDirection.front),
        ],
        createController: (description) {
          factoryCalls++;
          return CameraController(description, ResolutionPreset.medium);
        },
      );

      await expectLater(
        camera.acquirePreview(),
        throwsA(
          isA<OperationalCameraException>().having(
            (error) => error.failure,
            'failure',
            OperationalCameraFailure.unavailable,
          ),
        ),
      );
      expect(factoryCalls, 0);
      expect(camera.previewHandle, isNull);
    });

    // **Validates: Requirements 03.6, 20.1, 20.3, 20.6**
    test('classifies camera plugin permission denial for stable readiness',
        () async {
      final sandbox = await Directory.systemTemp.createTemp('e1_camera_test_');
      addTearDown(() => sandbox.delete(recursive: true));
      final back = _description('back', CameraLensDirection.back);
      var classifyCount = 0;
      final camera = OperationalCamera(
        imageStore: PrivateImageStore.at(sandbox),
        discoverCameras: () async => [back],
        createController: (description) => CameraController(
          description,
          ResolutionPreset.medium,
          enableAudio: false,
        ),
        initializeController: (_) async => throw CameraException(
          'CameraAccessDenied',
          'permission denied',
        ),
        disposeController: (_) async {},
        classifyFailure: (error) async {
          classifyCount++;
          expect(error.code, 'CameraAccessDenied');
          return OperationalCameraFailure.permissionDenied;
        },
      );

      await expectLater(
        camera.acquirePreview(),
        throwsA(
          isA<OperationalCameraException>().having(
            (error) => error.failure,
            'failure',
            OperationalCameraFailure.permissionDenied,
          ),
        ),
      );
      expect(classifyCount, 1);
      expect(camera.previewHandle, isNull);
    });
  });

  group('OperationalLocation adapter', () {
    // **Validates: Requirements 06.1, 06.2, 06.5, 06.6, 20.2**
    test('publishes and invalidates immutable precise foreground snapshots',
        () async {
      final updates = StreamController<Position>();
      addTearDown(updates.close);
      var requestedPermission = false;
      final location = _location(
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async {
          requestedPermission = true;
          return LocationPermission.whileInUse;
        },
        current: _position(latitude: -23.5, longitude: -46.6, speed: 10),
        stream: updates.stream,
      );

      await location.acquireForegroundUpdates();
      expect(requestedPermission, isTrue);
      expect(location.latestValidSnapshot?.point.latitude, -23.5);
      expect(location.latestValidSnapshot?.accuracyMeters, 4);
      expect(location.latestValidSnapshot?.speedMetersPerSecond, 10);

      updates.add(_position(latitude: -22, longitude: -45, speed: 0));
      await Future<void>.delayed(Duration.zero);
      expect(location.latestValidSnapshot?.point.latitude, -22);
      expect(location.latestValidSnapshot?.speedMetersPerSecond, 0);

      await location.release();
      expect(location.latestValidSnapshot, isNull);
    });

    // **Validates: Requirements 06.1, 06.3, 06.4, 20.2, 20.4, 20.5, 20.7**
    test('classifies every controlled GPS precondition failure', () async {
      final cases = <OperationalLocation, OperationalLocationFailure>{
        _location(serviceEnabled: false):
            OperationalLocationFailure.serviceDisabled,
        _location(
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () async => LocationPermission.denied,
        ): OperationalLocationFailure.permissionDenied,
        _location(
          checkPermission: () async => LocationPermission.deniedForever,
        ): OperationalLocationFailure.permissionDeniedPermanently,
        _location(accuracy: LocationAccuracyStatus.reduced):
            OperationalLocationFailure.reducedAccuracy,
        _location(currentError: StateError('provider unavailable')):
            OperationalLocationFailure.positionUnavailable,
      };

      for (final entry in cases.entries) {
        await expectLater(
          entry.key.acquireForegroundUpdates(),
          throwsA(
            isA<OperationalLocationException>().having(
              (error) => error.failure,
              'failure',
              entry.value,
            ),
          ),
          reason: entry.value.name,
        );
        expect(entry.key.latestValidSnapshot, isNull);
      }
    });
  });

  group('Operational application settings adapter', () {
    // **Validates: Requirements 20.5**
    test('opens Android app settings only on explicit action', () async {
      var openCount = 0;
      final settings = OperationalAppSettings(
        openSettings: () async {
          openCount++;
          return true;
        },
      );

      expect(openCount, 0);
      expect(await settings.open(), isTrue);
      expect(openCount, 1);
    });
  });

  group('Operational permission and status coordination', () {
    // **Validates: Requirements 20.1, 20.2, RNF-04.2**
    test('never starts location before camera permission work settles',
        () async {
      final gate = Completer<void>();
      final events = <String>[];
      final camera = _ControlledCamera(
        acquire: () async {
          events.add('camera-start');
          await gate.future;
          events.add('camera-end');
        },
      );
      final location = _ControlledLocation(
        acquire: () async => events.add('location-start'),
      );
      final controller = _controller(camera: camera, location: location);
      addTearDown(() async {
        controller.dispose();
        await controller.lifecycleSettled;
      });

      final starting = controller.startOperationalLifecycle();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['camera-start']);

      gate.complete();
      await starting;
      expect(events, ['camera-start', 'camera-end', 'location-start']);
    });

    // **Validates: Requirements 01.3, 03.6, 05.1, 06.3, 20.3–7**
    test('keeps GPS independent when camera fails and maps GPS failures',
        () async {
      final camera = _ControlledCamera(
        acquire: () async => throw StateError('camera unavailable'),
      );
      final healthyLocation = _ControlledLocation();
      final controller = _controller(
        camera: camera,
        location: healthyLocation,
      );
      addTearDown(() async {
        controller.dispose();
        await controller.lifecycleSettled;
      });

      await controller.startOperationalLifecycle();
      expect(controller.state.cameraStatus, OperationCameraStatus.unavailable);
      expect(controller.state.locationStatus, OperationLocationStatus.ready);
      expect(healthyLocation.acquireCount, 1);

      final mappings = <OperationalLocationFailure, OperationLocationStatus>{
        OperationalLocationFailure.serviceDisabled:
            OperationLocationStatus.serviceDisabled,
        OperationalLocationFailure.permissionDenied:
            OperationLocationStatus.permissionDenied,
        OperationalLocationFailure.permissionDeniedPermanently:
            OperationLocationStatus.permissionDeniedPermanently,
        OperationalLocationFailure.reducedAccuracy:
            OperationLocationStatus.reducedAccuracy,
        OperationalLocationFailure.positionUnavailable:
            OperationLocationStatus.unavailable,
      };
      for (final entry in mappings.entries) {
        final failedLocation = _ControlledLocation(
          acquire: () async => throw OperationalLocationException(entry.key),
        );
        final mapped = _controller(
          camera: _ControlledCamera(),
          location: failedLocation,
        );
        await mapped.startOperationalLifecycle();
        expect(mapped.state.locationStatus, entry.value,
            reason: entry.key.name);
        mapped.dispose();
        await mapped.lifecycleSettled;
      }
    });
  });
}

CameraDescription _description(String name, CameraLensDirection direction) {
  return CameraDescription(
    name: name,
    lensDirection: direction,
    sensorOrientation: 90,
  );
}

Position _position({
  required double latitude,
  required double longitude,
  required double speed,
}) {
  return Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: DateTime.utc(2025),
    accuracy: 4,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

OperationalLocation _location({
  bool serviceEnabled = true,
  Future<LocationPermission> Function()? checkPermission,
  Future<LocationPermission> Function()? requestPermission,
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise,
  Position? current,
  Object? currentError,
  Stream<Position>? stream,
}) {
  return OperationalLocation(
    isServiceEnabled: () async => serviceEnabled,
    checkPermission:
        checkPermission ?? () async => LocationPermission.whileInUse,
    requestPermission:
        requestPermission ?? () async => LocationPermission.whileInUse,
    getLocationAccuracy: () async => accuracy,
    getCurrentPosition: (_) async {
      if (currentError != null) {
        throw currentError;
      }
      return current ?? _position(latitude: -23.5, longitude: -46.6, speed: 0);
    },
    getPositionStream: (_) => stream ?? const Stream<Position>.empty(),
  );
}

OperationController<String> _controller({
  required OperationalCameraPort<String> camera,
  required OperationalLocationPort location,
}) {
  return OperationController<String>(
    candidateSource: const _UnusedSource(),
    postCandidateProcessor: const _UnusedProcessor(),
    camera: camera,
    location: location,
    screenAwake: const _Awake(),
    clock: const _Clock(),
  );
}

final class _ControlledCamera implements OperationalCameraPort<String> {
  _ControlledCamera({Future<void> Function()? acquire})
      : _acquire = acquire ?? _complete;

  final Future<void> Function() _acquire;

  @override
  String? get previewHandle => 'preview';

  @override
  Future<void> acquirePreview() => _acquire();

  @override
  Future<void> release() async {}

  @override
  Future<TemporaryCapture> takePicture() => throw UnsupportedError('not used');
}

final class _ControlledLocation implements OperationalLocationPort {
  _ControlledLocation({Future<void> Function()? acquire})
      : _acquire = acquire ?? _complete;

  final Future<void> Function() _acquire;
  var acquireCount = 0;

  @override
  LocationSnapshot? get latestValidSnapshot => const _Snapshot();

  @override
  Future<void> acquireForegroundUpdates() async {
    acquireCount++;
    await _acquire();
  }

  @override
  Future<void> release() async {}
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
      throw UnsupportedError('not used');
}

final class _UnusedProcessor
    implements PostCandidateProcessor<InMemoryOccurrence> {
  const _UnusedProcessor();

  @override
  Future<CandidateResult<InMemoryOccurrence>> process(
    CandidateInput candidate,
  ) =>
      throw UnsupportedError('not used');
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

Future<void> _complete() async {}
