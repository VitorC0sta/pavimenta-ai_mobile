import 'dart:async';

import 'package:flutter/material.dart';

import '../application/e3_configuration_use_cases.dart';
import '../domain/operational_configuration.dart';
import '../operation/operation_theme.dart';
import 'settings_controller.dart';
import 'settings_state.dart';

/// E3 settings presentation.
///
/// This route owns temporary text controllers only. In particular, the
/// credential controller is always empty on entry and is cleared after a
/// successful submission or when the route is disposed.
final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.controller, super.key});

  final SettingsController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _cooldownController;
  late final TextEditingController _minimumDistanceController;
  late final TextEditingController _confidenceController;
  late final TextEditingController _maximumFpsController;
  late final TextEditingController _credentialController;
  SettingsDraft? _displayedDraft;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _cooldownController = TextEditingController();
    _minimumDistanceController = TextEditingController();
    _confidenceController = TextEditingController();
    _maximumFpsController = TextEditingController();
    _credentialController = TextEditingController();
    widget.controller.addListener(_onControllerChanged);
    _syncDraft(widget.controller.state.draft);
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _baseUrlController.dispose();
    _cooldownController.dispose();
    _minimumDistanceController.dispose();
    _confidenceController.dispose();
    _maximumFpsController.dispose();
    _credentialController.clear();
    _credentialController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _syncDraft(widget.controller.state.draft);
  }

  void _syncDraft(SettingsDraft draft) {
    if (identical(_displayedDraft, draft)) {
      return;
    }
    _displayedDraft = draft;
    _baseUrlController.text = draft.baseUrlText;
    _cooldownController.text = draft.cooldownSecondsText;
    _minimumDistanceController.text = draft.minimumDistanceMetersText;
    _confidenceController.text = draft.confidenceThresholdText;
    _maximumFpsController.text = draft.maximumInferenceFpsText;
  }

  SettingsDraft _currentDraft() {
    return SettingsDraft(
      baseUrlText: _baseUrlController.text,
      cooldownSecondsText: _cooldownController.text,
      minimumDistanceMetersText: _minimumDistanceController.text,
      confidenceThresholdText: _confidenceController.text,
      maximumInferenceFpsText: _maximumFpsController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Scaffold(
          key: const Key('settings-screen'),
          appBar: AppBar(title: const Text('Configurações')),
          body: SafeArea(
            child: SingleChildScrollView(
              key: const Key('settings-scroll-view'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.isLoading) const _LoadingNotice(),
                      if (state.feedback case final feedback?) ...[
                        _FeedbackNotice(feedback: feedback),
                        const SizedBox(height: 16),
                      ],
                      _SettingsPanel(
                        title: 'Operação',
                        child: Column(
                          children: [
                            _NumberField(
                              key: const Key('cooldown-field'),
                              controller: _cooldownController,
                              enabled: state.canSaveParameters,
                              label: 'Cooldown',
                              unit: 's',
                              helper:
                                  'Padrão: 5 s. Informe um valor maior que zero.',
                              errorText: state.draft.cooldownSecondsError,
                            ),
                            const SizedBox(height: 16),
                            _NumberField(
                              key: const Key('minimum-distance-field'),
                              controller: _minimumDistanceController,
                              enabled: state.canSaveParameters,
                              label: 'Distância mínima',
                              unit: 'm',
                              helper:
                                  'Padrão: 15 m. Informe um valor maior que zero.',
                              errorText: state.draft.minimumDistanceMetersError,
                            ),
                            const SizedBox(height: 16),
                            _NumberField(
                              key: const Key('confidence-threshold-field'),
                              controller: _confidenceController,
                              enabled: state.canSaveParameters,
                              label: 'Limiar de confiança futuro',
                              helper:
                                  'Padrão: 0.5. Aceita valores entre 0 e 1.',
                              errorText: state.draft.confidenceThresholdError,
                            ),
                            const SizedBox(height: 16),
                            _NumberField(
                              key: const Key('maximum-fps-field'),
                              controller: _maximumFpsController,
                              enabled: state.canSaveParameters,
                              label: 'FPS máximo futuro',
                              unit: 'FPS',
                              helper:
                                  'Padrão: 5 FPS. Informe um valor maior que zero.',
                              errorText: state.draft.maximumInferenceFpsError,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SettingsPanel(
                        title: 'Destino futuro',
                        child: TextField(
                          key: const Key('base-url-field'),
                          controller: _baseUrlController,
                          enabled: state.canSaveParameters,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'BASE_URL (opcional)',
                            hintText: 'https://servidor-exemplo.invalid',
                            helperText:
                                'Não inclua /api/v1/occurrences. HTTPS é obrigatório fora do debug.',
                            errorText: state.draft.baseUrlError,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        key: const Key('save-parameters-button'),
                        onPressed: state.canSaveParameters
                            ? () => unawaited(
                                  controller.saveParameters(_currentDraft()),
                                )
                            : null,
                        icon: state.isSavingParameters
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          state.isSavingParameters
                              ? 'Salvando parâmetros'
                              : 'Salvar parâmetros',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SettingsPanel(
                        title: 'Credencial do dispositivo',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _CredentialStatus(status: state.credentialStatus),
                            if (state.credentialStatus ==
                                DeviceCredentialStatus.notConfigured) ...[
                              const SizedBox(height: 12),
                              const _CredentialRotationGuidance(),
                            ],
                            const SizedBox(height: 16),
                            TextField(
                              key: const Key('device-credential-field'),
                              controller: _credentialController,
                              enabled: state.canSaveCredential,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.visiblePassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) =>
                                  _saveCredential(controller, state),
                              decoration: InputDecoration(
                                labelText: state.credentialStatus ==
                                        DeviceCredentialStatus.configured
                                    ? 'Colar chave completa para substituir'
                                    : 'Colar chave completa',
                                helperText: state.credentialStatus ==
                                        DeviceCredentialStatus.configured
                                    ? 'Para trocar a chave, informe o novo valor completo.'
                                    : 'A chave é salva separadamente dos parâmetros.',
                                errorText: state.credentialError,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              key: const Key('save-credential-button'),
                              onPressed: state.canSaveCredential
                                  ? () => _saveCredential(controller, state)
                                  : null,
                              icon: state.isSavingCredential
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.lock_outline),
                              label: Text(
                                state.isSavingCredential
                                    ? 'Salvando chave'
                                    : state.credentialStatus ==
                                            DeviceCredentialStatus.configured
                                        ? 'Substituir chave'
                                        : 'Salvar chave',
                              ),
                            ),
                            if (state.credentialStatus ==
                                DeviceCredentialStatus.configured) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key('remove-credential-button'),
                                onPressed: state.canSaveCredential
                                    ? () =>
                                        _confirmCredentialRemoval(controller)
                                    : null,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Remover chave'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!state.isConfigurationReady ||
                          !state.isCredentialStatusReady) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          key: const Key('retry-settings-load-button'),
                          onPressed: state.isLoading
                              ? null
                              : () => unawaited(controller.load()),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar carregar novamente'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCredentialRemoval(
    SettingsController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover chave?'),
        content: const Text(
          'A chave configurada será removida deste dispositivo.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-remove-credential-button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-remove-credential-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover chave'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    final wasRemoved = await controller.removeCredential(
      confirmation: CredentialRemovalConfirmation.confirmed,
    );
    if (wasRemoved && mounted) {
      _credentialController.clear();
    }
  }

  void _saveCredential(SettingsController controller, SettingsState state) {
    if (!state.canSaveCredential) {
      return;
    }
    unawaited(() async {
      final wasSaved =
          await controller.saveCredential(_credentialController.text);
      if (wasSaved && mounted) {
        _credentialController.clear();
      }
    }());
  }
}

final class _CredentialStatus extends StatelessWidget {
  const _CredentialStatus({required this.status});

  final DeviceCredentialStatus status;

  @override
  Widget build(BuildContext context) {
    final label = status == DeviceCredentialStatus.configured
        ? 'Chave configurada'
        : 'Chave não configurada';
    return Semantics(
      key: const Key('device-credential-status'),
      liveRegion: true,
      label: label,
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

final class _CredentialRotationGuidance extends StatelessWidget {
  const _CredentialRotationGuidance();

  static const _message =
      'Se a chave foi perdida ou não foi copiada, peça a um administrador '
      'para rotacioná-la na Administração Next.js. Copie a nova chave '
      'completa exibida uma única vez e cole-a aqui. O aplicativo não '
      'recupera chaves já exibidas.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('credential-rotation-guidance'),
      container: true,
      label: _message,
      child: const Text(_message),
    );
  }
}

final class _LoadingNotice extends StatelessWidget {
  const _LoadingNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Carregando configurações',
      child: const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(),
      ),
    );
  }
}

final class _FeedbackNotice extends StatelessWidget {
  const _FeedbackNotice({required this.feedback});

  final SettingsFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final isError = feedback.kind == SettingsFeedbackKind.error;
    final color = isError ? OperationPalette.error : OperationPalette.success;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;
    return Semantics(
      liveRegion: true,
      container: true,
      label: feedback.message,
      child: Container(
        key: const Key('settings-feedback'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(feedback.message)),
          ],
        ),
      ),
    );
  }
}

final class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

final class _NumberField extends StatelessWidget {
  const _NumberField({
    required super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    required this.helper,
    required this.errorText,
    this.unit,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String? unit;
  final String helper;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        helperText: helper,
        errorText: errorText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
