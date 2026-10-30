import '../domain/configuration_validators.dart';
import '../domain/operational_configuration.dart';
import 'e3_storage_ports.dart';

/// Saves all non-secret E3 parameters as one validated configuration document.
///
/// The use case retains neither a credential nor a storage exception. Validation
/// failures carry only the affected non-secret draft fields and static messages.
///
/// When [deliveryChange] is supplied, a save that moves `BASE_URL` is applied
/// as a delivery configuration change (E4); a save that keeps the destination
/// does not touch delivery.
final class SaveOperationalParameters {
  const SaveOperationalParameters({
    required OperationalConfigurationRepository repository,
    required ConfigurationBuildVariant buildVariant,
    ConfigurationChangeGuard? deliveryChange,
  })  : _repository = repository,
        _buildVariant = buildVariant,
        _deliveryChange = deliveryChange;

  final OperationalConfigurationRepository _repository;
  final ConfigurationBuildVariant _buildVariant;
  final ConfigurationChangeGuard? _deliveryChange;

  Future<SaveOperationalParametersResult> call(SettingsDraft draft) async {
    final baseUrl = ConfigurationValidators.optionalBaseUrl(
      draft.baseUrlText,
      buildVariant: _buildVariant,
    );
    final cooldown = ConfigurationValidators.requiredPositiveNumber(
      draft.cooldownSecondsText,
    );
    final minimumDistance = ConfigurationValidators.requiredPositiveNumber(
      draft.minimumDistanceMetersText,
    );
    final confidence = ConfigurationValidators.requiredUnitInterval(
      draft.confidenceThresholdText,
    );
    final maximumFps = ConfigurationValidators.requiredPositiveNumber(
      draft.maximumInferenceFpsText,
    );

    final validatedDraft = SettingsDraft(
      baseUrlText: draft.baseUrlText,
      cooldownSecondsText: draft.cooldownSecondsText,
      minimumDistanceMetersText: draft.minimumDistanceMetersText,
      confidenceThresholdText: draft.confidenceThresholdText,
      maximumInferenceFpsText: draft.maximumInferenceFpsText,
      baseUrlError: baseUrl.errorMessage,
      cooldownSecondsError: cooldown.errorMessage,
      minimumDistanceMetersError: minimumDistance.errorMessage,
      confidenceThresholdError: confidence.errorMessage,
      maximumInferenceFpsError: maximumFps.errorMessage,
    );

    if (!baseUrl.isValid ||
        !cooldown.isValid ||
        !minimumDistance.isValid ||
        !confidence.isValid ||
        !maximumFps.isValid) {
      return OperationalParametersInvalid(validatedDraft);
    }

    final configuration = OperationalConfiguration(
      baseUrl: baseUrl.value,
      cooldown: Duration(microseconds: (cooldown.value! * 1000000).round()),
      minimumDistanceMeters: minimumDistance.value!,
      confidenceThreshold: confidence.value!,
      maximumInferenceFps: maximumFps.value!,
    );

    try {
      final deliveryChange = _deliveryChange;
      if (deliveryChange == null) {
        await _repository.save(configuration);
      } else {
        await deliveryChange.saveOperationalConfiguration<void>(
          readCurrentBaseUrl: () async => (await _repository.load()).baseUrl,
          newBaseUrl: configuration.baseUrl,
          write: () => _repository.save(configuration),
        );
      }
      return OperationalParametersSaved(configuration);
    } catch (_) {
      return const OperationalParametersSaveFailed();
    }
  }
}

sealed class SaveOperationalParametersResult {
  const SaveOperationalParametersResult();
}

/// Non-secret parameter document was persisted successfully.
final class OperationalParametersSaved extends SaveOperationalParametersResult {
  const OperationalParametersSaved(this.configuration);

  final OperationalConfiguration configuration;
}

/// One or more non-secret fields failed validation and nothing was persisted.
final class OperationalParametersInvalid
    extends SaveOperationalParametersResult {
  const OperationalParametersInvalid(this.draft);

  final SettingsDraft draft;
}

/// The configuration store failed without exposing its technical cause.
final class OperationalParametersSaveFailed
    extends SaveOperationalParametersResult {
  const OperationalParametersSaveFailed();
}

/// Validates and stores a complete replacement device credential.
///
/// The submitted value crosses directly to [DeviceCredentialStatusPort] after
/// validation. It is never placed in a result, state object, exception, or log.
///
/// When [deliveryChange] is supplied, the write is applied as a delivery
/// configuration change (E4): the old attempt is suspended first, and the
/// applicable pauses are cleared once the write is confirmed.
final class SaveOrReplaceDeviceCredential {
  const SaveOrReplaceDeviceCredential({
    required DeviceCredentialStatusPort credentialStore,
    ConfigurationChangeGuard? deliveryChange,
  })  : _credentialStore = credentialStore,
        _deliveryChange = deliveryChange;

  final DeviceCredentialStatusPort _credentialStore;
  final ConfigurationChangeGuard? _deliveryChange;

  Future<SaveDeviceCredentialResult> call(String submittedCredential) async {
    final validation =
        ConfigurationValidators.requiredCredential(submittedCredential);
    if (!validation.isValid) {
      return CredentialInvalid(validation.errorMessage!);
    }

    try {
      final deliveryChange = _deliveryChange;
      if (deliveryChange == null) {
        await _credentialStore.saveCredential(submittedCredential);
      } else {
        await deliveryChange.replaceDestinationOrCredential<void>(
          () => _credentialStore.saveCredential(submittedCredential),
        );
      }
      return const CredentialSaved();
    } catch (_) {
      return const CredentialSaveFailed();
    }
  }
}

sealed class SaveDeviceCredentialResult {
  const SaveDeviceCredentialResult();
}

/// The supplied credential was rejected without retaining its value.
final class CredentialInvalid extends SaveDeviceCredentialResult {
  const CredentialInvalid(this.errorMessage);

  final String errorMessage;
}

/// A complete, validated credential was stored securely.
final class CredentialSaved extends SaveDeviceCredentialResult {
  const CredentialSaved();

  static const status = DeviceCredentialStatus.configured;
}

/// The secure store could not save the credential.
final class CredentialSaveFailed extends SaveDeviceCredentialResult {
  const CredentialSaveFailed();
}

/// Explicit confirmation supplied by the credential-removal dialog.
enum CredentialRemovalConfirmation { confirmed, notConfirmed }

/// Removes the stored credential only after explicit confirmation.
///
/// When [deliveryChange] is supplied, the removal is applied as a delivery
/// configuration change (E4): the old attempt is suspended first, no pause is
/// cleared, and one evaluation is requested so delivery reports that the
/// configuration is required. The removal never opens a connection.
final class RemoveDeviceCredential {
  const RemoveDeviceCredential({
    required DeviceCredentialStatusPort credentialStore,
    ConfigurationChangeGuard? deliveryChange,
  })  : _credentialStore = credentialStore,
        _deliveryChange = deliveryChange;

  final DeviceCredentialStatusPort _credentialStore;
  final ConfigurationChangeGuard? _deliveryChange;

  Future<RemoveDeviceCredentialResult> call(
    CredentialRemovalConfirmation confirmation,
  ) async {
    if (confirmation != CredentialRemovalConfirmation.confirmed) {
      return const CredentialRemovalNeedsConfirmation();
    }

    try {
      final deliveryChange = _deliveryChange;
      if (deliveryChange == null) {
        await _credentialStore.removeCredential();
      } else {
        await deliveryChange.removeCredential<void>(
          _credentialStore.removeCredential,
        );
      }
      return const CredentialRemoved();
    } catch (_) {
      return const CredentialRemovalFailed();
    }
  }
}

sealed class RemoveDeviceCredentialResult {
  const RemoveDeviceCredentialResult();
}

/// No removal was attempted because the caller has not confirmed it.
final class CredentialRemovalNeedsConfirmation
    extends RemoveDeviceCredentialResult {
  const CredentialRemovalNeedsConfirmation();
}

/// The credential was removed and presentation may show a sanitized status.
final class CredentialRemoved extends RemoveDeviceCredentialResult {
  const CredentialRemoved();

  static const status = DeviceCredentialStatus.notConfigured;
}

/// The secure store could not remove the credential.
final class CredentialRemovalFailed extends RemoveDeviceCredentialResult {
  const CredentialRemovalFailed();
}
