import '../domain/operational_configuration.dart';

/// Sanitized feedback for the Settings route.
///
/// These messages are static and must never include submitted credentials,
/// stored values, paths, or technical exceptions.
enum SettingsFeedbackKind { success, error }

final class SettingsFeedback {
  const SettingsFeedback({required this.kind, required this.message});

  final SettingsFeedbackKind kind;
  final String message;
}

/// Immutable, presentation-safe snapshot for the E3 Settings route.
///
/// The only editable values held by this state are non-secret parameters.
/// Device credentials are represented exclusively by a boolean-like sanitized
/// status and a static validation message.
final class SettingsState {
  const SettingsState({
    required this.draft,
    required this.isLoading,
    required this.isConfigurationReady,
    required this.isCredentialStatusReady,
    required this.credentialStatus,
    required this.isSavingParameters,
    required this.isSavingCredential,
    required this.credentialError,
    required this.feedback,
  });

  factory SettingsState.loading() => SettingsState(
        draft: SettingsDraft(
          baseUrlText: '',
          cooldownSecondsText:
              _formatNumber(OperationalConfiguration.defaultCooldown.inSeconds),
          minimumDistanceMetersText: _formatNumber(
            OperationalConfiguration.defaultMinimumDistanceMeters,
          ),
          confidenceThresholdText: _formatNumber(
            OperationalConfiguration.defaultConfidenceThreshold,
          ),
          maximumInferenceFpsText: _formatNumber(
            OperationalConfiguration.defaultMaximumInferenceFps,
          ),
        ),
        isLoading: true,
        isConfigurationReady: false,
        isCredentialStatusReady: false,
        credentialStatus: DeviceCredentialStatus.notConfigured,
        isSavingParameters: false,
        isSavingCredential: false,
        credentialError: null,
        feedback: null,
      );

  final SettingsDraft draft;
  final bool isLoading;
  final bool isConfigurationReady;
  final bool isCredentialStatusReady;
  final DeviceCredentialStatus credentialStatus;
  final bool isSavingParameters;
  final bool isSavingCredential;
  final String? credentialError;
  final SettingsFeedback? feedback;

  bool get canSaveParameters =>
      isConfigurationReady && !isLoading && !isSavingParameters;

  bool get canSaveCredential =>
      isCredentialStatusReady && !isLoading && !isSavingCredential;

  SettingsState copyWith({
    SettingsDraft? draft,
    bool? isLoading,
    bool? isConfigurationReady,
    bool? isCredentialStatusReady,
    DeviceCredentialStatus? credentialStatus,
    bool? isSavingParameters,
    bool? isSavingCredential,
    Object? credentialError = _notProvided,
    Object? feedback = _notProvided,
  }) {
    return SettingsState(
      draft: draft ?? this.draft,
      isLoading: isLoading ?? this.isLoading,
      isConfigurationReady: isConfigurationReady ?? this.isConfigurationReady,
      isCredentialStatusReady:
          isCredentialStatusReady ?? this.isCredentialStatusReady,
      credentialStatus: credentialStatus ?? this.credentialStatus,
      isSavingParameters: isSavingParameters ?? this.isSavingParameters,
      isSavingCredential: isSavingCredential ?? this.isSavingCredential,
      credentialError: identical(credentialError, _notProvided)
          ? this.credentialError
          : credentialError as String?,
      feedback: identical(feedback, _notProvided)
          ? this.feedback
          : feedback as SettingsFeedback?,
    );
  }

  static String _formatNumber(num value) {
    final asDouble = value.toDouble();
    return asDouble == asDouble.roundToDouble()
        ? asDouble.toInt().toString()
        : asDouble.toString();
  }
}

const Object _notProvided = Object();
