import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';

/// Explicitly fictitious credential accepted by the E3 minimum format
/// (`prefix.secret`). It is not a real key and must never be printed.
const String fakeDeliveryCredential = 'fakeprefix.fake-secret-for-tests-only';

/// Test-local snapshot result (stand-in for `DeliveryConfigurationResult` and
/// `CredentialReadResult`, tasks 63.1 and 63.4).
sealed class FakeConfigurationResult {
  const FakeConfigurationResult();
}

/// Consistent URL + credential pair belonging to one [revision].
final class FakeConfigurationAvailable extends FakeConfigurationResult {
  const FakeConfigurationAvailable({
    required this.revision,
    required this.baseUrl,
    required this.credential,
  });

  final int revision;
  final Uri baseUrl;
  final String credential;

  @override
  String toString() => 'FakeConfigurationAvailable(revision: $revision)';
}

/// Destination or credential is not configured.
final class FakeConfigurationMissing extends FakeConfigurationResult {
  const FakeConfigurationMissing();
}

/// Credential exists but violates the E3 minimum shape.
final class FakeCredentialInvalidFormat extends FakeConfigurationResult {
  const FakeCredentialInvalidFormat();
}

final class FakeSecureStorageUnavailable extends FakeConfigurationResult {
  const FakeSecureStorageUnavailable();
}

/// In-memory configuration snapshot with a monotonic local revision.
///
/// It touches neither preferences nor secure storage. Every setter bumps the
/// revision so tests can prove that a stale attempt is detected.
final class FakeDeliveryConfigurationSnapshotPort {
  FakeDeliveryConfigurationSnapshotPort({
    Uri? baseUrl,
    String? credential,
    bool secureStorageAvailable = true,
  })  : _baseUrl = baseUrl,
        _credential = credential,
        _secureStorageAvailable = secureStorageAvailable;

  Uri? _baseUrl;
  String? _credential;
  bool _secureStorageAvailable;
  int _revision = 0;

  int readCount = 0;

  int get revision => _revision;

  void setBaseUrl(Uri? value) {
    _baseUrl = value;
    _revision++;
  }

  void setCredential(String? value) {
    _credential = value;
    _revision++;
  }

  void setSecureStorageAvailable(bool value) {
    _secureStorageAvailable = value;
    _revision++;
  }

  Future<FakeConfigurationResult> readForAttempt() async {
    readCount++;
    final baseUrl = _baseUrl;
    final credential = _credential;
    if (!_secureStorageAvailable) {
      return const FakeSecureStorageUnavailable();
    }
    if (baseUrl == null || credential == null) {
      return const FakeConfigurationMissing();
    }
    if (!ConfigurationValidators.requiredCredential(credential).isValid) {
      return const FakeCredentialInvalidFormat();
    }
    return FakeConfigurationAvailable(
      revision: _revision,
      baseUrl: baseUrl,
      credential: credential,
    );
  }

  bool isCurrent(int revision) => revision == _revision;
}
