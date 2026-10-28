import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _mainManifestPath = 'android/app/src/main/AndroidManifest.xml';
const _debugManifestPath = 'android/app/src/debug/AndroidManifest.xml';
const _debugNetworkConfigPath =
    'android/app/src/debug/res/xml/network_security_config_debug.xml';

void main() {
  group('E3 Android network security policy', () {
    // **Validates: Requirements RF-13.2–5, RNF-02.9–10**
    test('release policy requires HTTPS and has no cleartext override', () {
      final mainManifest = File(_mainManifestPath).readAsStringSync();
      final application = _application(mainManifest, _mainManifestPath);

      expect(application, contains('android:usesCleartextTraffic="false"'));
      expect(application, isNot(contains('android:networkSecurityConfig=')));
      expect(mainManifest, isNot(contains('cleartextTrafficPermitted="true"')));
    });

    // **Validates: Requirements RF-13.3–5, RNF-02.9–10**
    test('only debug references a localhost-only cleartext exception', () {
      final debugManifest = File(_debugManifestPath).readAsStringSync();
      final debugApplication = _application(debugManifest, _debugManifestPath);
      final debugConfig = File(_debugNetworkConfigPath).readAsStringSync();

      expect(
        debugApplication,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config_debug"',
        ),
      );
      expect(
        debugApplication,
        isNot(contains('android:usesCleartextTraffic="true"')),
      );

      expect(
        RegExp(r'<base-config\s+cleartextTrafficPermitted="false"\s*/>')
            .hasMatch(debugConfig),
        isTrue,
      );
      final enabledDomains = RegExp(
        r'<domain-config\s+cleartextTrafficPermitted="true">\s*'
        r'<domain\s+includeSubdomains="false">([^<]+)</domain>\s*'
        r'</domain-config>',
      ).allMatches(debugConfig).map((match) => match.group(1)!).toList();
      expect(enabledDomains, <String>['localhost']);
      expect(debugConfig, isNot(contains('includeSubdomains="true"')));
    });

    // **Validates: Requirements RF-13.3–5, RNF-02.9–10**
    test('no Android source set globally enables cleartext traffic', () {
      final androidSourceFiles = Directory('android/app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.xml'))
          .toList();

      for (final file in androidSourceFiles) {
        final normalizedPath = file.path.replaceAll(r'\', '/');
        final contents = file.readAsStringSync();
        expect(
          contents,
          isNot(contains('android:usesCleartextTraffic="true"')),
          reason: '$normalizedPath must not globally enable cleartext traffic.',
        );
        if (contents.contains('android:networkSecurityConfig=')) {
          expect(
            normalizedPath,
            endsWith(_debugManifestPath),
            reason:
                'Only the debug manifest may reference a network-security config.',
          );
          expect(
            contents,
            contains(
              'android:networkSecurityConfig="@xml/network_security_config_debug"',
            ),
          );
        }
        if (contents.contains('cleartextTrafficPermitted="true"')) {
          expect(
            normalizedPath,
            endsWith(_debugNetworkConfigPath),
            reason:
                'Only the debug network-security config may permit cleartext traffic.',
          );
        }
      }
    });
  });
}

String _application(String manifest, String path) {
  final application = RegExp(r'<application\b[\s\S]*?>').firstMatch(manifest);
  if (application == null) {
    throw StateError('Missing <application> element in $path.');
  }
  return application.group(0)!;
}
