import '../domain/location_snapshot.dart';
import '../infrastructure/image_artifacts.dart';

/// Stable failure categories exposed by the operational camera boundary.
enum OperationalCameraFailure {
  permissionDenied,
  permissionDeniedPermanently,
  unavailable,
}

/// Controlled camera failure that presentation can classify without
/// depending on the camera plugin.
final class OperationalCameraException implements Exception {
  const OperationalCameraException(this.failure);

  final OperationalCameraFailure failure;
}

/// Operational camera boundary used for preview and one deferred capture.
abstract interface class OperationalCameraPort<TPreview extends Object> {
  Future<void> acquirePreview();

  TPreview? get previewHandle;

  Future<TemporaryCapture> takePicture();

  Future<void> release();
}

/// Stable failure categories exposed by the operational location boundary.
enum OperationalLocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionDeniedPermanently,
  reducedAccuracy,
  positionUnavailable,
}

/// Controlled location failure that presentation can classify without
/// depending on the Geolocator plugin.
final class OperationalLocationException implements Exception {
  const OperationalLocationException(this.failure);

  final OperationalLocationFailure failure;
}

/// Foreground location boundary exposing the latest accepted snapshot.
abstract interface class OperationalLocationPort {
  LocationSnapshot? get latestValidSnapshot;

  Future<void> acquireForegroundUpdates();

  Future<void> release();
}

/// Converts one temporary capture into an owned prepared image.
abstract interface class ImagePreparer {
  Future<OwnedPreparedImage> prepare(TemporaryCapture capture);
}

/// Supplies the instant accepted by the application flow.
abstract interface class Clock {
  DateTime now();
}

/// Supplies one UUID version 4 value for an accepted occurrence.
abstract interface class UuidGenerator {
  String newV4();
}

/// Opens the Android application settings for permanent permission denial.
abstract interface class AppSettingsPort {
  Future<bool> open();
}

/// Controls whether the operational screen keeps the device awake.
abstract interface class ScreenAwakePort {
  Future<void> setEnabled(bool enabled);
}
