import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/detection/pothole_model_descriptor.dart';

const _modelExtensions = <String>[
  '.tflite',
  '.onnx',
  '.pt',
  '.pb',
  '.mlmodel',
  '.lite',
  '.ncnn',
];

// Generated or tool directories that never ship project sources.
const _ignoredRoots = <String>{
  '.dart_tool',
  '.git',
  '.gradle',
  '.idea',
  'build',
};

void main() {
  // **Validates: Requirements RF-02.2, RF-02.6–7, RNF-02.1** (task 77.3)
  group('PotholeModelDescriptor', () {
    test('the bundled asset matches the descriptor size and SHA-256', () {
      final asset = File(PotholeModelDescriptor.assetPath);
      expect(asset.existsSync(), isTrue);

      final bytes = asset.readAsBytesSync();
      expect(bytes.length, PotholeModelDescriptor.sizeInBytes);
      expect(sha256.convert(bytes).toString(), PotholeModelDescriptor.sha256);
    });

    test('the asset is the only model file in the project', () {
      final models = <String>[];
      for (final entity in Directory('.').listSync()) {
        final name =
            entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
        if (_ignoredRoots.contains(name)) {
          continue;
        }
        final files = entity is Directory
            ? entity.listSync(recursive: true).whereType<File>()
            : entity is File
                ? <File>[entity]
                : const <File>[];
        for (final file in files) {
          final path = file.path.replaceAll('\\', '/');
          if (path.contains('/build/') || path.contains('/.gradle/')) {
            continue;
          }
          if (_modelExtensions.any(path.toLowerCase().endsWith)) {
            models.add(path.startsWith('./') ? path.substring(2) : path);
          }
        }
      }

      expect(models, <String>[PotholeModelDescriptor.assetPath]);
    });

    test('describes a 640 detect model with a single pothole class', () {
      expect(PotholeModelDescriptor.task, 'detect');
      expect(PotholeModelDescriptor.inputSize, 640);
      expect(
        PotholeModelDescriptor.contractClassFor(
          classIndex: 0,
          className: 'buraco',
        ),
        'pothole',
      );
    });

    test('rejects any other class index or name', () {
      expect(
        PotholeModelDescriptor.contractClassFor(
          classIndex: 1,
          className: 'buraco',
        ),
        isNull,
      );
      expect(
        PotholeModelDescriptor.contractClassFor(
          classIndex: 0,
          className: 'pothole',
        ),
        isNull,
      );
    });
  });
}
