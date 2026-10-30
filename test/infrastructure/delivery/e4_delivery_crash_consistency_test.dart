import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_presentation_state.dart';

import '../../support/e4/e4_restart_world.dart';

/// Task 70.2: crashes and failures injected before and after the HTTP status,
/// around the durable decision, inside the removal protocol (JPEG move, SQLite
/// transaction, marker cleanup) and after it. Every scenario ends by proving
/// that no occurrence was lost, that nothing was resent after the decision was
/// durable, and that no orphan JPEG, marker or state row was left.
///
/// A "crash" is a force-stop at one exact protocol step: from that step on
/// nothing is persisted or logged, the files stay as they are and a new
/// process reopens them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const decisions = <(int, String)>[
    (200, 'alreadyExisting'),
    (201, 'created'),
    (400, 'invalidContract'),
    (409, 'conflict'),
    (413, 'imageTooLarge'),
    (415, 'unsupportedFormat'),
  ];

  List<String> rejectionLogs(String disposition) =>
      const <String>{'alreadyExisting', 'created'}.contains(disposition)
          ? const <String>[]
          : <String>[
              'E4_DELIVERY_DEFINITIVE_REJECTION disposition=$disposition'
            ];

  Future<E4RestartWorld> startWorld({bool withConfiguration = true}) async {
    final world =
        await E4RestartWorld.create(withConfiguration: withConfiguration);
    await world.boot(start: false);
    return world;
  }

  /// No lost data, no orphan state and no sensitive output.
  Future<void> expectClean(E4RestartWorld world) async {
    await world.expectConsistent();
    world.expectNoLeak();
    expect(world.client.unscripted, 0);
  }

  // **Validates: Requirements RF-05, RF-08–18, RF-21, RF-23.7–12, RNF-01–07**
  group('task 70.2 crash around the HTTP status', () {
    test(
        'a crash with the request in flight loses nothing and the restart '
        'resends the same key and the same image', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.scriptCrashInFlight();

      world.session.delivery.start();
      await world.waitForCrash();
      await world.kill();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), <String>[restartKeyA, restartKeyB]);
      expect(await world.stateRow(restartKeyA), isNull);
      expect(await world.controlRow(), isNull);
      expect(world.allLogs, isEmpty);
      await expectClean(world);

      world.client
        ..status(201)
        ..status(201);
      await world.boot();
      await world.settle();

      expect(
          world.client.keys, <String>[restartKeyA, restartKeyA, restartKeyB]);
      expect(
          world.client.seen[1].containsImage(world.jpeg(restartKeyA)), isTrue);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.canonicalImages(), isEmpty);
      expect(world.session.phase, DeliveryPhase.idle);
      await expectClean(world);
    });

    for (final (status, disposition) in decisions) {
      test(
          'HTTP $status received but the process dies before the decision is '
          'durable: the item stays and the restart resends the same key',
          () async {
        final world = await startWorld();
        await world.persist(restartKeyA, red: 1);
        world.client.status(status);
        world.session.faults
            .plan('recordDefinitiveDecision', Moment.before, Fault.crash);

        world.session.delivery.start();
        await world.waitForCrash();
        await world.kill();

        // The status was never recorded: there is no decision to honour.
        expect(world.client.keys, <String>[restartKeyA]);
        expect(await world.pendingKeys(), <String>[restartKeyA]);
        expect(await world.stateRow(restartKeyA), isNull);
        expect(world.canonicalImages(), hasLength(1));
        expect(world.allLogs, isEmpty, reason: disposition);

        world.client.status(201);
        await world.boot();
        await world.settle();

        expect(world.client.keys, <String>[restartKeyA, restartKeyA]);
        expect(await world.pendingKeys(), isEmpty);
        await expectClean(world);
      });
    }

    test(
        'a decision that is durable but reported as failed is never resent: '
        'the next evaluation only finishes the local removal', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(409);
      world.session.faults
          .plan('recordDefinitiveDecision', Moment.after, Fault.failure);

      world.session.delivery.start();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), <String>[restartKeyA]);
      expect((await world.stateRow(restartKeyA))!['pending_local_disposition'],
          'conflict');
      expect(world.canonicalImages(), hasLength(1));
      // No busy loop: the failed evaluation did not ask for another one.
      expect(world.client.seen, hasLength(1));

      world.session.delivery.onQueueChanged();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.canonicalImages(), isEmpty);
      await expectClean(world);
    });

    test(
        'a decision that could not be recorded keeps the item and the next '
        'evaluation resends it with the same key', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client
        ..status(409)
        ..status(201);
      world.session.faults
          .plan('recordDefinitiveDecision', Moment.before, Fault.failure);

      world.session.delivery.start();
      await world.settle();

      expect(world.client.seen, hasLength(1));
      expect(await world.pendingKeys(), <String>[restartKeyA]);
      expect(await world.stateRow(restartKeyA), isNull);
      expect(world.canonicalImages(), hasLength(1));

      world.session.delivery.onQueueChanged();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyA]);
      expect(await world.pendingKeys(), isEmpty);
      await expectClean(world);
    });

    test(
        'a crash before the recoverable failure is recorded leaves no backoff '
        'and the restart resends immediately', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(503);
      world.session.faults
          .plan('recordRecoverableFailure', Moment.before, Fault.crash);

      world.session.delivery.start();
      await world.waitForCrash();
      await world.kill();

      expect(await world.stateRow(restartKeyA), isNull);
      // Only the category logged before the process died; no later line.
      expect(world.allLogs, <String>[
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=serverError',
      ]);

      world.client.status(201);
      await world.boot();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyA]);
      expect(await world.pendingKeys(), isEmpty);
      await expectClean(world);
    });

    test(
        'a recoverable failure that could not be recorded keeps the item, '
        'shows no upload in progress and the manual retry resends it',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client
        ..network()
        ..status(201);
      world.session.faults
          .plan('recordRecoverableFailure', Moment.before, Fault.failure);

      world.session.delivery.start();
      await world.settle();

      expect(world.client.seen, hasLength(1));
      expect(await world.pendingKeys(), <String>[restartKeyA]);
      expect(await world.stateRow(restartKeyA), isNull);
      expect(world.session.phase, DeliveryPhase.ready);
      expect(world.session.delivery.presentation.canRetry, isTrue);

      await world.session.delivery.retryManually();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyA]);
      expect(await world.pendingKeys(), isEmpty);
      await expectClean(world);
    });

    test(
        'a pause that could not be persisted keeps the item and the next '
        'evaluation decides again from the server', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client
        ..status(401)
        ..status(401);
      world.session.faults.plan('pause', Moment.before, Fault.failure);

      world.session.delivery.start();
      await world.settle();

      expect(await world.pendingKeys(), <String>[restartKeyA]);
      expect(await world.controlRow(), isNull);
      // Nothing was concluded: the item waits for the next evaluation and the
      // user may ask for it, instead of seeing an upload that is not running.
      expect(world.session.phase, DeliveryPhase.ready);
      expect(world.session.delivery.presentation.canRetry, isTrue);

      world.session.delivery.onQueueChanged();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyA]);
      expect(await world.pendingKeys(), <String>[restartKeyA]);
      expect(await world.controlRow(), isNotNull);
      expect(world.session.phase, DeliveryPhase.pausedAuthentication);
      await expectClean(world);
    });

    test(
        'a crash in the middle of the queue never repeats a delivered item '
        'and keeps FIFO', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      await world.persist(restartKeyC, red: 3);
      world.client.status(201);
      world.scriptCrashInFlight();

      world.session.delivery.start();
      await world.waitForCrash();
      await world.kill();

      expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
      expect(await world.pendingKeys(), <String>[restartKeyB, restartKeyC]);
      expect(world.canonicalImages(), hasLength(2));
      await expectClean(world);

      world.client
        ..status(201)
        ..status(201);
      await world.boot();
      await world.settle();

      expect(world.client.keys, <String>[
        restartKeyA,
        restartKeyB,
        restartKeyB,
        restartKeyC,
      ]);
      expect(await world.pendingKeys(), isEmpty);
      await expectClean(world);
    });
  });

  group('task 70.2 crash after the durable decision', () {
    for (final (status, disposition) in decisions) {
      test(
          'HTTP $status decided, then a crash before the removal: the restart '
          'removes it without HTTP, configuration or resend', () async {
        final world = await startWorld();
        await world.persist(restartKeyA, red: 1);
        await world.persist(restartKeyB, red: 2);
        world.client.status(status);
        world.session.faults
            .plan('completePendingLocalRemoval', Moment.before, Fault.crash);

        world.session.delivery.start();
        await world.waitForCrash();
        await world.kill();

        expect(world.client.keys, <String>[restartKeyA]);
        expect(await world.pendingKeys(), <String>[restartKeyA, restartKeyB]);
        final row = (await world.stateRow(restartKeyA))!;
        expect(row['pending_local_disposition'], disposition);
        expect(row['next_attempt_at'], isNull);
        expect(world.canonicalImages(), hasLength(2));
        expect(world.allLogs, rejectionLogs(disposition));

        // The destination and the credential are gone and nothing is scripted:
        // any request would be counted as unscripted.
        world.repository.baseUrl = null;
        world.credentials.secret = null;
        await world.boot();
        await world.settle();

        expect(world.client.keys, <String>[restartKeyA]);
        expect(world.client.unscripted, 0);
        expect(await world.pendingKeys(), <String>[restartKeyB]);
        expect(await world.stateRow(restartKeyA), isNull);
        expect(world.canonicalImages(), hasLength(1));
        expect(world.session.phase, DeliveryPhase.configurationRequired);
        expect(world.allLogs, rejectionLogs(disposition),
            reason: 'the restart must not log the decision again');

        // The next item follows once the configuration returns.
        world.client.status(201);
        world.repository.baseUrl = restartBaseUrl;
        world.credentials.secret = restartSecret;
        await world.session.guard.replaceDestinationOrCredential(() async {});
        await world.settle();

        expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
        expect(await world.pendingKeys(), isEmpty);
        await expectClean(world);
      });
    }

    test(
        'a crash right after the removal committed, before the coordinator '
        'learns it: the restart finds nothing to resend', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client.status(201);
      world.session.faults
          .plan('completePendingLocalRemoval', Moment.after, Fault.crash);

      world.session.delivery.start();
      await world.waitForCrash();
      await world.kill();

      expect(await world.pendingKeys(), <String>[restartKeyB]);
      expect(await world.stateRow(restartKeyA), isNull);
      expect(world.canonicalImages(), hasLength(1));
      await expectClean(world);

      world.client.status(201);
      await world.boot();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.canonicalImages(), isEmpty);
      await expectClean(world);
    });

    test(
        'a crash after the commit but before the marker is retired leaves '
        'only a recognized marker, which the restart retires', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(201);
      world.session.faults
          .plan('finalizeAfterCommit', Moment.before, Fault.crash);

      world.session.delivery.start();
      await world.waitForCrash();
      await world.kill();

      expect(await world.pendingKeys(), isEmpty);
      expect(await world.stateRow(restartKeyA), isNull);
      expect(world.canonicalImages(), isEmpty);
      expect(world.deletingMarkers(), hasLength(1));
      expect(await world.orphanStateRows(), 0);

      await world.boot();
      await world.settle();

      expect(world.deletingMarkers(), isEmpty);
      expect(world.client.keys, <String>[restartKeyA]);
      expect(world.session.phase, DeliveryPhase.idle);
      await expectClean(world);
    });

    test(
        'a marker cleanup failure after the commit is not a failed removal: '
        'the count drops, the next item goes on and the restart retires it',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client
        ..status(409)
        ..status(201);
      world.session.faults
          .plan('finalizeAfterCommit', Moment.before, Fault.failure);

      world.session.delivery.start();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.deletingMarkers(), hasLength(1));
      expect(
          world.allLogs,
          <String>[
            'E4_DELIVERY_DEFINITIVE_REJECTION disposition=conflict',
          ],
          reason: 'no cleanup failure is reported for a confirmed removal');
      expect(world.session.phase, DeliveryPhase.idle);
      expect(await world.orphanStateRows(), 0);

      await world.kill();
      await world.boot();
      await world.settle();

      expect(world.deletingMarkers(), isEmpty);
      expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
      await expectClean(world);
    });
  });

  group('task 70.2 failures inside the removal protocol', () {
    test(
        'the JPEG cannot be moved: the decision stays, the cleanup backs off '
        'locally, nothing is resent and the next item is not overtaken',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client
        ..status(409)
        ..status(201);
      world.session.faults
          .plan('markForDeletion', Moment.before, Fault.failure);

      world.session.delivery.start();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), <String>[restartKeyA, restartKeyB]);
      final row = (await world.stateRow(restartKeyA))!;
      expect(row['pending_local_disposition'], 'conflict');
      expect(row['attempt_count'], 0);
      expect(row['cleanup_attempt_count'], 1);
      expect(
        DateTime.parse(row['next_cleanup_at']! as String)
            .isAtSameMomentAs(restartT0.add(const Duration(seconds: 5))),
        isTrue,
      );
      expect(world.canonicalImages(), hasLength(2));
      expect(world.deletingMarkers(), isEmpty);
      expect(world.session.phase, DeliveryPhase.cleaning);
      expect(world.fakeTimer.activeCount, 1);
      expect(world.allLogs, <String>[
        'E4_DELIVERY_DEFINITIVE_REJECTION disposition=conflict',
        'E4_DELIVERY_CLEANUP_FAILURE',
      ]);

      // Neither a notification, a resume nor the manual retry anticipates the
      // scheduled cleanup, and none of them reaches the network.
      world.session.delivery.onQueueChanged();
      world.session.delivery.onAppResumed();
      await world.session.delivery.retryManually();
      await world.settle();
      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), <String>[restartKeyA, restartKeyB]);
      expect((await world.stateRow(restartKeyA))!['cleanup_attempt_count'], 1);

      world.fakeTimer.advance(const Duration(seconds: 5));
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.canonicalImages(), isEmpty);
      await expectClean(world);
    });

    for (final fault in Fault.values) {
      test(
          'the JPEG is moved and then the process ${fault == Fault.crash ? 'dies' : 'fails'} '
          'before the commit: the row is retained and the restart restores the '
          'JPEG and finishes without HTTP', () async {
        final world = await startWorld();
        await world.persist(restartKeyA, red: 1);
        world.client.status(201);
        world.session.faults.plan('markForDeletion', Moment.after, fault);

        world.session.delivery.start();
        if (fault == Fault.crash) {
          await world.waitForCrash();
        } else {
          await world.settle();
        }

        // The decision is durable and the row is retained; the JPEG sits under
        // its recognized marker.
        expect(world.client.keys, <String>[restartKeyA]);
        expect(await world.pendingKeys(), <String>[restartKeyA]);
        expect(
            (await world.stateRow(restartKeyA))!['pending_local_disposition'],
            'created');
        expect(world.canonicalImages(), isEmpty);
        expect(world.deletingMarkers(), hasLength(1));

        await world.kill();
        await world.boot(start: false);

        // The bootstrap restored the canonical JPEG of the retained row.
        expect(world.deletingMarkers(), isEmpty);
        expect(world.canonicalImages(), await world.referencedImages());
        expect(world.canonicalImages(), hasLength(1));
        await world.expectConsistent();

        if (fault == Fault.failure) {
          // The failure scheduled the cleanup; the schedule survived.
          expect(world.session.phase, DeliveryPhase.idle);
          world.session.delivery.start();
          await world.settle();
          expect(await world.pendingKeys(), <String>[restartKeyA]);
          world.fakeTimer.advance(const Duration(seconds: 5));
        } else {
          world.session.delivery.start();
        }
        await world.settle();

        expect(world.client.keys, <String>[restartKeyA]);
        expect(world.client.unscripted, 0);
        expect(await world.pendingKeys(), isEmpty);
        expect(world.canonicalImages(), isEmpty);
        await expectClean(world);
      });
    }

    test(
        'while the JPEG sits under its marker the cleanup keeps backing off '
        'in process, loses nothing, never resends and holds the FIFO until '
        'the restart restores it', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.persist(restartKeyB, red: 2);
      world.client.status(201);
      world.session.faults.plan('markForDeletion', Moment.after, Fault.failure);

      world.session.delivery.start();
      await world.settle();
      expect(world.deletingMarkers(), hasLength(1));

      // The E2 protocol retires nothing and restores nothing before commit:
      // the in-process retries see the canonical JPEG missing and fail again
      // with a growing, bounded and persisted delay.
      world.fakeTimer.advance(const Duration(seconds: 5));
      await world.settle();
      var row = (await world.stateRow(restartKeyA))!;
      expect(row['cleanup_attempt_count'], 2);
      expect(
        DateTime.parse(row['next_cleanup_at']! as String)
            .isAtSameMomentAs(restartT0.add(const Duration(seconds: 20))),
        isTrue,
      );
      expect(row['pending_local_disposition'], 'created');
      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), <String>[restartKeyA, restartKeyB]);
      expect(world.deletingMarkers(), hasLength(1));
      expect(world.fakeTimer.maxConcurrentActive, 1);
      expect(world.allLogs, <String>[
        'E4_DELIVERY_CLEANUP_FAILURE',
        'E4_DELIVERY_CLEANUP_FAILURE',
      ]);

      await world.kill();
      world.client.status(201);
      await world.boot(start: false);
      expect(world.deletingMarkers(), isEmpty);
      world.fakeTimer.advance(const Duration(seconds: 15));
      world.session.delivery.start();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA, restartKeyB]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.canonicalImages(), isEmpty);
      row = (await world.stateRow(restartKeyA)) ?? <String, Object?>{};
      expect(row, isEmpty);
      await expectClean(world);
    });

    test(
        'the SQLite removal transaction rolls back: the row, the decision and '
        'the JPEG marker survive, and the restart finishes the removal',
        () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      await world.execute(
        'CREATE TRIGGER inject_removal_rollback BEFORE DELETE ON '
        'pendingOccurrences BEGIN '
        "SELECT RAISE(ABORT, 'injected_removal_failure'); END",
      );
      world.client.status(400);

      world.session.delivery.start();
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), <String>[restartKeyA]);
      final row = (await world.stateRow(restartKeyA))!;
      expect(row['pending_local_disposition'], 'invalidContract');
      expect(row['cleanup_attempt_count'], 1);
      expect(world.session.phase, DeliveryPhase.cleaning);
      expect(world.allLogs, <String>[
        'E4_DELIVERY_DEFINITIVE_REJECTION disposition=invalidContract',
        'E4_DELIVERY_CLEANUP_FAILURE',
      ]);

      await world.kill();
      await world.execute('DROP TRIGGER inject_removal_rollback');
      await world.boot(start: false);

      // The retained row has its JPEG back and is still decided.
      expect(world.deletingMarkers(), isEmpty);
      expect(world.canonicalImages(), hasLength(1));
      await world.expectConsistent();

      world.session.delivery.start();
      await world.settle();
      world.fakeTimer.advance(const Duration(seconds: 5));
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.canonicalImages(), isEmpty);
      await expectClean(world);
    });

    test(
        'a failing cleanup keeps backing off without ever touching the '
        'network, then succeeds once the failure is gone', () async {
      final world = await startWorld();
      await world.persist(restartKeyA, red: 1);
      world.client.status(409);
      world.session.faults
          .plan('markForDeletion', Moment.before, Fault.failure);

      world.session.delivery.start();
      await world.settle();
      expect((await world.stateRow(restartKeyA))!['cleanup_attempt_count'], 1);

      // Second failure: the delay grows and the schedule is persisted.
      world.session.faults
          .plan('markForDeletion', Moment.before, Fault.failure);
      world.fakeTimer.advance(const Duration(seconds: 5));
      await world.settle();
      var row = (await world.stateRow(restartKeyA))!;
      expect(row['cleanup_attempt_count'], 2);
      expect(
        DateTime.parse(row['next_cleanup_at']! as String)
            .isAtSameMomentAs(restartT0.add(const Duration(seconds: 20))),
        isTrue,
      );
      expect(world.client.keys, <String>[restartKeyA]);
      expect(world.fakeTimer.maxConcurrentActive, 1);

      world.fakeTimer.advance(const Duration(seconds: 15));
      await world.settle();

      expect(world.client.keys, <String>[restartKeyA]);
      expect(await world.pendingKeys(), isEmpty);
      expect(world.canonicalImages(), isEmpty);
      row = (await world.stateRow(restartKeyA)) ?? <String, Object?>{};
      expect(row, isEmpty);
      await expectClean(world);
    });
  });
}
