import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' as glados;
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';
import 'package:pavimenta_ai_mobile/infrastructure/operational_configuration_store.dart';

void main() {
  group('SharedPreferencesOperationalConfigurationStore', () {
    // **Validates: Requirements RF-19.4, RF-19.5, RNF-03.6**
    test('loads approved defaults when the document is absent', () async {
      final preferences = _FakePreferencesStore();
      final store = SharedPreferencesOperationalConfigurationStore(
        preferences: preferences,
      );

      expect(await store.load(), _hasApprovedDefaults());
      expect(preferences.readKeys, <String>[
        SharedPreferencesOperationalConfigurationStore.storageKey,
      ]);
    });

    // **Validates: Requirements RF-13.1–5, RF-19.2–5, RNF-03.6**
    test('saves and reloads every non-secret field in one versioned document',
        () async {
      final preferences = _FakePreferencesStore();
      final store = SharedPreferencesOperationalConfigurationStore(
        preferences: preferences,
      );
      final configuration = OperationalConfiguration(
        baseUrl: Uri.parse('https://settings.example.invalid'),
        cooldown: const Duration(milliseconds: 5250),
        minimumDistanceMeters: 19.75,
        confidenceThreshold: 0.25,
        maximumInferenceFps: 7.5,
      );

      await store.save(configuration);

      expect(preferences.writeCount, 1);
      expect(
        preferences.writtenKeys,
        <String>[SharedPreferencesOperationalConfigurationStore.storageKey],
      );
      final document =
          jsonDecode(preferences.values.values.single) as Map<String, dynamic>;
      expect(
          document['version'], OperationalConfiguration.currentStorageVersion);
      expect(document.containsKey('deviceApiKey'), isFalse);
      expect(document.containsKey('credential'), isFalse);

      final loaded = await store.load();
      expect(loaded.baseUrl, configuration.baseUrl);
      expect(loaded.cooldown, configuration.cooldown);
      expect(loaded.minimumDistanceMeters, configuration.minimumDistanceMeters);
      expect(loaded.confidenceThreshold, configuration.confidenceThreshold);
      expect(loaded.maximumInferenceFps, configuration.maximumInferenceFps);
    });

    // **Validates: Requirements RF-19.4, RF-19.5, RNF-03.6**
    test('defaults only absent fields in a valid versioned document', () async {
      final preferences = _FakePreferencesStore(initialValues: <String, String>{
        SharedPreferencesOperationalConfigurationStore.storageKey: jsonEncode(
          <String, Object?>{
            'version': OperationalConfiguration.currentStorageVersion,
            'minimumDistanceMeters': 24,
            'maximumInferenceFps': 9,
          },
        ),
      });
      final store = SharedPreferencesOperationalConfigurationStore(
        preferences: preferences,
      );

      final loaded = await store.load();

      expect(loaded.baseUrl, isNull);
      expect(loaded.cooldown, OperationalConfiguration.defaultCooldown);
      expect(loaded.minimumDistanceMeters, 24);
      expect(
        loaded.confidenceThreshold,
        OperationalConfiguration.defaultConfidenceThreshold,
      );
      expect(loaded.maximumInferenceFps, 9);
    });

    // **Validates: Requirements RF-19.4–5, RNF-03.6**
    test('recovers safely from malformed or invalid persisted documents',
        () async {
      final events = <String>[];
      final preferences = _FakePreferencesStore(initialValues: <String, String>{
        SharedPreferencesOperationalConfigurationStore.storageKey:
            '{not-a-configuration-document',
      });
      final store = SharedPreferencesOperationalConfigurationStore(
        preferences: preferences,
        logTechnicalEvent: events.add,
      );

      expect(await store.load(), _hasApprovedDefaults());
      expect(events, <String>['operational_configuration_corrupt']);

      preferences.values[SharedPreferencesOperationalConfigurationStore
          .storageKey] = jsonEncode(<String, Object?>{
        'version': OperationalConfiguration.currentStorageVersion,
        'cooldownMicroseconds': 0,
      });
      expect(await store.load(), _hasApprovedDefaults());
      expect(events.last, 'operational_configuration_corrupt');
    });

    // **Validates: Requirements RF-13.6–8, RF-19.4–5, RNF-02.1–3, RNF-03.6,10**
    test('logs only a sanitized event for corrupt persisted data', () async {
      final credentialLikeValue = String.fromCharCodes(<int>[
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
      ]);
      final events = <String>[];
      final preferences = _FakePreferencesStore(
        initialValues: <String, String>{
          SharedPreferencesOperationalConfigurationStore.storageKey: jsonEncode(
            <String, Object?>{
              'version': OperationalConfiguration.currentStorageVersion,
              'baseUrl': credentialLikeValue,
            },
          ),
        },
      );
      final store = SharedPreferencesOperationalConfigurationStore(
        preferences: preferences,
        logTechnicalEvent: events.add,
      );

      expect(await store.load(), _hasApprovedDefaults());
      expect(events, <String>['operational_configuration_corrupt']);
      expect(events.single, isNot(contains(credentialLikeValue)));
    });

    // **Validates: Requirements RF-19.4–5, RNF-03.6**
    test('recovers to defaults from an unsupported document version', () async {
      final events = <String>[];
      final preferences = _FakePreferencesStore(initialValues: <String, String>{
        SharedPreferencesOperationalConfigurationStore.storageKey: jsonEncode(
          <String, Object?>{
            'version': OperationalConfiguration.currentStorageVersion + 1,
          },
        ),
      });
      final store = SharedPreferencesOperationalConfigurationStore(
        preferences: preferences,
        logTechnicalEvent: events.add,
      );

      expect(await store.load(), _hasApprovedDefaults());
      expect(events, <String>['operational_configuration_unsupported_version']);
    });

    // **Validates: Requirements RNF-03.6, RNF-03.10**
    test('surfaces preference read and write faults as controlled failures',
        () async {
      final readStore = SharedPreferencesOperationalConfigurationStore(
        preferences: _FakePreferencesStore(failReads: true),
      );
      final writeStore = SharedPreferencesOperationalConfigurationStore(
        preferences: _FakePreferencesStore(writeResult: false),
      );

      await expectLater(
        readStore.load(),
        throwsA(
          isA<OperationalConfigurationStorageException>().having(
            (error) => error.failure,
            'failure',
            OperationalConfigurationStorageFailure.loadFailed,
          ),
        ),
      );
      await expectLater(
        writeStore.save(const OperationalConfiguration.defaults()),
        throwsA(
          isA<OperationalConfigurationStorageException>().having(
            (error) => error.failure,
            'failure',
            OperationalConfigurationStorageFailure.saveFailed,
          ),
        ),
      );
    });
  });

  // **Validates: Requirements RF-19.4–5, RNF-03.6**
  glados.Glados<int>(
    glados.any.positiveIntOrZero,
    glados.ExploreConfig(numRuns: 80),
  ).test('round-trips valid generated non-secret configuration values',
      (int seed) async {
    final preferences = _FakePreferencesStore();
    final store = SharedPreferencesOperationalConfigurationStore(
      preferences: preferences,
    );
    final configuration = OperationalConfiguration(
      baseUrl: seed.isEven
          ? Uri.parse('https://node${seed % 100000}.example.invalid')
          : null,
      cooldown: Duration(microseconds: 1 + seed % 10000000),
      minimumDistanceMeters: 0.25 + (seed % 100000) / 10,
      confidenceThreshold: (seed % 1001) / 1000,
      maximumInferenceFps: 0.25 + (seed % 100000) / 10,
    );

    await store.save(configuration);
    final loaded = await store.load();

    expect(loaded.baseUrl, configuration.baseUrl);
    expect(loaded.cooldown, configuration.cooldown);
    expect(loaded.minimumDistanceMeters, configuration.minimumDistanceMeters);
    expect(loaded.confidenceThreshold, configuration.confidenceThreshold);
    expect(loaded.maximumInferenceFps, configuration.maximumInferenceFps);
    expect(preferences.writeCount, 1);
  });
}

Matcher _hasApprovedDefaults() => isA<OperationalConfiguration>()
    .having((value) => value.baseUrl, 'base URL', isNull)
    .having(
      (value) => value.cooldown,
      'cooldown',
      OperationalConfiguration.defaultCooldown,
    )
    .having(
      (value) => value.minimumDistanceMeters,
      'minimum distance',
      OperationalConfiguration.defaultMinimumDistanceMeters,
    )
    .having(
      (value) => value.confidenceThreshold,
      'confidence threshold',
      OperationalConfiguration.defaultConfidenceThreshold,
    )
    .having(
      (value) => value.maximumInferenceFps,
      'maximum FPS',
      OperationalConfiguration.defaultMaximumInferenceFps,
    );

final class _FakePreferencesStore implements PreferencesStore {
  _FakePreferencesStore({
    Map<String, String>? initialValues,
    this.failReads = false,
    this.writeResult = true,
  }) : values = <String, String>{...?initialValues};

  final Map<String, String> values;
  final bool failReads;
  final bool writeResult;
  final List<String> readKeys = <String>[];
  final List<String> writtenKeys = <String>[];
  int writeCount = 0;

  @override
  Future<String?> getString(String key) async {
    readKeys.add(key);
    if (failReads) {
      throw StateError('preferences unavailable');
    }
    return values[key];
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    writeCount++;
    writtenKeys.add(key);
    if (writeResult) {
      values[key] = value;
    }
    return writeResult;
  }
}
