import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e1_ports.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';

import 'e4_fakes.dart';

void main() {
  final start = DateTime.utc(2025, 1, 1, 12);

  group('FakeClock', () {
    // **Validates: Requirements RNF-07.1**
    test('implements the existing Clock port and moves only on request', () {
      final Clock clock = FakeClock(start);

      expect(clock.now(), start);
      expect(clock.now(), start);

      final fake = clock as FakeClock;
      fake.advance(const Duration(seconds: 5));
      expect(clock.now(), start.add(const Duration(seconds: 5)));

      fake.set(start);
      expect(clock.now(), start);
      expect(
          () => fake.advance(const Duration(seconds: -1)), throwsArgumentError);
    });
  });

  group('FakeDeliveryTimer', () {
    // **Validates: Requirements RNF-07.1, RNF-03.7**
    test('fires only when advanced, in due order, moving the clock', () {
      final clock = FakeClock(start);
      final timer = FakeDeliveryTimer(clock);
      final fired = <String>[];
      final seenAt = <DateTime>[];

      timer.arm(start.add(const Duration(seconds: 15)), () {
        fired.add('late');
        seenAt.add(clock.now());
      });
      timer.arm(start.add(const Duration(seconds: 5)), () {
        fired.add('early');
        seenAt.add(clock.now());
      });

      expect(fired, isEmpty);
      timer.advance(const Duration(seconds: 4));
      expect(fired, isEmpty);

      timer.advance(const Duration(seconds: 20));
      expect(fired, <String>['early', 'late']);
      expect(seenAt, <DateTime>[
        start.add(const Duration(seconds: 5)),
        start.add(const Duration(seconds: 15)),
      ]);
      expect(clock.now(), start.add(const Duration(seconds: 24)));
      expect(timer.firedCount, 2);
      expect(timer.activeCount, 0);
    });

    test('does not fire cancelled timers and tracks concurrency', () {
      final clock = FakeClock(start);
      final timer = FakeDeliveryTimer(clock);
      var fired = 0;

      final handle = timer.arm(start.add(const Duration(seconds: 5)), () {
        fired++;
      });
      expect(timer.maxConcurrentActive, 1);
      timer.cancel(handle);
      expect(handle.isActive, isFalse);
      expect(timer.cancelledCount, 1);

      timer.advance(const Duration(minutes: 1));
      expect(fired, 0);
      expect(timer.fireNext(), isFalse);

      timer.arm(start.add(const Duration(minutes: 5)), () => fired++);
      timer.arm(start.add(const Duration(minutes: 6)), () => fired++);
      expect(timer.maxConcurrentActive, 2);
      expect(timer.fireNext(), isTrue);
      expect(clock.now(), start.add(const Duration(minutes: 5)));
      timer.cancelAll();
      expect(timer.activeCount, 0);
      expect(fired, 1);
    });

    test('honours timers armed by a callback within the advance window', () {
      final clock = FakeClock(start);
      final timer = FakeDeliveryTimer(clock);
      var fired = 0;

      timer.arm(start.add(const Duration(seconds: 1)), () {
        fired++;
        timer.arm(clock.now().add(const Duration(seconds: 1)), () => fired++);
      });

      timer.advance(const Duration(seconds: 10));
      expect(fired, 2);
    });
  });

  group('FakeOccurrenceTransport', () {
    FakeUploadRequest request() => FakeUploadRequest(
          uri: Uri.parse('https://api.example.invalid/x'),
          credential: fakeDeliveryCredential,
          idempotencyKey: 'key-1',
          imageBytes: const <int>[1, 2, 3],
        );

    // **Validates: Requirements RNF-07.1, RF-23.1**
    test('returns scripted results in order without a network', () async {
      final transport = FakeOccurrenceTransport()
        ..respondWith(const FakeHttpResponse(503))
        ..respondWith(const FakeNetworkFailure());

      final first = await transport.send(request());
      final second = await transport.send(request());

      expect((first as FakeHttpResponse).statusCode, 503);
      expect(second, isA<FakeNetworkFailure>());
      expect(transport.sendCount, 2);
      expect(transport.maxConcurrentSends, 1);
      expect(transport.inFlight, 0);
    });

    test('fails loudly when a send has no scripted result', () async {
      final transport = FakeOccurrenceTransport();

      await expectLater(transport.send(request()), throwsStateError);
      expect(transport.sendCount, 1);
      expect(transport.inFlight, 0);
    });

    test('holds a send until completed and cancels it on request', () async {
      final transport = FakeOccurrenceTransport();
      final held = transport.holdNext();
      final first = transport.send(request());
      await Future<void>.delayed(Duration.zero);
      expect(transport.inFlight, 1);

      held.complete(const FakeHttpResponse(201));
      expect((await first as FakeHttpResponse).statusCode, 201);

      transport.holdNext();
      final second = transport.send(request());
      await Future<void>.delayed(Duration.zero);
      await transport.cancelActive();
      expect(await second, isA<FakeTransportCancelled>());
      expect(transport.cancelActiveCount, 1);
      expect(transport.inFlight, 0);
    });

    test('never prints the credential', () {
      final text = request().toString();

      expect(text, isNot(contains(fakeDeliveryCredential)));
      expect(text, isNot(contains('fake-secret')));
    });
  });

  group('FakeDeliveryConfigurationSnapshotPort', () {
    final baseUrl = Uri.parse('https://api.example.invalid');

    // **Validates: Requirements RNF-03.7–10, RNF-01.6**
    test('reports each configuration state without storage access', () async {
      final port = FakeDeliveryConfigurationSnapshotPort();
      expect(await port.readForAttempt(), isA<FakeConfigurationMissing>());

      port.setBaseUrl(baseUrl);
      expect(await port.readForAttempt(), isA<FakeConfigurationMissing>());

      port.setCredential('malformed');
      expect(await port.readForAttempt(), isA<FakeCredentialInvalidFormat>());

      port.setCredential(fakeDeliveryCredential);
      final available = await port.readForAttempt();
      expect(available, isA<FakeConfigurationAvailable>());
      expect(available.toString(), isNot(contains('fake-secret')));

      port.setSecureStorageAvailable(false);
      expect(await port.readForAttempt(), isA<FakeSecureStorageUnavailable>());
      expect(port.readCount, 5);
    });

    test('revisions are monotonic and detect stale snapshots', () async {
      final port = FakeDeliveryConfigurationSnapshotPort(
        baseUrl: baseUrl,
        credential: fakeDeliveryCredential,
      );
      final snapshot =
          await port.readForAttempt() as FakeConfigurationAvailable;

      expect(port.isCurrent(snapshot.revision), isTrue);
      port.setBaseUrl(Uri.parse('https://other.example.invalid'));
      expect(port.isCurrent(snapshot.revision), isFalse);

      final next = await port.readForAttempt() as FakeConfigurationAvailable;
      expect(next.revision, greaterThan(snapshot.revision));
      expect(next.baseUrl.host, 'other.example.invalid');
    });
  });

  group('FakeDeliveryQueue', () {
    // **Validates: Requirements RF-23.1, RNF-07.1, RNF-01.6**
    test('selects the FIFO head and streams the image in chunks', () async {
      final queue = FakeDeliveryQueue(imageChunkSize: 2)
        ..add('a', const <int>[1, 2, 3, 4, 5])
        ..add('b', const <int>[9]);

      final head = await queue.nextHead(start) as FakeHeadEligible;
      expect(head.occurrence.idempotencyKey, 'a');
      expect(head.occurrence.queueSequence, 1);

      final chunks = await queue.openImage('a').toList();
      expect(chunks, <List<int>>[
        <int>[1, 2],
        <int>[3, 4],
        <int>[5],
      ]);
      expect(queue.snapshot.pendingCount, 2);
    });

    test('reports empty, unavailable and missing-image heads', () async {
      final queue = FakeDeliveryQueue();
      expect(await queue.nextHead(start), isA<FakeHeadEmpty>());

      queue.add('a', null);
      expect(await queue.nextHead(start), isA<FakeHeadLocalIntegrityFailure>());
      expect(() => queue.openImage('a'), throwsStateError);

      queue.available = false;
      expect(await queue.nextHead(start), isA<FakeHeadUnavailable>());
    });

    test('backoff holds the head and later items do not overtake it', () async {
      final queue = FakeDeliveryQueue()
        ..add('a', const <int>[1])
        ..add('b', const <int>[2]);
      final retryAt = start.add(const Duration(seconds: 5));

      expect(
        await queue.recordRecoverableFailure('a', start, retryAt),
        FakeMutationResult.applied,
      );

      final waiting = await queue.nextHead(start) as FakeHeadInBackoff;
      expect(waiting.occurrence.idempotencyKey, 'a');
      expect(waiting.occurrence.attemptCount, 1);
      expect(waiting.nextAttemptAt, retryAt);

      final due = await queue.nextHead(retryAt) as FakeHeadEligible;
      expect(due.occurrence.idempotencyKey, 'a');
      expect(
        await queue.recordRecoverableFailure('missing', start, retryAt),
        FakeMutationResult.notFound,
      );
    });

    test('pending cleanup precedes backoff and removal reuses E2 results',
        () async {
      final queue = FakeDeliveryQueue()..add('a', const <int>[1]);
      await queue.recordRecoverableFailure(
        'a',
        start,
        start.add(const Duration(minutes: 1)),
      );
      await queue.recordDefinitiveDecision('a', 'created');

      final immediate = await queue.nextHead(start) as FakeHeadPendingCleanup;
      expect(immediate.dueAt, isNull);

      queue.failNextRemovals = 1;
      expect(
        await queue.completePendingLocalRemoval('a'),
        isA<QueueOccurrenceRemovalFailed>(),
      );
      expect(queue.snapshot.pendingCount, 1);

      final cleanupAt = start.add(const Duration(seconds: 5));
      await queue.recordCleanupFailure('a', start, cleanupAt);
      final waiting = await queue.nextHead(start) as FakeHeadPendingCleanup;
      expect(waiting.dueAt, cleanupAt);
      expect(waiting.occurrence.cleanupAttemptCount, 1);

      final removed = await queue.completePendingLocalRemoval('a');
      expect(removed, isA<QueueOccurrenceRemoved>());
      expect((removed as QueueOccurrenceRemoved).snapshot.pendingCount, 0);
      expect(queue.removedKeys, <String>['a']);
      expect(
        await queue.completePendingLocalRemoval('a'),
        isA<QueueOccurrenceNotFound>(),
      );
      expect(await queue.nextHead(start), isA<FakeHeadEmpty>());
    });

    test('refuses removal without a recorded definitive decision', () async {
      final queue = FakeDeliveryQueue()..add('a', const <int>[1]);

      await expectLater(
          queue.completePendingLocalRemoval('a'), throwsStateError);
      expect(queue.snapshot.pendingCount, 1);
    });

    test('stores pause control and publishes aggregate summaries only',
        () async {
      final queue = FakeDeliveryQueue();
      final summaries = <int>[];
      final subscription =
          queue.watchSummary().listen((s) => summaries.add(s.pendingCount));

      expect(await queue.readControl(), FakePauseReason.none);
      await queue.pause(FakePauseReason.authentication);
      expect(await queue.readControl(), FakePauseReason.authentication);
      await queue.resume();
      expect(await queue.readControl(), FakePauseReason.none);
      await expectLater(queue.pause(FakePauseReason.none), throwsArgumentError);

      queue.add('a', const <int>[1]);
      await queue.recordDefinitiveDecision('a', 'created');
      await queue.completePendingLocalRemoval('a');
      await Future<void>.delayed(Duration.zero);

      expect(summaries, <int>[1, 0]);
      expect(queue.pending, isEmpty);
      await subscription.cancel();
      await queue.close();
    });

    test('rejects duplicate idempotency keys', () {
      final queue = FakeDeliveryQueue()..add('a', const <int>[1]);

      expect(() => queue.add('a', const <int>[2]), throwsStateError);
    });
  });
}
