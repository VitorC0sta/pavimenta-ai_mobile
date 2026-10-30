import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/http_delivery_decision_policy.dart';

void main() {
  group('HttpDeliveryDecisionPolicy', () {
    // **Validates: Requirements RF-15.1–8, RF-16.1–4, RF-17.1, RF-18.1–3**
    test('maps definitive statuses to their dispositions', () {
      const expected = <int, DeliveryDisposition>{
        200: DeliveryDisposition.alreadyExisting,
        201: DeliveryDisposition.created,
        400: DeliveryDisposition.invalidContract,
        409: DeliveryDisposition.conflict,
        413: DeliveryDisposition.imageTooLarge,
        415: DeliveryDisposition.unsupportedFormat,
      };
      expected.forEach((status, disposition) {
        expect(
          HttpDeliveryDecisionPolicy.classify(status),
          DefinitiveDeliveryDecision(disposition),
          reason: 'status $status',
        );
      });
    });

    test('pauses for authentication and access', () {
      expect(
        HttpDeliveryDecisionPolicy.classify(401),
        PausedDeliveryDecision(DeliveryPauseReason.authentication),
      );
      expect(
        HttpDeliveryDecisionPolicy.classify(403),
        PausedDeliveryDecision(DeliveryPauseReason.access),
      );
    });

    test('treats every 5xx as recoverable', () {
      for (var status = 500; status <= 599; status++) {
        expect(
          HttpDeliveryDecisionPolicy.classify(status),
          const RecoverableDeliveryDecision(
              RecoverableFailureCause.serverError),
          reason: 'status $status',
        );
      }
    });

    test('pauses conservatively on 3xx and other unspecified codes', () {
      for (final status in <int>[
        100, 202, 204, 301, 302, 304, 307, 308, 399, //
        402, 404, 408, 410, 422, 429, 499, 600, 0, -1,
      ]) {
        expect(
          HttpDeliveryDecisionPolicy.classify(status),
          PausedDeliveryDecision(
            DeliveryPauseReason.unexpectedResponse,
            unexpectedStatusCode: status,
          ),
          reason: 'status $status',
        );
      }
    });

    // **Validates: Requirements RF-15.1–8, RF-16.1–4, RF-17.1, RF-18.1–3**
    test('depends on the status code alone, never on body or headers', () {
      // The policy signature accepts only the numeric status, so a body or
      // header cannot influence it; repeated calls are deterministic.
      const DeliveryDecision Function(int) classify =
          HttpDeliveryDecisionPolicy.classify;
      for (var status = 0; status <= 700; status++) {
        expect(classify(status), classify(status), reason: 'status $status');
      }
    });

    test('only the six listed statuses are definitive', () {
      final definitive = <int>[
        for (var status = 0; status <= 700; status++)
          if (HttpDeliveryDecisionPolicy.classify(status)
              is DefinitiveDeliveryDecision)
            status,
      ];
      expect(definitive, <int>[200, 201, 400, 409, 413, 415]);
    });
  });
}
