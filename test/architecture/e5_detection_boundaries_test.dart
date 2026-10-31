import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Declared E5 detection boundaries (design E5.5 and E5.15).
///
/// The directories do not need to exist yet: tasks 78+ create the files and
/// this inspection keeps working unchanged.
const String _domainDetection = 'lib/domain/detection/';
const String _applicationDetection = 'lib/application/detection/';
const String _infrastructureDetection = 'lib/infrastructure/detection/';
const String _yoloCandidateSource = 'lib/candidate/yolo_candidate_source.dart';
const String _modelDescriptor =
    'lib/domain/detection/pothole_model_descriptor.dart';
const String _modelAsset = 'assets/models/buraco.tflite';

/// E3 owners of the operational parameters plus the single E5 reader.
const Set<String> _parameterOwners = <String>{
  'lib/domain/operational_configuration.dart',
  'lib/application/e3_configuration_use_cases.dart',
  'lib/infrastructure/operational_configuration_store.dart',
  'lib/settings/settings_controller.dart',
  'lib/settings/settings_state.dart',
  'lib/settings/settings_screen.dart',
  'lib/domain/detection/detection_parameters.dart',
};

const Set<String> _detectionParameters = <String>{
  'confidenceThreshold',
  'maximumInferenceFps',
  'confirmationRequiredFrames',
  'confirmationWindowFrames',
  'maximumBoxAreaRatio',
};

const Set<String> _forbiddenInferencePackages = <String>{
  'package:tflite_flutter/',
  'package:tflite_flutter_helper/',
  'package:google_mlkit',
  'package:google_ml_kit/',
  'package:onnxruntime',
  'package:flutter_onnxruntime/',
  'package:connectivity_plus/',
};

final RegExp _forbiddenEverywhere = RegExp(
  r'\b(?:Isolate\.spawn|compute|startImageStream|stopImageStream|'
  r'CameraImage)\b',
);

final RegExp _forbiddenModelSources = RegExp(
  r'\b(?:officialModels|defaultOfficialModel|switchModel)\b|'
  r'''https?://[^'"\s]*\.tflite''',
);

/// Own frame preprocessing; the plugin owns letterbox and normalization (D8).
final RegExp _ownFramePreprocessing = RegExp(
  r'\b(?:copyResize|gaussianBlur|GaussianBlur|ImageFilter|blur)\b',
);

void main() {
  // **Validates: Requirements RF-02.2, RF-02.6–7, RF-23.15, RNF-01.12,
  // RNF-02.1, RNF-03.10** (task 77.5)
  group('E5 detection boundaries', () {
    test('current production code respects the E5 boundaries', () {
      final sources = _productionSources();

      expect(sources, isNotEmpty);
      expect(_violationsOf(sources), isEmpty);
    });

    test('the declared E5 zones permit the detection capabilities', () {
      final allowed = <String, String>{
        '${_infrastructureDetection}yolo_view_session.dart': '''
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import '../../domain/detection/pothole_model_descriptor.dart';
final v = YOLOView(modelPath: PotholeModelDescriptor.assetPath);
''',
        'lib/main.dart':
            "import 'package:ultralytics_yolo/ultralytics_yolo.dart';",
        '${_domainDetection}detection_parameters.dart':
            'double f(c) => c.confidenceThreshold + c.maximumBoxAreaRatio;',
        '${_applicationDetection}detection_pipeline.dart':
            'final class DetectionPipeline {}',
      };

      expect(_violationsOf(allowed), isEmpty);
    });

    test('ultralytics_yolo is rejected outside the infrastructure adapters',
        () {
      const zones = <String>[
        '${_domainDetection}detection_filter.dart',
        '${_applicationDetection}detection_pipeline.dart',
        _yoloCandidateSource,
        'lib/operation/operation_screen.dart',
        'lib/operation/e1_composition.dart',
        'lib/infrastructure/operational_camera.dart',
      ];
      for (final zone in zones) {
        expect(
          _violationsOf(<String, String>{
            zone: "import 'package:ultralytics_yolo/ultralytics_yolo.dart';",
          }),
          isNotEmpty,
          reason: '$zone must not import ultralytics_yolo.',
        );
      }
    });

    test('other inference engines, isolates and frame streams stay forbidden',
        () {
      const offenders = <String, String>{
        'tflite_flutter':
            "import 'package:tflite_flutter/tflite_flutter.dart';",
        'ML Kit':
            "import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';",
        'ONNX': "import 'package:onnxruntime/onnxruntime.dart';",
        'connectivity':
            "import 'package:connectivity_plus/connectivity_plus.dart';",
        'isolate': 'void f() { Isolate.spawn(g, 1); }',
        'compute': 'void f() { compute(g, 1); }',
        'image stream': 'void f(c) { c.startImageStream((i) {}); }',
        'camera frame': 'void f(CameraImage image) {}',
      };
      for (final offender in offenders.entries) {
        expect(
          _violationsOf(<String, String>{
            '${_infrastructureDetection}yolo_view_session.dart': offender.value,
          }),
          isNotEmpty,
          reason: 'E5 must reject ${offender.key}.',
        );
      }
    });

    test('the model comes only from the descriptor asset', () {
      const offenders = <String, String>{
        'literal path': "final v = YOLOView(modelPath: 'other.tflite');",
        'official model': 'final m = YOLO.officialModels();',
        'default official model': 'final m = YOLO.defaultOfficialModel();',
        'model switch': 'void f(c) { c.switchModel(1, 2); }',
        'remote model': "const u = 'https://example.com/m.tflite';",
      };
      for (final offender in offenders.entries) {
        expect(
          _violationsOf(<String, String>{
            '${_infrastructureDetection}yolo_view_session.dart': offender.value,
          }),
          isNotEmpty,
          reason: 'E5 must reject ${offender.key}.',
        );
      }
    });

    test('operational parameters are read only by their owners', () {
      for (final parameter in _detectionParameters) {
        for (final zone in <String>[
          '${_infrastructureDetection}yolo_view_session.dart',
          '${_applicationDetection}detection_pipeline.dart',
          'lib/operation/operation_controller.dart',
        ]) {
          expect(
            _violationsOf(<String, String>{zone: 'final v = c.$parameter;'}),
            isNotEmpty,
            reason: '$zone must not read $parameter.',
          );
        }
      }
    });

    test('detection code applies no own blur, filter or resize to frames', () {
      for (final zone in <String>[
        '${_domainDetection}detection_filter.dart',
        '${_applicationDetection}detection_pipeline.dart',
        '${_infrastructureDetection}yolo_view_session.dart',
        _yoloCandidateSource,
      ]) {
        for (final offender in <String>[
          "import 'package:image/image.dart';",
          'final r = copyResize(i, width: 640);',
          'final b = gaussianBlur(i, radius: 3);',
          'final f = ImageFilter.blur(sigmaX: 1);',
        ]) {
          expect(
            _violationsOf(<String, String>{zone: offender}),
            isNotEmpty,
            reason: '$zone must not preprocess frames: $offender',
          );
        }
      }
    });

    test('pubspec declares only the model asset', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final assets = pubspec.substring(pubspec.indexOf('  assets:'));
      expect(
        RegExp(r'^\s+- (\S+)\s*$', multiLine: true)
            .allMatches(assets)
            .map((match) => match.group(1))
            .toList(),
        <String>[_modelAsset],
      );
      expect(File(_modelAsset).existsSync(), isTrue);
    });

    test(
        'the main manifest declares no component, background permission or '
        'extra INTERNET and strips the LiteRT merged permissions', () {
      final raw = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      final removed = RegExp(
        r'<uses-permission\s+android:name="([^"]+)"\s+tools:node="remove"\s*/>',
      ).allMatches(raw).map((match) => match.group(1)).toSet();
      expect(
        removed,
        containsAll(<String>[
          'android.permission.FOREGROUND_SERVICE',
          'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
          'android.permission.WAKE_LOCK',
          'android.permission.ACCESS_NETWORK_STATE',
          'android.permission.RECEIVE_BOOT_COMPLETED',
        ]),
      );

      final declared = raw.replaceAll(
        RegExp(r'<uses-permission\s+[^>]*tools:node="remove"\s*/>'),
        '',
      );
      expect(declared, isNot(contains('<service')));
      expect(declared, isNot(contains('<receiver')));
      expect(declared, isNot(contains('WAKE_LOCK')));
      expect(declared, isNot(contains('FOREGROUND_SERVICE')));
      expect(
        RegExp(r'android:name="android\.permission\.INTERNET"')
            .allMatches(declared),
        hasLength(1),
      );
    });
  });
}

/// Returns human-readable violations for [sources], keyed by `lib/...` path.
List<String> _violationsOf(Map<String, String> sources) {
  final violations = <String>[];

  for (final entry in sources.entries) {
    final path = entry.key;
    final imports = _importsOf(entry.value);
    final source = _withoutComments(entry.value);
    final isDetectionCode = path.startsWith(_domainDetection) ||
        path.startsWith(_applicationDetection) ||
        path.startsWith(_infrastructureDetection) ||
        path == _yoloCandidateSource;

    for (final value in imports) {
      if (value.startsWith('package:ultralytics_yolo/') &&
          !path.startsWith(_infrastructureDetection) &&
          path != 'lib/main.dart') {
        violations.add('$path imports ultralytics_yolo outside E5 adapters');
      }
      for (final forbidden in _forbiddenInferencePackages) {
        if (value.startsWith(forbidden)) {
          violations.add('$path imports forbidden package $forbidden');
        }
      }
      if (isDetectionCode && value.startsWith('package:image/')) {
        violations.add('$path imports package:image in detection code');
      }
    }

    if (_forbiddenEverywhere.hasMatch(source)) {
      violations.add('$path uses isolates or camera frame streams');
    }
    if (_forbiddenModelSources.hasMatch(source)) {
      violations.add('$path loads a model other than the bundled asset');
    }
    if (path != _modelDescriptor && source.contains('.tflite')) {
      violations.add('$path names a model file outside the descriptor');
    }
    final modelPaths = RegExp(r'modelPath\s*:\s*([^,)\s]+)')
        .allMatches(source)
        .map((match) => match.group(1));
    for (final value in modelPaths) {
      if (value != 'PotholeModelDescriptor.assetPath') {
        violations.add('$path passes modelPath $value');
      }
    }
    if (!_parameterOwners.contains(path)) {
      for (final parameter in _detectionParameters) {
        if (source.contains(parameter)) {
          violations.add('$path reads $parameter outside its owners');
        }
      }
    }
    if (isDetectionCode && _ownFramePreprocessing.hasMatch(source)) {
      violations.add('$path preprocesses frames itself');
    }
  }

  return violations;
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
  final pattern = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  return pattern
      .allMatches(source)
      .map((match) => match.group(1)!)
      .toList(growable: false);
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\r\n]*'), '');
