import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_configuration.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_presentation_state.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_transport_result.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';

// Explicitly fictitious values; none is a real key, URL, or identifier.
const String _fakeSecret = 'fakeprefix.fake-secret-for-tests-only';
const String _fakeKey = '11111111-2222-4333-8444-555555555555';
const String _fakeTimestamp = '2025-01-01T12:00:00.000Z';

DeliveryOccurrencePayload _payload() => DeliveryOccurrencePayload(
      detectedAtIso8601: _fakeTimestamp,
      latitude: -23.5505,
      longitude: -46.6333,
      speedKmh: 0,
      confidence: 1,
      defectClass: 'pothole',
      image: DeliveryImageRef(byteLength: 10, opaqueHandle: 'secret-path.jpg'),
    );

void main() {
  group('NonPrintableSecret', () {
    // **Validates: Requirements RNF-02.1–3, RF-23.11**
    test('never renders the value through string, JSON, or hash paths', () {
      final secret = NonPrintableSecret(_fakeSecret);

      expect(secret.reveal(), _fakeSecret);
      expect(secret.toString(), isNot(contains(_fakeSecret)));
      expect('$secret', isNot(contains('fake')));
      expect(jsonEncode(secret), '"<redacted>"');
      expect(jsonEncode(<String, Object>{'k': secret}),
          isNot(contains(_fakeSecret)));
      // Identity equality: equal text does not make wrappers equal.
      expect(secret == NonPrintableSecret(_fakeSecret), isFalse);
      expect(secret, equals(secret));
    });

    test('rejects an empty value without echoing it', () {
      expect(() => NonPrintableSecret(''), throwsArgumentError);
    });
  });

  group('configuration and credential results', () {
    // **Validates: Requirements RNF-02.1–3, RF-23.12**
    test('snapshot and results redact destination and credential', () {
      final configuration = DeliveryConfiguration(
        revision: 3,
        baseUrl: Uri.parse('https://example.invalid'),
        credential: NonPrintableSecret(_fakeSecret),
      );
      final rendered = <Object>[
        configuration,
        DeliveryConfigurationAvailable(configuration),
        CredentialAvailable(configuration.credential),
        const CredentialMissing(),
        const CredentialInvalidFormat(),
        const CredentialStorageUnavailable(),
        const DeliveryConfigurationMissing(),
        const DeliveryDestinationInvalid(),
        const DeliveryCredentialInvalidFormat(),
        const DeliverySecureStorageUnavailable(),
      ].map((value) => value.toString()).join(' ');

      expect(rendered, isNot(contains(_fakeSecret)));
      expect(rendered, isNot(contains('example.invalid')));
      expect(
        () => DeliveryConfiguration(
          revision: -1,
          baseUrl: Uri.parse('https://example.invalid'),
          credential: NonPrintableSecret(_fakeSecret),
        ),
        throwsArgumentError,
      );
    });
  });

  group('queue head and upload request', () {
    // **Validates: Requirements RNF-01.6–13, RNF-02.1–3, RF-23.11–12**
    test('keep the persisted values and render nothing sensitive', () {
      final payload = _payload();
      final head =
          DeliveryQueueHead(idempotencyKey: _fakeKey, queueSequence: 7);
      final configuration = DeliveryConfiguration(
        revision: 1,
        baseUrl: Uri.parse('https://example.invalid'),
        credential: NonPrintableSecret(_fakeSecret),
      );
      final request = OccurrenceUploadRequest.fromConfiguration(
        configuration: configuration,
        idempotencyKey: head.idempotencyKey,
        payload: payload,
        imageStream: const Stream<List<int>>.empty(),
      );

      expect(payload.speedKmh, 0, reason: 'explicit zero is preserved');
      expect(request.credential, same(configuration.credential));
      expect(request.configurationRevision, 1);
      expect(request.idempotencyKey, _fakeKey);

      final rendered = <Object>[
        payload,
        payload.image,
        head,
        request,
        DeliveryHeadEligible(head: head, payload: payload),
        DeliveryHeadInBackoff(head: head, nextAttemptAt: DateTime.utc(2025)),
        DeliveryHeadPendingCleanup(
          head: head,
          disposition: DeliveryDisposition.created,
        ),
        DeliveryHeadLocalIntegrityFailure(head: head),
        const DeliveryQueueEmpty(),
        const DeliveryQueueUnavailable(),
      ].map((value) => value.toString()).join(' ');

      for (final forbidden in <String>[
        _fakeSecret,
        _fakeKey,
        _fakeTimestamp,
        'example.invalid',
        'secret-path',
        '23.55',
        '46.63',
      ]) {
        expect(rendered, isNot(contains(forbidden)));
      }
    });

    test('reject invalid head and image values', () {
      expect(
        () => DeliveryQueueHead(idempotencyKey: '', queueSequence: 1),
        throwsArgumentError,
      );
      expect(
        () => DeliveryQueueHead(idempotencyKey: _fakeKey, queueSequence: 0),
        throwsArgumentError,
      );
      expect(
        () => DeliveryQueueHead(
          idempotencyKey: _fakeKey,
          queueSequence: 1,
          attemptCount: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => DeliveryImageRef(byteLength: 0, opaqueHandle: Object()),
        throwsArgumentError,
      );
    });
  });

  group('transport result and decisions', () {
    // **Validates: Requirements RF-15–18, RNF-03.8–10**
    test('carry only closed values and compare by value', () {
      expect(
          const TransportHttpResponse(200), const TransportHttpResponse(200));
      expect(const TransportHttpResponse(200),
          isNot(const TransportHttpResponse(201)));
      expect(
        const DefinitiveDeliveryDecision(DeliveryDisposition.created),
        const DefinitiveDeliveryDecision(DeliveryDisposition.created),
      );
      expect(
        const RecoverableDeliveryDecision(RecoverableFailureCause.timeout),
        isNot(
            const RecoverableDeliveryDecision(RecoverableFailureCause.network)),
      );
      expect(
        PausedDeliveryDecision(
          DeliveryPauseReason.unexpectedResponse,
          unexpectedStatusCode: 302,
        ),
        PausedDeliveryDecision(
          DeliveryPauseReason.unexpectedResponse,
          unexpectedStatusCode: 302,
        ),
      );
      expect(DeliveryDisposition.created.isAccepted, isTrue);
      expect(DeliveryDisposition.alreadyExisting.isAccepted, isTrue);
      expect(DeliveryDisposition.conflict.isAccepted, isFalse);
    });

    test('a pause carries a status only for an unexpected response', () {
      expect(
        () => PausedDeliveryDecision(
          DeliveryPauseReason.authentication,
          unexpectedStatusCode: 401,
        ),
        throwsArgumentError,
      );
      expect(
        () => PausedDeliveryDecision(DeliveryPauseReason.unexpectedResponse),
        throwsArgumentError,
      );
      expect(
        PausedDeliveryDecision(DeliveryPauseReason.access).toString(),
        'PausedDeliveryDecision(access)',
      );
    });
  });

  group('DeliveryPresentationState', () {
    // **Validates: Requirements RNF-02.1–3, RF-23.11–12**
    test('has a fixed message per phase and no sensitive content', () {
      for (final phase in DeliveryPhase.values) {
        final state = DeliveryPresentationState(phase: phase);
        expect(state.message, isNotEmpty);
        expect(state.message, isNot(contains('http')));
      }
      expect(
        DeliveryPresentationState(phase: DeliveryPhase.idle).message,
        'Nenhuma pendência para envio.',
      );
    });

    test('enforces retry and schedule invariants and compares by value', () {
      final at = DateTime.utc(2025, 1, 1, 12);
      expect(
        DeliveryPresentationState(
          phase: DeliveryPhase.waitingBackoff,
          nextRetryAt: at,
        ),
        DeliveryPresentationState(
          phase: DeliveryPhase.waitingBackoff,
          nextRetryAt: at,
        ),
      );
      expect(
        () => DeliveryPresentationState(
          phase: DeliveryPhase.waitingBackoff,
          canRetry: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => DeliveryPresentationState(
            phase: DeliveryPhase.idle, nextRetryAt: at),
        throwsArgumentError,
      );
      expect(
        DeliveryPresentationState(
          phase: DeliveryPhase.pausedAccess,
          canRetry: true,
        ).canRetry,
        isTrue,
      );
    });
  });
}
