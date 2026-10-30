import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_change_service.dart';
import 'package:pavimenta_ai_mobile/application/delivery/device_credential_read_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/exclusive_delivery_configuration_snapshot.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_coordinator.dart'
    hide DeliveryPhase;
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/operation_delivery_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_timer_port.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart'
    show DeliveryPauseReason;
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_presentation_state.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/http_occurrence_transport.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_transport_limits.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/persistent_delivery_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streamed_http_client_adapter.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_delivery_schema.dart';
import 'package:pavimenta_ai_mobile/infrastructure/sanitized_delivery_technical_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/e4/e4_fakes.dart';

// Explicitly fictitious values; none is a real destination, key or identifier.
final Uri _baseUrl = Uri.parse('https://delivery.example.invalid');
const String _wireUrl = 'https://delivery.example.invalid/api/v1/occurrences';
const String _secret = fakeDeliveryCredential;
const String _rotatedSecret = 'newprefix.new-secret-for-tests-only';
const String _keyA = '123e4567-e89b-42d3-a456-426614174000';
const String _keyB = '223e4567-e89b-42d3-a456-426614174000';
const String _keyC = '323e4567-e89b-42d3-a456-426614174000';
const String _keyD = '423e4567-e89b-42d3-a456-426614174000';

final DateTime _t0 = DateTime.utc(2026, 3, 1, 12);

const Set<String> _expectedFields = <String>{
  'idempotencyKey',
  'latitude',
  'longitude',
  'confidence',
  'defectClass',
  'detectedAt',
  'image',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late _World world;

  Future<_World> open({
    bool withConfiguration = true,
    Duration attemptTimeout = const Duration(milliseconds: 200),
  }) async {
    final opened = await _World.open(
      withConfiguration: withConfiguration,
      attemptTimeout: attemptTimeout,
    );
    world = opened;
    addTearDown(opened.dispose);
    return opened;
  }

  // **Validates: Requirements RF-05, RF-08–18, RF-21, RNF-01–07**
  group('task 70.1 multiple pending items', () {
    test(
        'delivers the queue in FIFO order, one at a time, with the exact wire '
        'contract and the stored idempotency keys', () async {
      await open();
      await world.persist(_keyA, red: 1);
      await world.persist(_keyB, red: 2);
      await world.persist(_keyC, red: 3);
      world.client
        ..status(201)
        ..status(200)
        ..status(201);

      world.start();
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyB, _keyC]);
      expect(world.client.maxInFlight, 1);
      expect(world.client.unscripted, 0);
      for (final request in world.client.seen) {
        expect(request.method, 'POST');
        expect(request.url, _wireUrl);
        expect(request.authorization, 'ApiKey $_secret');
        expect(request.contentLength, request.bodyBytes);
        expect(request.fields.toSet(), _expectedFields);
        expect(request.followRedirects, isFalse);
      }
      expect(await world.pendingCount(), 0);
      expect(world.jpegCount(), 0);
      expect(await world.stateRow(_keyA), isNull);
      expect(world.delivery.presentation.phase, DeliveryPhase.idle);
      expect(world.logs, isEmpty);
      // The cooldown anchor survives the removal of every pending item.
      final anchor = await world.queue.readAcceptedAnchor();
      expect(anchor, isNotNull);
      expect(anchor!.queueSequence, 3);
      world.expectNoLeak();
    });

    test('mixes outcomes without reordering and keeps every key stable',
        () async {
      await open();
      for (final (index, key) in <String>[_keyA, _keyB, _keyC, _keyD].indexed) {
        await world.persist(key, red: index + 1);
      }
      world.client
        ..status(201)
        ..status(409)
        ..network()
        ..status(200)
        ..status(400);

      world.start();
      await world.settle();

      // A created, B discarded, C failed: D must not overtake C.
      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyB, _keyC]);
      expect(await world.pendingCount(), 2);
      expect(world.delivery.presentation.phase, DeliveryPhase.waitingBackoff);

      world.timer.advance(const Duration(seconds: 5));
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyB, _keyC, _keyC, _keyD]);
      expect(world.client.maxInFlight, 1);
      expect(await world.pendingCount(), 0);
      expect(world.jpegCount(), 0);
      expect(world.delivery.presentation.phase, DeliveryPhase.idle);
      expect(world.logs, <String>[
        'E4_DELIVERY_DEFINITIVE_REJECTION disposition=conflict',
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=network',
        'E4_DELIVERY_DEFINITIVE_REJECTION disposition=invalidContract',
      ]);
      world.expectNoLeak();
    });

    test(
        'runs one attempt at a time, keeps persisting during the upload and '
        'lowers the count only after the confirmed removal', () async {
      await open();
      await world.persist(_keyA, red: 1);
      await world.persist(_keyB, red: 2);
      final gate = world.client.hold();
      world.client.status(201);
      world.start();
      await world.waitFor(() => world.client.seen.length == 1);

      expect(world.delivery.presentation.phase, DeliveryPhase.sending);
      expect(world.delivery.presentation.canRetry, isFalse);
      // The queue is not locked while the request is in flight.
      await world.persist(_keyC, red: 3).timeout(const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        world.delivery.onQueueChanged();
      }
      await world.delivery.retryManually();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(world.client.seen, hasLength(1));
      expect(world.client.maxInFlight, 1);
      expect(await world.pendingCount(), 3);

      world.client.status(201);
      gate.complete(201);
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyB, _keyC]);
      expect(world.client.maxInFlight, 1);
      expect(await world.pendingCount(), 0);
      world.expectNoLeak();
    });
  });

  group('task 70.1 definitive decisions', () {
    final cases = <(int, String?)>[
      (200, null),
      (201, null),
      (400, 'invalidContract'),
      (409, 'conflict'),
      (413, 'imageTooLarge'),
      (415, 'unsupportedFormat'),
    ];
    for (final (status, disposition) in cases) {
      test('HTTP $status removes the item and continues with the next one',
          () async {
        await open();
        await world.persist(_keyA, red: 1);
        await world.persist(_keyB, red: 2);
        world.client
          ..status(status)
          ..status(201);

        world.start();
        await world.settle();

        expect(world.client.seen.map((s) => s.idempotencyKey),
            <String>[_keyA, _keyB]);
        expect(await world.pendingCount(), 0);
        expect(world.jpegCount(), 0);
        expect(await world.stateRow(_keyA), isNull);
        expect(await world.deliveryQueue.readControl(),
            isA<DeliveryControlRunning>());
        expect(world.delivery.presentation.phase, DeliveryPhase.idle);
        expect(
          world.logs,
          disposition == null
              ? isEmpty
              : <String>[
                  'E4_DELIVERY_DEFINITIVE_REJECTION disposition=$disposition',
                ],
        );
        expect((await world.queue.readAcceptedAnchor())!.queueSequence, 2);
        world.expectNoLeak();
      });
    }
  });

  group('task 70.1 recoverable failures and backoff', () {
    test(
        'network failure and timeout keep the head, follow the 5 s / 15 s '
        'progression and resend the same key and image', () async {
      await open();
      await world.persist(_keyA, red: 1);
      await world.persist(_keyB, red: 2);
      world.client
        ..network()
        ..never()
        ..status(201)
        ..status(201);

      world.start();
      await world.settle();

      expect(world.client.seen, hasLength(1));
      var row = (await world.stateRow(_keyA))!;
      expect(row['attempt_count'], 1);
      expect(
        DateTime.parse(row['next_attempt_at']! as String)
            .isAtSameMomentAs(_t0.add(const Duration(seconds: 5))),
        isTrue,
      );
      expect(world.delivery.presentation.phase, DeliveryPhase.waitingBackoff);
      expect(world.delivery.presentation.canRetry, isFalse);
      expect(world.fakeTimer.activeCount, 1);
      expect(world.fakeTimer.active.single.dueAt,
          _t0.add(const Duration(seconds: 5)));

      // Neither a notification, a resume nor the manual retry shortens it.
      world.delivery.onQueueChanged();
      world.delivery.onAppResumed();
      expect(await world.delivery.retryManually(),
          DeliveryManualRetryResult.evaluationRequested);
      await world.settle();
      world.timer.advance(const Duration(seconds: 4));
      await world.settle();
      expect(world.client.seen, hasLength(1));
      expect(world.fakeTimer.activeCount, 1);
      expect((await world.stateRow(_keyA))!['attempt_count'], 1);

      world.timer.advance(const Duration(seconds: 1));
      await world.settle();

      expect(world.client.seen, hasLength(2));
      row = (await world.stateRow(_keyA))!;
      expect(row['attempt_count'], 2);
      expect(
        DateTime.parse(row['next_attempt_at']! as String)
            .isAtSameMomentAs(_t0.add(const Duration(seconds: 20))),
        isTrue,
      );
      expect(world.client.seen[1].idempotencyKey, _keyA);
      expect(world.client.seen[1].containsImage(world.jpeg(_keyA)), isTrue);

      world.timer.advance(const Duration(seconds: 15));
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyA, _keyA, _keyB]);
      for (final request in world.client.seen.take(3)) {
        expect(request.containsImage(world.jpeg(_keyA)), isTrue);
      }
      expect(await world.pendingCount(), 0);
      expect(world.fakeTimer.maxConcurrentActive, 1);
      expect(world.logs, <String>[
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=network',
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=timeout',
      ]);
      world.expectNoLeak();
    });

    for (final status in <int>[500, 503]) {
      test('HTTP $status is recoverable and never discards the item', () async {
        await open();
        await world.persist(_keyA, red: 1);
        world.client
          ..status(status)
          ..status(201);

        world.start();
        await world.settle();

        expect(world.client.seen, hasLength(1));
        expect(await world.pendingCount(), 1);
        expect(world.jpegCount(), 1);
        expect(await world.deliveryQueue.readControl(),
            isA<DeliveryControlRunning>());
        expect(world.delivery.presentation.phase, DeliveryPhase.waitingBackoff);
        expect(world.logs,
            <String>['E4_DELIVERY_RECOVERABLE_FAILURE cause=serverError']);

        world.timer.advance(const Duration(seconds: 5));
        await world.settle();

        expect(world.client.seen.map((s) => s.idempotencyKey),
            <String>[_keyA, _keyA]);
        expect(await world.pendingCount(), 0);
        world.expectNoLeak();
      });
    }

    test(
        'leaving the foreground cancels the attempt without recording a '
        'failure and the resume reuses the key', () async {
      await open();
      await world.persist(_keyA, red: 1);
      world.client.hold();
      world.client.status(201);
      world.start();
      await world.waitFor(() => world.client.seen.length == 1);

      await world.delivery.onAppLeftForeground();
      await world.settle();

      expect(world.client.seen, hasLength(1));
      expect(await world.pendingCount(), 1);
      final row = await world.stateRow(_keyA);
      expect(row == null || row['attempt_count'] == 0, isTrue);
      expect(world.fakeTimer.activeCount, 0);
      expect(world.logs, isEmpty);

      world.delivery.onAppResumed();
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyA]);
      expect(await world.pendingCount(), 0);
      world.expectNoLeak();
    });
  });

  group('task 70.1 pauses', () {
    test(
        '401 pauses persistently, preserves the queue and resumes with the '
        'corrected credential, never mixing the old one', () async {
      await open();
      await world.persist(_keyA, red: 1);
      await world.persist(_keyB, red: 2);
      world.client.status(401);

      world.start();
      await world.settle();

      expect(world.client.seen, hasLength(1));
      expect(await world.deliveryQueue.readControl(),
          isA<DeliveryControlPaused>());
      expect(world.delivery.presentation.phase,
          DeliveryPhase.pausedAuthentication);
      expect(world.delivery.presentation.canRetry, isTrue);
      expect(await world.pendingCount(), 2);
      final row = await world.stateRow(_keyA);
      expect(row == null || row['attempt_count'] == 0, isTrue);
      expect(world.fakeTimer.activeCount, 0);

      for (var i = 0; i < 3; i++) {
        world.delivery.onQueueChanged();
        world.delivery.onAppResumed();
      }
      await world.settle();
      expect(world.client.seen, hasLength(1), reason: 'no automatic retry');

      world.client
        ..status(201)
        ..status(201);
      await world.guard.replaceDestinationOrCredential(() async {
        world.credentials.secret = _rotatedSecret;
      });
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyA, _keyB]);
      expect(world.client.seen[0].authorization, 'ApiKey $_secret');
      expect(world.client.seen[1].authorization, 'ApiKey $_rotatedSecret');
      expect(world.client.seen[2].authorization, 'ApiKey $_rotatedSecret');
      expect(await world.pendingCount(), 0);
      expect(world.logs, isEmpty);
      world.expectNoLeak();
    });

    test('403 pauses on access and the manual retry resumes it', () async {
      await open();
      await world.persist(_keyA, red: 1);
      world.client
        ..status(403)
        ..status(201);

      world.start();
      await world.settle();

      final control = await world.deliveryQueue.readControl();
      expect((control as DeliveryControlPaused).reason,
          DeliveryPauseReason.access);
      expect(world.delivery.presentation.phase, DeliveryPhase.pausedAccess);
      expect(world.delivery.presentation.canRetry, isTrue);
      expect(world.client.seen, hasLength(1));

      expect(await world.delivery.retryManually(),
          DeliveryManualRetryResult.resumed);
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyA]);
      expect(await world.pendingCount(), 0);
      expect(await world.deliveryQueue.readControl(),
          isA<DeliveryControlRunning>());
      world.expectNoLeak();
    });

    for (final status in <int>[302, 404]) {
      test('HTTP $status is an unexpected response: pause, keep, log status',
          () async {
        await open();
        await world.persist(_keyA, red: 1);
        world.client
          ..status(status)
          ..status(201);

        world.start();
        await world.settle();

        final control = await world.deliveryQueue.readControl();
        expect((control as DeliveryControlPaused).reason,
            DeliveryPauseReason.unexpectedResponse);
        expect(control.unexpectedStatusCode, status);
        expect(
            world.delivery.presentation.phase, DeliveryPhase.pausedUnexpected);
        expect(await world.pendingCount(), 1);
        expect(world.logs,
            <String>['E4_DELIVERY_UNEXPECTED_RESPONSE status=$status']);

        expect(await world.delivery.retryManually(),
            DeliveryManualRetryResult.resumed);
        await world.settle();

        expect(world.client.seen, hasLength(2));
        expect(await world.pendingCount(), 0);
        world.expectNoLeak();
      });
    }

    test('a JPEG missing at the head pauses on local failure without a socket',
        () async {
      await open();
      await world.persist(_keyA, red: 1);
      await world.persist(_keyB, red: 2);
      final record = (await world.queue.listPending()).first.record;
      await PrivateDurableImageStore.at(world.sandbox).delete(record.image);

      world.start();
      await world.settle();

      expect(world.client.seen, isEmpty);
      final control = await world.deliveryQueue.readControl();
      expect((control as DeliveryControlPaused).reason,
          DeliveryPauseReason.localFailure);
      expect(
          world.delivery.presentation.phase, DeliveryPhase.pausedLocalFailure);
      expect(world.delivery.presentation.canRetry, isTrue);
      expect(await world.pendingCount(), 2);
      world.expectNoLeak();
    });
  });

  group('task 70.1 configuration', () {
    test(
        'missing destination or credential never reaches the transport and '
        'the saved configuration delivers the queue', () async {
      await open(withConfiguration: false);
      await world.persist(_keyA, red: 1);
      world.client.status(201);

      world.start();
      await world.settle();
      expect(world.delivery.presentation.phase,
          DeliveryPhase.configurationRequired);
      expect(world.delivery.presentation.canRetry, isFalse);

      await world.guard.replaceDestinationOrCredential(() async {
        world.repository.baseUrl = _baseUrl;
      });
      await world.settle();
      expect(world.delivery.presentation.phase,
          DeliveryPhase.configurationRequired);

      expect(world.client.seen, isEmpty);
      expect(await world.pendingCount(), 1);
      expect(await world.stateRow(_keyA), isNull);

      await world.guard.replaceDestinationOrCredential(() async {
        world.credentials.secret = _secret;
      });
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey), <String>[_keyA]);
      expect(await world.pendingCount(), 0);
      expect(world.delivery.presentation.phase, DeliveryPhase.idle);
      world.expectNoLeak();
    });

    test('removing the credential later never opens a connection', () async {
      await open();
      await world.persist(_keyA, red: 1);
      world.client.status(201);
      world.start();
      await world.settle();
      expect(await world.pendingCount(), 0);

      await world.persist(_keyB, red: 2);
      await world.guard.removeCredential(() async {
        world.credentials.secret = null;
      });
      world.delivery.onQueueChanged();
      await world.settle();

      expect(world.client.seen, hasLength(1));
      expect(world.delivery.presentation.phase,
          DeliveryPhase.configurationRequired);
      expect(await world.pendingCount(), 1);
      world.expectNoLeak();
    });

    test('a malformed credential stops before the image and the socket',
        () async {
      await open();
      world.credentials.secret = 'malformed-credential-without-separator';
      await world.persist(_keyA, red: 1);
      world.client.status(201);

      world.start();
      await world.settle();

      expect(world.client.seen, isEmpty);
      expect(world.delivery.presentation.phase,
          DeliveryPhase.pausedAuthentication);
      expect(world.delivery.presentation.canRetry, isTrue);
      expect(await world.pendingCount(), 1);

      await world.guard.replaceDestinationOrCredential(() async {
        world.credentials.secret = _secret;
      });
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey), <String>[_keyA]);
      expect(await world.pendingCount(), 0);
      world.expectNoLeak();
    });

    test(
        'an unreadable secure storage pauses on local failure, a correction '
        'does not clear it and the manual retry does', () async {
      await open();
      world.credentials.result = const CredentialStorageUnavailable();
      await world.persist(_keyA, red: 1);
      world.client.status(201);

      world.start();
      await world.settle();

      final control = await world.deliveryQueue.readControl();
      expect((control as DeliveryControlPaused).reason,
          DeliveryPauseReason.localFailure);
      expect(
          world.delivery.presentation.phase, DeliveryPhase.pausedLocalFailure);
      expect(world.client.seen, isEmpty);

      world.credentials.result = null;
      await world.guard.replaceDestinationOrCredential(() async {
        world.credentials.secret = _secret;
      });
      await world.settle();
      expect(world.client.seen, isEmpty);
      expect(await world.deliveryQueue.readControl(),
          isA<DeliveryControlPaused>());

      expect(await world.delivery.retryManually(),
          DeliveryManualRetryResult.resumed);
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey), <String>[_keyA]);
      expect(await world.pendingCount(), 0);
      world.expectNoLeak();
    });

    test(
        'a configuration change during an upload cancels it and the retry '
        'uses only the new pair with the same key', () async {
      await open();
      await world.persist(_keyA, red: 1);
      world.client.hold();
      world.client.status(201);
      world.start();
      await world.waitFor(() => world.client.seen.length == 1);

      await world.guard.replaceDestinationOrCredential(() async {
        world.credentials.secret = _rotatedSecret;
      });
      await world.settle();

      expect(world.client.seen.map((s) => s.idempotencyKey),
          <String>[_keyA, _keyA]);
      expect(world.client.seen[0].authorization, 'ApiKey $_secret');
      expect(world.client.seen[1].authorization, 'ApiKey $_rotatedSecret');
      expect(world.client.maxInFlight, 1);
      expect(await world.pendingCount(), 0);
      world.expectNoLeak();
    });
  });

  group('task 70.1 local cleanup and queue health', () {
    test(
        'a recorded definitive decision is finished locally without HTTP, '
        'configuration or backoff, then the next item waits for configuration',
        () async {
      await open(withConfiguration: false);
      await world.persist(_keyA, red: 1);
      await world.persist(_keyB, red: 2);
      await world.seedState(_keyA, disposition: 'conflict', attemptCount: 3);

      world.start();
      await world.settle();

      expect(world.client.seen, isEmpty);
      expect(await world.pendingCount(), 1);
      expect(world.jpegCount(), 1);
      expect(await world.stateRow(_keyA), isNull);
      expect(world.seen.map((s) => s.phase), contains(DeliveryPhase.cleaning));
      expect(world.delivery.presentation.phase,
          DeliveryPhase.configurationRequired);
      expect((await world.queue.readAcceptedAnchor())!.queueSequence, 2);
      expect(world.logs, isEmpty);
      world.expectNoLeak();
    });

    test('an unavailable queue is reported without touching the transport',
        () async {
      await open();
      await world.persist(_keyA, red: 1);
      await world.queue.close();

      world.start();
      await world.settle();

      expect(world.client.seen, isEmpty);
      expect(world.delivery.presentation.phase, DeliveryPhase.queueUnavailable);
      expect(world.delivery.presentation.canRetry, isFalse);
      world.expectNoLeak();
    });
  });
}

// ---------------------------------------------------------------------------
// World
// ---------------------------------------------------------------------------

/// Real queue v2, snapshot, encoder, transport, coordinator and presentation,
/// with a scripted HTTP client, a manual timer and a controllable clock.
final class _World {
  _World._({
    required this.sandbox,
    required this.databasePath,
    required this.clock,
    required this.fakeTimer,
    required this.timer,
    required this.queue,
    required this.deliveryQueue,
    required this.repository,
    required this.credentials,
    required this.snapshot,
    required this.client,
    required this.transport,
    required this.coordinator,
    required this.delivery,
    required this.guard,
  });

  static Future<_World> open({
    required bool withConfiguration,
    required Duration attemptTimeout,
  }) async {
    final sandbox = await Directory.systemTemp.createTemp('e4_integration_');
    final databasePath =
        '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName';
    final clock = FakeClock(_t0);
    final fakeTimer = FakeDeliveryTimer(clock);
    final timer = _PortTimer(fakeTimer);
    final queue = CoordinatedPersistentOccurrenceQueue(
      imageStore: PrivateDurableImageStore.at(sandbox),
      databaseOpener: () => QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      ),
    );
    await queue.bootstrap();
    final deliveryQueue = PersistentDeliveryQueue(queue, clock: clock);
    final repository = _Repository()
      ..baseUrl = withConfiguration ? _baseUrl : null;
    final credentials = _Credentials()
      ..secret = withConfiguration ? _secret : null;
    final snapshot = ExclusiveDeliveryConfigurationSnapshot(
      configurationRepository: repository,
      credentialReader: credentials,
      buildVariant: ConfigurationBuildVariant.release,
    );
    final client = _ScriptedClient();
    final transport = HttpOccurrenceTransport(
      StreamedHttpClientAdapter(client),
      limits: OccurrenceTransportLimits(attemptTimeout: attemptTimeout),
    );
    final logs = <String>[];
    final coordinator = OccurrenceDeliveryCoordinator(
      queue: deliveryQueue,
      configuration: snapshot,
      transport: transport,
      clock: clock,
      logger: SanitizedDeliveryTechnicalLogger(logs.add),
      timer: timer,
    );
    final delivery = CoordinatorOperationDelivery(coordinator);
    final world = _World._(
      sandbox: sandbox,
      databasePath: databasePath,
      clock: clock,
      fakeTimer: fakeTimer,
      timer: timer,
      queue: queue,
      deliveryQueue: deliveryQueue,
      repository: repository,
      credentials: credentials,
      snapshot: snapshot,
      client: client,
      transport: transport,
      coordinator: coordinator,
      delivery: delivery,
      guard: DeliveryConfigurationChangeService(
        snapshot: snapshot,
        queue: deliveryQueue,
        delivery: coordinator,
      ),
    );
    world.logs = logs;
    delivery.presentations.listen(world.seen.add);
    return world;
  }

  final Directory sandbox;
  final String databasePath;
  final FakeClock clock;
  final FakeDeliveryTimer fakeTimer;
  final _PortTimer timer;
  final CoordinatedPersistentOccurrenceQueue queue;
  final PersistentDeliveryQueue deliveryQueue;
  final _Repository repository;
  final _Credentials credentials;
  final ExclusiveDeliveryConfigurationSnapshot snapshot;
  final _ScriptedClient client;
  final HttpOccurrenceTransport transport;
  final OccurrenceDeliveryCoordinator coordinator;
  final CoordinatorOperationDelivery delivery;
  final DeliveryConfigurationChangeService guard;

  late final List<String> logs;
  final List<DeliveryPresentationState> seen = <DeliveryPresentationState>[];
  final Map<String, List<int>> _jpegs = <String, List<int>>{};

  void start() {
    delivery.start();
  }

  List<int> jpeg(String key) => _jpegs[key]!;

  Future<void> persist(String key, {required int red}) async {
    final bytes = _jpegBytes(red: red);
    _jpegs[key] = bytes;
    await queue.persist(
      const InMemoryOccurrenceFactory().createManual(
        idempotencyKey: key,
        detectedAt: DateTime.utc(2025, 1, 2, 3, 4, red),
        location: ImmutableLocationSnapshot(
          point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
          accuracyMeters: null,
          speedMetersPerSecond: null,
        ),
        image: _Lease(bytes, 8, 8),
      ),
    );
  }

  Future<int> pendingCount() async => (await queue.listPending()).length;

  /// Number of private JPEG files still stored.
  int jpegCount() => sandbox
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => RegExp(r'e2i_[0-9a-f]{32}\.jpg$').hasMatch(file.path))
      .length;

  Future<QueueDatabase> _openExtra() => QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );

  Future<Map<String, Object?>?> stateRow(String key) async {
    final extra = await _openExtra();
    try {
      final rows = await extra.database.query(
        e4DeliveryStateTable,
        where: 'idempotency_key = ?',
        whereArgs: <Object>[key],
      );
      return rows.isEmpty ? null : rows.single;
    } finally {
      await extra.close();
    }
  }

  Future<void> seedState(
    String key, {
    required String disposition,
    int attemptCount = 0,
  }) async {
    final extra = await _openExtra();
    try {
      await extra.database.insert(e4DeliveryStateTable, <String, Object?>{
        'idempotency_key': key,
        'attempt_count': attemptCount,
        'pending_local_disposition': disposition,
        'cleanup_attempt_count': 0,
      });
    } finally {
      await extra.close();
    }
  }

  /// Waits until the coordinator is idle for a few consecutive polls.
  Future<void> settle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var quiet = 0;
    while (quiet < 3) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      if (coordinator.isEvaluating) {
        quiet = 0;
      } else {
        quiet++;
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('the delivery did not settle in time');
      }
    }
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not reached in time');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Logs and every rendered presentation text carry only closed vocabulary.
  void expectNoLeak() {
    final line = RegExp(r'^E4_DELIVERY_[A-Z_]+( [a-z]+=[A-Za-z0-9]+)?$');
    for (final entry in logs) {
      expect(entry, matches(line));
    }
    final rendered = <String>[
      ...logs,
      for (final state in <DeliveryPresentationState>[
        ...seen,
        delivery.presentation,
      ]) ...<String>[state.message, state.statusLabel, '$state'],
    ].join('\n');
    for (final forbidden in <String>[
      _secret,
      _rotatedSecret,
      'delivery.example.invalid',
      'https://',
      'ApiKey',
      'Authorization',
      _keyA,
      _keyB,
      _keyC,
      _keyD,
      '-23.55',
      '-46.63',
      '2025-01-02',
      '.jpg',
      'e2i_',
    ]) {
      expect(rendered, isNot(contains(forbidden)), reason: forbidden);
    }
  }

  Future<void> dispose() async {
    await coordinator.dispose();
    await delivery.dispose();
    await transport.dispose();
    await queue.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

final class _PortTimerHandle implements DeliveryTimerHandle {
  _PortTimerHandle(this._handle);

  final FakeTimerHandle _handle;

  @override
  bool get isActive => _handle.isActive;

  @override
  void cancel() => _handle.cancel();
}

/// Exposes the manual E4 test timer through the production port.
final class _PortTimer implements DeliveryTimerPort {
  _PortTimer(this._timer);

  final FakeDeliveryTimer _timer;

  @override
  DeliveryTimerHandle arm(DateTime dueAt, void Function() onDue) =>
      _PortTimerHandle(_timer.arm(dueAt, onDue));

  void advance(Duration duration) => _timer.advance(duration);
}

final class _Repository implements OperationalConfigurationRepository {
  Uri? baseUrl;

  @override
  Future<OperationalConfiguration> load() async => OperationalConfiguration(
        baseUrl: baseUrl,
        cooldown: OperationalConfiguration.defaultCooldown,
        minimumDistanceMeters:
            OperationalConfiguration.defaultMinimumDistanceMeters,
        confidenceThreshold:
            OperationalConfiguration.defaultConfidenceThreshold,
        maximumInferenceFps:
            OperationalConfiguration.defaultMaximumInferenceFps,
      );

  @override
  Future<void> save(OperationalConfiguration configuration) async {
    baseUrl = configuration.baseUrl;
  }
}

final class _Credentials implements DeviceCredentialReadPort {
  String? secret;
  CredentialReadResult? result;

  @override
  Future<CredentialReadResult> readForDelivery() async {
    final forced = result;
    if (forced != null) {
      return forced;
    }
    final stored = secret;
    return stored == null
        ? const CredentialMissing()
        : CredentialAvailable(NonPrintableSecret(stored));
  }
}

/// One request as the server would see it.
final class _SeenRequest {
  _SeenRequest(http.BaseRequest request, List<int> body)
      : method = request.method,
        url = request.url.toString(),
        authorization = request.headers['Authorization'],
        contentLength = request.contentLength,
        followRedirects = request.followRedirects,
        bodyBytes = body.length,
        _wire = latin1.decode(body);

  final String method;
  final String url;
  final String? authorization;
  final int? contentLength;
  final bool followRedirects;
  final int bodyBytes;
  final String _wire;

  /// Names of the multipart form fields, in order.
  List<String> get fields => RegExp(
        r'Content-Disposition: form-data; name="(\w+)"',
      ).allMatches(_wire).map((match) => match.group(1)!).toList();

  String get idempotencyKey => RegExp(
        r'name="idempotencyKey"\r\n\r\n([^\r]+)\r\n',
      ).firstMatch(_wire)!.group(1)!;

  bool containsImage(List<int> jpeg) => _wire.contains(latin1.decode(jpeg));
}

typedef _Step = Future<int> Function(Future<void> aborted);

/// Drains each request like a real client, records it, then follows the next
/// scripted step. An unscripted request fails loudly and is counted.
final class _ScriptedClient extends http.BaseClient {
  final Queue<_Step> _script = Queue<_Step>();
  final List<_SeenRequest> seen = <_SeenRequest>[];
  int inFlight = 0;
  int maxInFlight = 0;
  int unscripted = 0;

  void status(int code) => _script.add((_) async => code);

  void network() =>
      _script.add((_) async => throw const SocketException('unreachable'));

  /// Never answers; ends only when the attempt is aborted.
  void never() => _script.add((aborted) async {
        await aborted;
        throw http.RequestAbortedException();
      });

  /// Holds the request until the returned completer is completed or the
  /// attempt is aborted.
  Completer<int> hold() {
    final gate = Completer<int>();
    _script.add((aborted) async {
      final abort = aborted.then<int>((_) => -1);
      final code = await Future.any<int>(<Future<int>>[gate.future, abort]);
      if (code == -1) {
        throw http.RequestAbortedException();
      }
      return code;
    });
    return gate;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    inFlight++;
    if (inFlight > maxInFlight) {
      maxInFlight = inFlight;
    }
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in request.finalize()) {
        builder.add(chunk);
      }
      seen.add(_SeenRequest(request, builder.takeBytes()));
      if (_script.isEmpty) {
        unscripted++;
        throw StateError('no scripted response');
      }
      final abortTrigger =
          request is http.Abortable ? request.abortTrigger : null;
      final code =
          await _script.removeFirst()(abortTrigger ?? Completer<void>().future);
      return http.StreamedResponse(const Stream<List<int>>.empty(), code);
    } finally {
      inFlight--;
    }
  }
}

// ---------------------------------------------------------------------------
// Occurrence fixtures
// ---------------------------------------------------------------------------

List<int> _jpegBytes({required int red}) {
  final image = image_codec.Image(width: 8, height: 8);
  image.clear(image_codec.ColorRgb8(red, 32, 16));
  return image_codec.encodeJpg(image, quality: 85);
}

final class _Lease implements PreparedImageLease {
  _Lease(this.bytes, this.width, this.height);

  final List<int> bytes;
  final int width;
  final int height;
  var _hasOwnership = true;

  @override
  bool get hasOwnership => _hasOwnership;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: 'image/jpeg',
        byteLength: bytes.length,
        width: width,
        height: height,
        quality: 85,
      );

  @override
  Stream<List<int>> openRead() => Stream<List<int>>.value(bytes);

  @override
  PreparedImageLease promoteOwnership() => this;

  @override
  Future<void> withdrawOwnership() async {
    _hasOwnership = false;
  }

  @override
  Future<void> dispose() => withdrawOwnership();
}
