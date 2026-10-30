/// Restartable E4 delivery world for the crash and force-stop tests
/// (tasks 70.2 and 70.3).
///
/// One [E4RestartWorld] owns what survives a process death: the sandbox with
/// the SQLite file and the private JPEGs, the persisted configuration, the
/// secure storage, the clock and the scripted server. One [E4Session] is one
/// process lifetime: real queue v2, snapshot, transport, coordinator and
/// presentation, with a fault layer in front of the queue port and the image
/// store. [E4RestartWorld.kill] ends a session like a force-stop (nothing more
/// is persisted, timers are dropped) and [E4RestartWorld.boot] reopens the same
/// files in a new session.
///
/// Every value here is explicitly fictitious.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_change_service.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_timer_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/device_credential_read_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/exclusive_delivery_configuration_snapshot.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_coordinator.dart'
    show OccurrenceDeliveryCoordinator;
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/operation_delivery_port.dart';
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_presentation_state.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/http_occurrence_transport.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_transport_limits.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/persistent_delivery_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streamed_http_client_adapter.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_delivery_schema.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_record_mapper.dart';
import 'package:pavimenta_ai_mobile/infrastructure/sanitized_delivery_technical_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_clock.dart';
import 'fake_delivery_configuration_snapshot.dart';
import 'fake_delivery_timer.dart';

final Uri restartBaseUrl = Uri.parse('https://delivery.example.invalid');
const String restartSecret = fakeDeliveryCredential;
const String restartRotatedSecret = 'newprefix.new-secret-for-tests-only';
const String restartKeyA = '123e4567-e89b-42d3-a456-426614174000';
const String restartKeyB = '223e4567-e89b-42d3-a456-426614174000';
const String restartKeyC = '323e4567-e89b-42d3-a456-426614174000';

/// First instant of every restart scenario.
final DateTime restartT0 = DateTime.utc(2026, 3, 1, 12);

/// Moment of an injected fault relative to the faulted operation.
enum Moment { before, after }

/// Kind of injected fault.
enum Fault {
  /// The process dies at that point: nothing else is persisted or logged.
  crash,

  /// The operation fails (before: not executed; after: executed but reported
  /// as failed).
  failure,
}

/// The simulated process died; thrown only inside the fault layer.
final class SimulatedCrash implements Exception {
  const SimulatedCrash();

  @override
  String toString() => 'SimulatedCrash';
}

/// Planned faults and the liveness of one session.
final class E4Faults {
  final Map<(String, Moment), Fault> _planned = <(String, Moment), Fault>{};

  /// Operations reached through the queue port, in order.
  final List<String> calls = <String>[];

  /// Once true, every port operation throws and nothing is persisted or
  /// logged any more.
  bool dead = false;

  /// Plans one fault for the next [operation] call at [moment].
  void plan(String operation, Moment moment, Fault fault) {
    _planned[(operation, moment)] = fault;
  }

  Fault? take(String operation, Moment moment) =>
      _planned.remove((operation, moment));

  void alive() {
    if (dead) {
      throw const SimulatedCrash();
    }
  }

  /// Applies a taken [fault]: a crash kills the session and throws.
  void crashIf(Fault? fault) {
    if (fault == Fault.crash) {
      dead = true;
      throw const SimulatedCrash();
    }
  }
}

/// Queue port in front of the real [PersistentDeliveryQueue].
final class FaultyDeliveryQueue implements OccurrenceDeliveryQueuePort {
  FaultyDeliveryQueue(this._inner, this._faults);

  final OccurrenceDeliveryQueuePort _inner;
  final E4Faults _faults;

  Future<T> _run<T>(
    String operation,
    Future<T> Function() body,
    T Function() failure,
  ) async {
    _faults.alive();
    _faults.calls.add(operation);
    final before = _faults.take(operation, Moment.before);
    _faults.crashIf(before);
    if (before == Fault.failure) {
      return failure();
    }
    final value = await body();
    // A kill while the operation was running must not let the coordinator act
    // on its result.
    _faults.alive();
    final after = _faults.take(operation, Moment.after);
    _faults.crashIf(after);
    return after == Fault.failure ? failure() : value;
  }

  @override
  Future<DeliveryHeadResult> nextHead(DateTime now) => _run(
        'nextHead',
        () => _inner.nextHead(now),
        () => const DeliveryQueueUnavailable(),
      );

  @override
  Stream<List<int>> openImage(DeliveryHeadEligible head) {
    _faults.alive();
    _faults.calls.add('openImage');
    return _inner.openImage(head);
  }

  @override
  Future<DeliveryMutationResult> recordRecoverableFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextAttemptAt,
  ) =>
      _run(
        'recordRecoverableFailure',
        () => _inner.recordRecoverableFailure(
          idempotencyKey,
          calculatedAt,
          nextAttemptAt,
        ),
        () => DeliveryMutationResult.storageFailure,
      );

  @override
  Future<DeliveryMutationResult> recordDefinitiveDecision(
    String idempotencyKey,
    DeliveryDisposition disposition,
  ) =>
      _run(
        'recordDefinitiveDecision',
        () => _inner.recordDefinitiveDecision(idempotencyKey, disposition),
        () => DeliveryMutationResult.storageFailure,
      );

  @override
  Future<QueueRemovalResult> completePendingLocalRemoval(
    String idempotencyKey,
  ) =>
      _run(
        'completePendingLocalRemoval',
        () => _inner.completePendingLocalRemoval(idempotencyKey),
        () => const QueueOccurrenceRemovalFailed(),
      );

  @override
  Future<DeliveryMutationResult> recordCleanupFailure(
    String idempotencyKey,
    DateTime calculatedAt,
    DateTime nextCleanupAt,
  ) =>
      _run(
        'recordCleanupFailure',
        () => _inner.recordCleanupFailure(
          idempotencyKey,
          calculatedAt,
          nextCleanupAt,
        ),
        () => DeliveryMutationResult.storageFailure,
      );

  @override
  Future<DeliveryControl> readControl() => _run(
        'readControl',
        _inner.readControl,
        () => const DeliveryControlUnavailable(),
      );

  @override
  Future<DeliveryMutationResult> pause(PausedDeliveryDecision pause) => _run(
        'pause',
        () => _inner.pause(pause),
        () => DeliveryMutationResult.storageFailure,
      );

  @override
  Future<DeliveryMutationResult> resume() => _run(
        'resume',
        _inner.resume,
        () => DeliveryMutationResult.storageFailure,
      );

  @override
  Stream<DeliveryQueueSummary> watchSummary() => _inner.watchSummary();
}

/// Image store in front of the real private store. It faults only the two
/// steps of the E2 removal protocol that surround the SQLite commit.
final class FaultyImageStore implements DurableImageStore {
  FaultyImageStore(this._inner, this._faults);

  final DurableImageStore _inner;
  final E4Faults _faults;

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) =>
      _inner.stage(source);

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) =>
      _inner.promote(source);

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) =>
      _inner.openRead(image);

  @override
  Future<DurableImageIntegrity> inspect(PersistedImageProjection image) =>
      _inner.inspect(image);

  @override
  Future<void> delete(PersistedImageProjection image) => _inner.delete(image);

  @override
  Future<DurableImageSweepResult> sweep(
    Set<String> referencedCanonicalNames,
  ) =>
      _inner.sweep(referencedCanonicalNames);

  /// `before`: the JPEG is not moved. `after`: the JPEG is already moved to
  /// its `.deleting` marker when the fault hits, before the SQLite commit.
  @override
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  ) async {
    _faults.alive();
    final before = _faults.take('markForDeletion', Moment.before);
    _faults.crashIf(before);
    if (before == Fault.failure) {
      throw StateError('injected: markForDeletion failed before the move');
    }
    final deletion = await _inner.markForDeletion(image);
    final after = _faults.take('markForDeletion', Moment.after);
    _faults.crashIf(after);
    if (after == Fault.failure) {
      throw StateError('injected: markForDeletion failed after the move');
    }
    return _FaultyDeletion(deletion, _faults);
  }
}

final class _FaultyDeletion implements DurableImageDeletion {
  _FaultyDeletion(this._inner, this._faults);

  final DurableImageDeletion _inner;
  final E4Faults _faults;

  /// Runs after the SQLite commit. A fault here leaves only the recognized
  /// `.deleting` marker of an already removed row.
  @override
  Future<void> finalizeAfterCommit() async {
    final fault = _faults.take('finalizeAfterCommit', Moment.before);
    _faults.crashIf(fault);
    if (fault == Fault.failure) {
      throw StateError('injected: finalizeAfterCommit failed');
    }
    await _inner.finalizeAfterCommit();
  }
}

/// One process lifetime.
final class E4Session {
  E4Session._({
    required this.faults,
    required this.queue,
    required this.rawDeliveryQueue,
    required this.deliveryQueue,
    required this.snapshot,
    required this.transport,
    required this.coordinator,
    required this.delivery,
    required this.guard,
    required this.logs,
    required this.phases,
  });

  final E4Faults faults;
  final CoordinatedPersistentOccurrenceQueue queue;
  final PersistentDeliveryQueue rawDeliveryQueue;
  final FaultyDeliveryQueue deliveryQueue;
  final ExclusiveDeliveryConfigurationSnapshot snapshot;
  final HttpOccurrenceTransport transport;
  final OccurrenceDeliveryCoordinator coordinator;
  final CoordinatorOperationDelivery delivery;
  final DeliveryConfigurationChangeService guard;

  /// Technical log lines of this process only.
  final List<String> logs;

  /// Every presentation state published by this process.
  final List<DeliveryPresentationState> phases;

  bool _killed = false;

  DeliveryPhase get phase => delivery.presentation.phase;
}

/// Everything that outlives a process.
final class E4RestartWorld {
  E4RestartWorld._({
    required this.sandbox,
    required this.databasePath,
    required this.clock,
    required this.fakeTimer,
    required this.repository,
    required this.credentials,
    required this.client,
    required this.attemptTimeout,
  });

  static Future<E4RestartWorld> create({
    bool withConfiguration = true,
    Duration attemptTimeout = const Duration(milliseconds: 200),
  }) async {
    sqfliteFfiInit();
    final sandbox = await Directory.systemTemp.createTemp('e4_restart_');
    final clock = FakeClock(restartT0);
    final world = E4RestartWorld._(
      sandbox: sandbox,
      databasePath:
          '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName',
      clock: clock,
      fakeTimer: FakeDeliveryTimer(clock),
      repository: E4Repository()
        ..baseUrl = withConfiguration ? restartBaseUrl : null,
      credentials: E4Credentials()
        ..secret = withConfiguration ? restartSecret : null,
      client: E4ScriptedClient(),
      attemptTimeout: attemptTimeout,
    );
    addTearDown(world.dispose);
    return world;
  }

  final Directory sandbox;
  final String databasePath;
  final FakeClock clock;
  final FakeDeliveryTimer fakeTimer;
  final E4Repository repository;
  final E4Credentials credentials;
  final E4ScriptedClient client;
  final Duration attemptTimeout;

  /// Technical log lines of every process, in order.
  final List<String> allLogs = <String>[];

  final Map<String, List<int>> _jpegs = <String, List<int>>{};
  final List<E4Session> _sessions = <E4Session>[];

  E4Session get session => _sessions.last;

  Future<E4Session> boot({bool start = true}) async {
    final faults = E4Faults();
    final logs = <String>[];
    final phases = <DeliveryPresentationState>[];
    final queue = CoordinatedPersistentOccurrenceQueue(
      imageStore: FaultyImageStore(
        PrivateDurableImageStore.at(sandbox),
        faults,
      ),
      databaseOpener: () => QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      ),
    );
    await queue.bootstrap();
    final raw = PersistentDeliveryQueue(queue, clock: clock);
    final gated = FaultyDeliveryQueue(raw, faults);
    final snapshot = ExclusiveDeliveryConfigurationSnapshot(
      configurationRepository: repository,
      credentialReader: credentials,
      buildVariant: ConfigurationBuildVariant.release,
    );
    final transport = HttpOccurrenceTransport(
      StreamedHttpClientAdapter(client),
      limits: OccurrenceTransportLimits(attemptTimeout: attemptTimeout),
    );
    final coordinator = OccurrenceDeliveryCoordinator(
      queue: gated,
      configuration: snapshot,
      transport: transport,
      clock: clock,
      logger: SanitizedDeliveryTechnicalLogger((line) {
        // A dead process writes nothing.
        if (!faults.dead) {
          logs.add(line);
          allLogs.add(line);
        }
      }),
      timer: _PortTimer(fakeTimer),
    );
    final delivery = CoordinatorOperationDelivery(coordinator);
    delivery.presentations.listen(phases.add);
    final session = E4Session._(
      faults: faults,
      queue: queue,
      rawDeliveryQueue: raw,
      deliveryQueue: gated,
      snapshot: snapshot,
      transport: transport,
      coordinator: coordinator,
      delivery: delivery,
      guard: DeliveryConfigurationChangeService(
        snapshot: snapshot,
        queue: gated,
        delivery: coordinator,
      ),
      logs: logs,
      phases: phases,
    );
    _sessions.add(session);
    if (start) {
      delivery.start();
    }
    return session;
  }

  /// Force-stop: nothing is persisted or logged afterwards, armed timers are
  /// dropped and the files stay exactly as they are.
  Future<void> kill() async {
    final session = _sessions.isEmpty ? null : _sessions.last;
    if (session == null || session._killed) {
      return;
    }
    session._killed = true;
    session.faults.dead = true;
    fakeTimer.cancelAll();
    await session.coordinator.dispose();
    await session.delivery.dispose();
    await session.transport.dispose();
    await session.queue.close();
    fakeTimer.cancelAll();
  }

  /// Persists one occurrence through the current session.
  Future<void> persist(
    String key, {
    required int red,
    DateTime? detectedAt,
    double latitude = -23.5505,
    double longitude = -46.6333,
  }) async {
    final bytes = _jpegBytes(red: red);
    _jpegs[key] = bytes;
    final result = await session.queue.persist(
      const InMemoryOccurrenceFactory().createManual(
        idempotencyKey: key,
        detectedAt: detectedAt ?? DateTime.utc(2025, 1, 2, 3, 4, red),
        location: ImmutableLocationSnapshot(
          point: ImmutableGeoPoint(latitude: latitude, longitude: longitude),
          accuracyMeters: null,
          speedMetersPerSecond: null,
        ),
        image: _Lease(bytes, 8, 8),
      ),
    );
    expect(result, isA<OccurrencePersisted>());
  }

  List<int> jpeg(String key) => _jpegs[key]!;

  /// Schedules a process death while the next request is in flight: the
  /// server received the request, but no status ever comes back.
  void scriptCrashInFlight() {
    client.step((_) async {
      session.faults.dead = true;
      throw const SocketException('process died');
    });
  }

  // -------------------------------------------------------------------------
  // Independent inspection of the persisted state (own SQLite connection and
  // the sandbox listing, never through a session)
  // -------------------------------------------------------------------------

  Future<T> _withExtra<T>(Future<T> Function(QueueDatabase extra) body) async {
    final extra = await QueueDatabase.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
    try {
      return await body(extra);
    } finally {
      await extra.close();
    }
  }

  /// Idempotency keys still queued, in FIFO order.
  Future<List<String>> pendingKeys() => _withExtra((extra) async {
        final rows = await extra.database.query(
          e2QueueTable,
          columns: <String>[QueueRecordColumns.idempotencyKey],
          orderBy: '${QueueRecordColumns.queueSequence} ASC',
        );
        return rows
            .map((row) => row[QueueRecordColumns.idempotencyKey]! as String)
            .toList();
      });

  Future<Map<String, Object?>?> stateRow(String key) =>
      _withExtra((extra) async {
        final rows = await extra.database.query(
          e4DeliveryStateTable,
          where: 'idempotency_key = ?',
          whereArgs: <Object>[key],
        );
        return rows.isEmpty ? null : rows.single;
      });

  /// State rows whose occurrence no longer exists.
  Future<int> orphanStateRows() => _withExtra((extra) async {
        final rows = await extra.database.rawQuery(
          'SELECT COUNT(*) AS n FROM $e4DeliveryStateTable '
          'WHERE idempotency_key NOT IN '
          '(SELECT ${QueueRecordColumns.idempotencyKey} FROM $e2QueueTable)',
        );
        return rows.single['n']! as int;
      });

  Future<Map<String, Object?>?> controlRow() => _withExtra((extra) async {
        final rows = await extra.database.query(e4DeliveryControlTable);
        return rows.isEmpty ? null : rows.single;
      });

  /// Canonical JPEG names referenced by the queued rows.
  Future<Set<String>> referencedImages() => _withExtra((extra) async {
        final rows = await extra.database.query(
          e2QueueTable,
          columns: <String>[QueueRecordColumns.imageRelativeName],
        );
        return rows
            .map((row) => row[QueueRecordColumns.imageRelativeName]! as String)
            .toSet();
      });

  /// Base names of every private image artifact (canonical, staging and
  /// `.deleting` marker) in the sandbox.
  Set<String> imageArtifacts() => sandbox
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where((name) => RegExp(r'^e2[isd]_').hasMatch(name))
      .toSet();

  Set<String> canonicalImages() =>
      imageArtifacts().where((name) => name.endsWith('.jpg')).toSet();

  Set<String> deletingMarkers() =>
      imageArtifacts().where((name) => name.endsWith('.deleting')).toSet();

  /// No lost data, no orphan state: the stored JPEGs are exactly the ones the
  /// queued rows reference, no staging or `.deleting` artifact is left and no
  /// delivery state row outlives its occurrence.
  Future<void> expectConsistent() async {
    expect(imageArtifacts(), await referencedImages(),
        reason: 'stored JPEGs must be exactly the referenced ones');
    expect(await orphanStateRows(), 0);
  }

  /// Runs [statement] on an independent connection.
  Future<void> execute(String statement) =>
      _withExtra((extra) => extra.database.execute(statement));

  /// Waits until the current coordinator is idle for a few consecutive polls.
  Future<void> settle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var quiet = 0;
    while (quiet < 3) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      if (session.coordinator.isEvaluating) {
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

  /// Waits for the planned crash to hit and for the dying evaluation to end.
  Future<void> waitForCrash() async {
    await waitFor(() => session.faults.dead);
    await waitFor(() => !session.coordinator.isEvaluating);
  }

  /// Logs and every rendered presentation text carry only closed vocabulary.
  void expectNoLeak() {
    final line = RegExp(r'^E4_DELIVERY_[A-Z_]+( [a-z]+=[A-Za-z0-9]+)?$');
    for (final entry in allLogs) {
      expect(entry, matches(line));
    }
    final rendered = <String>[
      ...allLogs,
      for (final session in _sessions)
        for (final state in <DeliveryPresentationState>[
          ...session.phases,
          session.delivery.presentation,
        ]) ...<String>[state.message, state.statusLabel, '$state'],
    ].join('\n');
    for (final forbidden in <String>[
      restartSecret,
      restartRotatedSecret,
      'delivery.example.invalid',
      'https://',
      'ApiKey',
      'Authorization',
      restartKeyA,
      restartKeyB,
      restartKeyC,
      '-23.55',
      '-46.63',
      '2025-01-02',
      '.jpg',
      'e2i_',
      '.deleting',
    ]) {
      expect(rendered, isNot(contains(forbidden)), reason: forbidden);
    }
  }

  Future<void> dispose() async {
    await kill();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

final class _PortTimerHandle implements DeliveryTimerHandle {
  _PortTimerHandle(this._handle);

  final FakeTimerHandle _handle;

  @override
  bool get isActive => _handle.isActive;

  @override
  void cancel() => _handle.cancel();
}

final class _PortTimer implements DeliveryTimerPort {
  _PortTimer(this._timer);

  final FakeDeliveryTimer _timer;

  @override
  DeliveryTimerHandle arm(DateTime dueAt, void Function() onDue) =>
      _PortTimerHandle(_timer.arm(dueAt, onDue));
}

final class E4Repository implements OperationalConfigurationRepository {
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

final class E4Credentials implements DeviceCredentialReadPort {
  String? secret;

  @override
  Future<CredentialReadResult> readForDelivery() async {
    final stored = secret;
    return stored == null
        ? const CredentialMissing()
        : CredentialAvailable(NonPrintableSecret(stored));
  }
}

/// One request as the server would see it.
final class E4SeenRequest {
  E4SeenRequest(http.BaseRequest request, List<int> body)
      : url = request.url.toString(),
        authorization = request.headers['Authorization'],
        _wire = latin1.decode(body);

  final String url;
  final String? authorization;
  final String _wire;

  String get idempotencyKey => RegExp(
        r'name="idempotencyKey"\r\n\r\n([^\r]+)\r\n',
      ).firstMatch(_wire)!.group(1)!;

  bool containsImage(List<int> jpeg) => _wire.contains(latin1.decode(jpeg));
}

typedef E4Step = Future<int> Function(Future<void> aborted);

/// The server: drains each request, records it, then follows the next scripted
/// step. An unscripted request fails loudly and is counted.
final class E4ScriptedClient extends http.BaseClient {
  final Queue<E4Step> _script = Queue<E4Step>();
  final List<E4SeenRequest> seen = <E4SeenRequest>[];
  int unscripted = 0;

  void status(int code) => _script.add((_) async => code);

  void network() =>
      _script.add((_) async => throw const SocketException('unreachable'));

  void step(E4Step step) => _script.add(step);

  List<String> get keys => seen.map((r) => r.idempotencyKey).toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.finalize()) {
      builder.add(chunk);
    }
    seen.add(E4SeenRequest(request, builder.takeBytes()));
    if (_script.isEmpty) {
      unscripted++;
      throw StateError('no scripted response');
    }
    final abortTrigger =
        request is http.Abortable ? request.abortTrigger : null;
    final code =
        await _script.removeFirst()(abortTrigger ?? Completer<void>().future);
    return http.StreamedResponse(const Stream<List<int>>.empty(), code);
  }
}

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
