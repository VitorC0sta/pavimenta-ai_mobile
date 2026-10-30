/// Immutable, non-secret operational configuration persisted by E3.
///
/// Construction intentionally does not validate values. Parsing and validation
/// belong to the configuration validators, while persistence and recovery
/// belong to the versioned repository.
final class OperationalConfiguration {
  const OperationalConfiguration({
    required this.baseUrl,
    required this.cooldown,
    required this.minimumDistanceMeters,
    required this.confidenceThreshold,
    required this.maximumInferenceFps,
    this.confirmationRequiredFrames = defaultConfirmationRequiredFrames,
    this.confirmationWindowFrames = defaultConfirmationWindowFrames,
    this.maximumBoxAreaRatio = defaultMaximumBoxAreaRatio,
  });

  const OperationalConfiguration.defaults()
      : baseUrl = null,
        cooldown = defaultCooldown,
        minimumDistanceMeters = defaultMinimumDistanceMeters,
        confidenceThreshold = defaultConfidenceThreshold,
        maximumInferenceFps = defaultMaximumInferenceFps,
        confirmationRequiredFrames = defaultConfirmationRequiredFrames,
        confirmationWindowFrames = defaultConfirmationWindowFrames,
        maximumBoxAreaRatio = defaultMaximumBoxAreaRatio;

  static const int currentStorageVersion = 1;
  static const Duration defaultCooldown = Duration(seconds: 5);
  static const double defaultMinimumDistanceMeters = 15;
  static const double defaultConfidenceThreshold = 0.5;
  static const double defaultMaximumInferenceFps = 5;

  // E5 detection defaults (design D9). They live only in code: they are not
  // persisted, not shown in Settings and do not change the storage version.
  static const int defaultConfirmationRequiredFrames = 2;
  static const int defaultConfirmationWindowFrames = 3;
  static const double defaultMaximumBoxAreaRatio = 0.20;

  final Uri? baseUrl;
  final Duration cooldown;
  final double minimumDistanceMeters;
  final double confidenceThreshold;
  final double maximumInferenceFps;
  final int confirmationRequiredFrames;
  final int confirmationWindowFrames;
  final double maximumBoxAreaRatio;
}

/// Immutable text-only draft for editing non-secret configuration.
///
/// Field errors are presentation-safe messages produced by validators. The
/// device credential is deliberately absent because it must never be retained
/// in an application or presentation state object.
final class SettingsDraft {
  const SettingsDraft({
    required this.baseUrlText,
    required this.cooldownSecondsText,
    required this.minimumDistanceMetersText,
    required this.confidenceThresholdText,
    required this.maximumInferenceFpsText,
    this.baseUrlError,
    this.cooldownSecondsError,
    this.minimumDistanceMetersError,
    this.confidenceThresholdError,
    this.maximumInferenceFpsError,
  });

  final String baseUrlText;
  final String cooldownSecondsText;
  final String minimumDistanceMetersText;
  final String confidenceThresholdText;
  final String maximumInferenceFpsText;

  final String? baseUrlError;
  final String? cooldownSecondsError;
  final String? minimumDistanceMetersError;
  final String? confidenceThresholdError;
  final String? maximumInferenceFpsError;
}

/// Presentation-safe credential state.
///
/// No enum value can carry, reconstruct, or expose the complete credential.
enum DeviceCredentialStatus { notConfigured, configured }
