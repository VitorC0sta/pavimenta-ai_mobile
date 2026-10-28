import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e3_configuration_use_cases.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';

void main() {
  group('E3 configuration use cases', () {
    // **Validates: Requirements RF-13.14–16, RF-19.12, RNF-03.6,10**
    test('converts non-secret storage failure into a controlled result',
        () async {
      final repository = _FakeConfigurationRepository(failSaves: true);
      final saveParameters = SaveOperationalParameters(
        repository: repository,
        buildVariant: ConfigurationBuildVariant.release,
      );

      final result = await saveParameters(_validDraft());

      expect(result, isA<OperationalParametersSaveFailed>());
      expect(repository.saveAttempts, 1);
    });

    // **Validates: Requirements RF-13.6–8,17,22–23, RF-19.9–10,15–16, RNF-02.4–6,11–12, RNF-03.6,10**
    test('replaces a credential through a status-only port without reads',
        () async {
      final credentialStore = _FakeCredentialStatusPort();
      final saveCredential = SaveOrReplaceDeviceCredential(
        credentialStore: credentialStore,
      );

      expect(await credentialStore.hasCredential(), isFalse);
      expect(await saveCredential(_credential(1)), isA<CredentialSaved>());
      expect(await saveCredential(_credential(2)), isA<CredentialSaved>());

      expect(credentialStore.saveCount, 2);
      expect(await credentialStore.hasCredential(), isTrue);
      expect(credentialStore.readCount, 0);
    });

    // **Validates: Requirements RF-13.6–8,17,22–23, RF-19.9–10,14–16, RNF-02.2,4–6,11–12, RNF-03.6,10**
    test(
        'returns a sanitized failure when credential storage rejects a replacement',
        () async {
      final credentialStore = _FakeCredentialStatusPort(failSaves: true);
      final saveCredential = SaveOrReplaceDeviceCredential(
        credentialStore: credentialStore,
      );
      final submittedCredential = _credential(3);

      final result = await saveCredential(submittedCredential);

      expect(result, isA<CredentialSaveFailed>());
      expect(result.toString(), isNot(contains(submittedCredential)));
      expect(credentialStore.saveCount, 1);
      expect(credentialStore.readCount, 0);
    });

    // **Validates: Requirements RF-13.24, RF-19.17, RNF-02.13, RNF-03.6,10**
    test(
        'requires confirmation before removal and keeps removal failures controlled',
        () async {
      final unconfirmedStore = _FakeCredentialStatusPort();
      final removeUnconfirmed = RemoveDeviceCredential(
        credentialStore: unconfirmedStore,
      );
      final failedStore = _FakeCredentialStatusPort(failRemovals: true);
      final removeFailed = RemoveDeviceCredential(credentialStore: failedStore);

      expect(
        await removeUnconfirmed(CredentialRemovalConfirmation.notConfirmed),
        isA<CredentialRemovalNeedsConfirmation>(),
      );
      expect(unconfirmedStore.removeCount, 0);

      expect(
        await removeFailed(CredentialRemovalConfirmation.confirmed),
        isA<CredentialRemovalFailed>(),
      );
      expect(failedStore.removeCount, 1);
      expect(failedStore.readCount, 0);
    });
  });
}

SettingsDraft _validDraft() => const SettingsDraft(
      baseUrlText: 'https://settings.example.invalid',
      cooldownSecondsText: '5',
      minimumDistanceMetersText: '15',
      confidenceThresholdText: '0.5',
      maximumInferenceFpsText: '5',
    );

String _credential(int suffix) => String.fromCharCodes(<int>[
      100,
      101,
      118,
      105,
      99,
      101,
      46,
      115,
      101,
      99,
      114,
      101,
      116,
      48 + suffix,
    ]);

final class _FakeConfigurationRepository
    implements OperationalConfigurationRepository {
  _FakeConfigurationRepository({this.failSaves = false});

  final bool failSaves;
  int saveAttempts = 0;

  @override
  Future<OperationalConfiguration> load() async =>
      const OperationalConfiguration.defaults();

  @override
  Future<void> save(OperationalConfiguration configuration) async {
    saveAttempts++;
    if (failSaves) {
      throw StateError('preferences unavailable');
    }
  }
}

final class _FakeCredentialStatusPort implements DeviceCredentialStatusPort {
  _FakeCredentialStatusPort({
    this.failSaves = false,
    this.failRemovals = false,
  });

  final bool failSaves;
  final bool failRemovals;
  bool _hasCredential = false;
  int saveCount = 0;
  int removeCount = 0;
  int readCount = 0;

  @override
  Future<bool> hasCredential() async => _hasCredential;

  @override
  Future<void> removeCredential() async {
    removeCount++;
    if (failRemovals) {
      throw StateError('secure storage unavailable');
    }
    _hasCredential = false;
  }

  @override
  Future<void> saveCredential(String credential) async {
    saveCount++;
    if (failSaves) {
      throw StateError('secure storage unavailable');
    }
    _hasCredential = true;
  }
}
