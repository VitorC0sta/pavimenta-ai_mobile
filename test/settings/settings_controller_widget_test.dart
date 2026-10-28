import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';
import 'package:pavimenta_ai_mobile/settings/settings_controller.dart';
import 'package:pavimenta_ai_mobile/settings/settings_screen.dart';

void main() {
  group('SettingsController E3 loading and saving', () {
    // **Validates: Requirements RF-19.1–8, RNF-02.6, RNF-04.2**
    testWidgets('loads defaults before enabling independent save actions',
        (tester) async {
      final repository = _ControlledConfigurationRepository();
      final credentialStore = _ControlledCredentialStore();
      final controller = _controller(repository, credentialStore);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(controller: controller)),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Carregando configurações'), findsOneWidget);
      expect(_button(tester, 'save-parameters-button').onPressed, isNull);
      expect(_button(tester, 'save-credential-button').onPressed, isNull);

      repository.completeLoad(const OperationalConfiguration.defaults());
      credentialStore.completeStatus(isConfigured: false);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Carregando configurações'), findsNothing);
      expect(_field(tester, 'base-url-field').controller!.text, isEmpty);
      expect(_field(tester, 'cooldown-field').controller!.text, '5');
      expect(_field(tester, 'minimum-distance-field').controller!.text, '15');
      expect(
        _field(tester, 'confidence-threshold-field').controller!.text,
        '0.5',
      );
      expect(_field(tester, 'maximum-fps-field').controller!.text, '5');
      expect(_button(tester, 'save-parameters-button').onPressed, isNotNull);
      expect(_button(tester, 'save-credential-button').onPressed, isNotNull);
    });

    // **Validates: Requirements RF-13.1, RF-13.17, RF-19.4–8, RNF-03.6**
    testWidgets(
        'keeps absent URL and credential optional while rejecting invalid parameter saves',
        (tester) async {
      final repository = _ConfigurationRepository();
      final credentialStore = _CredentialStore();
      final controller = _controller(repository, credentialStore);
      addTearDown(controller.dispose);

      await _pumpSettings(tester, controller);

      expect(find.text('Chave não configurada'), findsOneWidget);
      expect(_field(tester, 'base-url-field').controller!.text, isEmpty);
      expect(_button(tester, 'save-parameters-button').onPressed, isNotNull);
      expect(_button(tester, 'save-credential-button').onPressed, isNotNull);

      await tester.enterText(_editable('cooldown-field'), '0');
      await _tap(tester, 'save-parameters-button');
      await tester.pumpAndSettle();

      expect(repository.saved, isEmpty);
      expect(find.text('Informe um valor maior que zero.'), findsOneWidget);
      expect(find.text('Revise os campos indicados.'), findsOneWidget);

      await tester.enterText(_editable('cooldown-field'), '7');
      await _tap(tester, 'save-parameters-button');
      await tester.pumpAndSettle();

      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.baseUrl, isNull);
      expect(repository.saved.single.cooldown, const Duration(seconds: 7));
      expect(find.text('Parâmetros salvos.'), findsOneWidget);
    });

    // **Validates: Requirements RF-13.6–8, RF-13.22–24, RF-19.9–10,15–17, RNF-02.4–6,11–13**
    testWidgets(
        'never renders or reconstructs a saved credential during replacement and removal',
        (tester) async {
      const originalCredential = 'device.original-secret';
      const replacementCredential = 'device.replacement-secret';
      final repository = _ConfigurationRepository();
      final credentialStore = _CredentialStore(
        isConfigured: true,
        storedCredential: originalCredential,
      );
      final controller = _controller(repository, credentialStore);
      addTearDown(controller.dispose);

      await _pumpSettings(tester, controller);

      expect(find.text('Chave configurada'), findsOneWidget);
      expect(
          _field(tester, 'device-credential-field').controller!.text, isEmpty);
      _expectSecretAbsent(tester, originalCredential);

      await tester.enterText(
        _editable('device-credential-field'),
        replacementCredential,
      );
      await _tap(tester, 'save-credential-button');
      await tester.pumpAndSettle();

      expect(credentialStore.storedCredential, replacementCredential);
      expect(
          _field(tester, 'device-credential-field').controller!.text, isEmpty);
      _expectSecretAbsent(tester, originalCredential);
      _expectSecretAbsent(tester, replacementCredential);

      await _tap(tester, 'remove-credential-button');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('confirm-remove-credential-button')),
      );
      await tester.pumpAndSettle();

      expect(credentialStore.removeCount, 1);
      expect(credentialStore.storedCredential, isNull);
      expect(find.text('Chave não configurada'), findsOneWidget);
      expect(
          _field(tester, 'device-credential-field').controller!.text, isEmpty);
      _expectSecretAbsent(tester, replacementCredential);
    });

    // **Validates: Requirements RF-13.6–8, RF-19.9–10, RNF-02.2–6,11–14**
    testWidgets('contains storage failures with sanitized retryable feedback',
        (tester) async {
      const submittedCredential = 'device.submitted-secret';
      final repository = _ConfigurationRepository(throwOnSave: true);
      final credentialStore = _CredentialStore(throwOnSave: true);
      final controller = _controller(repository, credentialStore);
      addTearDown(controller.dispose);

      await _pumpSettings(tester, controller);

      await _tap(tester, 'save-parameters-button');
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível salvar os parâmetros. Tente novamente.'),
        findsOneWidget,
      );

      await tester.enterText(
        _editable('device-credential-field'),
        submittedCredential,
      );
      await _tap(tester, 'save-credential-button');
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível salvar a chave. Tente novamente.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings-feedback')), findsOneWidget);
      expect(credentialStore.storedCredential, isNull);
      expect(controller.state.credentialError, isNull);
      expect(controller.state.feedback!.message,
          isNot(contains(submittedCredential)));
      expect(tester.takeException(), isNull);
    });

    // **Validates: Requirements RF-13.7–8, RF-19.10–11,15, RNF-02.6,8,11, RNF-04.2**
    testWidgets(
        'announces credential state and keeps the narrow settings form usable',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = _controller(
        _ConfigurationRepository(),
        _CredentialStore(),
      );
      addTearDown(controller.dispose);

      await tester.binding.setSurfaceSize(const Size(320, 480));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
            ),
            child: SettingsScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final credentialStatus = tester.widget<Semantics>(
        find.byKey(const Key('device-credential-status')),
      );
      expect(credentialStatus.properties.label, 'Chave não configurada');
      final rotationGuidance = tester.widget<Semantics>(
        find.byKey(const Key('credential-rotation-guidance')),
      );
      expect(
        rotationGuidance.properties.label,
        contains('O aplicativo não recupera chaves já exibidas.'),
      );
      expect(find.byKey(const Key('settings-scroll-view')), findsOneWidget);

      await tester
          .ensureVisible(find.byKey(const Key('save-credential-button')));
      expect(_button(tester, 'save-credential-button').onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  SettingsController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(home: SettingsScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
}

ElevatedButton _button(WidgetTester tester, String key) {
  return tester.widget<ElevatedButton>(find.byKey(Key(key)));
}

TextField _field(WidgetTester tester, String key) {
  final target = find.byKey(Key(key));
  final widget = tester.widget<Widget>(target);
  if (widget is TextField) {
    return widget;
  }
  return tester.widget<TextField>(
    find.descendant(of: target, matching: find.byType(TextField)),
  );
}

Finder _editable(String key) {
  return find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(EditableText),
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
}

void _expectSecretAbsent(WidgetTester tester, String secret) {
  expect(find.textContaining(secret), findsNothing);
  for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
    expect(field.controller!.text, isNot(contains(secret)));
  }
}

SettingsController _controller(
  OperationalConfigurationRepository repository,
  DeviceCredentialStatusPort credentialStore,
) {
  return SettingsController(
    configurationRepository: repository,
    credentialStore: credentialStore,
  );
}

final class _ConfigurationRepository
    implements OperationalConfigurationRepository {
  _ConfigurationRepository({this.throwOnSave = false});

  final bool throwOnSave;
  final List<OperationalConfiguration> saved = <OperationalConfiguration>[];

  @override
  Future<OperationalConfiguration> load() async =>
      const OperationalConfiguration.defaults();

  @override
  Future<void> save(OperationalConfiguration configuration) async {
    if (throwOnSave) {
      throw StateError('configuration storage failure');
    }
    saved.add(configuration);
  }
}

final class _ControlledConfigurationRepository
    implements OperationalConfigurationRepository {
  final Completer<OperationalConfiguration> _load =
      Completer<OperationalConfiguration>();

  @override
  Future<OperationalConfiguration> load() => _load.future;

  void completeLoad(OperationalConfiguration configuration) =>
      _load.complete(configuration);

  @override
  Future<void> save(OperationalConfiguration configuration) async {}
}

final class _CredentialStore implements DeviceCredentialStatusPort {
  _CredentialStore({
    bool isConfigured = false,
    this.storedCredential,
    this.throwOnSave = false,
  }) : _isConfigured = isConfigured;

  bool _isConfigured;
  String? storedCredential;
  final bool throwOnSave;
  var removeCount = 0;

  @override
  Future<bool> hasCredential() async => _isConfigured;

  @override
  Future<void> removeCredential() async {
    removeCount++;
    _isConfigured = false;
    storedCredential = null;
  }

  @override
  Future<void> saveCredential(String credential) async {
    if (throwOnSave) {
      throw StateError('secure storage failure');
    }
    _isConfigured = true;
    storedCredential = credential;
  }
}

final class _ControlledCredentialStore implements DeviceCredentialStatusPort {
  final Completer<bool> _status = Completer<bool>();

  @override
  Future<bool> hasCredential() => _status.future;

  void completeStatus({required bool isConfigured}) =>
      _status.complete(isConfigured);

  @override
  Future<void> removeCredential() async {}

  @override
  Future<void> saveCredential(String credential) async {}
}
