import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../application/e1_ports.dart';
import 'image_artifacts.dart';
import 'private_image_store.dart';

typedef OperationalCameraDiscovery = Future<List<CameraDescription>> Function();
typedef OperationalCameraFactory = CameraController Function(
  CameraDescription description,
);
typedef OperationalCameraAction = Future<void> Function(
  CameraController controller,
);
typedef OperationalPictureTaker = Future<XFile> Function(
  CameraController controller,
);
typedef OperationalCameraReadiness = bool Function(
  CameraController controller,
);
typedef OperationalCameraFailureClassifier = Future<OperationalCameraFailure>
    Function(CameraException error);

/// Owns the rear camera used by the active E1 Operation route.
final class OperationalCamera
    implements OperationalCameraPort<CameraController> {
  OperationalCamera({
    required PrivateImageStore imageStore,
    OperationalCameraDiscovery? discoverCameras,
    OperationalCameraFactory? createController,
    OperationalCameraAction? initializeController,
    OperationalPictureTaker? takePicture,
    OperationalCameraAction? disposeController,
    OperationalCameraReadiness? isControllerReady,
    OperationalCameraFailureClassifier? classifyFailure,
  })  : _imageStore = imageStore,
        _discoverCameras = discoverCameras ?? availableCameras,
        _createController = createController ?? _createProductionController,
        _initializeController =
            initializeController ?? _initializeProductionController,
        _takePicture = takePicture ?? _takeProductionPicture,
        _disposeController = disposeController ?? _disposeProductionController,
        _isControllerReady = isControllerReady ?? _isProductionControllerReady,
        _classifyFailure = classifyFailure ?? _classifyProductionFailure;

  final PrivateImageStore _imageStore;
  final OperationalCameraDiscovery _discoverCameras;
  final OperationalCameraFactory _createController;
  final OperationalCameraAction _initializeController;
  final OperationalPictureTaker _takePicture;
  final OperationalCameraAction _disposeController;
  final OperationalCameraReadiness _isControllerReady;
  final OperationalCameraFailureClassifier _classifyFailure;
  CameraController? _controller;

  @override
  CameraController? get previewHandle {
    final controller = _controller;
    if (controller == null || !_isControllerReady(controller)) {
      return null;
    }
    return controller;
  }

  @override
  Future<void> acquirePreview() async {
    await release();
    final cameras = await _discoverCameras();
    final rearCameras = cameras.where(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    if (rearCameras.isEmpty) {
      throw const OperationalCameraException(
        OperationalCameraFailure.unavailable,
      );
    }

    final controller = _createController(rearCameras.first);
    try {
      await _initializeController(controller);
      _controller = controller;
    } on CameraException catch (error) {
      await _disposeController(controller);
      throw OperationalCameraException(await _classifyFailure(error));
    } catch (_) {
      await _disposeController(controller);
      rethrow;
    }
  }

  @override
  Future<TemporaryCapture> takePicture() async {
    final controller = previewHandle;
    if (controller == null || controller.value.isTakingPicture) {
      throw StateError('The operational camera is not ready.');
    }
    final capture = await _takePicture(controller);
    return _imageStore.adoptCapture(File(capture.path));
  }

  @override
  Future<void> release() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await _disposeController(controller);
    }
  }
}

CameraController _createProductionController(CameraDescription description) {
  return CameraController(
    description,
    ResolutionPreset.medium,
    enableAudio: false,
  );
}

Future<void> _initializeProductionController(CameraController controller) {
  return controller.initialize();
}

Future<XFile> _takeProductionPicture(CameraController controller) {
  return controller.takePicture();
}

Future<void> _disposeProductionController(CameraController controller) {
  return controller.dispose();
}

bool _isProductionControllerReady(CameraController controller) {
  return controller.value.isInitialized;
}

Future<OperationalCameraFailure> _classifyProductionFailure(
  CameraException error,
) async {
  switch (error.code) {
    case 'CameraAccessDenied':
      return await _isCameraPermissionPermanentlyDenied()
          ? OperationalCameraFailure.permissionDeniedPermanently
          : OperationalCameraFailure.permissionDenied;
    case 'CameraAccessDeniedWithoutPrompt':
    case 'CameraAccessRestricted':
      return OperationalCameraFailure.permissionDeniedPermanently;
    default:
      return OperationalCameraFailure.unavailable;
  }
}

const MethodChannel _cameraPermissionChannel = MethodChannel(
  'com.vitor.pavimenta_ai_mobile/e0_camera_diagnostic',
);

Future<bool> _isCameraPermissionPermanentlyDenied() async {
  try {
    return await _cameraPermissionChannel.invokeMethod<bool>(
          'isCameraPermissionPermanentlyDenied',
        ) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
