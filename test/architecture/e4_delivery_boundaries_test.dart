import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Declared E4 delivery boundaries.
///
/// The directories do not need to exist yet: tasks 63+ create the files and
/// this inspection keeps working unchanged. Anything outside these prefixes is
/// a forbidden zone for the capability in question.
const String _domainDelivery = 'lib/domain/delivery/';
const String _applicationDelivery = 'lib/application/delivery/';
const String _infrastructureDelivery = 'lib/infrastructure/delivery/';

/// The only Diagnostic (E0) file that may touch `dart:io` `HttpClient`.
const String _diagnosticHttpClient = 'lib/e0/diagnostic_http_client.dart';

/// Files that declare or implement the E3 credential store. They predate E4
/// and are the only non-E4 files that may name the full-read capability.
const Set<String> _credentialStoreFiles = <String>{
  'lib/application/e3_storage_ports.dart',
  'lib/infrastructure/device_credential_store.dart',
};

/// Additive E4 SQLite schema (v2) kept beside the E2 queue database. It only
/// names persistence columns; it implements no transport or policy.
const String _queueDeliverySchema =
    'lib/infrastructure/queue_delivery_schema.dart';

final class _Capability {
  const _Capability({
    required this.name,
    required this.patterns,
    required this.allowedPrefixes,
    this.allowedFiles = const <String>{},
  });

  final String name;
  final List<Pattern> patterns;
  final List<String> allowedPrefixes;
  final Set<String> allowedFiles;

  bool permits(String path) =>
      allowedFiles.contains(path) ||
      allowedPrefixes.any((prefix) => path.startsWith(prefix));
}

final List<_Capability> _capabilities = <_Capability>[
  const _Capability(
    name: 'occurrence wire transport',
    patterns: <Pattern>[
      '/api/v1/occurrences',
      'Authorization',
      'ApiKey ',
      'IOClient',
      'StreamedRequest',
    ],
    allowedPrefixes: <String>[_infrastructureDelivery],
  ),
  _Capability(
    name: 'dart:io HttpClient',
    patterns: <Pattern>[RegExp(r'\bHttpClient(?:Request|Response)?\b')],
    allowedPrefixes: const <String>[_infrastructureDelivery],
    allowedFiles: const <String>{_diagnosticHttpClient},
  ),
  _Capability(
    name: 'multipart encoding',
    patterns: <Pattern>[RegExp('multipart', caseSensitive: false)],
    allowedPrefixes: const <String>[_infrastructureDelivery],
  ),
  _Capability(
    name: 'HTTP post/send invocation',
    patterns: <Pattern>[RegExp(r'\.\s*(?:post|send)\s*\(')],
    allowedPrefixes: const <String>[
      _applicationDelivery,
      _infrastructureDelivery,
    ],
  ),
  _Capability(
    name: 'complete credential read',
    patterns: <Pattern>[
      RegExp(
        r'\b(?:DeviceCredentialReadPort|readCredential|readForDelivery|'
        r'CredentialReadResult|NonPrintableSecret)\b',
      ),
    ],
    allowedPrefixes: const <String>[
      _domainDelivery,
      _applicationDelivery,
      _infrastructureDelivery,
    ],
    allowedFiles: _credentialStoreFiles,
  ),
  _Capability(
    name: 'delivery backoff',
    patterns: <Pattern>[RegExp('backoff', caseSensitive: false)],
    allowedPrefixes: const <String>[
      _domainDelivery,
      _applicationDelivery,
      _infrastructureDelivery,
    ],
    // Persistence columns of the E4 schema v2 live next to the E2 database.
    allowedFiles: const <String>{_queueDeliverySchema},
  ),
];

/// Still forbidden everywhere, including the E4 boundaries: E4 has no worker
/// and E5 inference does not exist yet.
final RegExp _forbiddenEverywhere = RegExp(
  r'\b(?:Workmanager|workmanager|BackgroundFetch|BackgroundService|Worker|'
  r'ultralytics_yolo|tflite(?:_flutter)?|TFLite|inference|Inference|'
  r'ModelLoader|ModelRunner|ModelInterpreter)\b',
);

const String _approvedManualBanner = 'Modo manual — YOLO ainda não configurado';

const Set<String> _forbiddenPackages = <String>{
  'package:dio/',
  'package:workmanager/',
  'package:flutter_background_service/',
  'package:background_fetch/',
  'package:connectivity_plus/',
  'package:ultralytics_yolo/',
  'package:tflite_flutter/',
  'package:tflite_flutter_helper/',
};

const Set<String> _storePackages = <String>{
  'package:shared_preferences/',
  'package:flutter_secure_storage/',
};

void main() {
  // **Validates: Requirements RF-23.1–12, RNF-01.6–13, RNF-03.7–10,
  // RNF-07.1, RNF-07.5, RNF-07.10**
  test('current production code respects the positive E4 boundaries', () {
    final sources = _productionSources();

    expect(sources, isNotEmpty);
    expect(_violationsOf(sources), isEmpty);
  });

  test('declared E4 boundaries permit delivery capabilities when created', () {
    final delivery = <String, String>{
      '${_infrastructureDelivery}http_occurrence_transport.dart': '''
import 'package:http/http.dart' as http;
import 'dart:io';
final class T {
  Future<void> run(http.Client client, Uri uri, String key) async {
    final request = http.StreamedRequest('POST', uri)
      ..headers['Authorization'] = 'ApiKey \$key'
      ..headers['Content-Type'] = 'multipart/form-data; boundary=b';
    await client.send(request);
    final path = '/api/v1/occurrences';
    HttpClient();
  }
}
''',
      '${_infrastructureDelivery}streaming_multipart_encoder.dart':
          'class StreamingMultipartEncoder { const MultipartFile(); }',
      '${_infrastructureDelivery}credential_reader.dart':
          'class A { Future<String?> f(DeviceCredentialReadPort p) => p.readCredential(); }',
      '${_applicationDelivery}coordinator.dart': '''
class Coordinator {
  Future<void> go(OccurrenceTransportPort transport, Object request) async {
    await transport.send(request);
    final delay = DeliveryBackoffPolicy().delayFor(1);
    final CredentialReadResult? result = null;
  }
}
''',
      '${_domainDelivery}delivery_backoff_policy.dart':
          'final class DeliveryBackoffPolicy { const DeliveryBackoffPolicy(); }',
    };

    expect(_violationsOf(delivery), isEmpty);
  });

  test('delivery capabilities are rejected in every forbidden zone', () {
    const forbiddenZones = <String>[
      // Widgets, controllers and state.
      'lib/operation/operation_screen.dart',
      'lib/operation/operation_controller.dart',
      'lib/settings/settings_screen.dart',
      // Occurrence domain.
      'lib/domain/in_memory_occurrence.dart',
      'lib/domain/persistent_occurrence.dart',
      // Manual source and post-candidate pipeline.
      'lib/candidate/manual_candidate_source.dart',
      'lib/application/post_candidate_processor.dart',
      // Diagnostic E0.
      'lib/e0/diagnostic_http_client.dart',
      'lib/e0/e0_controller.dart',
      // Other infrastructure outside the E4 delivery directory.
      'lib/infrastructure/persistent_occurrence_queue.dart',
    ];
    const offenders = <String, String>{
      'transport endpoint': "const p = '/api/v1/occurrences';",
      'auth header': "const h = 'Authorization';",
      'api key scheme': "const h = 'ApiKey ';",
      'multipart': "const t = 'multipart/form-data';",
      'multipart class': 'final r = MultipartRequest();',
      'post call': 'void f(c) { c.post(1); }',
      'send call': 'void f(c) { c.send(1); }',
      'credential read': 'Future<String?> f(p) => p.readCredential();',
      'credential port':
          'abstract interface class X implements DeviceCredentialReadPort {}',
      'backoff': 'const d = DeliveryBackoffPolicy();',
      'http package': "import 'package:http/http.dart';",
    };

    for (final zone in forbiddenZones) {
      for (final offender in offenders.entries) {
        final violations = _violationsOf(<String, String>{
          zone: offender.value,
        });
        // The E0 client keeps a pre-existing dart:io HttpClient, which is not
        // part of any offender here, so every offender must be reported.
        expect(
          violations,
          isNotEmpty,
          reason: '$zone must reject ${offender.key}.',
        );
      }
    }
  });

  test('Diagnostic E0 may only reject, never use, the occurrence endpoint', () {
    final guardOnly = <String, String>{
      _diagnosticHttpClient: '''
final decodedPath = '/x';
if (decodedPath == '/api/v1/occurrences' ||
    decodedPath == '/api/v1/occurrences/') {
  return null;
}
final client = HttpClient();
''',
    };
    expect(_violationsOf(guardOnly), isEmpty);

    final usesEndpoint = <String, String>{
      _diagnosticHttpClient:
          "final u = Uri.parse(base + '/api/v1/occurrences');",
    };
    expect(_violationsOf(usesEndpoint), isNotEmpty);
  });

  test('presentation, E0, candidate and occurrence domain never import E4', () {
    final domainImportingDelivery = <String, String>{
      'lib/domain/in_memory_occurrence.dart':
          "import 'delivery/delivery_backoff_policy.dart';",
    };
    expect(_violationsOf(domainImportingDelivery), isNotEmpty);

    final screenImportingInfrastructure = <String, String>{
      'lib/operation/operation_screen.dart':
          "import '../infrastructure/delivery/http_occurrence_transport.dart';",
    };
    expect(_violationsOf(screenImportingInfrastructure), isNotEmpty);

    final screenImportingApplication = <String, String>{
      'lib/operation/operation_controller.dart':
          "import '../application/delivery/occurrence_delivery_coordinator.dart';",
    };
    expect(_violationsOf(screenImportingApplication), isEmpty);

    final diagnosticImportingDelivery = <String, String>{
      'lib/e0/e0_controller.dart':
          "import '../application/delivery/occurrence_delivery_coordinator.dart';",
    };
    expect(_violationsOf(diagnosticImportingDelivery), isNotEmpty);

    final candidateImportingDelivery = <String, String>{
      'lib/candidate/manual_candidate_source.dart':
          "import '../domain/delivery/delivery_policy.dart';",
      'lib/application/post_candidate_processor.dart':
          "import 'delivery/occurrence_delivery_coordinator.dart';",
    };
    expect(_violationsOf(candidateImportingDelivery), hasLength(2));
  });

  test('E4 layers keep their dependency direction', () {
    final domainImportingInfrastructure = <String, String>{
      '${_domainDelivery}policy.dart':
          "import '../../infrastructure/system_clock.dart';",
    };
    expect(_violationsOf(domainImportingInfrastructure), isNotEmpty);

    final applicationImportingConcreteClient = <String, String>{
      '${_applicationDelivery}coordinator.dart': "import 'dart:io';",
    };
    expect(_violationsOf(applicationImportingConcreteClient), isNotEmpty);

    final transportImportingCamera = <String, String>{
      '${_infrastructureDelivery}transport.dart':
          "import 'package:camera/camera.dart';",
    };
    expect(_violationsOf(transportImportingCamera), isNotEmpty);

    final transportImportingDiagnostic = <String, String>{
      '${_infrastructureDelivery}transport.dart':
          "import '../../e0/diagnostic_http_client.dart';",
    };
    expect(_violationsOf(transportImportingDiagnostic), isNotEmpty);
  });

  test('workers, connectivity, state libraries and inference stay forbidden',
      () {
    for (final location in <String>[
      '${_infrastructureDelivery}worker.dart',
      '${_applicationDelivery}coordinator.dart',
      'lib/operation/operation_controller.dart',
    ]) {
      expect(
        _violationsOf(<String, String>{
          location: 'final w = Workmanager();',
        }),
        isNotEmpty,
        reason: '$location must not introduce a worker.',
      );
      expect(
        _violationsOf(<String, String>{
          location: "import 'package:dio/dio.dart';",
        }),
        isNotEmpty,
        reason: '$location must not import dio.',
      );
      expect(
        _violationsOf(<String, String>{
          location:
              "import 'package:connectivity_plus/connectivity_plus.dart';",
        }),
        isNotEmpty,
        reason: '$location must not import a connectivity plugin.',
      );
    }
  });

  test('package:http is confined to the E4 infrastructure boundary', () {
    expect(
      _violationsOf(<String, String>{
        '${_infrastructureDelivery}http_occurrence_transport.dart':
            "import 'package:http/http.dart' as http;",
      }),
      isEmpty,
    );
    expect(
      _violationsOf(<String, String>{
        'lib/infrastructure/system_clock.dart':
            "import 'package:http/http.dart' as http;",
      }),
      isNotEmpty,
    );
    expect(
      _violationsOf(<String, String>{
        '${_applicationDelivery}coordinator.dart':
            "import 'package:http/http.dart' as http;",
      }),
      isNotEmpty,
    );
  });

  // **Validates: Requirements RF-23.1–12, RNF-01.6–13, RNF-07.1, RNF-07.5,
  // RNF-07.10** (task 70.5)
  group('task 70.5 E0–E3 integrity and absent capabilities', () {
    test('pubspec declares no connectivity, worker, YOLO or model package', () {
      final pubspec = _withoutYamlComments(
        File('pubspec.yaml').readAsStringSync(),
      );
      const forbidden = <String>[
        'connectivity',
        'internet_connection',
        'network_info',
        'workmanager',
        'background_fetch',
        'background_service',
        'flutter_background',
        'android_alarm',
        'ultralytics',
        'yolo',
        'tflite',
        'onnx',
        'pytorch',
        'mlkit',
        'ml_kit',
        'google_mlkit',
        'dio',
      ];
      final dependencies = RegExp(r'^\s{2}([a-z0-9_]+):', multiLine: true)
          .allMatches(pubspec)
          .map((match) => match.group(1)!)
          .toList();
      expect(dependencies, isNotEmpty);
      for (final name in dependencies) {
        for (final fragment in forbidden) {
          if (fragment == 'dio') {
            expect(name, isNot('dio'));
          } else {
            expect(name, isNot(contains(fragment)),
                reason: '$name is a forbidden capability');
          }
        }
      }
      // The only network package is the E4 transport's package:http.
      expect(dependencies, contains('http'));
      expect(pubspec, isNot(contains('assets:')));
    });

    test(
        'the Android app declares no worker, service, receiver or network '
        'state permission', () {
      final manifest = _withoutXmlComments(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );

      expect(manifest, isNot(contains('<service')));
      expect(manifest, isNot(contains('<receiver')));
      expect(manifest, isNot(contains('<provider')));
      expect(manifest, isNot(contains('WorkManager')));
      expect(manifest, isNot(contains('ACCESS_NETWORK_STATE')));
      expect(manifest, isNot(contains('CHANGE_NETWORK_STATE')));
      expect(manifest, isNot(contains('FOREGROUND_SERVICE')));
      expect(manifest, isNot(contains('RECEIVE_BOOT_COMPLETED')));
      expect(manifest, isNot(contains('WAKE_LOCK')));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(
        RegExp(r'android:name="android\.permission\.INTERNET"')
            .allMatches(manifest),
        hasLength(1),
      );
    });

    test('no native source and no model file exists in the project', () {
      final native = Directory('android/app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.replaceAll('\\', '/'))
          .where((path) => path.endsWith('.kt') || path.endsWith('.java'))
          .toList();
      expect(native.map((path) => path.split('/').last).toSet(), <String>{
        'MainActivity.kt',
        'GeneratedPluginRegistrant.java',
      });
      for (final path in native) {
        final source = File(path).readAsStringSync();
        expect(
            source,
            isNot(matches(
                RegExp(r'Worker|JobService|tflite', caseSensitive: false))),
            reason: path);
      }

      const modelExtensions = <String>[
        '.tflite',
        '.onnx',
        '.pt',
        '.pb',
        '.mlmodel',
        '.lite',
        '.ncnn',
      ];
      for (final root in <String>['assets', 'android/app/src', 'lib', 'test']) {
        final directory = Directory(root);
        if (!directory.existsSync()) {
          continue;
        }
        for (final file in directory.listSync(recursive: true)) {
          final path = file.path.toLowerCase();
          for (final extension in modelExtensions) {
            expect(path.endsWith(extension), isFalse,
                reason: '$path looks like a model file');
          }
        }
      }
    });

    test(
        'no production code observes connectivity or schedules background '
        'work', () {
      final sources = _productionSources();
      final pattern = RegExp(
        r'\b(?:Connectivity|ConnectivityResult|NetworkInfo|'
        r'InternetConnectionChecker|ACCESS_NETWORK_STATE|NetworkCallback|'
        r'isolateWorker|Isolate\.spawn|compute|AndroidAlarmManager|'
        r'Workmanager|WorkManager|ForegroundService)\b',
      );
      for (final entry in sources.entries) {
        expect(pattern.hasMatch(_withoutComments(entry.value)), isFalse,
            reason: '${entry.key} introduces connectivity or background work');
      }
    });

    test('E0 diagnostic code never reaches E4 and keeps its own client', () {
      final e0 = _productionSources().entries.where(
            (entry) => entry.key.startsWith('lib/e0/'),
          );
      expect(e0, isNotEmpty);
      for (final entry in e0) {
        final imports = _importsOf(entry.value)
            .map((value) => _resolveImport(entry.key, value));
        for (final target in imports) {
          expect(
            target.startsWith(_domainDelivery) ||
                target.startsWith(_applicationDelivery) ||
                target.startsWith(_infrastructureDelivery) ||
                target.contains('queue_delivery_schema') ||
                target.contains('sanitized_delivery_technical_logger'),
            isFalse,
            reason: '${entry.key} imports $target',
          );
        }
      }
    });

    test('E1–E3 files do not depend on E4 outside the composition roots', () {
      final sources = _productionSources();
      final e4Targets = RegExp(
        r"(?:domain|application|infrastructure)/delivery/|"
        r'queue_delivery_schema|sanitized_delivery_technical_logger',
      );
      final allowed = <String>{
        'lib/main.dart',
        'lib/operation/e1_composition.dart',
        'lib/operation/operation_controller.dart',
        'lib/operation/operation_state.dart',
        'lib/operation/operation_screen.dart',
        'lib/settings/settings_screen.dart',
      };
      final offenders = <String>[];
      for (final entry in sources.entries) {
        if (entry.key.contains('/delivery/') ||
            entry.key == _queueDeliverySchema ||
            entry.key ==
                'lib/infrastructure/sanitized_delivery_technical_logger.dart' ||
            allowed.contains(entry.key)) {
          continue;
        }
        for (final value in _importsOf(entry.value)) {
          if (e4Targets.hasMatch(value)) {
            offenders.add('${entry.key} imports $value');
          }
        }
      }
      // Pre-existing E2/E3 files that adopted the additive E4 contracts in
      // tasks 63–68 are listed explicitly so any new coupling is noticed.
      expect(offenders.where((o) => o.startsWith('lib/e0/')), isEmpty);
      expect(offenders.where((o) => o.startsWith('lib/candidate/')), isEmpty);
      expect(
        offenders.where((o) => o.startsWith('lib/domain/in_memory_')),
        isEmpty,
      );
      expect(
        offenders.where(
          (o) => o.startsWith('lib/application/post_candidate_processor'),
        ),
        isEmpty,
      );
    });

    test('the manual candidate source is unchanged and network-free', () {
      const path = 'lib/candidate/manual_candidate_source.dart';
      final source = _withoutComments(File(path).readAsStringSync());

      expect(
        _importsOf(source),
        <String>['occurrence_candidate_source.dart'],
        reason: 'the manual source may only know the candidate contract',
      );
      expect(source, contains("static const String defectClass = 'pothole';"));
      expect(source, contains('static const double confidence = 1.0;'));
      expect(source, contains('observedAt: seed.observedAt'));
      expect(source, contains('location: seed.location'));
      expect(source, contains('acquireImage: seed.acquireImage'));
      // Image acquisition is forwarded, never invoked, by the source.
      expect(source, isNot(contains('acquireImage(')));
      expect(source, isNot(contains('async')));
      expect(_violationsOf(<String, String>{path: source}), isEmpty);

      final contract = _withoutComments(
        File('lib/candidate/occurrence_candidate_source.dart')
            .readAsStringSync(),
      );
      expect(_importsOf(contract), isNot(contains(contains('delivery'))));
      expect(
        RegExp(r'\b(?:YOLO|yolo|inference|tflite)\b').hasMatch(contract),
        isFalse,
      );
    });

    test('the only YOLO text in production is the approved manual banner', () {
      final banner = <String>[];
      for (final entry in _productionSources().entries) {
        final source = _withoutComments(entry.value);
        if (RegExp(r'\b(?:YOLO|yolo)\b').hasMatch(source)) {
          banner.add(entry.key);
          expect(
            RegExp(r'\b(?:YOLO|yolo)\b')
                .hasMatch(source.replaceAll(_approvedManualBanner, '')),
            isFalse,
            reason: '${entry.key} mentions YOLO beyond the approved banner',
          );
        }
      }
      expect(banner, isNotEmpty);
    });
  });
}

String _withoutYamlComments(String source) =>
    source.replaceAll(RegExp(r'(^|\s)#[^\r\n]*'), '');

String _withoutXmlComments(String source) =>
    source.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

/// Returns human-readable violations for [sources], keyed by `lib/...` path.
List<String> _violationsOf(Map<String, String> sources) {
  final violations = <String>[];

  for (final entry in sources.entries) {
    final path = entry.key;
    final imports = _importsOf(entry.value);
    final resolvedImports = <String>[
      for (final value in imports) _resolveImport(path, value),
    ];

    // Package policy.
    for (final value in imports) {
      for (final forbidden in _forbiddenPackages) {
        if (value.startsWith(forbidden)) {
          violations.add('$path imports forbidden package $forbidden');
        }
      }
      if (value.startsWith('package:http/') &&
          !path.startsWith(_infrastructureDelivery)) {
        violations.add('$path imports package:http outside E4 transport');
      }
      for (final store in _storePackages) {
        if (value.startsWith(store) &&
            !path.startsWith('lib/infrastructure/')) {
          violations.add('$path imports $store outside infrastructure');
        }
      }
    }

    // Capability policy on code without comments.
    var source = _withoutComments(entry.value);
    if (path == 'lib/settings/settings_screen.dart') {
      // Presentation guidance telling the operator NOT to include the path.
      source = source.replaceAll(
        'Não inclua /api/v1/occurrences. HTTPS é obrigatório fora do debug.',
        '',
      );
    }
    if (path == _diagnosticHttpClient) {
      // The Diagnostic client may only reject the occurrence endpoint.
      source = source.replaceAll(
        RegExp(r"decodedPath\s*==\s*'/api/v1/occurrences/?'"),
        '',
      );
    }
    for (final capability in _capabilities) {
      if (capability.permits(path)) {
        continue;
      }
      for (final pattern in capability.patterns) {
        if (_contains(source, pattern)) {
          violations.add('$path uses ${capability.name} outside E4 boundary');
        }
      }
    }
    if (_forbiddenEverywhere.hasMatch(source)) {
      violations.add('$path introduces a worker or model inference');
    }
    if (RegExp(r'\b(?:YOLO|yolo)\b')
        .hasMatch(source.replaceAll(_approvedManualBanner, ''))) {
      violations.add('$path mentions YOLO beyond the approved manual banner');
    }

    // Dependency direction per zone.
    final isPresentation = _isPresentation(path);
    final inE4Layer = path.startsWith(_domainDelivery) ||
        path.startsWith(_applicationDelivery) ||
        path.startsWith(_infrastructureDelivery);

    if (!inE4Layer) {
      final mayUseApplicationOrDomainDelivery =
          (isPresentation && !path.startsWith('lib/e0/')) ||
              _isCompositionRoot(path) ||
              _isOtherInfrastructure(path);
      for (final target in resolvedImports) {
        if (target.startsWith(_infrastructureDelivery) &&
            !_isCompositionRoot(path)) {
          violations.add('$path imports E4 infrastructure');
        } else if ((target.startsWith(_applicationDelivery) ||
                target.startsWith(_domainDelivery)) &&
            !mayUseApplicationOrDomainDelivery) {
          violations.add('$path imports E4 application/domain');
        }
      }
    }

    if (path.startsWith(_domainDelivery)) {
      for (final target in resolvedImports) {
        if (target.startsWith('lib/application/') ||
            target.startsWith('lib/infrastructure/')) {
          violations.add('$path (E4 domain) imports an outer layer');
        }
      }
      _forbidImports(
        violations,
        path,
        imports,
        const <String>['package:flutter/', 'package:http/', 'dart:io'],
      );
    }

    if (path.startsWith(_applicationDelivery)) {
      for (final target in resolvedImports) {
        if (target.startsWith(_infrastructureDelivery)) {
          violations.add('$path (E4 application) imports concrete transport');
        }
      }
      _forbidImports(
        violations,
        path,
        imports,
        const <String>[
          'package:flutter/',
          'package:http/',
          'package:sqflite',
          'package:flutter_secure_storage/',
          'dart:io',
        ],
      );
    }

    if (path.startsWith(_infrastructureDelivery)) {
      for (final target in resolvedImports) {
        const forbiddenTargets = <String>[
          'lib/e0/',
          'lib/candidate/',
          'lib/operation/',
          'lib/settings/',
          'lib/domain/cooldown_policy.dart',
          'lib/infrastructure/operational_camera.dart',
          'lib/infrastructure/operational_location.dart',
        ];
        if (forbiddenTargets.any(target.startsWith)) {
          violations.add('$path (E4 transport) imports $target');
        }
      }
      _forbidImports(
        violations,
        path,
        imports,
        const <String>[
          'package:flutter/',
          'package:camera/',
          'package:geolocator/',
        ],
      );
    }
  }

  return violations;
}

bool _isPresentation(String path) =>
    (path.startsWith('lib/operation/') ||
        path.startsWith('lib/settings/') ||
        path.startsWith('lib/e0/')) &&
    !_isCompositionRoot(path);

bool _isCompositionRoot(String path) =>
    path == 'lib/main.dart' || path == 'lib/operation/e1_composition.dart';

bool _isOtherInfrastructure(String path) =>
    path.startsWith('lib/infrastructure/');

void _forbidImports(
  List<String> violations,
  String path,
  List<String> imports,
  List<String> forbidden,
) {
  for (final value in imports) {
    for (final fragment in forbidden) {
      if (value.startsWith(fragment)) {
        violations.add('$path must not import $fragment');
      }
    }
  }
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

/// Resolves an import to a `lib/...` path when it targets this package.
String _resolveImport(String fromPath, String import) {
  if (import.startsWith('dart:')) {
    return import;
  }
  if (import.startsWith('package:pavimenta_ai_mobile/')) {
    return 'lib/${import.substring('package:pavimenta_ai_mobile/'.length)}';
  }
  if (import.startsWith('package:')) {
    return import;
  }
  final segments = fromPath.split('/')..removeLast();
  for (final part in import.split('/')) {
    if (part == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
    } else if (part != '.' && part.isNotEmpty) {
      segments.add(part);
    }
  }
  return segments.join('/');
}

bool _contains(String source, Pattern pattern) => switch (pattern) {
      String value => source.contains(value),
      RegExp value => value.hasMatch(source),
      _ => throw ArgumentError.value(pattern, 'pattern'),
    };

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\r\n]*'), '');
