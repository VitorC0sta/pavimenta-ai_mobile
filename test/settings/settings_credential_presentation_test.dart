import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/e3_configuration_use_cases.dart';
import 'package:pavimenta_ai_mobile/application/e3_storage_ports.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';
import 'package:pavimenta_ai_mobile/settings/settings_controller.dart';
import 'package:pavimenta_ai_mobile/settings/settings_screen.dart';

void main() {
  group('SettingsController credential removal', () {
    // **Validates: Requirements RF-13.24, RF-19.12, RF-19.17, RNF-02.4–6**
    test('removes a configured credential only after explicit confirmation',
        () async {
      final credentialStore = _FakeCredentialStore(isConfigured: true);
      final controller = _controller(credentialStore);
      addTearDown(controller.dispose);

      await controller.load();

      expect(
        await controller.removeCredential(
          confirmation: CredentialRemovalConfirmation.notConfirmed,
        ),
        isFalse,
      );
      expect(credentialStore.removeCount, 0);
      expect(
        controller.state.credentialStatus,
        DeviceCredentialStatus.configured,
      );

      expect(
        await controller.removeCredential(
          confirmation: CredentialRemovalConfirmation.confirmed,
        ),
        isTrue,
      );
      expect(credentialStore.removeCount, 1);
      expect(
        controller.state.credentialStatus,
        DeviceCredentialStatus.notConfigured,
      );
    });
  });

  group('SettingsScreen device credential', () {
    // **Validates: Requirements RF-13.18–20, RF-13.25–26, RNF-02.4–6**
    testWidgets(
      'guides rotation in Next.js when no credential is configured',
      (tester) async {
        final controller =
            _controller(_FakeCredentialStore(isConfigured: false));
        addTearDown(controller.dispose);

        await _pumpSettings(tester, controller);

        expect(find.text('Chave não configurada'), findsOneWidget);
        expect(
          find.byKey(const Key('credential-rotation-guidance')),
          findsOneWidget,
        );
        expect(
          find.textContaining('rotacioná-la na Administração Next.js'),
          findsOneWidget,
        );
        expect(
          find.textContaining('exibida uma única vez'),
          findsOneWidget,
        );
        expect(
          find.textContaining('O aplicativo não recupera chaves'),
          findsOneWidget,
        );
        expect(
          find.text('https://servidor-exemplo.invalid'),
          findsOneWidget,
        );
      },
    );
    // **Validates: Requirements RF-13.17, RF-13.22–23, RF-19.9–10, RNF-02.4–6**
    testWidgets(
      'shows only configured status, keeps the field empty, and requires a complete replacement',
      (tester) async {
        final credentialStore = _FakeCredentialStore(isConfigured: true);
        final controller = _controller(credentialStore);
        addTearDown(controller.dispose);

        await _pumpSettings(tester, controller);

        expect(find.text('Chave configurada'), findsOneWidget);
        expect(find.text('Chave não configurada'), findsNothing);
        expect(
            find.text('Colar chave completa para substituir'), findsOneWidget);
        expect(_credentialField(tester).controller!.text, isEmpty);

        await tester.ensureVisible(
          find.byKey(const Key('save-credential-button')),
        );
        await tester.tap(find.byKey(const Key('save-credential-button')));
        await tester.pumpAndSettle();

        expect(credentialStore.saveCount, 0);
        expect(find.text('Revise o campo da chave.'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('device-credential-field')),
          'teste.segredo',
        );
        await tester.tap(find.byKey(const Key('save-credential-button')));
        await tester.pumpAndSettle();

        expect(credentialStore.saveCount, 1);
        expect(_credentialField(tester).controller!.text, isEmpty);
        expect(find.text('Chave configurada'), findsOneWidget);
      },
    );

    // **Validates: Requirements RF-13.24, RF-19.17, RNF-02.4–6**
    testWidgets('removes the key only after the removal dialog is confirmed',
        (tester) async {
      final credentialStore = _FakeCredentialStore(isConfigured: true);
      final controller = _controller(credentialStore);
      addTearDown(controller.dispose);

      await _pumpSettings(tester, controller);

      await tester.ensureVisible(
        find.byKey(const Key('remove-credential-button')),
      );
      await tester.tap(find.byKey(const Key('remove-credential-button')));
      await tester.pumpAndSettle();
      expect(find.text('Remover chave?'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('cancel-remove-credential-button')),
      );
      await tester.pumpAndSettle();
      expect(credentialStore.removeCount, 0);
      expect(find.text('Chave configurada'), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove-credential-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('confirm-remove-credential-button')),
      );
      await tester.pumpAndSettle();

      expect(credentialStore.removeCount, 1);
      expect(find.text('Chave não configurada'), findsOneWidget);
      expect(find.byKey(const Key('remove-credential-button')), findsNothing);
      expect(_credentialField(tester).controller!.text, isEmpty);
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

TextField _credentialField(WidgetTester tester) {
  return tester.widget<TextField>(
    find.byKey(const Key('device-credential-field')),
  );
}

SettingsController _controller(_FakeCredentialStore credentialStore) {
  return SettingsController(
    configurationRepository: const _FakeConfigurationRepository(),
    credentialStore: credentialStore,
  );
}

final class _FakeConfigurationRepository
    implements OperationalConfigurationRepository {
  const _FakeConfigurationRepository();

  @override
  Future<OperationalConfiguration> load() async =>
      const OperationalConfiguration.defaults();

  @override
  Future<void> save(OperationalConfiguration configuration) async {}
}

final class _FakeCredentialStore implements DeviceCredentialStatusPort {
  _FakeCredentialStore({required bool isConfigured})
      : _isConfigured = isConfigured;

  bool _isConfigured;
  int saveCount = 0;
  int removeCount = 0;

  @override
  Future<bool> hasCredential() async => _isConfigured;

  @override
  Future<void> removeCredential() async {
    removeCount++;
    _isConfigured = false;
  }

  @override
  Future<void> saveCredential(String credential) async {
    saveCount++;
    _isConfigured = true;
  }
}
