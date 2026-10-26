import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _approvedHostedPins = <String, String>{
  'camera': '0.11.0+2',
  'geolocator': '13.0.2',
  'image': '4.2.0',
  'uuid': '4.6.0',
  'wakelock_plus': '1.2.8',
  'path_provider': '2.1.4',
  'sqflite': '2.4.1',
  'crypto': '3.0.7',
  'glados': '1.1.7',
  'sqflite_common_ffi': '2.3.4+4',
};

const _approvedMainDependencies = <String>{
  'flutter',
  'camera',
  'geolocator',
  'image',
  'uuid',
  'wakelock_plus',
  'path_provider',
  'sqflite',
  'crypto',
};

const _approvedDevDependencies = <String>{
  'flutter_test',
  'flutter_lints',
  'glados',
  'sqflite_common_ffi',
};

const _laterStageDependencyFamilies = <String>{
  'dio',
  'flutter_secure_storage',
  'hive',
  'hive_flutter',
  'drift',
  'floor',
  'objectbox',
  'workmanager',
  'background_fetch',
  'provider',
  'riverpod',
  'flutter_riverpod',
  'bloc',
  'flutter_bloc',
  'get_it',
  'mockito',
  'mocktail',
  'permission_handler',
  'ultralytics_yolo',
  'tflite_flutter',
};

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final lockfile = File('pubspec.lock').readAsStringSync();
  final mainDependencies = _parsePubspecSection(pubspec, 'dependencies');
  final devDependencies = _parsePubspecSection(pubspec, 'dev_dependencies');
  final lockedPackages = _parseLockPackages(lockfile);

  group('E2 direct dependency policy', () {
    test('keeps only the approved production and development dependencies', () {
      expect(mainDependencies.keys.toSet(), _approvedMainDependencies);
      expect(devDependencies.keys.toSet(), _approvedDevDependencies);

      final allDirectNames = <String>{
        ...mainDependencies.keys,
        ...devDependencies.keys,
      };
      expect(
        allDirectNames.intersection(_laterStageDependencyFamilies),
        isEmpty,
        reason:
            'E3-E5 dependency families must not be direct dependencies in E2.',
      );
    });

    test('pins every approved hosted dependency to its exact version', () {
      final allDirectDependencies = <String, String?>{
        ...mainDependencies,
        ...devDependencies,
      };

      for (final pin in _approvedHostedPins.entries) {
        expect(
          allDirectDependencies[pin.key],
          pin.value,
          reason: '${pin.key} must use the approved exact E1/E2 pin.',
        );
      }
    });

    test('resolves each exact pin with the correct direct dependency kind', () {
      for (final pin in _approvedHostedPins.entries) {
        final locked = lockedPackages[pin.key];
        expect(locked, isNotNull, reason: '${pin.key} must be resolved.');
        expect(locked!.version, pin.value);

        final expectedKind = mainDependencies.containsKey(pin.key)
            ? 'direct main'
            : 'direct dev';
        expect(
          locked.dependency,
          expectedKind,
          reason: '${pin.key} must remain a $expectedKind dependency.',
        );
      }

      expect(mainDependencies, isNot(contains('sqflite_common_ffi')));
      expect(devDependencies['sqflite_common_ffi'], '2.3.4+4');
    });
  });
}

Map<String, String?> _parsePubspecSection(String contents, String section) {
  final result = <String, String?>{};
  var inSection = false;

  for (final line in contents.split(RegExp(r'\r?\n'))) {
    if (line == '$section:') {
      inSection = true;
      continue;
    }
    if (inSection && line.isNotEmpty && !line.startsWith(' ')) {
      break;
    }
    if (!inSection) {
      continue;
    }

    final match = RegExp(r'^  ([a-zA-Z0-9_]+):(?: (.+))?$').firstMatch(line);
    if (match != null) {
      result[match.group(1)!] = match.group(2);
    }
  }

  return result;
}

Map<String, _LockedPackage> _parseLockPackages(String contents) {
  final result = <String, _LockedPackage>{};
  String? currentName;
  String? dependency;
  String? version;

  void commitCurrent() {
    if (currentName != null && dependency != null && version != null) {
      result[currentName] = _LockedPackage(
        dependency: _unquote(dependency),
        version: _unquote(version),
      );
    }
  }

  for (final line in contents.split(RegExp(r'\r?\n'))) {
    final packageMatch = RegExp(r'^  ([a-zA-Z0-9_]+):$').firstMatch(line);
    if (packageMatch != null) {
      commitCurrent();
      currentName = packageMatch.group(1);
      dependency = null;
      version = null;
      continue;
    }
    if (currentName == null) {
      continue;
    }

    final dependencyMatch = RegExp(r'^    dependency: (.+)$').firstMatch(line);
    if (dependencyMatch != null) {
      dependency = dependencyMatch.group(1);
    }
    final versionMatch = RegExp(r'^    version: (.+)$').firstMatch(line);
    if (versionMatch != null) {
      version = versionMatch.group(1);
    }
  }
  commitCurrent();

  return result;
}

String _unquote(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

final class _LockedPackage {
  const _LockedPackage({required this.dependency, required this.version});

  final String dependency;
  final String version;
}
