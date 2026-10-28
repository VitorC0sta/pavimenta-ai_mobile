import 'dart:convert';

import '../application/e3_storage_ports.dart';
import '../domain/operational_configuration.dart';

typedef OperationalConfigurationTechnicalLogger = void Function(String event);

/// Sanitized failure codes for preference access or invalid save requests.
enum OperationalConfigurationStorageFailure {
  loadFailed,
  saveFailed,
  invalidConfiguration,
}

/// A controlled failure that contains no persisted document or configuration.
final class OperationalConfigurationStorageException implements Exception {
  const OperationalConfigurationStorageException(this.failure);

  final OperationalConfigurationStorageFailure failure;

  @override
  String toString() =>
      'OperationalConfigurationStorageException(${failure.name})';
}

/// Versioned, single-document persistence for non-secret E3 configuration.
///
/// A complete document is written with one preference operation. Missing
/// fields are defaulted for forward-compatible recovery, while malformed or
/// unsupported documents are ignored as a whole and recover to safe defaults.
final class SharedPreferencesOperationalConfigurationStore
    implements OperationalConfigurationRepository {
  SharedPreferencesOperationalConfigurationStore({
    required PreferencesStore preferences,
    OperationalConfigurationTechnicalLogger? logTechnicalEvent,
  })  : _preferences = preferences,
        _logTechnicalEvent = logTechnicalEvent ?? _discardTechnicalEvent;

  static const storageKey = 'e3_operational_configuration_v1';

  final PreferencesStore _preferences;
  final OperationalConfigurationTechnicalLogger _logTechnicalEvent;

  @override
  Future<OperationalConfiguration> load() async {
    final String? document;
    try {
      document = await _preferences.getString(storageKey);
    } catch (_) {
      _logTechnicalEvent('operational_configuration_load_failed');
      throw const OperationalConfigurationStorageException(
        OperationalConfigurationStorageFailure.loadFailed,
      );
    }

    if (document == null) {
      return const OperationalConfiguration.defaults();
    }

    try {
      return _decode(document);
    } on _UnsupportedConfigurationVersion {
      _logTechnicalEvent('operational_configuration_unsupported_version');
      return const OperationalConfiguration.defaults();
    } on FormatException {
      _logTechnicalEvent('operational_configuration_corrupt');
      return const OperationalConfiguration.defaults();
    } catch (_) {
      _logTechnicalEvent('operational_configuration_corrupt');
      return const OperationalConfiguration.defaults();
    }
  }

  @override
  Future<void> save(OperationalConfiguration configuration) async {
    final document = _encode(configuration);
    try {
      final saved = await _preferences.setString(storageKey, document);
      if (!saved) {
        throw StateError('Preference write was rejected.');
      }
    } catch (_) {
      _logTechnicalEvent('operational_configuration_save_failed');
      throw const OperationalConfigurationStorageException(
        OperationalConfigurationStorageFailure.saveFailed,
      );
    }
  }

  String _encode(OperationalConfiguration configuration) {
    if (!_isPersistable(configuration)) {
      throw const OperationalConfigurationStorageException(
        OperationalConfigurationStorageFailure.invalidConfiguration,
      );
    }

    return jsonEncode(<String, Object?>{
      'version': OperationalConfiguration.currentStorageVersion,
      'baseUrl': configuration.baseUrl?.toString(),
      'cooldownMicroseconds': configuration.cooldown.inMicroseconds,
      'minimumDistanceMeters': configuration.minimumDistanceMeters,
      'confidenceThreshold': configuration.confidenceThreshold,
      'maximumInferenceFps': configuration.maximumInferenceFps,
    });
  }

  OperationalConfiguration _decode(String document) {
    final decoded = jsonDecode(document);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Configuration document must be an object.');
    }

    final map = Map<String, Object?>.from(decoded);
    final version = map['version'];
    if (version is! int) {
      throw const FormatException(
          'Configuration version is missing or invalid.');
    }
    if (version != OperationalConfiguration.currentStorageVersion) {
      throw const _UnsupportedConfigurationVersion();
    }

    const defaults = OperationalConfiguration.defaults();
    final baseUrl = _readBaseUrl(map['baseUrl']);
    final cooldown = map.containsKey('cooldownMicroseconds')
        ? _readPositiveDuration(map['cooldownMicroseconds'])
        : defaults.cooldown;
    final minimumDistanceMeters = map.containsKey('minimumDistanceMeters')
        ? _readPositiveNumber(map['minimumDistanceMeters'])
        : defaults.minimumDistanceMeters;
    final confidenceThreshold = map.containsKey('confidenceThreshold')
        ? _readConfidence(map['confidenceThreshold'])
        : defaults.confidenceThreshold;
    final maximumInferenceFps = map.containsKey('maximumInferenceFps')
        ? _readPositiveNumber(map['maximumInferenceFps'])
        : defaults.maximumInferenceFps;

    return OperationalConfiguration(
      baseUrl: baseUrl,
      cooldown: cooldown,
      minimumDistanceMeters: minimumDistanceMeters,
      confidenceThreshold: confidenceThreshold,
      maximumInferenceFps: maximumInferenceFps,
    );
  }

  Uri? _readBaseUrl(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw const FormatException('Configuration base URL is invalid.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !_isStructuredOrigin(uri)) {
      throw const FormatException('Configuration base URL is invalid.');
    }
    return uri;
  }

  Duration _readPositiveDuration(Object? value) {
    if (value is! int || value <= 0) {
      throw const FormatException('Configuration cooldown is invalid.');
    }
    return Duration(microseconds: value);
  }

  double _readPositiveNumber(Object? value) {
    if (value is! num || !value.isFinite || value <= 0) {
      throw const FormatException('Configuration value is invalid.');
    }
    return value.toDouble();
  }

  double _readConfidence(Object? value) {
    if (value is! num || !value.isFinite || value < 0 || value > 1) {
      throw const FormatException('Configuration confidence is invalid.');
    }
    return value.toDouble();
  }

  bool _isPersistable(OperationalConfiguration configuration) =>
      configuration.cooldown > Duration.zero &&
      configuration.minimumDistanceMeters.isFinite &&
      configuration.minimumDistanceMeters > 0 &&
      configuration.confidenceThreshold.isFinite &&
      configuration.confidenceThreshold >= 0 &&
      configuration.confidenceThreshold <= 1 &&
      configuration.maximumInferenceFps.isFinite &&
      configuration.maximumInferenceFps > 0 &&
      (configuration.baseUrl == null ||
          _isStructuredOrigin(configuration.baseUrl!));

  bool _isStructuredOrigin(Uri uri) =>
      uri.isAbsolute &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (uri.path.isEmpty || uri.path == '/');
}

final class _UnsupportedConfigurationVersion implements Exception {
  const _UnsupportedConfigurationVersion();
}

void _discardTechnicalEvent(String _) {}
