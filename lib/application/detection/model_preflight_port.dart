/// Fixed, sanitized categories for an unavailable model (E5.6). They carry no
/// path and no raw exception.
enum ModelUnavailableReason {
  metadataMismatch('model_metadata_mismatch'),
  loadFailed('model_load_failed'),
  loadTimeout('model_load_timeout');

  const ModelUnavailableReason(this.category);

  /// Category written to technical logs.
  final String category;
}

sealed class ModelPreflightResult {
  const ModelPreflightResult();
}

final class ModelAvailable extends ModelPreflightResult {
  const ModelAvailable();
}

final class ModelUnavailable extends ModelPreflightResult {
  const ModelUnavailable(this.reason);

  final ModelUnavailableReason reason;
}

/// Checks once, at bootstrap, that the bundled model can be used.
abstract interface class ModelPreflightPort {
  /// Preflight timeout (E5.6).
  static const Duration timeout = Duration(seconds: 15);

  Future<ModelPreflightResult> check();
}
