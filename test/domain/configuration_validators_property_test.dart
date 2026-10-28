import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect;
import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';

void main() {
  // **Validates: Requirements RF-19.4–8, RNF-03.6**
  Glados<int>(
    any.positiveIntOrZero,
    ExploreConfig(numRuns: 120),
  ).test('accepts exactly the generated numeric values inside each domain',
      (int seed) {
    final positive = 1 + seed % 1000000;
    final positiveResult = ConfigurationValidators.requiredPositiveNumber(
      positive.toString(),
    );
    final zeroResult = ConfigurationValidators.requiredPositiveNumber('0');
    final negativeResult = ConfigurationValidators.requiredPositiveNumber(
      (-positive).toString(),
    );

    expect(positiveResult.isValid, isTrue);
    expect(positiveResult.value, positive.toDouble());
    expect(zeroResult.isValid, isFalse);
    expect(zeroResult.value, isNull);
    expect(negativeResult.isValid, isFalse);
    expect(negativeResult.value, isNull);

    final confidence = (seed % 1001) / 1000;
    final confidenceResult = ConfigurationValidators.requiredUnitInterval(
      confidence.toString(),
    );
    final belowResult = ConfigurationValidators.requiredUnitInterval(
      (-1 - seed % 1000).toString(),
    );
    final aboveResult = ConfigurationValidators.requiredUnitInterval(
      (2 + seed % 1000).toString(),
    );

    expect(confidenceResult.isValid, isTrue);
    expect(confidenceResult.value, confidence);
    expect(belowResult.isValid, isFalse);
    expect(belowResult.value, isNull);
    expect(aboveResult.isValid, isFalse);
    expect(aboveResult.value, isNull);
  });

  // **Validates: Requirements RF-13.1–5, RF-19.4–5, RNF-02.1,
  // RNF-03.6**
  Glados<int>(
    any.positiveIntOrZero,
    ExploreConfig(numRuns: 120),
  ).test('normalizes generated HTTPS origins and preserves absent defaults',
      (int seed) {
    final whitespace = List<String>.filled(seed % 8, ' ').join();
    final absent = ConfigurationValidators.optionalBaseUrl(
      whitespace,
      buildVariant: ConfigurationBuildVariant.release,
    );

    expect(absent.isValid, isTrue);
    expect(absent.value, isNull);
    const defaults = OperationalConfiguration.defaults();
    expect(defaults.baseUrl, isNull);
    expect(defaults.cooldown, const Duration(seconds: 5));
    expect(defaults.minimumDistanceMeters, 15);
    expect(defaults.confidenceThreshold, 0.5);
    expect(defaults.maximumInferenceFps, 5);

    final host = 'node${seed % 100000}.example.invalid';
    final input = '${whitespace}https://$host/$whitespace';
    for (final variant in ConfigurationBuildVariant.values) {
      final normalized = ConfigurationValidators.optionalBaseUrl(
        input,
        buildVariant: variant,
      );

      expect(normalized.isValid, isTrue);
      expect(normalized.value, Uri.parse('https://$host'));
    }
  });

  // **Validates: Requirements RF-13.17, RF-19.14, RNF-02.2,
  // RNF-03.6**
  Glados<int>(
    any.positiveIntOrZero,
    ExploreConfig(numRuns: 120),
  ).test('validates generated credential shapes without returning their text',
      (int seed) {
    final prefix = String.fromCharCodes(<int>[
      112,
      seed % 10 + 48,
      120,
    ]);
    final secret = String.fromCharCodes(<int>[
      115,
      seed % 26 + 97,
      99,
      114,
      101,
      116,
    ]);
    final submitted = '$prefix.$secret';
    final valid = ConfigurationValidators.requiredCredential(submitted);

    expect(valid.isValid, isTrue);
    expect(valid.value, isTrue);
    expect(valid.errorMessage, isNull);
    expect(valid.toString(), isNot(contains(submitted)));

    final malformed = '$prefix.';
    final invalid = ConfigurationValidators.requiredCredential(malformed);

    expect(invalid.isValid, isFalse);
    expect(invalid.value, isNull);
    expect(
      invalid.issue,
      ConfigurationValidationIssue.invalidCredentialFormat,
    );
    expect(invalid.errorMessage, isNot(contains(malformed)));
    expect(invalid.toString(), isNot(contains(malformed)));
  });
}
