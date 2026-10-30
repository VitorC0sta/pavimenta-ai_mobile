import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domain and application contracts import neither Flutter nor SQLite',
      () {
    final files = <File>[
      ..._dartFilesUnder('lib/domain'),
      ..._dartFilesUnder('lib/application'),
    ];

    expect(files, isNotEmpty);
    for (final file in files) {
      final imports = _importsOf(file);
      expect(
        imports,
        isNot(contains(startsWith('package:flutter/'))),
        reason: '${file.path} must remain independent of Flutter.',
      );
      expect(
        imports,
        isNot(contains(startsWith('package:sqflite/'))),
        reason: '${file.path} must remain independent of SQLite.',
      );
      expect(
        imports,
        isNot(contains(startsWith('package:sqflite_common'))),
        reason: '${file.path} must remain independent of SQLite adapters.',
      );
    }
  });

  // **Validates: Requirements RNF-01.1, RNF-01.6, RNF-01.11–13**
  test('E2 models and ports have no UI, source, hardware, or network imports',
      () {
    final files = <File>[
      File('lib/domain/persistent_occurrence.dart'),
      File('lib/application/e2_persistence_ports.dart'),
    ];
    const forbiddenImportFragments = <String>[
      'package:flutter/',
      'package:sqflite/',
      'package:sqflite_common',
      'package:camera/',
      'package:geolocator/',
      'package:http/',
      'package:dio/',
      '/candidate/',
      'occurrence_candidate_source.dart',
      'e1_ports.dart',
      'dart:io',
    ];

    for (final file in files) {
      final imports = _importsOf(file);
      for (final forbidden in forbiddenImportFragments) {
        expect(
          imports.where((value) => value.contains(forbidden)),
          isEmpty,
          reason: '${file.path} must not import $forbidden.',
        );
      }
    }
  });

  // **Validates: Requirements RF-12.5, RNF-01.7–8**
  test('presentation snapshot exposes only aggregate queue state', () {
    final source = File(
      'lib/domain/persistent_occurrence.dart',
    ).readAsStringSync();
    final snapshotSource = source.substring(
      source.indexOf('final class QueueSnapshot'),
    );

    for (final forbidden in <String>[
      'absolutePath',
      'imageBytes',
      'idempotencyKey',
      'sha256',
      'latitude',
      'longitude',
      'detectedAtIso8601',
      'relativeName',
    ]) {
      expect(
        snapshotSource,
        isNot(contains(forbidden)),
        reason: 'QueueSnapshot must not expose $forbidden.',
      );
    }
  });

  // **Validates: Requirements RF-00.4, RF-00.20, RF-12.3, RF-23.9,
  // RNF-01.12, RNF-04.1–2**
  test('queue bootstrap and retry cannot own hardware or Diagnostic routing',
      () {
    final files = <File>[
      File('lib/application/e2_persistence_ports.dart'),
      File('lib/infrastructure/persistent_occurrence_queue.dart'),
    ];
    const forbiddenImportFragments = <String>[
      'package:camera/',
      'package:geolocator/',
      'package:flutter/',
      '/e0/',
      '/operation/',
      'operational_camera.dart',
      'operational_location.dart',
    ];

    for (final file in files) {
      final imports = _importsOf(file);
      for (final forbidden in forbiddenImportFragments) {
        expect(
          imports.where((value) => value.contains(forbidden)),
          isEmpty,
          reason: '${file.path} must not import $forbidden.',
        );
      }
    }

    final queueSource = files.last.readAsStringSync();
    expect(queueSource, isNot(contains('suspendForDiagnostic')));
    expect(queueSource, isNot(contains('acquirePreview')));
    expect(queueSource, isNot(contains('acquireForegroundUpdates')));
  });

  // **Validates: Requirements RF-23.9, RNF-05.5**
  test('E2 persistence ports contain no sending or UI removal API', () {
    final source = File(
      'lib/application/e2_persistence_ports.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('package:http')));
    expect(source, isNot(contains('package:dio')));
    expect(source, isNot(contains('multipart')));
    expect(source, isNot(contains('Authorization')));
    expect(source, isNot(contains('Widget')));
    expect(source, isNot(contains('removeFromUi')));
    expect(source, contains('removeInternal'));
  });

  // **Validates: Requirements RF-12.9, RF-12.11, RNF-03.5, RNF-05.4,
  // RNF-06.2, RNF-06.10–11**
  test('E2 removal remains internal with E4 as its single production caller',
      () {
    const contractPath = 'lib/application/e2_persistence_ports.dart';
    const queuePath = 'lib/infrastructure/persistent_occurrence_queue.dart';
    // The E4 delivery port (design E4.4) is the single declared application
    // contract through which the delivery coordinator completes local
    // removal of an item whose definitive decision was recorded.
    const deliveryQueuePortPath =
        'lib/application/delivery/occurrence_delivery_queue_port.dart';
    // The E4 persistent delivery queue (design E4.5) is the only production
    // caller of E2 removal: once a definitive decision is recorded, it runs
    // the E2 removal protocol (row and JPEG) for that item.
    const deliveryQueuePath =
        'lib/infrastructure/delivery/persistent_delivery_queue.dart';
    const deliveryCoordinatorPath =
        'lib/application/delivery/occurrence_delivery_coordinator.dart';
    const deliveryResultSymbols = <String>{
      'QueueRemovalResult',
      'QueueOccurrenceRemoved',
      'QueueOccurrenceNotFound',
      'QueueOccurrenceRemovalFailed',
    };
    const removalSymbols = <String>{
      'removeInternal',
      'QueueRemovalResult',
      'QueueOccurrenceRemoved',
      'QueueOccurrenceNotFound',
      'QueueOccurrenceRemovalFailed',
      'CrashConsistentQueueMutationDriver',
    };
    final productionFiles = _dartFilesUnder('lib').toList(growable: false);
    final sources = <String, String>{
      for (final file in productionFiles)
        file.path.replaceAll('\\', '/'): file.readAsStringSync(),
    };

    expect(
      sources.keys.where((path) => sources[path]!.contains('removeInternal')),
      unorderedEquals(<String>[contractPath, queuePath, deliveryQueuePath]),
      reason: 'Only the E2 contract, the E2 queue implementation, and the E4 '
          'persistent delivery queue (design E4.5) may know the removal API.',
    );
    final removalCall = RegExp(r'\.\s*removeInternal\s*\(');
    expect(
      sources.keys.where((path) => removalCall.hasMatch(sources[path]!)),
      unorderedEquals(<String>[deliveryQueuePath]),
      reason:
          'The E4 persistent delivery queue (design E4.5) is the only allowed '
          'caller of E2 removal; no widget, button, route, controller, timer, '
          'worker, or service may call it.',
    );

    for (final entry in sources.entries) {
      if (entry.key == contractPath ||
          entry.key == queuePath ||
          entry.key == deliveryQueuePortPath ||
          entry.key == deliveryQueuePath) {
        continue;
      }
      for (final symbol in removalSymbols) {
        // The delivery coordinator only interprets the result of the E4 port
        // (`completePendingLocalRemoval`). It still cannot name the removal
        // call or the mutation driver, and `removeInternal` stays confined by
        // the assertions above.
        if (entry.key == deliveryCoordinatorPath &&
            deliveryResultSymbols.contains(symbol)) {
          continue;
        }
        expect(
          entry.value,
          isNot(contains(symbol)),
          reason:
              '${entry.key} must not receive an internal E2 removal capability.',
        );
      }
    }
  });
}

Iterable<File> _dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

List<String> _importsOf(File file) {
  final source = file.readAsStringSync();
  final importPattern = RegExp(
    r'''^\s*import\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  return importPattern
      .allMatches(source)
      .map((match) => match.group(1)!)
      .toList(growable: false);
}
