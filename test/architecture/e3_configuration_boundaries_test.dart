import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The E3 global negative inspection (no occurrence transport, backoff, or
  // worker anywhere) was replaced by the positive E4 boundary test in
  // e4_delivery_boundaries_test.dart.

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
      // E5.15: the only E5 reader of the operational parameters.
      'lib/domain/detection/detection_parameters.dart',
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

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\r\n]*'), '');
