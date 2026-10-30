import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/application/delivery/delivery_technical_logger.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_decision.dart';
import 'package:pavimenta_ai_mobile/infrastructure/sanitized_delivery_technical_logger.dart';

// Explicitly fictitious values; none is a real key, URL, or identifier.
const List<String> _forbiddenFragments = <String>[
  'fakeprefix',
  'fake-secret',
  'authorization',
  'x-api-key',
  'bearer',
  'http',
  'example.invalid',
  'multipart',
  'boundary',
  'content-type',
  '.jpg',
  '/data/',
  'sha256',
  '11111111-2222-4333-8444-555555555555',
  '2025-01-01',
  '-23.55',
  '-46.63',
  'exception',
  'stacktrace',
];

final RegExp _lineShape = RegExp(
  r'^E4_DELIVERY_[A-Z_]+( (disposition|status|cause)=[A-Za-z0-9]+)?$',
);

void main() {
  group('SanitizedDeliveryTechnicalLogger', () {
    late List<String> lines;
    late DeliveryTechnicalLogger logger;

    setUp(() {
      lines = <String>[];
      logger = SanitizedDeliveryTechnicalLogger(lines.add);
    });

    // **Validates: Requirements RF-23.11–12, RNF-02.1–3, RNF-03.8–10**
    test('exposes the four fixed categories with stable codes', () {
      expect(
        DeliveryLogCategory.values.map((c) => c.code),
        <String>[
          'E4_DELIVERY_DEFINITIVE_REJECTION',
          'E4_DELIVERY_UNEXPECTED_RESPONSE',
          'E4_DELIVERY_RECOVERABLE_FAILURE',
          'E4_DELIVERY_CLEANUP_FAILURE',
        ],
      );
    });

    test('emits the definitive-rejection category for every rejection', () {
      final rejections =
          DeliveryDisposition.values.where((d) => !d.isAccepted).toList();
      expect(rejections, isNotEmpty);

      for (final disposition in rejections) {
        logger.definitiveRejection(disposition);
      }

      expect(lines, <String>[
        for (final d in rejections)
          'E4_DELIVERY_DEFINITIVE_REJECTION disposition=${d.name}',
      ]);
    });

    test('never logs an accepted outcome as a rejection', () {
      for (final disposition
          in DeliveryDisposition.values.where((d) => d.isAccepted)) {
        logger.definitiveRejection(disposition);
      }

      expect(lines, isEmpty);
    });

    test('emits the unexpected-response category with the numeric status', () {
      logger
        ..unexpectedResponse(302)
        ..unexpectedResponse(404)
        ..unexpectedResponse(100)
        ..unexpectedResponse(599);

      expect(lines, <String>[
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=302',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=404',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=100',
        'E4_DELIVERY_UNEXPECTED_RESPONSE status=599',
      ]);
    });

    test('collapses an out-of-range status to a fixed token', () {
      for (final status in <int>[-1, 0, 99, 600, 123456789]) {
        logger.unexpectedResponse(status);
      }

      expect(
        lines,
        everyElement('E4_DELIVERY_UNEXPECTED_RESPONSE status=invalid'),
      );
      expect(lines, hasLength(5));
    });

    test('emits the recoverable-failure category for every cause', () {
      for (final cause in RecoverableFailureCause.values) {
        logger.recoverableFailure(cause);
      }

      expect(lines, <String>[
        for (final c in RecoverableFailureCause.values)
          'E4_DELIVERY_RECOVERABLE_FAILURE cause=${c.name}',
      ]);
    });

    test('emits the cleanup-failure category with no payload', () {
      logger.cleanupFailure();

      expect(lines, <String>['E4_DELIVERY_CLEANUP_FAILURE']);
    });

    test('every possible line has the fixed shape and no forbidden content',
        () {
      for (final d in DeliveryDisposition.values) {
        logger.definitiveRejection(d);
      }
      for (var status = -5; status <= 700; status++) {
        logger.unexpectedResponse(status);
      }
      for (final c in RecoverableFailureCause.values) {
        logger.recoverableFailure(c);
      }
      logger.cleanupFailure();

      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(_lineShape.hasMatch(line), isTrue, reason: line);
        final lower = line.toLowerCase();
        for (final fragment in _forbiddenFragments) {
          expect(lower, isNot(contains(fragment)), reason: line);
        }
      }
    });

    test('a failing sink never reaches the delivery flow', () {
      final failing = SanitizedDeliveryTechnicalLogger(
        (_) => throw StateError('sink broke at /data/user/0/secret.jpg'),
      );

      expect(() => failing.definitiveRejection(DeliveryDisposition.conflict),
          returnsNormally);
      expect(() => failing.unexpectedResponse(302), returnsNormally);
      expect(
        () => failing.recoverableFailure(RecoverableFailureCause.timeout),
        returnsNormally,
      );
      expect(failing.cleanupFailure, returnsNormally);
    });

    test('the discarding logger accepts every event without effect', () {
      const discarding = SanitizedDeliveryTechnicalLogger.discarding();

      expect(() {
        discarding
          ..definitiveRejection(DeliveryDisposition.imageTooLarge)
          ..unexpectedResponse(301)
          ..recoverableFailure(RecoverableFailureCause.network)
          ..cleanupFailure();
      }, returnsNormally);
    });
  });
}
