import 'package:flutter/foundation.dart';

import '../application/e3_configuration_use_cases.dart';
import '../application/e3_storage_ports.dart';
import '../domain/configuration_validators.dart';
import '../domain/operational_configuration.dart';
import 'settings_state.dart';

/// Coordinates E3 configuration presentation without retaining a credential.
///
/// Non-secret operational parameters and the credential are intentionally
/// saved through independent actions. This prevents a secure-store issue from
/// changing the non-secret configuration, and vice versa.
final class SettingsController extends ChangeNotifier {
  SettingsController({
    required OperationalConfigurationRepository configurationRepository,
    required DeviceCredentialStatusPort credentialStore,
    ConfigurationBuildVariant? buildVariant,
    ConfigurationChangeGuard? deliveryChange,
  })  : _configurationRepository = configurationRepository,
        _credentialStore = credentialStore,
        _saveParameters = SaveOperationalParameters(
          repository: configurationRepository,
          buildVariant: buildVariant ??
              (kDebugMode
                  ? ConfigurationBuildVariant.debug
                  : ConfigurationBuildVariant.release),
          deliveryChange: deliveryChange,
        ),
        _saveCredential = SaveOrReplaceDeviceCredential(
          credentialStore: credentialStore,
          deliveryChange: deliveryChange,
        ),
        _removeCredential = RemoveDeviceCredential(
          credentialStore: credentialStore,
          deliveryChange: deliveryChange,
        ),
        _state = SettingsState.loading();

  final OperationalConfigurationRepository _configurationRepository;
  final DeviceCredentialStatusPort _credentialStore;
  final SaveOperationalParameters _saveParameters;
  final SaveOrReplaceDeviceCredential _saveCredential;
  final RemoveDeviceCredential _removeCredential;

  SettingsState _state;
  bool _disposed = false;

  SettingsState get state => _state;

  /// Loads independent E3 stores before their respective save action is ready.
  ///
  /// A failure is intentionally contained to its own section, allowing the
  /// other action to remain usable when its store loaded successfully.
  Future<void> load() async {
    if (_disposed) {
      return;
    }
    _publish(
      _state.copyWith(
        isLoading: true,
        isConfigurationReady: false,
        isCredentialStatusReady: false,
        credentialError: null,
        feedback: null,
      ),
    );

    final configurationFuture = _loadConfiguration();
    final credentialStatusFuture = _loadCredentialStatus();
    final results =
        await Future.wait([configurationFuture, credentialStatusFuture]);
    if (_disposed) {
      return;
    }

    final configuration = results[0] as _ConfigurationLoadResult;
    final credential = results[1] as _CredentialStatusLoadResult;
    _publish(
      _state.copyWith(
        draft: configuration.draft ?? _state.draft,
        isLoading: false,
        isConfigurationReady: configuration.isReady,
        isCredentialStatusReady: credential.isReady,
        credentialStatus: credential.status ?? _state.credentialStatus,
        feedback: configuration.failed || credential.failed
            ? const SettingsFeedback(
                kind: SettingsFeedbackKind.error,
                message:
                    'Não foi possível carregar todas as configurações. Tente novamente.',
              )
            : null,
      ),
    );
  }

  /// Saves the non-secret draft independently from the credential action.
  Future<void> saveParameters(SettingsDraft draft) async {
    if (_disposed || !_state.canSaveParameters) {
      return;
    }
    _publish(
      _state.copyWith(
        isSavingParameters: true,
        feedback: null,
      ),
    );

    final result = await _saveParameters(draft);
    if (_disposed) {
      return;
    }

    switch (result) {
      case OperationalParametersSaved(:final configuration):
        _publish(
          _state.copyWith(
            draft: _draftFromConfiguration(configuration),
            isSavingParameters: false,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.success,
              message: 'Parâmetros salvos.',
            ),
          ),
        );
      case OperationalParametersInvalid(:final draft):
        _publish(
          _state.copyWith(
            draft: draft,
            isSavingParameters: false,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.error,
              message: 'Revise os campos indicados.',
            ),
          ),
        );
      case OperationalParametersSaveFailed():
        _publish(
          _state.copyWith(
            isSavingParameters: false,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.error,
              message:
                  'Não foi possível salvar os parâmetros. Tente novamente.',
            ),
          ),
        );
    }
  }

  /// Validates and saves a replacement credential without placing it in state.
  ///
  /// The return value only tells the caller whether it must clear its temporary
  /// text controller. It never returns, logs, or persists the submitted text.
  Future<bool> saveCredential(String submittedCredential) async {
    if (_disposed || !_state.canSaveCredential) {
      return false;
    }
    _publish(
      _state.copyWith(
        isSavingCredential: true,
        credentialError: null,
        feedback: null,
      ),
    );

    final result = await _saveCredential(submittedCredential);
    if (_disposed) {
      return false;
    }

    switch (result) {
      case CredentialSaved():
        _publish(
          _state.copyWith(
            isSavingCredential: false,
            credentialStatus: DeviceCredentialStatus.configured,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.success,
              message: 'Chave salva com segurança.',
            ),
          ),
        );
        return true;
      case CredentialInvalid(:final errorMessage):
        _publish(
          _state.copyWith(
            isSavingCredential: false,
            credentialError: errorMessage,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.error,
              message: 'Revise o campo da chave.',
            ),
          ),
        );
        return false;
      case CredentialSaveFailed():
        _publish(
          _state.copyWith(
            isSavingCredential: false,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.error,
              message: 'Não foi possível salvar a chave. Tente novamente.',
            ),
          ),
        );
        return false;
    }
  }

  /// Removes the credential only when presentation passes explicit confirmation.
  ///
  /// The controller never treats an empty replacement field as removal. The
  /// result remains sanitized and returns no stored or submitted credential.
  Future<bool> removeCredential({
    required CredentialRemovalConfirmation confirmation,
  }) async {
    if (_disposed ||
        confirmation != CredentialRemovalConfirmation.confirmed ||
        !_state.canSaveCredential ||
        _state.credentialStatus != DeviceCredentialStatus.configured) {
      return false;
    }

    _publish(
      _state.copyWith(
        isSavingCredential: true,
        credentialError: null,
        feedback: null,
      ),
    );

    final result = await _removeCredential(confirmation);
    if (_disposed) {
      return false;
    }

    switch (result) {
      case CredentialRemoved():
        _publish(
          _state.copyWith(
            isSavingCredential: false,
            credentialStatus: DeviceCredentialStatus.notConfigured,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.success,
              message: 'Chave removida com segurança.',
            ),
          ),
        );
        return true;
      case CredentialRemovalNeedsConfirmation():
        _publish(
          _state.copyWith(
            isSavingCredential: false,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.error,
              message: 'Confirme a remoção da chave para continuar.',
            ),
          ),
        );
        return false;
      case CredentialRemovalFailed():
        _publish(
          _state.copyWith(
            isSavingCredential: false,
            feedback: const SettingsFeedback(
              kind: SettingsFeedbackKind.error,
              message: 'Não foi possível remover a chave. Tente novamente.',
            ),
          ),
        );
        return false;
    }
  }

  Future<_ConfigurationLoadResult> _loadConfiguration() async {
    try {
      final configuration = await _configurationRepository.load();
      return _ConfigurationLoadResult.ready(
          _draftFromConfiguration(configuration));
    } catch (_) {
      return const _ConfigurationLoadResult.failed();
    }
  }

  Future<_CredentialStatusLoadResult> _loadCredentialStatus() async {
    try {
      final hasCredential = await _credentialStore.hasCredential();
      return _CredentialStatusLoadResult.ready(
        hasCredential
            ? DeviceCredentialStatus.configured
            : DeviceCredentialStatus.notConfigured,
      );
    } catch (_) {
      return const _CredentialStatusLoadResult.failed();
    }
  }

  SettingsDraft _draftFromConfiguration(
      OperationalConfiguration configuration) {
    return SettingsDraft(
      baseUrlText: configuration.baseUrl?.toString() ?? '',
      cooldownSecondsText: _formatNumber(
        configuration.cooldown.inMicroseconds / Duration.microsecondsPerSecond,
      ),
      minimumDistanceMetersText:
          _formatNumber(configuration.minimumDistanceMeters),
      confidenceThresholdText: _formatNumber(configuration.confidenceThreshold),
      maximumInferenceFpsText: _formatNumber(configuration.maximumInferenceFps),
    );
  }

  String _formatNumber(num value) {
    final asDouble = value.toDouble();
    return asDouble == asDouble.roundToDouble()
        ? asDouble.toInt().toString()
        : asDouble.toString();
  }

  void _publish(SettingsState state) {
    if (_disposed) {
      return;
    }
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _ConfigurationLoadResult {
  const _ConfigurationLoadResult._({
    required this.isReady,
    required this.draft,
    required this.failed,
  });

  const _ConfigurationLoadResult.ready(SettingsDraft draft)
      : this._(isReady: true, draft: draft, failed: false);

  const _ConfigurationLoadResult.failed()
      : this._(isReady: false, draft: null, failed: true);

  final bool isReady;
  final SettingsDraft? draft;
  final bool failed;
}

final class _CredentialStatusLoadResult {
  const _CredentialStatusLoadResult._({
    required this.isReady,
    required this.status,
    required this.failed,
  });

  const _CredentialStatusLoadResult.ready(DeviceCredentialStatus status)
      : this._(isReady: true, status: status, failed: false);

  const _CredentialStatusLoadResult.failed()
      : this._(isReady: false, status: null, failed: true);

  final bool isReady;
  final DeviceCredentialStatus? status;
  final bool failed;
}
