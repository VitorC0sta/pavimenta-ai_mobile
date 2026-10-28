import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/configuration_validators.dart';
import 'package:pavimenta_ai_mobile/domain/operational_configuration.dart';

void main() {
  group('OperationalConfiguration defaults', () {
    // **Validates: Requirements RF-19.4, RF-19.5, RNF-03.6**
    test('uses approved values when no configuration exists', () {
      const configuration = OperationalConfiguration.defaults();

      expect(configuration.baseUrl, isNull);
      expect(configuration.cooldown, const Duration(seconds: 5));
      expect(configuration.minimumDistanceMeters, 15);
      expect(configuration.confidenceThreshold, 0.5);
      expect(configuration.maximumInferenceFps, 5);
    });

    // **Validates: Requirements RF-13.7, RF-19.10, RNF-02.6**
    test('credential status represents presence without carrying a value', () {
      expect(
        DeviceCredentialStatus.values,
        <DeviceCredentialStatus>[
          DeviceCredentialStatus.notConfigured,
          DeviceCredentialStatus.configured,
        ],
      );
      expect(DeviceCredentialStatus.configured.name, 'configured');
      expect(DeviceCredentialStatus.notConfigured.name, 'notConfigured');
    });
  });

  group('requiredPositiveNumber', () {
    test('parses a finite positive decimal after trimming', () {
      final result = ConfigurationValidators.requiredPositiveNumber(' 5.5 ');

      expect(result.isValid, isTrue);
      expect(result.value, 5.5);
      expect(result.issue, isNull);
      expect(result.errorMessage, isNull);
    });

    test('distinguishes a missing value from malformed and non-finite values',
        () {
      final missing = ConfigurationValidators.requiredPositiveNumber('  ');
      expect(missing.isValid, isFalse);
      expect(missing.issue, ConfigurationValidationIssue.required);

      for (final input in <String>['not-a-number', 'NaN', 'Infinity']) {
        final result = ConfigurationValidators.requiredPositiveNumber(input);
        expect(result.isValid, isFalse, reason: 'input: $input');
        expect(
          result.issue,
          ConfigurationValidationIssue.invalidNumber,
          reason: 'input: $input',
        );
      }
    });

    test('rejects zero and negative numbers', () {
      for (final input in <String>['0', '-0.1']) {
        final result = ConfigurationValidators.requiredPositiveNumber(input);
        expect(result.isValid, isFalse, reason: 'input: $input');
        expect(
          result.issue,
          ConfigurationValidationIssue.mustBePositive,
          reason: 'input: $input',
        );
      }
    });
  });

  group('requiredUnitInterval', () {
    test('accepts both inclusive boundaries and an interior value', () {
      for (final input in <String>['0', '0.5', '1']) {
        final result = ConfigurationValidators.requiredUnitInterval(input);
        expect(result.isValid, isTrue, reason: 'input: $input');
        expect(result.value, double.parse(input), reason: 'input: $input');
      }
    });

    test('rejects values outside the interval and missing values', () {
      for (final input in <String>['-0.01', '1.01']) {
        final result = ConfigurationValidators.requiredUnitInterval(input);
        expect(result.isValid, isFalse, reason: 'input: $input');
        expect(
          result.issue,
          ConfigurationValidationIssue.outsideUnitInterval,
          reason: 'input: $input',
        );
      }

      expect(
        ConfigurationValidators.requiredUnitInterval('').issue,
        ConfigurationValidationIssue.required,
      );
    });
  });

  group('optionalUri', () {
    test('represents an absent optional URI without an error', () {
      final result = ConfigurationValidators.optionalUri('   ');

      expect(result.isValid, isTrue);
      expect(result.value, isNull);
    });

    test('trims and parses a syntactically valid URI', () {
      final result = ConfigurationValidators.optionalUri(
        '  https://example.invalid  ',
      );

      expect(result.isValid, isTrue);
      expect(result.value, Uri.parse('https://example.invalid'));
    });

    test('rejects malformed URI syntax', () {
      final result = ConfigurationValidators.optionalUri('https://host/%');

      expect(result.isValid, isFalse);
      expect(result.issue, ConfigurationValidationIssue.invalidUri);
      expect(result.value, isNull);
    });
  });

  group('optionalBaseUrl', () {
    // **Validates: Requirements RF-13.1–5, RF-19.1, RNF-02.9–10**
    test('accepts HTTPS in every variant and removes a trailing slash', () {
      for (final variant in ConfigurationBuildVariant.values) {
        final result = ConfigurationValidators.optionalBaseUrl(
          '  https://example.invalid/  ',
          buildVariant: variant,
        );

        expect(result.isValid, isTrue, reason: 'variant: $variant');
        expect(
          result.value,
          Uri.parse('https://example.invalid'),
          reason: 'variant: $variant',
        );
      }
    });

    // **Validates: Requirements RF-13.3–5, RNF-02.9–10**
    test('allows exact localhost HTTP origin only in debug', () {
      final debugResult = ConfigurationValidators.optionalBaseUrl(
        'http://localhost:3000/',
        buildVariant: ConfigurationBuildVariant.debug,
      );
      final releaseResult = ConfigurationValidators.optionalBaseUrl(
        'http://localhost:3000',
        buildVariant: ConfigurationBuildVariant.release,
      );

      expect(debugResult.isValid, isTrue);
      expect(debugResult.value, Uri.parse('http://localhost:3000'));
      expect(releaseResult.isValid, isFalse);
      expect(releaseResult.issue, ConfigurationValidationIssue.invalidUri);
    });

    // **Validates: Requirements RF-13.3–5, RNF-02.9–10**
    test('rejects other cleartext hosts, ports, and loopback spellings', () {
      final invalidInputs = <String>[
        'http://localhost',
        'http://localhost:3001',
        'http://example.invalid:3000',
        'http://127.0.0.1:3000',
        'http://[::1]:3000',
      ];

      for (final input in invalidInputs) {
        final result = ConfigurationValidators.optionalBaseUrl(
          input,
          buildVariant: ConfigurationBuildVariant.debug,
        );
        expect(result.isValid, isFalse, reason: 'input: $input');
        expect(result.issue, ConfigurationValidationIssue.invalidUri);
      }
    });

    // **Validates: Requirements RF-13.1–5, RNF-02.1**
    test('rejects paths, endpoint suffix, query, fragment, and userinfo', () {
      final invalidInputs = <String>[
        'https://example.invalid/health',
        'https://example.invalid/api/v1/occurrences',
        'https://example.invalid/%61pi/v1/occurrences',
        'https://example.invalid/?mode=test',
        'https://example.invalid/#section',
        'https://user:password@example.invalid',
        'https://@example.invalid',
      ];

      for (final variant in ConfigurationBuildVariant.values) {
        for (final input in invalidInputs) {
          final result = ConfigurationValidators.optionalBaseUrl(
            input,
            buildVariant: variant,
          );
          expect(
            result.isValid,
            isFalse,
            reason: 'variant: $variant; input: $input',
          );
          expect(result.issue, ConfigurationValidationIssue.invalidUri);
        }
      }
    });

    // **Validates: Requirements RF-13.1–5**
    test('rejects values that are not absolute origins with a host', () {
      for (final input in <String>[
        'example.invalid',
        'https:example.invalid',
        'file:///settings',
      ]) {
        final result = ConfigurationValidators.optionalBaseUrl(
          input,
          buildVariant: ConfigurationBuildVariant.debug,
        );
        expect(result.isValid, isFalse, reason: 'input: $input');
        expect(result.issue, ConfigurationValidationIssue.invalidUri);
      }
    });
  });

  group('requiredCredential', () {
    test('accepts the minimum non-empty prefix and secret shape', () {
      final result = ConfigurationValidators.requiredCredential(
        _credentialWithSeparator(),
      );

      expect(result.isValid, isTrue);
      expect(result.value, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('rejects a missing prefix, separator, secret, or complete value', () {
      final invalidInputs = <String>[
        '',
        '.secret',
        'prefix',
        'prefix.',
        '   .secret',
        'prefix.   ',
      ];

      for (final input in invalidInputs) {
        final result = ConfigurationValidators.requiredCredential(input);
        expect(result.isValid, isFalse, reason: 'invalid credential shape');
        expect(result.value, isNull);
        expect(
          result.issue,
          input.isEmpty
              ? ConfigurationValidationIssue.required
              : ConfigurationValidationIssue.invalidCredentialFormat,
        );
      }
    });

    test('never includes submitted credential text in validation errors', () {
      final submitted = _invalidCredential();
      final result = ConfigurationValidators.requiredCredential(submitted);

      expect(result.isValid, isFalse);
      expect(result.value, isNull);
      expect(result.errorMessage, isNot(contains(submitted)));
      expect(result.toString(), isNot(contains(submitted)));
    });
  });
}

String _credentialWithSeparator() => String.fromCharCodes(<int>[
      112,
      114,
      101,
      102,
      105,
      120,
      46,
      115,
      101,
      99,
      114,
      101,
      116,
    ]);

String _invalidCredential() => String.fromCharCodes(<int>[
      112,
      114,
      105,
      118,
      97,
      116,
      101,
      45,
      118,
      97,
      108,
      117,
      101,
      46,
    ]);
