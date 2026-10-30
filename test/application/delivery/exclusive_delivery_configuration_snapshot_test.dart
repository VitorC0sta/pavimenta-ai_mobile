import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/delivery/device_credential_read_port.dart';
import 'package:pavimenta_ai_mobile/application/delivery/exclusive_delivery_configuration_snapshot.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';

// Explicitly fictitious values; none is a real destination or key.
final Uri _urlA = Uri.parse('https://old.example.invalid');
final Uri _urlB = Uri.parse('https://new.example.invalid');
const String _secretA = 'oldprefix.old-secret-for-tests-only';
const String _secretB = 'newprefix.new-secret-for-tests-only';

final class _FakeRepository implements OperationalConfigurationRepository {
  Uri? baseUrl;
  Object? loadError;
  int loadCount = 0;

  @override
  Future<OperationalConfiguration> load() async {
    loadCount++;
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return OperationalConfiguration(
      baseUrl: baseUrl,
      cooldown: OperationalConfiguration.defaultCooldown,
      minimumDistanceMeters:
          OperationalConfiguration.defaultMinimumDistanceMeters,
      confidenceThreshold: OperationalConfiguration.defaultConfidenceThreshold,
      maximumInferenceFps: OperationalConfiguration.defaultMaximumInferenceFps,
    );
  }

  @override
  Future<void> save(OperationalConfiguration configuration) async {
    baseUrl = configuration.baseUrl;
  }
}

final class _FakeCredentialReader implements DeviceCredentialReadPort {
  String? secret;
  CredentialReadResult? forcedResult;
  Object? readError;
  Completer<void>? gate;
  int readCount = 0;

  @override
  Future<CredentialReadResult> readForDelivery() async {
    readCount++;
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
    final error = readError;
    if (error != null) {
      throw error;
    }
    final forced = forcedResult;
    if (forced != null) {
      return forced;
    }
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
  late _FakeRepository repository;
  late _FakeCredentialReader reader;
  late ExclusiveDeliveryConfigurationSnapshot port;

  setUp(() {
    repository = _FakeRepository()..baseUrl = _urlA;
    reader = _FakeCredentialReader()..secret = _secretA;
    port = ExclusiveDeliveryConfigurationSnapshot(
      configurationRepository: repository,
      credentialReader: reader,
      buildVariant: ConfigurationBuildVariant.release,
    );
  });

  group('revalidation before transport', () {
    // **Validates: Requirements RF-13.9–17, RF-16.6–8, RNF-02, RNF-03.6**
    test(
        'rejects a stored destination that breaks the BASE_URL rules without '
        'reading the credential', () async {
      final invalid = <Uri>[
        Uri.parse('http://old.example.invalid'), // not HTTPS
        Uri.parse('http://localhost:3000'), // debug-only exception
        Uri.parse('https://old.example.invalid/api/v1/occurrences'),
        Uri.parse('https://user:pass@old.example.invalid'),
        Uri.parse('https://old.example.invalid?x=1'),
        Uri.parse('https://old.example.invalid#frag'),
        Uri.parse('/relative/only'),
      ];

      for (final url in invalid) {
        repository.baseUrl = url;
        final result = await port.readForAttempt();

        expect(result, isA<DeliveryDestinationInvalid>(), reason: '$url');
        expect('$result', isNot(contains('example.invalid')));
      }
      expect(reader.readCount, 0, reason: 'No valid destination, no key read.');
    });

    test('keeps the debug localhost exception only for debug builds', () async {
      repository.baseUrl = Uri.parse('http://localhost:3000');
      final debugPort = ExclusiveDeliveryConfigurationSnapshot(
        configurationRepository: repository,
        credentialReader: reader,
        buildVariant: ConfigurationBuildVariant.debug,
      );

      final result = await debugPort.readForAttempt();

      expect(result, isA<DeliveryConfigurationAvailable>());
      expect(await port.readForAttempt(), isA<DeliveryDestinationInvalid>());
    });

    test('normalizes a destination that only carries a root path', () async {
      repository.baseUrl = Uri.parse('https://old.example.invalid/');

      final configuration =
          (await port.readForAttempt() as DeliveryConfigurationAvailable)
              .configuration;

      expect(configuration.baseUrl.path, isEmpty);
      expect(configuration.baseUrl.host, 'old.example.invalid');
    });

    test(
        'rejects an available credential that is not prefix.secret even if '
        'the reader accepted it', () async {
      for (final malformed in <String>[
        'no-separator-secret',
        '.only-secret',
        'only-prefix.',
        ' .  ',
      ]) {
        reader.forcedResult = CredentialAvailable(
          NonPrintableSecret(malformed),
        );

        final result = await port.readForAttempt();

        expect(result, isA<DeliveryCredentialInvalidFormat>(),
            reason: 'shape: "$malformed"');
        expect('$result', isNot(contains(malformed)));
      }
    });

    test('accepts the minimum prefix.secret shape', () async {
      reader.forcedResult = CredentialAvailable(NonPrintableSecret('p.s'));

      expect(
          await port.readForAttempt(), isA<DeliveryConfigurationAvailable>());
    });

    test('a keystore failure is a controlled local state and recovers later',
        () async {
      reader.readError = StateError('keystore raw failure $_secretA');
      final first = await port.readForAttempt();
      expect(first, isA<DeliverySecureStorageUnavailable>());
      expect('$first', isNot(contains('keystore')));

      reader.readError = null;
      expect(
          await port.readForAttempt(), isA<DeliveryConfigurationAvailable>());
    });
  });

  group('snapshot results', () {
    // **Validates: Requirements RF-13.1–17, RF-16.6–8, RNF-02, RNF-03.6**
    test('returns the destination and credential of the current revision',
        () async {
      final result = await port.readForAttempt();

      expect(result, isA<DeliveryConfigurationAvailable>());
      final configuration =
          (result as DeliveryConfigurationAvailable).configuration;
      expect(configuration.revision, 0);
      expect(configuration.baseUrl, _urlA);
      expect(configuration.credential.reveal(), _secretA);
    });

    test('maps every missing, invalid, and unavailable state', () async {
      repository.baseUrl = null;
      expect(await port.readForAttempt(), isA<DeliveryConfigurationMissing>());
      expect(reader.readCount, 0, reason: 'No destination, no secret read.');

      repository.baseUrl = _urlA;
      reader.secret = null;
      expect(await port.readForAttempt(), isA<DeliveryConfigurationMissing>());

      reader.forcedResult = const CredentialInvalidFormat();
      expect(
        await port.readForAttempt(),
        isA<DeliveryCredentialInvalidFormat>(),
      );

      reader.forcedResult = const CredentialStorageUnavailable();
      expect(
        await port.readForAttempt(),
        isA<DeliverySecureStorageUnavailable>(),
      );
    });

    test('turns reader or repository failures into controlled results',
        () async {
      reader.readError = StateError('raw failure containing $_secretA');
      final unavailable = await port.readForAttempt();
      expect(unavailable, isA<DeliverySecureStorageUnavailable>());
      expect('$unavailable', isNot(contains(_secretA)));

      repository.loadError = StateError('raw failure');
      expect(await port.readForAttempt(), isA<DeliveryConfigurationMissing>());
    });

    test('never renders the secret or the destination', () async {
      final result = await port.readForAttempt();
      final configuration =
          (result as DeliveryConfigurationAvailable).configuration;

      for (final text in <String>['$result', '$configuration']) {
        expect(text, isNot(contains('secret')));
        expect(text, isNot(contains('example.invalid')));
      }
    });
  });

  group('local revision', () {
    // **Validates: Requirements RF-13.22–26, RF-18.5–6, RNF-03.10**
    test('stays stable without mutations and grows once per mutation',
        () async {
      final seen = <int>[];
      for (var i = 0; i < 3; i++) {
        final result = await port.readForAttempt();
        seen.add(
          (result as DeliveryConfigurationAvailable).configuration.revision,
        );
        await port.runConfigurationMutation<void>(() async {});
      }

      expect(seen, <int>[0, 1, 2]);
      expect(port.revision, 3);
    });

    test('invalidates earlier snapshots after a mutation', () async {
      final first =
          (await port.readForAttempt() as DeliveryConfigurationAvailable)
              .configuration;
      expect(port.isCurrent(first.revision), isTrue);

      await port.runConfigurationMutation<void>(() async {
        repository.baseUrl = _urlB;
      });

      expect(port.isCurrent(first.revision), isFalse);
      final second =
          (await port.readForAttempt() as DeliveryConfigurationAvailable)
              .configuration;
      expect(second.revision, greaterThan(first.revision));
      expect(port.isCurrent(second.revision), isTrue);
      expect(second.baseUrl, _urlB);
    });

    test('advances even when the mutation fails and keeps the failure',
        () async {
      await expectLater(
        port.runConfigurationMutation<void>(() async => throw StateError('x')),
        throwsStateError,
      );

      expect(port.revision, 1);
      // The exclusion is released: later work still runs.
      expect(
          await port.readForAttempt(), isA<DeliveryConfigurationAvailable>());
    });

    test('reports no revision as current while a mutation is writing',
        () async {
      final release = Completer<void>();
      final mutation = port.runConfigurationMutation<void>(
        () => release.future,
      );
      await _flush();

      expect(port.isCurrent(port.revision), isFalse);

      release.complete();
      await mutation;
      expect(port.isCurrent(port.revision), isTrue);
    });
  });

  group('mutual exclusion', () {
    // **Validates: Requirements RF-13.22–26, RF-16.6–8, RNF-05.5**
    test('a read started during a mutation sees only the new pair', () async {
      final release = Completer<void>();
      final mutation = port.runConfigurationMutation<void>(() async {
        repository.baseUrl = _urlB;
        await release.future; // Destination written, credential not yet.
        reader.secret = _secretB;
      });
      await _flush();

      final read = port.readForAttempt();
      await _flush();
      expect(repository.loadCount, 0, reason: 'The read must wait.');
      expect(reader.readCount, 0);

      release.complete();
      await mutation;
      final configuration =
          (await read as DeliveryConfigurationAvailable).configuration;

      expect(configuration.baseUrl, _urlB);
      expect(configuration.credential.reveal(), _secretB);
      expect(configuration.revision, 1);
    });

    test('a mutation requested during a read waits and leaves the old pair',
        () async {
      reader.gate = Completer<void>();
      final read = port.readForAttempt();
      await _flush();
      expect(reader.readCount, 1);

      var mutationStarted = false;
      final mutation = port.runConfigurationMutation<void>(() async {
        mutationStarted = true;
        repository.baseUrl = _urlB;
        reader.secret = _secretB;
      });
      await _flush();
      expect(mutationStarted, isFalse, reason: 'The mutation must wait.');

      reader.gate!.complete();
      final configuration =
          (await read as DeliveryConfigurationAvailable).configuration;
      await mutation;

      expect(configuration.baseUrl, _urlA);
      expect(configuration.credential.reveal(), _secretA);
      expect(configuration.revision, 0);
      expect(mutationStarted, isTrue);
      expect(port.isCurrent(configuration.revision), isFalse);
    });

    test('runs sections in request order and survives a failing one', () async {
      final order = <String>[];
      final first = port.runConfigurationMutation<void>(() async {
        await _flush();
        order.add('first');
        throw StateError('x');
      });
      final firstOutcome = expectLater(first, throwsStateError);
      final second = port.runConfigurationMutation<String>(() async {
        order.add('second');
        return 'done';
      });
      final read = port.readForAttempt().then((_) => order.add('read'));

      await firstOutcome;
      expect(await second, 'done');
      await read;

      expect(order, <String>['first', 'second', 'read']);
      expect(port.revision, 2);
    });
  });
}
