import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

enum CameraFailureType {
  permissionDenied,
  permissionDeniedPermanently,
  cameraInUse,
  initializationFailed,
}

class CameraDiagnostic {
  const CameraDiagnostic();

  static const MethodChannel _platformChannel = MethodChannel(
    'com.vitor.pavimenta_ai_mobile/e0_camera_diagnostic',
  );

  Future<List<CameraDescription>> enumerateAvailableCameras() {
    return availableCameras();
  }

  CameraDescription? selectFirstBackCamera(
    List<CameraDescription> cameras,
  ) {
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        return camera;
      }
    }

    return null;
  }

  Future<CameraFailureType> classifyFailure(CameraException error) async {
    switch (error.code) {
      case 'CameraAccessDenied':
        return await _isCameraPermissionPermanentlyDenied()
            ? CameraFailureType.permissionDeniedPermanently
            : CameraFailureType.permissionDenied;
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return CameraFailureType.permissionDeniedPermanently;
    }

    final normalizedDetails = '${error.code} ${error.description ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '');
    const cameraInUseMarkers = <String>[
      'camerainuse',
      'maxcamerasinuse',
      'alreadyinuse',
      'beingused',
      'limitnumberofopencameras',
      'morecamerascannotbeopened',
    ];

    if (cameraInUseMarkers.any(normalizedDetails.contains)) {
      return CameraFailureType.cameraInUse;
    }

    return CameraFailureType.initializationFailed;
  }

  Future<bool> _isCameraPermissionPermanentlyDenied() async {
    try {
      return await _platformChannel.invokeMethod<bool>(
            'isCameraPermissionPermanentlyDenied',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<CameraController> initializePreviewController(
    CameraDescription backCamera,
  ) async {
    final controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller.initialize();
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }
}
