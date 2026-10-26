import 'package:geolocator/geolocator.dart';

import '../application/e1_ports.dart';

typedef OpenApplicationSettings = Future<bool> Function();

/// Opens only the Android application details page after a permanent denial.
final class OperationalAppSettings implements AppSettingsPort {
  const OperationalAppSettings({OpenApplicationSettings? openSettings})
      : _openSettings = openSettings ?? Geolocator.openAppSettings;

  final OpenApplicationSettings _openSettings;

  @override
  Future<bool> open() => _openSettings();
}
