import '../configuration_validators.dart';
import 'non_printable_secret.dart';

/// Pure revalidation of the stored destination and credential right before an
/// attempt may reach the transport (design E4.6 step 7, E4.12).
///
/// The E3 save flow already validates both values, but the stores outlive that
/// flow (legacy data, a build switch from debug to release, manual tampering).
/// E4 therefore applies the very same E3 rules again at its own boundary
/// instead of trusting what was persisted earlier. Neither method retains,
/// formats, or returns the credential.
abstract final class DeliveryConfigurationRevalidation {
  /// Returns the destination normalized by the E3 `BASE_URL` rules (an origin
  /// without path, query, fragment, or user information), or `null` when
  /// [stored] violates them for [buildVariant].
  static Uri? validatedDestination(
    Uri stored, {
    required ConfigurationBuildVariant buildVariant,
  }) {
    final result = ConfigurationValidators.optionalBaseUrl(
      stored.toString(),
      buildVariant: buildVariant,
    );
    return result.isValid ? result.value : null;
  }

  /// Whether [credential] still has the minimum E3 `prefix.secret` shape.
  static bool hasValidCredentialShape(NonPrintableSecret credential) =>
      ConfigurationValidators.requiredCredential(credential.reveal()).isValid;
}
