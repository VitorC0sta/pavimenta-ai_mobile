import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_technical_logger.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_presentation_state.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/http_delivery_decision_policy.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_transport_result.dart';
import 'package:pavimenta_ai_mobile/infrastructure/sanitized_delivery_technical_logger.dart';

// Explicitly fictitious values; none is a real key, URL, or identifier.
const String _fakeSecret = 'fakeprefix.fake-secret-for-tests-only';
const String _fakeKey = '11111111-2222-4333-8444-555555555555';
const String _fakeTimestamp = '2025-01-01T12:00:00.000Z';
const String _fakeHost = 'api.example.invalid';
const String _fakePath = '/data/user/0/app/files/fake-image-handle.jpg';
const String _fakeDigest = 'sha256:0123456789abcdef0123456789abcdef';

const List<String> _forbidden = <String>[
  _fakeSecret,
  'fake-secret',
  _fakeKey,
  _fakeTimestamp,
  _fakeHost,
  'https://',
  _fakePath,
  'fake-image-handle',
  _fakeDigest,
  '-23.5505',
  '-46.6333',
  'authorization',
  'x-api-key',
  'multipart',
  'boundary',
  'stacktrace',
  'Exception',
];

void _expectClean(String text, {String? reason}) {
  for (final fragment in _forbidden) {
    expect(text, isNot(contains(fragment)), reason: reason ?? text);
  }
}

/// Test-local consumer of the pure policies: classifies a status and reports
/// the matching technical event, as the future coordinator will.
void _report(int status, DeliveryTechnicalLogger logger) {
  switch (HttpDeliveryDecisionPolicy.classify(status)) {
    case DefinitiveDeliveryDecision(:final disposition):
      logger.definitiveRejection(disposition);
    case RecoverableDeliveryDecision(:final cause):
      logger.recoverableFailure(cause);
    case PausedDeliveryDecision(:final unexpectedStatusCode?):
      logger.unexpectedResponse(unexpectedStatusCode);
    case PausedDeliveryDecision():
      break;
  }
}

void main() {
  group('sanitized serialization of results and state', () {
    // **Validates: Requirements RNF-02.1–3, RF-23.11–12, RNF-03.8–10**
    test('decisions render only closed names and numeric statuses', () {
      final rendered = <String>[
        for (var status = 0; status <= 700; status++)
          HttpDeliveryDecisionPolicy.classify(status).toString(),
        for (final d in DeliveryDisposition.values)
          DefinitiveDeliveryDecision(d).toString(),
        for (final c in RecoverableFailureCause.values)
          RecoverableDeliveryDecision(c).toString(),
      ];

      for (final text in rendered) {
        _expectClean(text);
        expect(
          RegExp(r'^(Definitive|Recoverable|Paused)DeliveryDecision\([A-Za-z]+'
                  r'(, \d{1,3})?\)$')
              .hasMatch(text),
          isTrue,
          reason: text,
        );
      }
    });

    test('transport results render without body, header, URL, or exception',
        () {
      final results = <OccurrenceTransportResult>[
        const TransportHttpResponse(201),
        const TransportHttpResponse(302),
        const TransportNetworkFailure(),
        const TransportTimeout(),
        const TransportCancelled(),
        const TransportLocalFailure(),
      ];

      for (final result in results) {
        final text = result.toString();
        _expectClean(text);
        expect(text, matches(RegExp(r'^Transport[A-Za-z]+\(\d{0,3}\)$')));
      }
    });

    test('presentation state is fixed text keyed by phase', () {
      final messages = <String>{};
      for (final phase in DeliveryPhase.values) {
        final state = DeliveryPresentationState(phase: phase);
        _expectClean(state.message);
        _expectClean(state.toString());
        expect(state.toString(), isNot(contains('nextRetryAt')));
        messages.add(state.message);
      }
      expect(messages, hasLength(DeliveryPhase.values.length));

      final waiting = DeliveryPresentationState(
        phase: DeliveryPhase.waitingBackoff,
        nextRetryAt: DateTime.utc(2025, 1, 1, 12),
      );
      expect(waiting.toString(), isNot(contains('2025')));
      expect(waiting.message, isNot(contains('2025')));
    });

    test('secret, configuration, and queue models never serialize values', () {
      final secret = NonPrintableSecret(_fakeSecret);
      final configuration = DeliveryConfiguration(
        revision: 2,
        baseUrl: Uri.parse('https://$_fakeHost'),
        credential: secret,
      );
      final payload = DeliveryOccurrencePayload(
        detectedAtIso8601: _fakeTimestamp,
        latitude: -23.5505,
        longitude: -46.6333,
        speedKmh: null,
        confidence: 0.9,
        defectClass: 'pothole',
        image: DeliveryImageRef(byteLength: 3, opaqueHandle: _fakePath),
      );
      final head =
          DeliveryQueueHead(idempotencyKey: _fakeKey, queueSequence: 1);

      final values = <Object>[
        secret,
        configuration,
        DeliveryConfigurationAvailable(configuration),
        CredentialAvailable(secret),
        payload,
        payload.image,
        head,
        DeliveryHeadEligible(head: head, payload: payload),
        DeliveryHeadInBackoff(head: head, nextAttemptAt: DateTime.utc(2025)),
        DeliveryHeadPendingCleanup(
          head: head,
          disposition: DeliveryDisposition.conflict,
        ),
        DeliveryHeadLocalIntegrityFailure(head: head),
      ];

      for (final value in values) {
        _expectClean(value.toString(), reason: value.runtimeType.toString());
      }
      _expectClean(jsonEncode(secret));
      _expectClean(jsonEncode(<String, Object>{'credential': secret}));
    });

    test('validation errors never echo the offending values', () {
      final errors = <Object>[];
      void capture(void Function() body) {
        try {
          body();
        } on ArgumentError catch (error) {
          errors.add(error);
        }
      }

      capture(() => NonPrintableSecret(''));
      capture(() => DeliveryQueueHead(idempotencyKey: '', queueSequence: 1));
      capture(
          () => DeliveryQueueHead(idempotencyKey: _fakeKey, queueSequence: 0));
      capture(() => DeliveryImageRef(byteLength: 0, opaqueHandle: _fakePath));
      capture(
        () => DeliveryConfiguration(
          revision: -1,
          baseUrl: Uri.parse('https://$_fakeHost'),
          credential: NonPrintableSecret(_fakeSecret),
        ),
      );
      capture(
        () => PausedDeliveryDecision(
          DeliveryPauseReason.access,
          unexpectedStatusCode: 403,
        ),
      );
      capture(
        () => DeliveryPresentationState(
          phase: DeliveryPhase.idle,
          nextRetryAt: DateTime.utc(2025, 1, 1, 12),
        ),
      );

      expect(errors, hasLength(7));
      for (final error in errors) {
        _expectClean(error.toString());
      }
    });
  });

  group('absence of secrets and raw exceptions in logs', () {
    // **Validates: Requirements RF-23.11–12, RNF-01.6–13, RNF-02.1–3**
    test('logging every classified status leaks nothing and is deterministic',
        () {
      final lines = <String>[];
      final logger = SanitizedDeliveryTechnicalLogger(lines.add);

      for (var status = -5; status <= 700; status++) {
        _report(status, logger);
      }

      expect(lines, isNotEmpty);
      for (final line in lines) {
        _expectClean(line);
      }
      expect(lines.where((l) => l.contains('E4_DELIVERY_CLEANUP')), isEmpty);

      final again = <String>[];
      final second = SanitizedDeliveryTechnicalLogger(again.add);
      for (var status = -5; status <= 700; status++) {
        _report(status, second);
      }
      expect(again, lines);
    });

    test('statuses map to the expected mandatory categories', () {
      String? firstLine(int status) {
        final lines = <String>[];
        _report(status, SanitizedDeliveryTechnicalLogger(lines.add));
        return lines.isEmpty ? null : lines.single;
      }

      expect(firstLine(201), isNull, reason: 'accepted is not a rejection');
      expect(firstLine(200), isNull, reason: 'accepted is not a rejection');
      expect(firstLine(401), isNull, reason: 'pause has no log category');
      expect(firstLine(403), isNull, reason: 'pause has no log category');
      expect(
        firstLine(409),
        'E4_DELIVERY_DEFINITIVE_REJECTION disposition=conflict',
      );
      expect(
        firstLine(503),
        'E4_DELIVERY_RECOVERABLE_FAILURE cause=serverError',
      );
      expect(firstLine(302), 'E4_DELIVERY_UNEXPECTED_RESPONSE status=302');
    });

    test('a sink exception carrying sensitive text never surfaces', () {
      final logger = SanitizedDeliveryTechnicalLogger(
        (_) => throw Exception('$_fakeSecret $_fakePath $_fakeHost'),
      );

      expect(() => _report(409, logger), returnsNormally);
      expect(() => _report(302, logger), returnsNormally);
      expect(() => _report(500, logger), returnsNormally);
      expect(logger.cleanupFailure, returnsNormally);
    });
  });
}
