import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _legacyRulesPath = 'android/app/src/main/res/xml/backup_rules.xml';
const _modernRulesPath =
    'android/app/src/main/res/xml/data_extraction_rules.xml';

final _expectedExclusions = <_Exclusion>{
  const _Exclusion('database', e2QueueDatabaseName),
  const _Exclusion('database', '$e2QueueDatabaseName-journal'),
  const _Exclusion('database', '$e2QueueDatabaseName-wal'),
  const _Exclusion('database', '$e2QueueDatabaseName-shm'),
  const _Exclusion('file', '$e2DurableImageNamespace/'),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Android E2 backup policy', () {
    // **Validates: Requirements RF-12.2, RF-12.4, RF-12.11, RNF-06.3, RNF-06.9–12**
    test(
        'manifest references both selective policies without broad disablement',
        () {
      final manifest = File(_manifestPath).readAsStringSync();
      final application = RegExp(
        r'<application\b[\s\S]*?>',
      ).firstMatch(manifest)!.group(0)!;

      expect(
        application,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        application,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      expect(application, contains('android:usesCleartextTraffic="false"'));
      expect(application, isNot(contains('android:allowBackup="false"')));

      final activePermissions = RegExp(r'<uses-permission\b[\s\S]*?/>')
          .allMatches(manifest)
          .map((match) => match.group(0)!)
          .where((element) => !element.contains('tools:node="remove"'))
          .map(
            (element) => RegExp(r'android:name="([^"]+)"')
                .firstMatch(element)!
                .group(1)!,
          )
          .toSet();
      expect(activePermissions, <String>{
        'android.permission.CAMERA',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
        'android.permission.INTERNET',
      });
    });

    // **Validates: Requirements RF-12.2, RF-12.4, RF-12.11, RNF-05.1–3, RNF-06.9–12**
    test('legacy and Android 12 policies exclude the same complete E2 set', () {
      final legacy = File(_legacyRulesPath).readAsStringSync();
      final modern = File(_modernRulesPath).readAsStringSync();

      expect(legacy, contains('<full-backup-content>'));
      expect(legacy, isNot(contains('<include')));
      expect(_exclusions(legacy), _expectedExclusions);

      final cloudBackup = _section(modern, 'cloud-backup');
      final deviceTransfer = _section(modern, 'device-transfer');
      expect(modern, contains('<data-extraction-rules>'));
      expect(modern, isNot(contains('<include')));
      expect(_exclusions(cloudBackup), _expectedExclusions);
      expect(_exclusions(deviceTransfer), _expectedExclusions);
      expect(_exclusions(cloudBackup), _exclusions(deviceTransfer));
    });

    // **Validates: Requirements RF-12.2, RF-12.4, RF-12.11, RNF-06.3, RNF-06.9–12**
    test(
        'sqflite and path_provider production resolution matches excluded relative paths',
        () async {
      final legacy = File(_legacyRulesPath).readAsStringSync();
      final declared = _exclusions(legacy);

      final databasesRoot = await databaseFactoryFfi.getDatabasesPath();
      final expectedDatabasePath = _join(databasesRoot, e2QueueDatabaseName);
      await databaseFactoryFfi.deleteDatabase(expectedDatabasePath);
      final queue = await QueueDatabase.open(factory: databaseFactoryFfi);
      addTearDown(() async {
        await queue.close();
        await databaseFactoryFfi.deleteDatabase(expectedDatabasePath);
      });

      expect(_normalize(queue.path), _normalize(expectedDatabasePath));
      final actualDatabaseName = _basename(queue.path);
      expect(actualDatabaseName, e2QueueDatabaseName);
      expect(
        declared.where((entry) => entry.domain == 'database').toSet(),
        <_Exclusion>{
          _Exclusion('database', actualDatabaseName),
          _Exclusion('database', '$actualDatabaseName-journal'),
          _Exclusion('database', '$actualDatabaseName-wal'),
          _Exclusion('database', '$actualDatabaseName-shm'),
        },
      );

      final supportRoot =
          await Directory.systemTemp.createTemp('e2_android_backup_paths_');
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        expect(call.method, 'getApplicationSupportDirectory');
        return supportRoot.path;
      });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        if (await supportRoot.exists()) {
          await supportRoot.delete(recursive: true);
        }
      });

      // Exercise path_provider's production API and the store's default
      // provider; only the native platform boundary is redirected to the
      // isolated host sandbox.
      final pathProviderSupportRoot = await getApplicationSupportDirectory();
      expect(
        _normalize(pathProviderSupportRoot.path),
        _normalize(supportRoot.path),
      );
      await PrivateDurableImageStore.create();
      final actualNamespace = Directory(
        _join(pathProviderSupportRoot.path, e2DurableImageNamespace),
      );
      expect(await actualNamespace.exists(), isTrue);
      final relativeNamespace = '${_relativeDirectChild(
        pathProviderSupportRoot.path,
        actualNamespace.path,
      )}/';
      expect(
        declared.where((entry) => entry.domain == 'file').toSet(),
        <_Exclusion>{_Exclusion('file', relativeNamespace)},
      );
    });
  });
}

Set<_Exclusion> _exclusions(String xml) {
  return RegExp(r'<exclude\s+domain="([^"]+)"\s+path="([^"]+)"\s*/>')
      .allMatches(xml)
      .map((match) => _Exclusion(match.group(1)!, match.group(2)!))
      .toSet();
}

String _section(String xml, String tag) {
  final match = RegExp('<$tag>([\\s\\S]*?)</$tag>').firstMatch(xml);
  if (match == null) {
    throw StateError('Missing <$tag> section.');
  }
  return match.group(1)!;
}

String _join(String parent, String child) {
  if (parent.endsWith('/') || parent.endsWith(r'\')) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

String _normalize(String path) => path.replaceAll(r'\', '/');

String _basename(String path) {
  final normalized = _normalize(path);
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _relativeDirectChild(String parent, String child) {
  final normalizedParent = _normalize(parent).replaceFirst(RegExp(r'/$'), '');
  final normalizedChild = _normalize(child);
  final prefix = '$normalizedParent/';
  if (!normalizedChild.startsWith(prefix)) {
    throw StateError('Resolved path is outside the expected private root.');
  }
  final relative = normalizedChild.substring(prefix.length);
  if (relative.isEmpty || relative.contains('/')) {
    throw StateError('Resolved path is not a direct private child.');
  }
  return relative;
}

final class _Exclusion {
  const _Exclusion(this.domain, this.path);

  final String domain;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is _Exclusion && other.domain == domain && other.path == path;

  @override
  int get hashCode => Object.hash(domain, path);

  @override
  String toString() => '$domain:$path';
}
