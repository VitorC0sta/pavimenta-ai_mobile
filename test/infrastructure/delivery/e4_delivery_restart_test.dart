import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_coordinator.dart'
    show DeliveryManualRetryResult;
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart'
    show DeliveryMutationResult;
import 'package:pavimenta_ai_mobile/domain/cooldown_policy.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_backoff_policy.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_presentation_state.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';

import '../../support/e4/e4_restart_world.dart';

/// Task 70.3: force-stop and reopening with a pending backoff, a persisted
/// pause, a pending local cleanup and an empty queue, plus the persisted
/// reconciliation of a regressed clock and the restored cooldown anchor.
///
/// Every restart discards the whole process (coordinator, timers, caches) and
/// reopens only the SQLite file and the private JPEGs, so everything asserted
/// after a boot was read from disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<E4RestartWorld> startWorld({bool withConfiguration = true}) async {
    final world =
        await E4RestartWorld.create(withConfiguration: withConfiguration);
    await world.boot(start: false);
    return world;
  }

  Future<void> expectClean(E4RestartWorld world) async {
    await world.expectConsistent();
    world.expectNoLeak();
    expect(world.client.unscripted, 0);
  }

  DateTime at(Object? stored) => DateTime.parse(stored! as String);

  // **Validates: Requirements RF-05, RF-08â€“18, RF-21, RF-23.7â€“12, RNF-01â€“07**
  group('task 70.3 backoff across a force-stop', () {
    test(
        'the persisted wait is honoured after the reopening, re-armed at the '
        'same instant, and the attempt counter keeps growing', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client.network();

      world.session.delivery.start();
      await world.settle();
      expect(world.client.keys, <String>[restartKeyA]);
      expect((await world.stateRow(restartKeyA))!['attempt_count'], 1);
      await world.kill();

      // The process stays dead for 2 s of the 5 s wait.
      world.clock.advance(const Duration(seconds: 2));
      await world.boot();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(world.session.phase, DeliveryPhase.waitingBackoff);
      expect(world.session.delivery.presentation.canRetry, isFalse);
      expect(world.fakeTimer.activeCount, 1);
      expect(world.fakeTimer.active.single.dueAt,
          restartT0.add(const Duration(seconds: 5)));
      expect(world.session.logs, isEmpty);

      // Nothing shortens it, and the later item never overtakes the head.
      world.session.delivery.onQueueChanged();
      world.session.delivery.onAppResumed();
      expect(await world.session.delivery.retryManually(),
          DeliveryManualRetryResult.evaluationRequested);
      await world.settle();
      expect(world.client.keys, <String>[restartKeyA]);
      expect((await world.stateRow(restartKeyA))!['attempt_count'], 1);

      world.client.network();
      world.fakeTimer.advance(const Duration(seconds: 3));
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyA]);
      var row = (await world.stateRow(restartKeyA))!;
      expect(row['attempt_count'], 2);
      expect(at(row['next_attempt_at']),
          restartT0.add(const Duration(seconds: 20)));
      await world.kill();

      // Long after the instant: the first evaluation sends at once and leaves
      // no timer behind.
      world.clock.set(restartT0.add(const Duration(minutes: 5)));
      world.client
        ..status(201)
        ..status(201);
      await world.boot();
      await world.settle();

      expect(world.client.keys,
          <String>[restartKeyA, restartKeyA, restartKeyA, restartKeyB]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.fakeTimer.activeCount, 0);
      expect(world.session.phase, DeliveryPhase.idle);
      row = await world.stateRow(restartKeyA) ?? <String, Object?>{};
      expect(row, isEmpty);
      await expectClean(world);
    });

    test('a recoverable failure never loses the JPEG across restarts',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(503);
      world.session.delivery.start();
      await world.settle();
      await world.kill();

      world.client.status(503);
      world.clock.advance(const Duration(seconds: 5));
      await world.boot();
      await world.settle();
      await world.kill();

      world.client.status(201);
      world.clock.advance(const Duration(minutes: 1));
      await world.boot();
      await world.settle();

      expect(
          world.client.keys, <String>[restartKeyA, restartKeyA, restartKeyA]);
      for (final request in world.client.seen) {
        expect(request.containsImage(world.jpeg(restartKeyA)), isTrue);
      }
      expect(await world.pendingKeys(), isEmpty);
      await expectClean(world);
    });
  });

  group('task 70.3 pause across a force-stop', () {
    const cases = <(int, String, DeliveryPhase, int?)>[
      (401, 'authentication', DeliveryPhase.pausedAuthentication, null),
      (403, 'access', DeliveryPhase.pausedAccess, null),
      (404, 'unexpectedResponse', DeliveryPhase.pausedUnexpected, 404),
      (302, 'unexpectedResponse', DeliveryPhase.pausedUnexpected, 302),
    ];
    for (final (status, reason, phase, unexpected) in cases) {
      test(
          'HTTP $status stays paused after the reopening, sends nothing by '
          'itself and resumes only on the manual retry', () async {
        final world = await startWorld();
        await world.persist(restartKeyA, red: 1);
        await world.persist(restartKeyB, red: 2);
        world.client.status(status);

        world.session.delivery.start();
        await world.settle();
        await world.kill();

        final control = (await world.controlRow())!;
        expect(control['pause_reason'], reason);
        expect(control['unexpected_status'], unexpected);
        final state = await world.stateRow(restartKeyA);
        expect(state == null || state['attempt_count'] == 0, isTrue,
            reason: 'a pause does not count as a failed attempt');

        world.clock.advance(const Duration(hours: 1));
        await world.boot();
        await world.settle();

        expect(world.client.keys, <String>[restartKeyA]);
        expect(world.session.phase, phase);
        expect(world.session.delivery.presentation.canRetry, isTrue);
        expect(world.fakeTimer.activeCount, 0);
        expect(world.session.logs, isEmpty,
            reason: 'the restart must not log the old response again');

        for (var i = 0; i < 3; i++) {
          world.session.delivery.onQueueChanged();
          world.session.delivery.onAppResumed();
        }
        await world.settle();
        expect(world.client.keys, <String>[restartKeyA]);
        expect(world.session.phase, phase);

        world.client
          ..status(201)
          ..status(201);
        expect(await world.session.delivery.retryManually(),
            DeliveryManualRetryResult.resumed);
        await world.settle();

        expect(
            world.client.keys, <String>[restartKeyA, restartKeyA, restartKeyB]);
        expect((await world.controlRow())!['pause_reason'], 'none');
        expect(await world.pendingKeys(), isEmpty);
        await expectClean(world);
      });
    }

    test(
        'a credential corrected after the reopening clears the pause and the '
        'retry uses only the new one', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(401);
      world.session.delivery.start();
      await world.settle();
      await world.kill();

      await world.boot();
      await world.settle();
      expect(world.session.phase, DeliveryPhase.pausedAuthentication);
      expect(world.client.keys, <String>[restartKeyA]);

      world.client.status(201);
      await world.session.guard.replaceDestinationOrCredential(() async {
        world.credentials.secret = restartRotatedSecret;
      });
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyA]);
      expect(world.client.seen.first.authorization, 'ApiKey $restartSecret');
      expect(
          world.client.seen.last.authorization, 'ApiKey $restartRotatedSecret');
      expect(await world.pendingKeys(), isEmpty);
      await expectClean(world);
    });

    test('a local-failure pause is cleared only by the manual retry', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      // The JPEG disappears behind the app's back: a controlled local stop.
      for (final name in world.canonicalImages()) {
        final file = world.sandbox
            .listSync(recursive: true)
            .firstWhere((entity) => entity.uri.pathSegments.last == name);
        await file.delete();
      }
      world.session.delivery.start();
      await world.settle();
      expect(world.session.phase, DeliveryPhase.pausedLocalFailure);
      expect(world.client.seen, isEmpty);
      await world.kill();

      await world.boot();
      await world.settle();

      expect((await world.controlRow())!['pause_reason'], 'localFailure');
      expect(world.session.phase, DeliveryPhase.pausedLocalFailure);
      expect(world.client.seen, isEmpty);
      expect(await world.pendingKeys(), <String>[restartKeyA]);
      world.expectNoLeak();
    });
  });

  group('task 70.3 pending local cleanup across a force-stop', () {
    test(
        'the cleanup schedule survives: nothing is removed or sent before the '
        'instant, and the next failure continues the progression', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client.status(409);
      world.session.faults
          .plan('markForDeletion', Moment.before, Fault.failure);

      world.session.delivery.start();
      await world.settle();
      expect((await world.stateRow(restartKeyA))!['cleanup_attempt_count'], 1);
      await world.kill();

      // Without destination or credential: the cleanup is still local only.
      world.repository.baseUrl = null;
      world.credentials.secret = null;
      world.clock.advance(const Duration(seconds: 2));
      await world.boot();
      await world.settle();

      expect(world.session.phase, DeliveryPhase.cleaning);
      expect(world.fakeTimer.activeCount, 1);
      expect(world.fakeTimer.active.single.dueAt,
          restartT0.add(const Duration(seconds: 5)));
      expect(await world.pendingKeys(), <String>[restartKeyA, restartKeyB]);
      expect(world.client.keys, <String>[restartKeyA]);
      expect(world.session.faults.calls, isNot(contains('openImage')));
      expect(world.canonicalImages(), hasLength(2));

      // The due cleanup fails once more: the next delay is 15 s.
      world.session.faults
          .plan('markForDeletion', Moment.before, Fault.failure);
      world.fakeTimer.advance(const Duration(seconds: 3));
      await world.settle();
      var row = (await world.stateRow(restartKeyA))!;
      expect(row['cleanup_attempt_count'], 2);
      expect(at(row['next_cleanup_at']),
          restartT0.add(const Duration(seconds: 20)));
      expect(world.session.logs, <String>['E4_DELIVERY_CLEANUP_FAILURE']);
      await world.kill();

      world.clock.set(restartT0.add(const Duration(minutes: 1)));
      await world.boot();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA],
          reason: 'configuration is still missing, so B waits');
      expect(await world.pendingKeys(), <String>[restartKeyB]);
      expect(world.canonicalImages(), hasLength(1));
      expect(world.session.phase, DeliveryPhase.configurationRequired);
      row = await world.stateRow(restartKeyA) ?? <String, Object?>{};
      expect(row, isEmpty);

      world.client.status(201);
      world.repository.baseUrl = restartBaseUrl;
      world.credentials.secret = restartSecret;
      await world.session.guard.replaceDestinationOrCredential(() async {});
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
      expect(await world.pendingKeys(), isEmpty);
      await expectClean(world);
    });

    test(
        'a decided item is finished after the reopening even while delivery '
        'is paused, and the pause keeps holding the next item', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client.status(201);
      world.session.faults
          .plan('completePendingLocalRemoval', Moment.before, Fault.crash);
      world.session.delivery.start();
      await world.waitForCrash();
      await world.kill();

      await world.boot(start: false);
      expect(
        await world.session.rawDeliveryQueue
            .pause(PausedDeliveryDecision(DeliveryPauseReason.access)),
        DeliveryMutationResult.applied,
      );
      world.session.delivery.start();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), <String>[restartKeyB]);
      expect(await world.stateRow(restartKeyA), isNull);
      expect(world.canonicalImages(), hasLength(1));
      expect(world.session.phase, DeliveryPhase.pausedAccess);
      expect((await world.controlRow())!['pause_reason'], 'access');
      await expectClean(world);
    });
  });

  group('task 70.3 empty queue across a force-stop', () {
    test(
        'an emptied queue reopens idle without HTTP, timer or configuration '
        'read, and a new item is delivered afterwards', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client
        ..status(201)
        ..status(409);
      world.session.delivery.start();
      await world.settle();
      expect(await world.pendingKeys(), isEmpty);
      await world.kill();

      world.clock.advance(const Duration(hours: 3));
      await world.boot();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
      expect(world.session.phase, DeliveryPhase.idle);
      expect(world.session.delivery.presentation.canRetry, isFalse);
      expect(world.fakeTimer.activeCount, 0);
      expect(world.session.faults.calls, <String>['nextHead']);
      expect(world.canonicalImages(), isEmpty);
      expect(world.session.logs, isEmpty);

      await world.persist(restartKeyC, red: 3);
      world.client.status(201);
      world.session.delivery.onQueueChanged();
      await world.settle();

      expect(
          world.client.keys, <String>[restartKeyA, restartKeyB, restartKeyC]);
      expect(await world.pendingKeys(), isEmpty);
      await expectClean(world);
    });
  });

  group('task 70.3 regressed clock reconciled and persisted', () {
    test(
        'a backoff recorded before the regression is re-anchored once, '
        'persisted, and not postponed again by the next reopening', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.network();
      world.session.delivery.start();
      await world.settle();
      expect(at((await world.stateRow(restartKeyA))!['next_attempt_at']),
          restartT0.add(const Duration(seconds: 5)));
      await world.kill();

      final regressed = restartT0.subtract(const Duration(hours: 1));
      world.clock.set(regressed);
      await world.boot();
      await world.settle();

      var row = (await world.stateRow(restartKeyA))!;
      expect(at(row['backoff_calculated_at']), regressed);
      expect(at(row['next_attempt_at']),
          regressed.add(const Duration(seconds: 5)));
      expect(row['attempt_count'], 1);
      expect(world.session.phase, DeliveryPhase.waitingBackoff);
      expect(world.fakeTimer.active.single.dueAt,
          regressed.add(const Duration(seconds: 5)));
      expect(world.client.keys, <String>[restartKeyA]);
      await world.kill();

      world.clock.set(regressed.add(const Duration(seconds: 2)));
      await world.boot();
      await world.settle();

      // The persisted values are the reconciled ones: nothing moved again.
      expect(await world.stateRow(restartKeyA), row);
      expect(world.fakeTimer.active.single.dueAt,
          regressed.add(const Duration(seconds: 5)));
      expect(world.client.keys, <String>[restartKeyA]);

      world.client.status(201);
      world.fakeTimer.advance(const Duration(seconds: 3));
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyA]);
      expect(await world.pendingKeys(), isEmpty);
      row = await world.stateRow(restartKeyA) ?? <String, Object?>{};
      expect(row, isEmpty);
      await expectClean(world);
    });

    test(
        'an implausibly distant stored backoff is capped at the ceiling and '
        'persisted', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.network();
      world.session.delivery.start();
      await world.settle();
      await world.kill();
      await world.execute(
        "UPDATE occurrence_delivery_state SET next_attempt_at = "
        "'2100-01-01T00:00:00.000Z'",
      );

      await world.boot();
      await world.settle();

      final row = (await world.stateRow(restartKeyA))!;
      expect(at(row['next_attempt_at']),
          restartT0.add(DeliveryBackoffPolicy.maxDelay));
      expect(at(row['backoff_calculated_at']), restartT0);
      expect(world.fakeTimer.active.single.dueAt,
          restartT0.add(DeliveryBackoffPolicy.maxDelay));
      expect(world.client.keys, <String>[restartKeyA]);
      world.expectNoLeak();
    });

    test(
        'a cleanup deadline left beyond the ceiling by a regressed clock is '
        're-anchored, persisted, and the removal still never uses HTTP',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(409);
      world.session.faults
          .plan('markForDeletion', Moment.before, Fault.failure);
      world.session.delivery.start();
      await world.settle();
      expect(at((await world.stateRow(restartKeyA))!['next_cleanup_at']),
          restartT0.add(const Duration(seconds: 5)));
      await world.kill();

      final regressed = restartT0.subtract(const Duration(hours: 2));
      world.clock.set(regressed);
      await world.boot();
      await world.settle();

      var row = (await world.stateRow(restartKeyA))!;
      expect(row['cleanup_attempt_count'], 1);
      expect(row['pending_local_disposition'], 'conflict');
      expect(at(row['next_cleanup_at']),
          regressed.add(const Duration(seconds: 5)));
      expect(world.session.phase, DeliveryPhase.cleaning);
      expect(world.fakeTimer.active.single.dueAt,
          regressed.add(const Duration(seconds: 5)));
      await world.kill();

      world.clock.set(regressed.add(const Duration(seconds: 1)));
      await world.boot();
      await world.settle();
      expect(await world.stateRow(restartKeyA), row,
          reason: 'the reopening must not postpone the cleanup again');

      world.fakeTimer.advance(const Duration(seconds: 4));
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.canonicalImages(), isEmpty);
      row = await world.stateRow(restartKeyA) ?? <String, Object?>{};
      expect(row, isEmpty);
      await expectClean(world);
    });
  });

  group('task 70.3 cooldown anchor across a force-stop', () {
    final firstAt = DateTime.utc(2026, 2, 28, 10);
    final secondAt = firstAt.add(const Duration(seconds: 10));
    const secondLatitude = -23.5600;
    const secondLongitude = -46.6400;

    CooldownPolicy restored(AcceptedOccurrenceAnchor anchor) =>
        CooldownPolicy()..restoreAcceptedAnchor(anchor);

    test(
        'the anchor outlives the delivery of every item, a reopening and a '
        'regressed clock, and keeps the cooldown rule', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1, detectedAt: firstAt);
      await world.persist(
        restartKeyB,
        red: 2,
        detectedAt: secondAt,
        latitude: secondLatitude,
        longitude: secondLongitude,
      );
      world.client
        ..status(201)
        ..status(201);
      world.session.delivery.start();
      await world.settle();
      expect(await world.pendingKeys(), isEmpty);
      await world.kill();

      world.clock.set(restartT0.subtract(const Duration(hours: 3)));
      await world.boot();
      await world.settle();

      final anchor = (await world.session.queue.readAcceptedAnchor())!;
      expect(anchor.queueSequence, 2);
      expect(DateTime.parse(anchor.detectedAtIso8601), secondAt);
      expect(anchor.latitude, secondLatitude);
      expect(anchor.longitude, secondLongitude);
      expect(await world.pendingKeys(), isEmpty);

      final cooldown = restored(anchor);
      final here = ImmutableGeoPoint(
        latitude: secondLatitude,
        longitude: secondLongitude,
      );
      final far = ImmutableGeoPoint(
        latitude: secondLatitude - 0.01,
        longitude: secondLongitude,
      );
      expect(
          cooldown
              .evaluate(secondAt.add(const Duration(seconds: 1)), here)
              .isBlocked,
          isTrue);
      expect(
          cooldown
              .evaluate(secondAt.add(const Duration(seconds: 5)), here)
              .isAllowed,
          isTrue);
      expect(
          cooldown
              .evaluate(secondAt.add(const Duration(seconds: 1)), far)
              .isAllowed,
          isTrue);
      // An attempt that appears to precede the anchor (clock regression) is
      // still inside the cooldown, never a free pass.
      expect(
          cooldown
              .evaluate(secondAt.subtract(const Duration(hours: 1)), here)
              .isBlocked,
          isTrue);
      await expectClean(world);
    });

    test(
        'the anchor of the last item survives its removal finished only after '
        'a force-stop', () async {
      final world = await startWorld();
      await world.persist(
        restartKeyA,
        red: 1,
        detectedAt: firstAt,
        latitude: secondLatitude,
        longitude: secondLongitude,
      );
      world.client.status(201);
      world.session.faults
          .plan('completePendingLocalRemoval', Moment.before, Fault.crash);
      world.session.delivery.start();
      await world.waitForCrash();
      await world.kill();

      final before = (await _readAnchor(world))!;
      expect(await world.pendingKeys(), <String>[restartKeyA]);

      await world.boot();
      await world.settle();

      final after = (await world.session.queue.readAcceptedAnchor())!;
      expect(await world.pendingKeys(), isEmpty);
      expect(after.queueSequence, before.queueSequence);
      expect(after.detectedAtIso8601, before.detectedAtIso8601);
      expect(after.latitude, secondLatitude);
      expect(after.longitude, secondLongitude);
      expect(
        restored(after)
            .evaluate(
              firstAt.add(const Duration(seconds: 1)),
              ImmutableGeoPoint(
                latitude: secondLatitude,
                longitude: secondLongitude,
              ),
            )
            .isBlocked,
        isTrue,
      );
      await expectClean(world);
    });
  });
}

/// Reads the anchor straight from the reopened queue, without delivery.
Future<AcceptedOccurrenceAnchor?> _readAnchor(
  E4RestartWorld world,
) async {
  await world.boot(start: false);
  final anchor = await world.session.queue.readAcceptedAnchor();
  await world.kill();
  return anchor;
}
