import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/delivery/device_credential_read_port.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/infrastructure/device_credential_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/shared_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesStore', () {
    test('round-trips and removes non-secret configuration strings', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'existing': 'stored-value',
      });
      final store = await SharedPreferencesStore.create();

      expect(await store.getString('existing'), 'stored-value');
      expect(await store.getString('missing'), isNull);
      expect(
          await store.setString('configuration', 'versioned-document'), isTrue);
      expect(await store.getString('configuration'), 'versioned-document');
      expect(await store.remove('configuration'), isTrue);
      expect(await store.getString('configuration'), isNull);
    });
  });

  group('DeviceCredentialStore', () {
    // **Validates: Requirements RF-13.6–8,22–24, RF-19.9–17, RNF-02.4–6,11–13, RNF-03.10**
    test(
        'reports status without reading a value and supports replacement and removal',
        () async {
      final backend = _FakeSecureCredentialBackend();
      final DeviceCredentialStatusPort store = DeviceCredentialStore(
        backend: backend,
      );

      expect(await store.hasCredential(), isFalse);
      expect(backend.readCount, 0);

      await store.saveCredential(_submittedCredential(1));
      await store.saveCredential(_submittedCredential(2));
      expect(backend.writeCount, 2);
      expect(backend.lastWriteKey, DeviceCredentialStore.credentialKey);
      expect(backend.receivedValue, isTrue);
      expect(await store.hasCredential(), isTrue);
      expect(backend.readCount, 0);

      await store.removeCredential();
      expect(backend.deleteCount, 1);
      expect(backend.lastDeleteKey, DeviceCredentialStore.credentialKey);
      expect(await store.hasCredential(), isFalse);
      expect(backend.readCount, 0);
    });

    // **Validates: Requirements RF-13.6–8, RF-19.9–10, RNF-02.2,4–6, RNF-03.10**
    test('propagates secure storage failures without including credential data',
        () async {
      final store = DeviceCredentialStore(
        backend: _FakeSecureCredentialBackend(failWrites: true),
      );

      await expectLater(
        store.saveCredential(_submittedCredential(3)),
        throwsA(isA<StateError>()),
      );
    });

    // **Validates: Requirements RF-13.6–8, RF-19.9–10, RNF-02.4–6, RNF-03.10**
    test('reports controlled status lookup and deletion storage failures',
        () async {
      final containsFailure = DeviceCredentialStore(
        backend: _FakeSecureCredentialBackend(failContains: true),
      );
      final deleteFailure = DeviceCredentialStore(
        backend: _FakeSecureCredentialBackend(failDeletes: true),
      );

      await expectLater(
          containsFailure.hasCredential(), throwsA(isA<StateError>()));
      await expectLater(
        deleteFailure.removeCredential(),
        throwsA(isA<StateError>()),
      );
    });

    // **Validates: Requirements RF-13.6–8,22–24, RF-16.6–8, RNF-02.4–6, RNF-03.10**
    test('readForDelivery returns the stored credential as a redacted secret',
        () async {
      final secret = _submittedCredential(1);
      final backend = _FakeSecureCredentialBackend(storedValue: secret);
      final DeviceCredentialReadPort store =
          DeviceCredentialStore(backend: backend);

      final result = await store.readForDelivery();

      expect(result, isA<CredentialAvailable>());
      expect((result as CredentialAvailable).secret.reveal(), secret);
      expect(backend.readCount, 1);
      _expectNoLeak(result, secret);
      _expectNoLeak(result.secret, secret);
    });

    test('readForDelivery reports a missing credential', () async {
      final store = DeviceCredentialStore(
        backend: _FakeSecureCredentialBackend(),
      );

      final result = await store.readForDelivery();

      expect(result, isA<CredentialMissing>());
    });

    test('readForDelivery reports invalid formats without the value', () async {
      for (final stored in <String>[
        '',
        'semseparador',
        '.segredo',
        'prefixo.',
        ' .segredo',
        'prefixo. ',
      ]) {
        final store = DeviceCredentialStore(
          backend: _FakeSecureCredentialBackend(storedValue: stored),
        );

        final result = await store.readForDelivery();

        expect(result, isA<CredentialInvalidFormat>(), reason: 'for "$stored"');
        if (stored.isNotEmpty) {
          _expectNoLeak(result, stored);
        }
      }
    });

    test('readForDelivery maps backend failures without raw exceptions',
        () async {
      final secret = _submittedCredential(2);
      final store = DeviceCredentialStore(
        backend: _FakeSecureCredentialBackend(
          storedValue: secret,
          failReads: true,
        ),
      );

      final result = await store.readForDelivery();

      expect(result, isA<CredentialStorageUnavailable>());
      _expectNoLeak(result, secret);
      _expectNoLeak(result, 'StateError');
    });
  });
}

/// Asserts that no implicit rendering of [object] exposes [fragment].
void _expectNoLeak(Object object, String fragment) {
  expect(object.toString(), isNot(contains(fragment)));
  expect('$object', isNot(contains(fragment)));
  if (object is NonPrintableSecret) {
    expect(jsonEncode(object), isNot(contains(fragment)));
  }
}

String _submittedCredential(int suffix) => String.fromCharCodes(<int>[
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

final class _FakeSecureCredentialBackend implements SecureCredentialBackend {
  _FakeSecureCredentialBackend({
    this.failContains = false,
    this.failWrites = false,
    this.failDeletes = false,
    this.failReads = false,
    String? storedValue,
  })  : _storedValue = storedValue,
        _hasCredential = storedValue != null;

  final bool failContains;
  final bool failWrites;
  final bool failDeletes;
  final bool failReads;
  String? _storedValue;
  bool _hasCredential;
  bool receivedValue = false;
  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;
  String? lastWriteKey;
  String? lastDeleteKey;

  @override
  Future<bool> containsKey(String key) async {
    if (failContains) {
      throw StateError('secure storage unavailable');
    }
    return _hasCredential;
  }

  @override
  Future<String?> read(String key) async {
    readCount++;
    if (failReads) {
      throw StateError('secure storage unavailable $_storedValue');
    }
    return _storedValue;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) {
      throw StateError('secure storage unavailable');
    }
    deleteCount++;
    lastDeleteKey = key;
    _storedValue = null;
    _hasCredential = false;
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) {
      throw StateError('secure storage unavailable');
    }
    writeCount++;
    lastWriteKey = key;
    receivedValue = value.isNotEmpty;
    _storedValue = value;
    _hasCredential = true;
  }
}
