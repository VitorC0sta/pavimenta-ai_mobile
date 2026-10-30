import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_change_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_change_service.dart';
import 'package:pavimenta_ai_mobile/application/delivery/device_credential_read_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/exclusive_delivery_configuration_snapshot.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_transport_port.dart';
import 'package:pavimenta_ai_mobile/application/e3_configuration_use_cases.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_transport_result.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/domain/in_memory_occurrence.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/persistent_delivery_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/persistent_occurrence_queue.dart';
import 'package:pavimenta_ai_mobile/infrastructure/queue_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Explicitly fictitious values; none is a real destination or key.
const String _urlAText = 'https://old.example.invalid';
const String _urlBText = 'https://new.example.invalid';
final Uri _urlA = Uri.parse(_urlAText);
final Uri _urlB = Uri.parse(_urlBText);
const String _secretA = 'oldprefix.old-secret-for-tests-only';
const String _secretB = 'newprefix.new-secret-for-tests-only';
const String _occurrenceKey = '123e4567-e89b-42d3-a456-426614174000';

/// What the attempt stand-in decided; the coordinator itself is task 68.
enum _Outcome {
  empty,
  paused,
  configurationRequired,
  localFailure,
  cancelled,
  stale,
  delivered,
  pausedByResponse,
}

/// One time-ordered list of every observable step, shared by all fakes.
typedef _Log = List<String>;

/// Configuration stores that outlive an app "process".
final class _Repository implements OperationalConfigurationRepository {
  _Repository(this._log) {
    _document = _documentFor(_urlA);
  }

  final _Log _log;
  late OperationalConfiguration _document;

  Uri? get baseUrl => _document.baseUrl;

  set baseUrl(Uri? value) => _document = _documentFor(value);

  @override
  Future<OperationalConfiguration> load() async => _document;

  @override
  Future<void> save(OperationalConfiguration configuration) async {
    _log.add('write:settings');
    _document = configuration;
  }
}

OperationalConfiguration _documentFor(Uri? baseUrl) => OperationalConfiguration(
      baseUrl: baseUrl,
      cooldown: OperationalConfiguration.defaultCooldown,
      minimumDistanceMeters:
          OperationalConfiguration.defaultMinimumDistanceMeters,
      confidenceThreshold: OperationalConfiguration.defaultConfidenceThreshold,
      maximumInferenceFps: OperationalConfiguration.defaultMaximumInferenceFps,
    );

final class _Credentials
    implements DeviceCredentialStatusPort, DeviceCredentialReadPort {
  _Credentials(this._log, {this.secret});

  final _Log _log;
  String? secret;
  Object? saveError;

  /// Number of times the restricted E4 read was used.
  int secretReads = 0;

  Completer<void>? _readGate;
  Completer<void> _readReached = Completer<void>();

  /// Holds the next E4 read until [releaseRead]; completes [readReached] once
  /// the read is waiting.
  void holdRead() {
    _readGate = Completer<void>();
    _readReached = Completer<void>();
  }

  Future<void> get readReached => _readReached.future;

  void releaseRead() => _readGate!.complete();

  @override
  Future<bool> hasCredential() async => secret != null;

  @override
  Future<void> saveCredential(String credential) async {
    _log.add('write:credential');
    final error = saveError;
    if (error != null) {
      throw error;
    }
    secret = credential;
  }

  @override
  Future<void> removeCredential() async {
    _log.add('remove:credential');
    secret = null;
  }

  @override
  Future<CredentialReadResult> readForDelivery() async {
    secretReads++;
    final gate = _readGate;
    if (gate != null) {
      if (!_readReached.isCompleted) {
        _readReached.complete();
      }
      await gate.future;
    }
    final stored = secret;
    return stored == null
        ? const CredentialMissing()
        : CredentialAvailable(NonPrintableSecret(stored));
  }
}

/// One request as the socket would have seen it.
final class _Sent {
  _Sent(OccurrenceUploadRequest request)
      : baseUrl = request.baseUrl,
        secret = request.credential.reveal(),
        revision = request.configurationRevision,
        rendered = '$request';

  final Uri baseUrl;
  final String secret;
  final int revision;
  final String rendered;
}

final class _Transport implements OccurrenceTransportPort {
  _Transport(this._log);

  final _Log _log;
  final List<_Sent> sent = <_Sent>[];
  final Queue<OccurrenceTransportResult> _results =
      Queue<OccurrenceTransportResult>();
  final List<Completer<void>> _startWaiters = <Completer<void>>[];
  Completer<OccurrenceTransportResult>? _holdNext;
  Completer<OccurrenceTransportResult>? _active;
  int cancelActiveCalls = 0;

  void respondWith(OccurrenceTransportResult result) => _results.add(result);

  Completer<OccurrenceTransportResult> holdNext() =>
      _holdNext = Completer<OccurrenceTransportResult>();

  /// Completes when the next request reaches the socket.
  Future<void> nextSendStarted() {
    final waiter = Completer<void>();
    _startWaiters.add(waiter);
    return waiter.future;
  }

  @override
  Future<OccurrenceTransportResult> send(
      OccurrenceUploadRequest request) async {
    sent.add(_Sent(request));
    _log.add('socket:open');
    for (final waiter in _startWaiters) {
      waiter.complete();
    }
    _startWaiters.clear();
    final held = _holdNext;
    _holdNext = null;
    if (held != null) {
      _active = held;
      try {
        return await held.future;
      } finally {
        _active = null;
      }
    }
    return _results.isEmpty
        ? const TransportHttpResponse(201)
        : _results.removeFirst();
  }

  @override
  Future<void> cancelActive() async {
    cancelActiveCalls++;
    final active = _active;
    if (active != null && !active.isCompleted) {
      _log.add('socket:cancelled');
      active.complete(const TransportCancelled());
    }
  }
}

/// Delegates to the real persistent delivery queue and counts image opens.
final class _QueuePort implements OccurrenceDeliveryQueuePort {
  _QueuePort(this._queue);

  final PersistentDeliveryQueue _queue;
  int imageOpens = 0;

  @override
  Future<DeliveryHeadResult> nextHead(DateTime now) => _queue.nextHead(now);

  @override
  Stream<List<int>> openImage(DeliveryHeadEligible head) {
    imageOpens++;
    return _queue.openImage(head);
  }

  @override
  Future<DeliveryControl> readControl() => _queue.readControl();

  @override
  Future<DeliveryMutationResult> pause(PausedDeliveryDecision pause) =>
      _queue.pause(pause);

  @override
  Future<DeliveryMutationResult> resume() => _queue.resume();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Minimal stand-in for the coordinator of task 68, following design E4.6:
/// head, pause, snapshot, preparation, revision check, then the socket.
///
/// With [cancelsOnChange] it also honours the suspend/evaluate hook; without
/// it the revision check is the only defence, so each layer is tested alone.
final class _AttemptDriver implements DeliveryConfigurationChangePort {
  _AttemptDriver({
    required _QueuePort queue,
    required ExclusiveDeliveryConfigurationSnapshot snapshot,
    required _Transport transport,
    required _Log log,
    required this.cancelsOnChange,
  })  : _queue = queue,
        _snapshot = snapshot,
        _transport = transport,
        _log = log;

  final _QueuePort _queue;
  final ExclusiveDeliveryConfigurationSnapshot _snapshot;
  final _Transport _transport;
  final _Log _log;
  final bool cancelsOnChange;

  final List<_Outcome> outcomes = <_Outcome>[];
  final List<int> readRevisions = <int>[];
  int suspendCalls = 0;
  int evaluationRequests = 0;

  bool _suspended = false;
  Future<void>? _active;
  Completer<void>? _cancel;
  Completer<void>? _preparationGate;
  bool _preparationArmed = false;
  Completer<void> _preparationReached = Completer<void>();

  _Outcome get last => outcomes.last;

  /// Holds the next attempt after its image was prepared and before the
  /// revision check that precedes the socket.
  void holdPreparation() {
    _preparationGate = Completer<void>();
    _preparationArmed = true;
    _preparationReached = Completer<void>();
  }

  Future<void> get preparationReached => _preparationReached.future;

  void releasePreparation() => _preparationGate!.complete();

  @override
  Future<void> suspendForConfigurationChange() async {
    suspendCalls++;
    if (!cancelsOnChange) {
      return;
    }
    _suspended = true;
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) {
      cancel.complete();
    }
    await _transport.cancelActive();
    await _active;
  }

  @override
  void onConfigurationChanged() {
    evaluationRequests++;
    _suspended = false;
  }

  /// Runs one evaluation; a call during an attempt joins that attempt.
  Future<void> evaluate() {
    final running = _active;
    if (running != null) {
      return running;
    }
    if (_suspended) {
      return Future<void>.value();
    }
    final run = _attempt().whenComplete(() => _active = null);
    _active = run;
    return run;
  }

  void _finish(_Outcome outcome) => outcomes.add(outcome);

  Future<void> _attempt() async {
    final cancel = _cancel = Completer<void>();
    bool cancelled() => cancel.isCompleted;

    final head = await _queue.nextHead(DateTime.utc(2025, 3, 4, 5, 6, 7));
    if (head is! DeliveryHeadEligible) {
      return _finish(_Outcome.empty);
    }
    if (await _queue.readControl() is DeliveryControlPaused) {
      return _finish(_Outcome.paused);
    }

    final result = await _snapshot.readForAttempt();
    if (result is! DeliveryConfigurationAvailable) {
      return _finish(
        result is DeliverySecureStorageUnavailable
            ? _Outcome.localFailure
            : _Outcome.configurationRequired,
      );
    }
    final configuration = result.configuration;
    readRevisions.add(configuration.revision);
    if (cancelled()) {
      _log.add('attempt:cancelled');
      return _finish(_Outcome.cancelled);
    }

    final bytes = await _queue.openImage(head).expand((c) => c).toList();
    final gate = _preparationArmed ? _preparationGate : null;
    _preparationArmed = false; // The hold applies to one attempt only.
    if (gate != null) {
      if (!_preparationReached.isCompleted) {
        _preparationReached.complete();
      }
      await Future.any<void>(<Future<void>>[gate.future, cancel.future]);
    }
    if (cancelled()) {
      _log.add('attempt:cancelled');
      return _finish(_Outcome.cancelled);
    }
    if (!_snapshot.isCurrent(configuration.revision)) {
      _log.add('attempt:stale');
      return _finish(_Outcome.stale);
    }

    final response = await _transport.send(
      OccurrenceUploadRequest.fromConfiguration(
        configuration: configuration,
        idempotencyKey: head.head.idempotencyKey,
        payload: head.payload,
        imageStream: Stream<List<int>>.value(bytes),
      ),
    );
    if (response is TransportCancelled) {
      _log.add('attempt:cancelled');
      return _finish(_Outcome.cancelled);
    }
    if (response is TransportHttpResponse) {
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return _finish(_Outcome.delivered);
      }
      final reason = switch (status) {
        401 => DeliveryPauseReason.authentication,
        403 => DeliveryPauseReason.access,
        _ => DeliveryPauseReason.unexpectedResponse,
      };
      await _queue.pause(
        PausedDeliveryDecision(
          reason,
          unexpectedStatusCode:
              reason == DeliveryPauseReason.unexpectedResponse ? status : null,
        ),
      );
      return _finish(_Outcome.pausedByResponse);
    }
    return _finish(_Outcome.localFailure);
  }
}

/// One run of the application over the shared stores and database.
final class _App {
  _App({
    required this.queue,
    required this.deliveryQueue,
    required this.port,
    required this.snapshot,
    required this.driver,
    required this.saveCredential,
    required this.removeCredential,
    required this.saveParameters,
  });

  final CoordinatedPersistentOccurrenceQueue queue;
  final PersistentDeliveryQueue deliveryQueue;
  final _QueuePort port;
  final ExclusiveDeliveryConfigurationSnapshot snapshot;
  final _AttemptDriver driver;
  final SaveOrReplaceDeviceCredential saveCredential;
  final RemoveDeviceCredential removeCredential;
  final SaveOperationalParameters saveParameters;

  Future<DeliveryControl> control() => deliveryQueue.readControl();
}

/// A temporary database plus stores and a "network" that survive reopening.
final class _Harness {
  _Harness._(this.sandbox) {
    repository = _Repository(log);
    credentials = _Credentials(log, secret: _secretA);
    transport = _Transport(log);
  }

  final Directory sandbox;
  final _Log log = <String>[];
  late final _Repository repository;
  late final _Credentials credentials;
  late final _Transport transport;
  late _App app;
  final List<_App> _opened = <_App>[];

  String get databasePath =>
      '${sandbox.path}${Platform.pathSeparator}$e2QueueDatabaseName';

  static Future<_Harness> create({bool cancelsOnChange = true}) async {
    final harness = _Harness._(
      await Directory.systemTemp.createTemp('e4_configuration_consistency_'),
    );
    harness.app = await harness._openApp(cancelsOnChange: cancelsOnChange);
    await harness.app.queue.persist(
      _occurrence(
        key: _occurrenceKey,
        detectedAt: DateTime.utc(2025, 1, 2, 3, 4, 5),
        bytes: _jpeg(width: 8, height: 8, red: 3),
        width: 8,
        height: 8,
      ),
    );
    return harness;
  }

  Future<_App> _openApp({required bool cancelsOnChange}) async {
    final queue = CoordinatedPersistentOccurrenceQueue(
      imageStore: PrivateDurableImageStore.at(sandbox),
      databaseOpener: () => QueueDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      ),
    );
    await queue.bootstrap();
    final deliveryQueue = PersistentDeliveryQueue(queue);
    final port = _QueuePort(deliveryQueue);
    final snapshot = ExclusiveDeliveryConfigurationSnapshot(
      configurationRepository: repository,
      credentialReader: credentials,
      buildVariant: ConfigurationBuildVariant.release,
    );
    final driver = _AttemptDriver(
      queue: port,
      snapshot: snapshot,
      transport: transport,
      log: log,
      cancelsOnChange: cancelsOnChange,
    );
    final service = DeliveryConfigurationChangeService(
      snapshot: snapshot,
      queue: port,
      delivery: driver,
    );
    final app = _App(
      queue: queue,
      deliveryQueue: deliveryQueue,
      port: port,
      snapshot: snapshot,
      driver: driver,
      saveCredential: SaveOrReplaceDeviceCredential(
        credentialStore: credentials,
        deliveryChange: service,
      ),
      removeCredential: RemoveDeviceCredential(
        credentialStore: credentials,
        deliveryChange: service,
      ),
      saveParameters: SaveOperationalParameters(
        repository: repository,
        buildVariant: ConfigurationBuildVariant.release,
        deliveryChange: service,
      ),
    );
    _opened.add(app);
    return app;
  }

  /// Simulates closing and reopening the application: the snapshot, the
  /// revision, and the driver are new; the database and stores are not.
  Future<_App> reopen({bool cancelsOnChange = true}) async {
    await app.queue.close();
    return app = await _openApp(cancelsOnChange: cancelsOnChange);
  }

  Future<void> dispose() async {
    for (final opened in _opened) {
      await opened.queue.close();
    }
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  }

  Future<void> pause(DeliveryPauseReason reason) async {
    final result = await app.deliveryQueue.pause(
      PausedDeliveryDecision(
        reason,
        unexpectedStatusCode:
            reason == DeliveryPauseReason.unexpectedResponse ? 418 : null,
      ),
    );
    expect(result, DeliveryMutationResult.applied);
  }
}

SettingsDraft _draft({
  String baseUrl = _urlAText,
  String cooldown = '5',
  String distance = '15',
  String confidence = '0.5',
  String fps = '5',
}) =>
    SettingsDraft(
      baseUrlText: baseUrl,
      cooldownSecondsText: cooldown,
      minimumDistanceMetersText: distance,
      confidenceThresholdText: confidence,
      maximumInferenceFpsText: fps,
    );

void _expectSent(_Sent sent, Uri url, String secret) {
  expect(sent.baseUrl, url);
  expect(sent.secret, secret);
  expect(sent.rendered, isNot(contains('example')));
  expect(sent.rendered, isNot(contains('secret')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late _Harness h;

  Future<void> open({bool cancelsOnChange = true}) async {
    h = await _Harness.create(cancelsOnChange: cancelsOnChange);
    addTearDown(h.dispose);
  }

  /// Starts an attempt and waits until it is held right before the revision
  /// check that precedes the socket.
  Future<({Future<void> attempt})> startHeldInPreparation() async {
    h.app.driver.holdPreparation();
    final attempt = h.app.driver.evaluate();
    await h.app.driver.preparationReached;
    return (attempt: attempt);
  }

  group('changes interleaved with read, preparation and socket', () {
    // **Validates: Requirements RF-13.14Ã¢â‚¬â€œ16, RF-13.22Ã¢â‚¬â€œ26, RNF-03.6, RNF-05.5**
    group('revision check alone (no cancellation)', () {
      setUp(() => open(cancelsOnChange: false));

      test('a replaced credential makes the prepared snapshot stale', () async {
        final attempt = (await startHeldInPreparation()).attempt;

        expect(await h.app.saveCredential(_secretB), isA<CredentialSaved>());
        h.app.driver.releasePreparation();
        await attempt;

        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.stale]);
        expect(h.transport.sent, isEmpty, reason: 'No old pair, no socket.');

        await h.app.driver.evaluate();
        expect(h.app.driver.last, _Outcome.delivered);
        expect(h.transport.sent, hasLength(1));
        _expectSent(h.transport.sent.single, _urlA, _secretB);
        expect(h.transport.sent.single.revision, 1);
      });

      test('a replaced destination makes the prepared snapshot stale',
          () async {
        final attempt = (await startHeldInPreparation()).attempt;

        await h.app.saveParameters(_draft(baseUrl: _urlBText));
        h.app.driver.releasePreparation();
        await attempt;

        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.stale]);
        expect(h.transport.sent, isEmpty);

        await h.app.driver.evaluate();
        _expectSent(h.transport.sent.single, _urlB, _secretA);
      });

      test('a removed credential never reaches the socket', () async {
        final attempt = (await startHeldInPreparation()).attempt;

        await h.app.removeCredential(CredentialRemovalConfirmation.confirmed);
        h.app.driver.releasePreparation();
        await attempt;
        await h.app.driver.evaluate();

        expect(h.app.driver.outcomes, <_Outcome>[
          _Outcome.stale,
          _Outcome.configurationRequired,
        ]);
        expect(h.transport.sent, isEmpty);
      });

      test('a removed destination never reaches the socket nor reads the key',
          () async {
        final attempt = (await startHeldInPreparation()).attempt;
        final readsDuringAttempt = h.credentials.secretReads;

        await h.app.saveParameters(_draft(baseUrl: ''));
        h.app.driver.releasePreparation();
        await attempt;
        final imagesBefore = h.app.port.imageOpens;
        await h.app.driver.evaluate();

        expect(h.app.driver.outcomes, <_Outcome>[
          _Outcome.stale,
          _Outcome.configurationRequired,
        ]);
        expect(h.transport.sent, isEmpty);
        expect(h.credentials.secretReads, readsDuringAttempt,
            reason: 'Without a destination the key is not read.');
        expect(h.app.port.imageOpens, imagesBefore,
            reason: 'Without a destination the image is not opened.');
      });

      test('a half-written replacement is never combined with the old pair',
          () async {
        final attempt = (await startHeldInPreparation()).attempt;
        final writeDone = Completer<void>();
        final finishWrite = Completer<void>();
        final service = DeliveryConfigurationChangeService(
          snapshot: h.app.snapshot,
          queue: h.app.port,
          delivery: h.app.driver,
        );

        final replacing =
            service.replaceDestinationOrCredential<void>(() async {
          h.repository.baseUrl = _urlB; // Destination new, credential old.
          writeDone.complete();
          await finishWrite.future;
          h.credentials.secret = _secretB;
        });
        await writeDone.future;

        h.app.driver.releasePreparation();
        await attempt;
        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.stale]);
        expect(h.transport.sent, isEmpty);

        finishWrite.complete();
        await replacing;
        await h.app.driver.evaluate();

        expect(h.transport.sent, hasLength(1));
        _expectSent(h.transport.sent.single, _urlB, _secretB);
      });

      test('a mutation requested while the snapshot is read waits for it',
          () async {
        h.credentials.holdRead();
        h.app.driver.holdPreparation();
        final attempt = h.app.driver.evaluate();
        await h.credentials.readReached;

        final saving = h.app.saveCredential(_secretB);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(h.credentials.secret, _secretA,
            reason: 'The write waits for the snapshot in progress.');

        h.credentials.releaseRead();
        await h.app.driver.preparationReached;
        await saving;
        h.app.driver.releasePreparation();
        await attempt;

        expect(h.app.driver.readRevisions, <int>[0],
            reason: 'The snapshot was the complete old pair.');
        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.stale]);
        expect(h.transport.sent, isEmpty);
      });

      test('a failed write also retires the snapshot and the retry is whole',
          () async {
        final attempt = (await startHeldInPreparation()).attempt;
        h.credentials.saveError = StateError('keystore failure');

        expect(
            await h.app.saveCredential(_secretB), isA<CredentialSaveFailed>());
        h.app.driver.releasePreparation();
        await attempt;
        await h.app.driver.evaluate();

        expect(h.app.driver.outcomes.first, _Outcome.stale);
        expect(h.transport.sent, hasLength(1));
        _expectSent(h.transport.sent.single, _urlA, _secretA);
        expect(h.transport.sent.single.revision, 1);
      });
    });

    group('with cancellation of the old attempt', () {
      setUp(open);

      test('an upload in flight is cancelled before the new value is written',
          () async {
        final upload = h.transport.holdNext();
        final started = h.transport.nextSendStarted();
        final attempt = h.app.driver.evaluate();
        await started;

        final saved = await h.app.saveCredential(_secretB);
        await attempt;

        expect(saved, isA<CredentialSaved>());
        expect(upload.isCompleted, isTrue);
        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.cancelled]);
        final socketOpened = h.log.indexOf('socket:open');
        final socketCancelled = h.log.indexOf('socket:cancelled');
        final written = h.log.indexOf('write:credential');
        expect(socketOpened, isNonNegative);
        expect(socketCancelled, greaterThan(socketOpened));
        expect(written, greaterThan(socketCancelled),
            reason: 'The new key is written only after the old send ended.');
        _expectSent(h.transport.sent.single, _urlA, _secretA);

        expect(h.app.driver.evaluationRequests, 1);
        await h.app.driver.evaluate();
        expect(h.transport.sent, hasLength(2));
        _expectSent(h.transport.sent.last, _urlA, _secretB);
      });

      test('a destination change during preparation opens no socket', () async {
        final attempt = (await startHeldInPreparation()).attempt;

        final change = h.app.saveParameters(_draft(baseUrl: _urlBText));
        await attempt;
        await change;

        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.cancelled]);
        expect(h.transport.sent, isEmpty);
        expect(h.log.indexOf('attempt:cancelled'),
            lessThan(h.log.indexOf('write:settings')));

        await h.app.driver.evaluate();
        _expectSent(h.transport.sent.single, _urlB, _secretA);
      });

      test('a change during the snapshot read ends before image and socket',
          () async {
        h.credentials.holdRead();
        final attempt = h.app.driver.evaluate();
        await h.credentials.readReached;

        final change = h.app.saveCredential(_secretB);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(h.credentials.secret, _secretA);

        h.credentials.releaseRead();
        await attempt;
        await change;

        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.cancelled]);
        expect(h.app.port.imageOpens, 0);
        expect(h.transport.sent, isEmpty);
        expect(h.credentials.secret, _secretB);
      });

      test(
          'removing the credential during an upload cancels it and sends '
          'nothing new', () async {
        h.transport.holdNext();
        final started = h.transport.nextSendStarted();
        final attempt = h.app.driver.evaluate();
        await started;

        await h.app.removeCredential(CredentialRemovalConfirmation.confirmed);
        await attempt;
        await h.app.driver.evaluate();

        expect(h.app.driver.outcomes, <_Outcome>[
          _Outcome.cancelled,
          _Outcome.configurationRequired,
        ]);
        expect(h.transport.sent, hasLength(1));
        _expectSent(h.transport.sent.single, _urlA, _secretA);
      });
    });
  });

  group('the key is read only at the E4 boundary', () {
    // **Validates: Requirements RF-13.14Ã¢â‚¬â€œ16, RNF-02, RNF-03.10**
    setUp(open);

    test('settings operations never read the key', () async {
      await h.app.saveCredential(_secretB);
      await h.app.saveParameters(_draft(baseUrl: _urlBText));
      await h.app.saveParameters(_draft(baseUrl: _urlBText, cooldown: '9'));
      await h.app.removeCredential(CredentialRemovalConfirmation.confirmed);
      expect(await h.credentials.hasCredential(), isFalse);

      expect(h.credentials.secretReads, 0);
    });

    test('each attempt reads the key once, and a pause reads nothing',
        () async {
      await h.app.driver.evaluate();
      await h.app.driver.evaluate();
      expect(h.credentials.secretReads, 2);

      await h.pause(DeliveryPauseReason.authentication);
      await h.app.driver.evaluate();
      await h.reopen();
      await h.app.driver.evaluate();

      expect(h.app.driver.outcomes, <_Outcome>[_Outcome.paused]);
      expect(h.credentials.secretReads, 2);
      expect(h.app.port.imageOpens, 0);
    });

    test('a missing or invalid destination reads no key and opens no image',
        () async {
      h.repository.baseUrl = null;
      await h.app.driver.evaluate();
      h.repository.baseUrl = Uri.parse('http://old.example.invalid');
      await h.app.driver.evaluate();

      expect(h.app.driver.outcomes, <_Outcome>[
        _Outcome.configurationRequired,
        _Outcome.configurationRequired,
      ]);
      expect(h.credentials.secretReads, 0);
      expect(h.app.port.imageOpens, 0);
      expect(h.transport.sent, isEmpty);
    });

    test('the request never renders the pair it carries', () async {
      await h.app.driver.evaluate();

      final sent = h.transport.sent.single;
      expect(sent.rendered, 'OccurrenceUploadRequest(<redacted>)');
      expect(sent.rendered, isNot(contains(_secretA)));
    });
  });

  group('resuming each applicable pause after a correction', () {
    // **Validates: Requirements RF-16.6Ã¢â‚¬â€œ8, RF-18.5Ã¢â‚¬â€œ6, RNF-03.10, RNF-05.5**
    const statusByReason = <DeliveryPauseReason, int>{
      DeliveryPauseReason.authentication: 401,
      DeliveryPauseReason.access: 403,
      DeliveryPauseReason.unexpectedResponse: 418,
    };
    final corrections = <String,
        ({
      Future<void> Function(_App app) apply,
      Uri url,
      String secret,
    })>{
      'credential': (
        apply: (app) async {
          expect(await app.saveCredential(_secretB), isA<CredentialSaved>());
        },
        url: _urlA,
        secret: _secretB,
      ),
      'destination': (
        apply: (app) async {
          expect(
            await app.saveParameters(_draft(baseUrl: _urlBText)),
            isA<OperationalParametersSaved>(),
          );
        },
        url: _urlB,
        secret: _secretA,
      ),
      'destination edited together with operational values': (
        apply: (app) async {
          expect(
            await app.saveParameters(
              _draft(baseUrl: _urlBText, cooldown: '9', fps: '3'),
            ),
            isA<OperationalParametersSaved>(),
          );
        },
        url: _urlB,
        secret: _secretA,
      ),
    };

    setUp(open);

    for (final reason in statusByReason.entries) {
      for (final correction in corrections.entries) {
        test(
            '${reason.key.name} is resolved by a corrected ${correction.key}, '
            'also after reopening', () async {
          h.transport.respondWith(TransportHttpResponse(reason.value));
          await h.app.driver.evaluate();
          expect(h.app.driver.last, _Outcome.pausedByResponse);
          final paused = await h.app.control() as DeliveryControlPaused;
          expect(paused.reason, reason.key);
          await h.app.driver.evaluate();
          expect(h.app.driver.last, _Outcome.paused);
          expect(h.transport.sent, hasLength(1));
          _expectSent(h.transport.sent.single, _urlA, _secretA);

          final readsBeforeReopen = h.credentials.secretReads;
          await h.reopen();
          await h.app.driver.evaluate();
          expect(h.app.driver.outcomes, <_Outcome>[_Outcome.paused]);
          expect(h.transport.sent, hasLength(1));
          expect(h.credentials.secretReads, readsBeforeReopen);

          await correction.value.apply(h.app);
          expect(await h.app.control(), isA<DeliveryControlRunning>());
          expect(h.app.driver.evaluationRequests, 1,
              reason: 'One immediate evaluation, not one per cleared pause.');

          await h.app.driver.evaluate();
          expect(h.app.driver.last, _Outcome.delivered);
          expect(h.transport.sent, hasLength(2));
          _expectSent(
            h.transport.sent.last,
            correction.value.url,
            correction.value.secret,
          );
        });
      }
    }

    test(
        'a correction that was persisted survives a restart before the '
        'evaluation', () async {
      h.transport.respondWith(const TransportHttpResponse(401));
      await h.app.driver.evaluate();
      await h.app.saveCredential(_secretB);

      await h.reopen();
      expect(h.app.driver.evaluationRequests, 0);
      await h.app.driver.evaluate();

      expect(h.app.driver.outcomes, <_Outcome>[_Outcome.delivered]);
      _expectSent(h.transport.sent.last, _urlA, _secretB);
      expect(h.transport.sent.last.revision, 0,
          reason: 'The revision is process-local and restarts.');
    });

    test('a failed correction keeps the pause, also after reopening', () async {
      h.transport.respondWith(const TransportHttpResponse(403));
      await h.app.driver.evaluate();
      h.credentials.saveError = StateError('keystore failure');

      expect(await h.app.saveCredential(_secretB), isA<CredentialSaveFailed>());
      await h.reopen();
      await h.app.driver.evaluate();

      expect(h.app.driver.outcomes, <_Outcome>[_Outcome.paused]);
      expect(h.transport.sent, hasLength(1));
    });

    test('a local failure pause is not a configuration problem and stays',
        () async {
      await h.pause(DeliveryPauseReason.localFailure);

      await h.app.saveCredential(_secretB);
      await h.app.saveParameters(_draft(baseUrl: _urlBText));
      expect(h.app.driver.evaluationRequests, 2);
      await h.reopen();
      await h.app.driver.evaluate();

      expect(h.app.driver.outcomes, <_Outcome>[_Outcome.paused]);
      expect(h.transport.sent, isEmpty);

      expect(
          await h.app.deliveryQueue.resume(), DeliveryMutationResult.applied);
      await h.app.driver.evaluate();
      expect(h.app.driver.last, _Outcome.delivered);
      _expectSent(h.transport.sent.single, _urlB, _secretB);
    });
  });

  group('removal without network', () {
    // **Validates: Requirements RF-13.22Ã¢â‚¬â€œ26, RF-16.6Ã¢â‚¬â€œ8, RNF-02, RNF-05.5**
    setUp(open);

    test('removing the credential requires configuration and opens nothing',
        () async {
      expect(
        await h.app.removeCredential(CredentialRemovalConfirmation.confirmed),
        isA<CredentialRemoved>(),
      );
      expect(h.transport.sent, isEmpty, reason: 'Removing opens no socket.');
      expect(h.app.driver.evaluationRequests, 1);

      await h.app.driver.evaluate();

      expect(h.app.driver.outcomes, <_Outcome>[_Outcome.configurationRequired]);
      expect(h.app.port.imageOpens, 0);
      expect(h.transport.sent, isEmpty);
      expect(h.transport.cancelActiveCalls, 1);
    });

    test('removing the destination requires configuration and opens nothing',
        () async {
      expect(
        await h.app.saveParameters(_draft(baseUrl: '')),
        isA<OperationalParametersSaved>(),
      );
      await h.app.driver.evaluate();

      expect(h.app.driver.outcomes, <_Outcome>[_Outcome.configurationRequired]);
      expect(h.credentials.secretReads, 0);
      expect(h.app.port.imageOpens, 0);
      expect(h.transport.sent, isEmpty);
    });

    test('restoring only half of the pair stays without network', () async {
      await h.app.removeCredential(CredentialRemovalConfirmation.confirmed);
      await h.app.saveParameters(_draft(baseUrl: ''));

      await h.app.saveParameters(_draft(baseUrl: _urlBText));
      await h.app.driver.evaluate();
      expect(h.app.driver.last, _Outcome.configurationRequired);
      expect(h.transport.sent, isEmpty);

      await h.app.saveCredential(_secretB);
      await h.app.driver.evaluate();
      expect(h.app.driver.last, _Outcome.delivered);
      _expectSent(h.transport.sent.single, _urlB, _secretB);
    });

    test('removal keeps every clearable pause, also after reopening', () async {
      for (final reason in configurationClearablePauses) {
        await h.pause(reason);
        h.credentials.secret = _secretA;

        await h.app.removeCredential(CredentialRemovalConfirmation.confirmed);
        await h.app.saveParameters(_draft(baseUrl: ''));
        await h.reopen();
        await h.app.driver.evaluate();

        final control = await h.app.control() as DeliveryControlPaused;
        expect(control.reason, reason);
        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.paused]);
        h.repository.baseUrl = _urlA;
      }
      expect(h.transport.sent, isEmpty);
    });

    test('after a removal during a pause, a new credential resumes delivery',
        () async {
      await h.pause(DeliveryPauseReason.authentication);
      await h.app.removeCredential(CredentialRemovalConfirmation.confirmed);
      await h.reopen();

      await h.app.saveCredential(_secretB);
      await h.app.driver.evaluate();

      expect(await h.app.control(), isA<DeliveryControlRunning>());
      expect(h.app.driver.last, _Outcome.delivered);
      _expectSent(h.transport.sent.single, _urlA, _secretB);
    });
  });

  group('operational changes preserve the pause', () {
    // **Validates: Requirements RF-13.1Ã¢â‚¬â€œ17, RF-16.6Ã¢â‚¬â€œ8, RNF-05.5**
    final edits = <String, SettingsDraft Function()>{
      'cooldown': () => _draft(cooldown: '9'),
      'distance': () => _draft(distance: '30'),
      'confidence': () => _draft(confidence: '0.8'),
      'FPS': () => _draft(fps: '3'),
    };

    setUp(open);

    for (final edit in edits.entries) {
      test('changing only ${edit.key} keeps every pause and sends nothing',
          () async {
        for (final reason in DeliveryPauseReason.values) {
          await h.pause(reason);

          expect(
            await h.app.saveParameters(edit.value()),
            isA<OperationalParametersSaved>(),
          );

          final control = await h.app.control() as DeliveryControlPaused;
          expect(control.reason, reason);
        }
        expect(h.app.driver.suspendCalls, 0);
        expect(h.app.driver.evaluationRequests, 0);
        expect(h.app.snapshot.revision, 0);
        expect(h.transport.sent, isEmpty);

        await h.app.driver.evaluate();
        await h.reopen();
        await h.app.driver.evaluate();
        expect(h.app.driver.outcomes, <_Outcome>[_Outcome.paused]);
        expect(h.transport.sent, isEmpty);
      });
    }

    test('an edit with nothing paused still triggers no delivery', () async {
      await h.app.saveParameters(_draft(cooldown: '9', fps: '3'));

      expect(h.app.driver.evaluationRequests, 0);
      expect(h.app.driver.outcomes, isEmpty);
      expect(h.transport.sent, isEmpty);
      expect(h.credentials.secretReads, 0);
    });

    test('an edit during an upload neither cancels it nor retires its pair',
        () async {
      final upload = h.transport.holdNext();
      final started = h.transport.nextSendStarted();
      final attempt = h.app.driver.evaluate();
      await started;

      await h.app.saveParameters(_draft(distance: '30'));
      expect(h.transport.cancelActiveCalls, 0);
      expect(h.app.snapshot.isCurrent(0), isTrue);

      upload.complete(const TransportHttpResponse(201));
      await attempt;

      expect(h.app.driver.outcomes, <_Outcome>[_Outcome.delivered]);
      expect(h.app.driver.evaluationRequests, 0);
    });

    test('an edit during preparation keeps the snapshot usable', () async {
      final attempt = (await startHeldInPreparation()).attempt;

      await h.app.saveParameters(_draft(confidence: '0.8'));
      h.app.driver.releasePreparation();
      await attempt;

      expect(h.app.driver.outcomes, <_Outcome>[_Outcome.delivered]);
      _expectSent(h.transport.sent.single, _urlA, _secretA);
      expect(h.transport.sent.single.revision, 0);
    });
  });
}

InMemoryOccurrence _occurrence({
  required String key,
  required DateTime detectedAt,
  required List<int> bytes,
  required int width,
  required int height,
}) {
  return const InMemoryOccurrenceFactory().createManual(
    idempotencyKey: key,
    detectedAt: detectedAt,
    location: ImmutableLocationSnapshot(
      point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      accuracyMeters: null,
      speedMetersPerSecond: null,
    ),
    image: _Lease(bytes, width, height),
  );
}

List<int> _jpeg({required int width, required int height, required int red}) {
  final image = image_codec.Image(width: width, height: height);
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
