import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_backoff_policy.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_presentation_state.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/infrastructure/sanitized_delivery_technical_logger.dart';

import '../../support/e4/e4_restart_world.dart';

/// Task 70.4: inspection of sources, tests, logs and rendered state.
///
/// Confirms that the four required technical categories are emitted and that
/// no secret, header, URL, body, multipart, image, identifier, coordinate,
/// occurrence time, file name, path, digest or raw exception can reach a log
/// line or a rendered delivery text.
///
/// Every value is explicitly fictitious.
const String _sensitiveLatitude = '-23.5505';
const String _sensitiveLongitude = '-46.6333';

final RegExp _lineShape = RegExp(
  r'^E4_DELIVERY_[A-Z_]+( (disposition|status|cause)=[A-Za-z0-9]+)?$',
);

/// Fragments that must never appear in a log line or rendered text.
const List<String> _forbiddenFragments = <String>[
  // Credential and headers.
  restartSecret,
  restartRotatedSecret,
  'fakeprefix',
  'fake-secret',
  'ApiKey',
  'Authorization',
  'X-Api-Key',
  'Bearer',
  'Content-Type',
  'Content-Disposition',
  'Content-Length',
  // URL and endpoint.
  'delivery.example.invalid',
  'http://',
  'https://',
  '/api/v1',
  // Body, multipart and image.
  'multipart',
  'boundary',
  'form-data',
  'idempotencyKey',
  'defectClass',
  'confidence',
  'detectedAt',
  'image/jpeg',
  // Identifiers, coordinates, occurrence time.
  restartKeyA,
  restartKeyB,
  restartKeyC,
  '123e4567',
  _sensitiveLatitude,
  _sensitiveLongitude,
  '-23.55',
  '-46.63',
  '2025-01-02',
  // File names, paths and digests.
  '.jpg',
  '.jpeg',
  '.deleting',
  'e2i_',
  'e2s_',
  'e2d_',
  'sqlite',
  'sha256',
  'digest',
  // Raw exceptions.
  'Exception',
  'SocketException',
  'RequestAbortedException',
  'StateError',
  'SimulatedCrash',
  'unreachable',
  'StackTrace',
  '#0 ',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // **Validates: Requirements RF-23.7–12, RNF-01–03, RNF-07**
  group('task 70.4 emitted logs and rendered state', () {
    Future<E4RestartWorld> startWorld() async {
      final world = await E4RestartWorld.create();
      await world.boot(start: false);
      return world;
    }

    void expectClosedVocabulary(E4RestartWorld world) {
      final rendered = <String>[
        ...world.allLogs,
        for (final phase in DeliveryPhase.values) ...<String>[
          DeliveryPresentationState(phase: phase).message,
          DeliveryPresentationState(phase: phase).statusLabel,
          '${DeliveryPresentationState(phase: phase)}',
        ],
      ];
      for (final entry in world.allLogs) {
        expect(entry, matches(_lineShape));
      }
      for (final text in rendered) {
        for (final fragment in _forbiddenFragments) {
          expect(
            text.toLowerCase(),
            isNot(contains(fragment.toLowerCase())),
            reason: '"$text" must not contain "$fragment"',
          );
        }
        expect(text, isNot(contains(world.sandbox.path)));
        expect(text, isNot(contains(world.databasePath)));
      }
      world.expectNoLeak();
    }

    test(
        'definitive, recoverable and unexpected-response categories are '
        'emitted while the wire carries the sensitive data the logs omit',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client
        ..status(409)
        ..network()
        ..step((aborted) async {
          await aborted;
          throw http.RequestAbortedException();
        })
        ..status(503)
        ..status(302);

      world.session.delivery.start();
      await world.settle();
      for (var i = 0; i < 3; i++) {
        world.fakeTimer.advance(DeliveryBackoffPolicy.maxDelay);
        await world.settle();
      }

      expect(world.client.keys, <String>[
        restartKeyA,
        restartKeyB,
        restartKeyB,
        restartKeyB,
        restartKeyB,
      ]);
      expect(world.allLogs, <String>[
        'E4_DELIVERY_DEFINITIVE_REJECTION disposition=conflict',
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=network',
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=timeout',
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=serverError',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=302',
      ]);
      expect(world.session.phase, DeliveryPhase.pausedUnexpected);

      // The inspection has teeth: the request really carried what the log
      // vocabulary is forbidden to repeat.
      final request = world.client.seen.first;
      expect(request.url, contains('delivery.example.invalid'));
      expect(request.authorization, 'ApiKey $restartSecret');
      expect(request.idempotencyKey, restartKeyA);

      expectClosedVocabulary(world);
      expect(world.client.unscripted, 0);
    });

    test('the cleanup-failure category is emitted without any payload',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(201);
      world.session.faults
          .plan('markForDeletion', Moment.before, Fault.failure);

      world.session.delivery.start();
      await world.settle();

      expect(world.allLogs, <String>['E4_DELIVERY_CLEANUP_FAILURE']);
      expect(world.session.phase, DeliveryPhase.cleaning);
      expectClosedVocabulary(world);
    });

    test('authentication and access pauses log nothing and render only text',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(401);

      world.session.delivery.start();
      await world.settle();

      expect(world.session.phase, DeliveryPhase.pausedAuthentication);
      expect(world.allLogs, isEmpty);
      expectClosedVocabulary(world);
    });

    test('the log contract has exactly the four required fixed categories', () {
      expect(
        DeliveryLogCategory.values.map((category) => category.code).toList(),
        <String>[
          'E4_DELIVERY_DEFINITIVE_REJECTION',
          'E4_DELIVERY_UNEXPECTED_RESPONSE',
          'E4_DELIVERY_RECOVERABLE_FAILURE',
          'E4_DELIVERY_CLEANUP_FAILURE',
        ],
      );
    });

    test('every phase text is closed, fictitious-free and detail-free', () {
      for (final phase in DeliveryPhase.values) {
        final state = DeliveryPresentationState(phase: phase);
        for (final text in <String>[
          state.message,
          state.statusLabel,
          '$state',
        ]) {
          expect(text, isNotEmpty);
          for (final fragment in _forbiddenFragments) {
            expect(
              text.toLowerCase(),
              isNot(contains(fragment.toLowerCase())),
              reason: '$phase: "$text" must not contain "$fragment"',
            );
          }
          expect(text, isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}'))));
          expect(text, isNot(matches(RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-'))));
        }
      }
    });
  });

  group('task 70.4 production sources', () {
    final delivery = _dartSources(<String>[
      'lib/domain/delivery',
      'lib/application/delivery',
      'lib/infrastructure/delivery',
    ]);

    test('the logger port accepts only enumerations or a numeric status', () {
      final port = _withoutComments(
        File('lib/application/delivery/delivery_technical_logger.dart')
            .readAsStringSync(),
      );
      final signatures = RegExp(r'void\s+(\w+)\(([^)]*)\)\s*;')
          .allMatches(port)
          .map((match) => '${match.group(1)}(${match.group(2)!.trim()})')
          .toList();

      expect(signatures, <String>[
        'definitiveRejection(DeliveryDisposition disposition)',
        'unexpectedResponse(int statusCode)',
        'recoverableFailure(RecoverableFailureCause cause)',
        'cleanupFailure()',
      ]);
    });

    test('the coordinator emits only the four closed events', () {
      final coordinator = _withoutComments(
        File('lib/application/delivery/occurrence_delivery_coordinator.dart')
            .readAsStringSync(),
      );
      final calls = RegExp(r'logger\.(\w+)\(([^)]*)\)')
          .allMatches(coordinator)
          .map((match) => '${match.group(1)}(${match.group(2)})')
          .toList();

      expect(calls, <String>[
        'definitiveRejection(disposition)',
        'cleanupFailure()',
        'unexpectedResponse(statusCode)',
        'recoverableFailure(cause)',
      ]);
    });

    test('there is a single logger implementation and no other output', () {
      final implementations = <String>[
        for (final entry in _dartSources(<String>['lib']).entries)
          if (RegExp(r'implements\s+DeliveryTechnicalLogger\b')
              .hasMatch(entry.value))
            entry.key,
      ];
      expect(implementations, <String>[
        'lib/infrastructure/sanitized_delivery_technical_logger.dart',
      ]);

      final output = RegExp(
        r'\b(?:print|debugPrint|stdout|stderr|developer\.log|'
        r'dumpErrorToConsole|FlutterError\.reportError)\b',
      );
      for (final entry in delivery.entries) {
        expect(output.hasMatch(entry.value), isFalse,
            reason: '${entry.key} must not write to any output');
      }

      // The only sink wiring is the debug-only composition in main.
      final debugPrints = <String>[
        for (final entry in _dartSources(<String>['lib']).entries)
          if (RegExp(r'\bdebugPrint\b').hasMatch(entry.value)) entry.key,
      ];
      expect(debugPrints, <String>['lib/main.dart']);
      expect(
        File('lib/main.dart').readAsStringSync(),
        contains('logSink: kDebugMode ? debugPrint : null'),
      );
    });

    test('delivery sources never interpolate raw errors or stack traces', () {
      final interpolation = RegExp(
        r'\$\{?\s*(?:e|ex|err|error|exception|stack|stackTrace|trace)\b',
      );
      final rawToString = RegExp(
        r'\b(?:e|ex|err|error|exception|stack|stackTrace)\.toString\(',
      );
      final files = <String, String>{
        ...delivery,
        'lib/infrastructure/sanitized_delivery_technical_logger.dart':
            File('lib/infrastructure/sanitized_delivery_technical_logger.dart')
                .readAsStringSync(),
      };
      for (final entry in files.entries) {
        final source = _withoutComments(entry.value);
        expect(interpolation.hasMatch(source), isFalse,
            reason: '${entry.key} interpolates a raw error');
        expect(rawToString.hasMatch(source), isFalse,
            reason: '${entry.key} stringifies a raw error');
      }
    });

    test('delivery value types override toString without sensitive fields', () {
      final secret = NonPrintableSecret(restartSecret);
      expect('$secret', isNot(contains('fake')));
      expect('$secret', contains(redactedSecretPlaceholder));
      expect(secret.toJson(), redactedSecretPlaceholder);
    });
  });

  group('task 70.4 test sources', () {
    test('delivery tests print nothing and use only reserved .invalid hosts',
        () {
      final sources = _dartSources(<String>[
        'test/infrastructure/delivery',
        'test/support/e4',
      ]);
      expect(sources, isNotEmpty);

      final url = RegExp(r'''https?://(?:[^/\s@'"]*@)?([^/\s'"\\:$?#]+)''');
      // RFC 2606 / 6761 reserved names and loopback only; never a real host.
      final reserved = RegExp(
        r'^(?:.*\.(?:invalid|test|example)|localhost|127\.0\.0\.1|x)$',
      );
      for (final entry in sources.entries) {
        final source = entry.value;
        expect(RegExp(r'\b(?:print|debugPrint)\(').hasMatch(source), isFalse,
            reason: '${entry.key} must not print');
        for (final match in url.allMatches(source)) {
          final host = match.group(1)!;
          expect(reserved.hasMatch(host), isTrue,
              reason: '${entry.key} uses a non-reserved host: $host');
        }
      }
    });
  });
}

Map<String, String> _dartSources(List<String> roots) {
  final result = <String, String>{};
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      continue;
    }
    for (final file in directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      result[file.path.replaceAll('\\', '/')] = file.readAsStringSync();
    }
  }
  return result;
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\r\n]*'), '');
