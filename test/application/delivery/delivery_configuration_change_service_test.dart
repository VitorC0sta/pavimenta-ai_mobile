import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_change_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_configuration_change_service.dart';
import 'package:pavimenta_ai_mobile/application/delivery/device_credential_read_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/exclusive_delivery_configuration_snapshot.dart';
import 'package:pavimenta_ai_mobile/application/delivery/occurrence_delivery_queue_port.dart';
import 'package:pavimenta_ai_mobile/application/e3_configuration_use_cases.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';

// Explicitly fictitious values; none is a real destination or key.
final Uri _urlA = Uri.parse('https://old.example.invalid');
final Uri _urlB = Uri.parse('https://new.example.invalid');
const String _secretA = 'oldprefix.old-secret-for-tests-only';
const String _secretB = 'newprefix.new-secret-for-tests-only';

/// Records every observable step in one list so tests can assert ordering.
final class _Log {
  final List<String> events = <String>[];
}

final class _FakeDelivery implements DeliveryConfigurationChangePort {
  _FakeDelivery(this._log);

  final _Log _log;
  Completer<void>? suspendGate;
  Object? onChangedError;
  int evaluationRequests = 0;

  @override
  Future<void> suspendForConfigurationChange() async {
    _log.events.add('suspend:start');
    final gate = suspendGate;
    if (gate != null) {
      await gate.future;
    }
    _log.events.add('suspend:done');
  }

  @override
  void onConfigurationChanged() {
    evaluationRequests++;
    _log.events.add('evaluate');
    final error = onChangedError;
    if (error != null) {
      throw error;
    }
  }
}

/// Only the pause control is used by the service; any other member fails loudly.
final class _FakeQueue implements OccurrenceDeliveryQueuePort {
  _FakeQueue(this._log, this.control);

  final _Log _log;
  DeliveryControl control;
  Object? readError;
  Object? resumeError;
  int resumeCalls = 0;

  @override
  Future<DeliveryControl> readControl() async {
    _log.events.add('readControl');
    final error = readError;
    if (error != null) {
      throw error;
    }
    return control;
  }

  @override
  Future<DeliveryMutationResult> resume() async {
    resumeCalls++;
    _log.events.add('resume');
    final error = resumeError;
    if (error != null) {
      throw error;
    }
    control = const DeliveryControlRunning();
    return DeliveryMutationResult.applied;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

final class _FakeRepository implements OperationalConfigurationRepository {
  _FakeRepository(this._log, {this.baseUrl});

  final _Log _log;
  Uri? baseUrl;
  Object? loadError;
  Object? saveError;
  int saveCalls = 0;

  @override
  Future<OperationalConfiguration> load() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return _document(baseUrl);
  }

  @override
  Future<void> save(OperationalConfiguration configuration) async {
    saveCalls++;
    _log.events.add('write:url');
    final error = saveError;
    if (error != null) {
      throw error;
    }
    baseUrl = configuration.baseUrl;
  }
}

OperationalConfiguration _document(Uri? baseUrl) => OperationalConfiguration(
      baseUrl: baseUrl,
      cooldown: OperationalConfiguration.defaultCooldown,
      minimumDistanceMeters:
          OperationalConfiguration.defaultMinimumDistanceMeters,
      confidenceThreshold: OperationalConfiguration.defaultConfidenceThreshold,
      maximumInferenceFps: OperationalConfiguration.defaultMaximumInferenceFps,
    );

final class _FakeCredentialStore
    implements DeviceCredentialStatusPort, DeviceCredentialReadPort {
  _FakeCredentialStore(this._log, {this.secret});

  final _Log _log;
  String? secret;
  Object? saveError;
  Object? removeError;

  @override
  Future<bool> hasCredential() async => secret != null;

  @override
  Future<void> saveCredential(String credential) async {
    _log.events.add('write:credential');
    final error = saveError;
    if (error != null) {
      throw error;
    }
    secret = credential;
  }

  @override
  Future<void> removeCredential() async {
    _log.events.add('remove:credential');
    final error = removeError;
    if (error != null) {
      throw error;
    }
    secret = null;
  }

  @override
  Future<CredentialReadResult> readForDelivery() async {
    final stored = secret;
    return stored == null
        ? const CredentialMissing()
        : CredentialAvailable(NonPrintableSecret(stored));
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Log log;
  late _FakeDelivery delivery;
  late _FakeQueue queue;
  late _FakeRepository repository;
  late _FakeCredentialStore credentials;
  late ExclusiveDeliveryConfigurationSnapshot snapshot;
  late DeliveryConfigurationChangeService service;
  late SaveOrReplaceDeviceCredential saveCredential;
  late SaveOperationalParameters saveParameters;

  late RemoveDeviceCredential removeCredential;

  setUp(() {
    log = _Log();
    delivery = _FakeDelivery(log);
    queue = _FakeQueue(
      log,
      DeliveryControlPaused(DeliveryPauseReason.authentication),
    );
    repository = _FakeRepository(log, baseUrl: _urlA);
    credentials = _FakeCredentialStore(log, secret: _secretA);
    snapshot = ExclusiveDeliveryConfigurationSnapshot(
      configurationRepository: repository,
      credentialReader: credentials,
      buildVariant: ConfigurationBuildVariant.release,
    );
    service = DeliveryConfigurationChangeService(
      snapshot: snapshot,
      queue: queue,
      delivery: delivery,
    );
    saveCredential = SaveOrReplaceDeviceCredential(
      credentialStore: credentials,
      deliveryChange: service,
    );
    removeCredential = RemoveDeviceCredential(
      credentialStore: credentials,
      deliveryChange: service,
    );
    saveParameters = SaveOperationalParameters(
      repository: repository,
      buildVariant: ConfigurationBuildVariant.release,
      deliveryChange: service,
    );
  });

  SettingsDraft draft({
    String baseUrl = 'https://new.example.invalid',
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

  group('credential replacement', () {
    // **Validates: Requirements RF-13.22–26, RF-16.6–8, RF-18.5–6, RNF-05.5**
    test(
        'suspends the old attempt, writes, clears the pause, then evaluates once',
        () async {
      final result = await saveCredential(_secretB);

      expect(result, isA<CredentialSaved>());
      expect(credentials.secret, _secretB);
      expect(log.events, <String>[
        'suspend:start',
        'suspend:done',
        'write:credential',
        'readControl',
        'resume',
        'evaluate',
      ]);
      expect(queue.control, isA<DeliveryControlRunning>());
      expect(delivery.evaluationRequests, 1);
    });

    test('does not write before the old attempt is suspended', () async {
      delivery.suspendGate = Completer<void>();

      final saving = saveCredential(_secretB);
      await _flush();

      expect(log.events, <String>['suspend:start']);
      expect(credentials.secret, _secretA);

      delivery.suspendGate!.complete();
      await saving;
      expect(credentials.secret, _secretB);
    });

    test('invalidates snapshots taken before the replacement', () async {
      final before =
          (await snapshot.readForAttempt() as DeliveryConfigurationAvailable)
              .configuration;
      final revision = before.revision;
      expect(snapshot.isCurrent(revision), isTrue);

      await saveCredential(_secretB);

      expect(snapshot.isCurrent(revision), isFalse);
      expect(snapshot.isCurrent(snapshot.revision), isTrue);
    });

    test('keeps the pause and still evaluates once when the write fails',
        () async {
      credentials.saveError = StateError('keystore failure with $_secretB');

      final result = await saveCredential(_secretB);

      expect(result, isA<CredentialSaveFailed>());
      expect('$result', isNot(contains(_secretB)));
      expect(queue.control, isA<DeliveryControlPaused>());
      expect(queue.resumeCalls, 0);
      expect(log.events, isNot(contains('readControl')));
      expect(delivery.evaluationRequests, 1);
    });

    test('validation failure never reaches delivery', () async {
      final result = await saveCredential('no-separator');

      expect(result, isA<CredentialInvalid>());
      expect(log.events, isEmpty);
    });
  });

  group('pause clearing', () {
    // **Validates: Requirements RF-16.6, RF-18.5, RNF-03.10**
    for (final reason in <DeliveryPauseReason>[
      DeliveryPauseReason.authentication,
      DeliveryPauseReason.access,
      DeliveryPauseReason.unexpectedResponse,
    ]) {
      test('clears the ${reason.name} pause', () async {
        queue.control = DeliveryControlPaused(
          reason,
          unexpectedStatusCode:
              reason == DeliveryPauseReason.unexpectedResponse ? 418 : null,
        );

        await saveCredential(_secretB);

        expect(queue.control, isA<DeliveryControlRunning>());
        expect(queue.resumeCalls, 1);
        expect(delivery.evaluationRequests, 1);
      });
    }

    test('keeps a localFailure pause but still requests the evaluation',
        () async {
      queue.control = DeliveryControlPaused(DeliveryPauseReason.localFailure);

      await saveCredential(_secretB);

      expect(queue.control, isA<DeliveryControlPaused>());
      expect(queue.resumeCalls, 0);
      expect(delivery.evaluationRequests, 1);
    });

    test('does not write the control when delivery is running or unreadable',
        () async {
      queue.control = const DeliveryControlRunning();
      await saveCredential(_secretB);
      queue.control = const DeliveryControlUnavailable();
      await saveCredential(_secretA);

      expect(queue.resumeCalls, 0);
      expect(delivery.evaluationRequests, 2);
    });

    test('a failing control does not fail the confirmed write', () async {
      queue.readError = StateError('db failure');
      expect(await saveCredential(_secretB), isA<CredentialSaved>());

      queue.readError = null;
      queue.resumeError = StateError('db failure');
      expect(await saveCredential(_secretA), isA<CredentialSaved>());

      expect(credentials.secret, _secretA);
      expect(delivery.evaluationRequests, 2);
    });

    test('a failing evaluation request does not fail the confirmed write',
        () async {
      delivery.onChangedError = StateError('coordinator failure');

      expect(await saveCredential(_secretB), isA<CredentialSaved>());
      expect(delivery.evaluationRequests, 1);
    });
  });

  group('BASE_URL save', () {
    // **Validates: Requirements RF-13.1–17, RF-16.6–8, RF-18.5–6, RNF-05.5**
    test('a new destination follows the same suspend, write, clear, evaluate',
        () async {
      final result = await saveParameters(draft());

      expect(result, isA<OperationalParametersSaved>());
      expect(repository.baseUrl, _urlB);
      expect(log.events, <String>[
        'suspend:start',
        'suspend:done',
        'write:url',
        'readControl',
        'resume',
        'evaluate',
      ]);
      expect(snapshot.revision, 1);
    });

    test('an operational-only edit leaves delivery and the pause untouched',
        () async {
      repository.baseUrl = _urlB;

      final result = await saveParameters(draft(cooldown: '9'));

      expect(result, isA<OperationalParametersSaved>());
      expect(repository.saveCalls, 1);
      expect(log.events, <String>['write:url']);
      expect(queue.control, isA<DeliveryControlPaused>());
      expect(delivery.evaluationRequests, 0);
      expect(snapshot.revision, 0);
    });

    test('an unreadable current destination is handled as a change', () async {
      repository.loadError = StateError('preferences failure');

      await saveParameters(draft());

      expect(log.events.first, 'suspend:start');
      expect(log.events, contains('resume'));
      expect(delivery.evaluationRequests, 1);
    });

    test('a failed write keeps the pause and evaluates once', () async {
      repository.saveError = StateError('preferences failure');

      final result = await saveParameters(draft());

      expect(result, isA<OperationalParametersSaveFailed>());
      expect(queue.resumeCalls, 0);
      expect(delivery.evaluationRequests, 1);
    });

    test('removing the destination suspends and evaluates but clears nothing',
        () async {
      await service.saveOperationalConfiguration<void>(
        readCurrentBaseUrl: () async => _urlA,
        newBaseUrl: null,
        write: () => repository.save(_document(null)),
      );

      expect(log.events, <String>[
        'suspend:start',
        'suspend:done',
        'write:url',
        'evaluate',
      ]);
      expect(queue.control, isA<DeliveryControlPaused>());
    });
  });

  group('removal without network', () {
    // **Validates: Requirements RF-13.22–26, RF-16.6–8, RNF-05.5**
    test(
        'credential removal suspends, removes, keeps the pause, evaluates once',
        () async {
      final result =
          await removeCredential(CredentialRemovalConfirmation.confirmed);

      expect(result, isA<CredentialRemoved>());
      expect(credentials.secret, isNull);
      expect(log.events, <String>[
        'suspend:start',
        'suspend:done',
        'remove:credential',
        'evaluate',
      ]);
      expect(queue.control, isA<DeliveryControlPaused>());
      expect(queue.resumeCalls, 0);
      expect(snapshot.revision, 1);
    });

    test('after removal the snapshot reports the credential as missing',
        () async {
      await removeCredential(CredentialRemovalConfirmation.confirmed);

      final result = await snapshot.readForAttempt();

      expect(result, isNot(isA<DeliveryConfigurationAvailable>()));
    });

    test('an unconfirmed removal never reaches delivery', () async {
      final result =
          await removeCredential(CredentialRemovalConfirmation.notConfirmed);

      expect(result, isA<CredentialRemovalNeedsConfirmation>());
      expect(credentials.secret, _secretA);
      expect(log.events, isEmpty);
    });

    test('a failed removal keeps the credential and the pause, evaluates once',
        () async {
      credentials.removeError = StateError('keystore failure');

      final result =
          await removeCredential(CredentialRemovalConfirmation.confirmed);

      expect(result, isA<CredentialRemovalFailed>());
      expect(credentials.secret, _secretA);
      expect(queue.resumeCalls, 0);
      expect(delivery.evaluationRequests, 1);
    });

    test('erasing BASE_URL through settings clears no pause and evaluates once',
        () async {
      final result = await saveParameters(draft(baseUrl: ''));

      expect(result, isA<OperationalParametersSaved>());
      expect(repository.baseUrl, isNull);
      expect(log.events, <String>[
        'suspend:start',
        'suspend:done',
        'write:url',
        'evaluate',
      ]);
      expect(queue.control, isA<DeliveryControlPaused>());
      expect(queue.resumeCalls, 0);
      expect(snapshot.revision, 1);
    });

    test('removal does not clear any pause reason, including a clearable one',
        () async {
      for (final reason in configurationClearablePauses) {
        queue.control = DeliveryControlPaused(
          reason,
          unexpectedStatusCode:
              reason == DeliveryPauseReason.unexpectedResponse ? 418 : null,
        );
        credentials.secret = _secretA;

        await removeCredential(CredentialRemovalConfirmation.confirmed);

        expect(queue.control, isA<DeliveryControlPaused>(), reason: '$reason');
      }
      expect(queue.resumeCalls, 0);
    });
  });

  group('operational-only edits', () {
    // **Validates: Requirements RF-13.1–17, RF-16.6–8, RNF-05.5**
    final edits = <String, SettingsDraft Function()>{
      'cooldown': () => draft(cooldown: '9'),
      'distance': () => draft(distance: '30'),
      'confidence': () => draft(confidence: '0.8'),
      'FPS': () => draft(fps: '3'),
    };

    for (final entry in edits.entries) {
      test('changing only ${entry.key} keeps the pause and requests nothing',
          () async {
        repository.baseUrl = _urlB;

        final result = await saveParameters(entry.value());

        expect(result, isA<OperationalParametersSaved>());
        expect(log.events, <String>['write:url']);
        expect(queue.control, isA<DeliveryControlPaused>());
        expect(queue.resumeCalls, 0);
        expect(delivery.evaluationRequests, 0);
        expect(snapshot.revision, 0);
      });
    }

    test('an operational edit with no destination at all stays inert',
        () async {
      repository.baseUrl = null;

      await saveParameters(draft(baseUrl: '', fps: '3'));

      expect(log.events, <String>['write:url']);
      expect(queue.control, isA<DeliveryControlPaused>());
      expect(delivery.evaluationRequests, 0);
    });
  });

  group('exclusion', () {
    // **Validates: Requirements RF-13.14–16, RNF-03.6, RNF-05.5**
    test('a snapshot requested during a change sees only the new pair',
        () async {
      final release = Completer<void>();
      final replacing = service.replaceDestinationOrCredential<void>(() async {
        repository.baseUrl = _urlB;
        await release.future; // Destination written, credential not yet.
        credentials.secret = _secretB;
      });
      await _flush();

      final read = snapshot.readForAttempt();
      await _flush();
      release.complete();
      await replacing;

      final configuration =
          (await read as DeliveryConfigurationAvailable).configuration;
      expect(configuration.baseUrl, _urlB);
      expect(configuration.credential.reveal(), _secretB);
      expect(snapshot.isCurrent(configuration.revision), isTrue);
    });
  });
}
