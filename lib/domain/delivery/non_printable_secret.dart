/// Placeholder emitted wherever a secret would otherwise be rendered.
const String redactedSecretPlaceholder = '<redacted>';

/// Wrapper for the complete device credential during one delivery attempt.
///
/// The value is reachable only through the explicit [reveal] call, which the
/// transport adapter uses once to build the credential header. Every implicit
/// rendering path is redacted:
///
/// * [toString] (string interpolation, logs, assertion messages, debug
///   output) returns a constant placeholder;
/// * [toJson] returns the same placeholder, so `jsonEncode` never emits it;
/// * equality and hash code are the default identity ones, so neither a
///   `==` comparison nor a hash-based collection derives anything from the
///   value, and two wrappers around the same text are intentionally unequal.
///
/// There is deliberately no length, prefix, suffix, or masked accessor.
/// Holders must drop their reference after the attempt finishes; no zeroing
/// of managed memory is claimed.
final class NonPrintableSecret {
  /// Wraps [value]. The error message never contains the value.
  NonPrintableSecret(String value) : _value = value {
    if (value.isEmpty) {
      throw ArgumentError('A secret must not be empty.');
    }
  }

  final String _value;

  /// Returns the complete secret. Call only at the point of use and never
  /// store, log, or forward the result.
  String reveal() => _value;

  String toJson() => redactedSecretPlaceholder;

  @override
  String toString() => 'NonPrintableSecret($redactedSecretPlaceholder)';
}
