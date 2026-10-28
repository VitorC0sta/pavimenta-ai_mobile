import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // **Validates: Requirements RF-23.1–10, RNF-01.7–13, RNF-03.6, RNF-07.1, RNF-07.10**
  test(
      'E3 permits configuration and credential stores, not occurrence transport',
      () {
    final sources = _productionSources();
    final nonDiagnosticSources = <String, String>{
      for (final entry in sources.entries)
        if (!entry.key.startsWith('lib/e0/')) entry.key: entry.value,
    };

    const forbiddenPackages = <String>{
      'package:http/',
      'package:dio/',
      'package:workmanager/',
      'package:flutter_background_service/',
      'package:background_fetch/',
      'package:ultralytics_yolo/',
      'package:tflite_flutter/',
      'package:tflite_flutter_helper/',
    };
    const allowedE3StorePackages = <String>{
      'package:shared_preferences/',
      'package:flutter_secure_storage/',
    };

    for (final entry in sources.entries) {
      final imports = _importsOf(entry.value);
      for (final forbiddenPackage in forbiddenPackages) {
        expect(
          imports.where((value) => value.startsWith(forbiddenPackage)),
          isEmpty,
          reason:
              '${entry.key} must not introduce $forbiddenPackage before E4/E5.',
        );
      }

      for (final storePackage in allowedE3StorePackages) {
        if (imports.any((value) => value.startsWith(storePackage))) {
          expect(
            entry.key,
            startsWith('lib/infrastructure/'),
            reason:
                '$storePackage is allowed only in an E3 infrastructure store.',
          );
        }
      }
    }

    const forbiddenOccurrenceTransport = <Pattern>[
      '/api/v1/occurrences',
      'multipart/form-data',
      'Authorization',
      'ApiKey ',
      'MultipartRequest',
      'MultipartFile',
      r'\bHttpClient\b',
      r'\.\s*(?:post|send)\s*\(',
    ];
    for (final entry in nonDiagnosticSources.entries) {
      var source = _withoutComments(entry.value);
      // E3 must tell the operator not to include the future endpoint. This is
      // presentation guidance, not a transport implementation.
      if (entry.key == 'lib/settings/settings_screen.dart') {
        source = source.replaceAll(
          'Não inclua /api/v1/occurrences. HTTPS é obrigatório fora do debug.',
          '',
        );
      }
      for (final forbidden in forbiddenOccurrenceTransport) {
        expect(
          _contains(source, forbidden),
          isFalse,
          reason:
              '${entry.key} must not introduce occurrence transport before E4.',
        );
      }
    }
  });

  // **Validates: Requirements RF-23.10, RNF-01.9–12, RNF-07.10**
  test('E3 contains no worker, backoff, or model inference implementation', () {
    final sources = _productionSources();
    const approvedManualBanner = 'Modo manual — YOLO ainda não configurado';
    final forbiddenExecutionAndInference = RegExp(
      r'\b(?:Workmanager|workmanager|BackgroundFetch|BackgroundService|Worker|'
      r'backoff|Backoff|exponentialBackoff|ultralytics_yolo|tflite(?:_flutter)?|'
      r'TFLite|inference|Inference|ModelLoader|ModelRunner|ModelInterpreter)\b',
    );

    for (final entry in sources.entries) {
      var source = _withoutComments(entry.value);
      source = source
          .replaceAll(approvedManualBanner, '')
          // E3 persists this approved E5 parameter without implementing E5.
          .replaceAll('maximumInferenceFps', 'maximumFps');

      expect(
        forbiddenExecutionAndInference.allMatches(source),
        isEmpty,
        reason:
            '${entry.key} must not introduce E4 workers/backoff or E5 inference.',
      );
      expect(
        RegExp(r'\b(?:YOLO|yolo)\b').allMatches(source),
        isEmpty,
        reason:
            '${entry.key} may only retain the approved E1 manual-mode banner.',
      );
    }
  });

  // **Validates: Requirements RF-19.2–5, RF-21.1–7, RNF-01.9–12**
  test('E3 keeps confidence and FPS as future parameters without frame loops',
      () {
    final sources = _productionSources();
    const parameterOwners = <String>{
      'lib/domain/operational_configuration.dart',
      'lib/application/e3_configuration_use_cases.dart',
      'lib/infrastructure/operational_configuration_store.dart',
      'lib/settings/settings_controller.dart',
      'lib/settings/settings_state.dart',
      'lib/settings/settings_screen.dart',
    };
    const futureParameters = <String>{
      'confidenceThreshold',
      'maximumInferenceFps',
    };

    for (final parameter in futureParameters) {
      final consumers = sources.entries
          .where((entry) => entry.value.contains(parameter))
          .map((entry) => entry.key)
          .toSet();
      expect(
        consumers.difference(parameterOwners),
        isEmpty,
        reason:
            '$parameter is reserved for E5 and may only be modeled, persisted, or presented in E3.',
      );
    }

    final settingsScreen = sources['lib/settings/settings_screen.dart']!;
    expect(settingsScreen, contains('Limiar de confiança futuro'));
    expect(settingsScreen, contains('FPS máximo futuro'));

    const forbiddenFrameProcessing = <String>{
      'startImageStream',
      'stopImageStream',
      'CameraImage',
      'ImageStream',
      'FrameLoop',
      'FrameProcessor',
      'processFrame',
    };
    for (final entry in sources.entries) {
      final source = _withoutComments(entry.value);
      for (final forbidden in forbiddenFrameProcessing) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              '${entry.key} must not introduce camera-frame processing before E5.',
        );
      }
    }
  });
}

Map<String, String> _productionSources() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));

  return <String, String>{
    for (final file in files)
      file.path.replaceAll('\\', '/'): file.readAsStringSync(),
  };
}

List<String> _importsOf(String source) {
  final pattern = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);
  return pattern
      .allMatches(source)
      .map((match) => match.group(1)!)
      .toList(growable: false);
}

bool _contains(String source, Pattern pattern) => switch (pattern) {
      String value => source.contains(value),
      RegExp value => value.hasMatch(source),
      _ => throw ArgumentError.value(pattern, 'pattern'),
    };

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\r\n]*'), '');
