/// Stable categories for validation failures exposed to presentation code.
enum ConfigurationValidationIssue {
  required,
  invalidNumber,
  mustBePositive,
  outsideUnitInterval,
  invalidUri,
  invalidCredentialFormat,
}

/// Build variant relevant to the E3 BASE_URL transport policy.
enum ConfigurationBuildVariant { debug, release }

/// Immutable validation outcome that never retains the submitted text.
///
/// In particular, failed credential validation contains only a stable issue
/// and a static, presentation-safe message.
final class ConfigurationValidationResult<T> {
  const ConfigurationValidationResult.valid(this.value)
      : issue = null,
        errorMessage = null;

  const ConfigurationValidationResult.invalid({
    required ConfigurationValidationIssue this.issue,
    required String this.errorMessage,
  }) : value = null;

  final T? value;
  final ConfigurationValidationIssue? issue;
  final String? errorMessage;

  bool get isValid => issue == null;
}

/// Pure validators for E3 configuration input.
///
/// Credential validation returns only a boolean success marker so the
/// submitted secret cannot be retained in a result or error. BASE_URL policy
/// receives the build variant explicitly, keeping the domain independent from
/// Flutter build-mode constants and deterministic in tests.
abstract final class ConfigurationValidators {
  static const String _requiredMessage = 'Campo obrigatório.';
  static const String _invalidNumberMessage =
      'Informe um número válido e finito.';
  static const String _positiveNumberMessage =
      'Informe um valor maior que zero.';
  static const String _unitIntervalMessage = 'Informe um valor entre 0 e 1.';
  static const String _invalidUriMessage = 'Informe uma URI válida.';
  static const String _invalidCredentialMessage =
      'Informe a chave completa no formato prefixo.segredo.';

  static ConfigurationValidationResult<double> requiredPositiveNumber(
    String input,
  ) {
    final parsed = _requiredFiniteNumber(input);
    if (!parsed.isValid) {
      return parsed;
    }
    if (parsed.value! <= 0) {
      return const ConfigurationValidationResult<double>.invalid(
        issue: ConfigurationValidationIssue.mustBePositive,
        errorMessage: _positiveNumberMessage,
      );
    }
    return parsed;
  }

  static ConfigurationValidationResult<double> requiredUnitInterval(
    String input,
  ) {
    final parsed = _requiredFiniteNumber(input);
    if (!parsed.isValid) {
      return parsed;
    }
    final value = parsed.value!;
    if (value < 0 || value > 1) {
      return const ConfigurationValidationResult<double>.invalid(
        issue: ConfigurationValidationIssue.outsideUnitInterval,
        errorMessage: _unitIntervalMessage,
      );
    }
    return parsed;
  }

  /// Parses and validates the optional BASE_URL for the selected build.
  ///
  /// Every accepted value is an origin without a path, query, fragment or
  /// user information. HTTPS is valid in every build. Debug additionally
  /// permits exactly `http://localhost:3000` for USB development.
  static ConfigurationValidationResult<Uri> optionalBaseUrl(
    String input, {
    required ConfigurationBuildVariant buildVariant,
  }) {
    final parsed = optionalUri(input);
    if (!parsed.isValid || parsed.value == null) {
      return parsed;
    }

    final uri = parsed.value!;
    final trimmed = input.trim();
    final hasAllowedPath = uri.path.isEmpty || uri.path == '/';
    final hasUserInfo = _hasExplicitUserInfo(trimmed);
    final isHttps = uri.scheme == 'https';
    final isDebugLocalhost = buildVariant == ConfigurationBuildVariant.debug &&
        uri.scheme == 'http' &&
        uri.host == 'localhost' &&
        uri.hasPort &&
        uri.port == 3000;

    if (!uri.isAbsolute ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        hasUserInfo ||
        uri.hasQuery ||
        uri.hasFragment ||
        !hasAllowedPath ||
        (!isHttps && !isDebugLocalhost)) {
      return const ConfigurationValidationResult<Uri>.invalid(
        issue: ConfigurationValidationIssue.invalidUri,
        errorMessage: _invalidUriMessage,
      );
    }

    return ConfigurationValidationResult<Uri>.valid(uri.replace(path: ''));
  }

  /// Parses an optional URI without applying build-variant URL policy.
  static ConfigurationValidationResult<Uri> optionalUri(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const ConfigurationValidationResult<Uri>.valid(null);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || _hasMalformedPercentEncoding(trimmed)) {
      return const ConfigurationValidationResult<Uri>.invalid(
        issue: ConfigurationValidationIssue.invalidUri,
        errorMessage: _invalidUriMessage,
      );
    }
    return ConfigurationValidationResult<Uri>.valid(uri);
  }

  static bool _hasExplicitUserInfo(String input) {
    final schemeSeparator = input.indexOf('://');
    if (schemeSeparator < 0) {
      return false;
    }
    final authorityStart = schemeSeparator + 3;
    final authorityEnd = input.indexOf(RegExp(r'[/\?#]'), authorityStart);
    final authority = authorityEnd < 0
        ? input.substring(authorityStart)
        : input.substring(authorityStart, authorityEnd);
    return authority.contains('@');
  }

  static bool _hasMalformedPercentEncoding(String input) {
    for (var index = 0; index < input.length; index++) {
      if (input.codeUnitAt(index) != 0x25) {
        continue;
      }
      if (index + 2 >= input.length ||
          !_isHexDigit(input.codeUnitAt(index + 1)) ||
          !_isHexDigit(input.codeUnitAt(index + 2))) {
        return true;
      }
      index += 2;
    }
    return false;
  }

  static bool _isHexDigit(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);

  /// Checks the minimum `prefix.secret` shape without retaining the secret.
  static ConfigurationValidationResult<bool> requiredCredential(String input) {
    if (input.isEmpty) {
      return const ConfigurationValidationResult<bool>.invalid(
        issue: ConfigurationValidationIssue.required,
        errorMessage: _requiredMessage,
      );
    }

    final separator = input.indexOf('.');
    final hasPrefix =
        separator > 0 && input.substring(0, separator).trim().isNotEmpty;
    final hasSecret = separator >= 0 &&
        separator < input.length - 1 &&
        input.substring(separator + 1).trim().isNotEmpty;
    if (!hasPrefix || !hasSecret) {
      return const ConfigurationValidationResult<bool>.invalid(
        issue: ConfigurationValidationIssue.invalidCredentialFormat,
        errorMessage: _invalidCredentialMessage,
      );
    }

    return const ConfigurationValidationResult<bool>.valid(true);
  }

  static ConfigurationValidationResult<double> _requiredFiniteNumber(
    String input,
  ) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const ConfigurationValidationResult<double>.invalid(
        issue: ConfigurationValidationIssue.required,
        errorMessage: _requiredMessage,
      );
    }

    final value = double.tryParse(trimmed);
    if (value == null || !value.isFinite) {
      return const ConfigurationValidationResult<double>.invalid(
        issue: ConfigurationValidationIssue.invalidNumber,
        errorMessage: _invalidNumberMessage,
      );
    }
    return ConfigurationValidationResult<double>.valid(value);
  }
}
