import 'delivery_decision.dart';

/// Classifies a complete HTTP response by its status code alone (RF-15–18).
///
/// Pure and stateless: it never receives, and therefore can never depend on,
/// the response body or headers. Network failures, timeouts, and cancellation
/// have no status and are outside this policy.
///
/// | Status                      | Decision                                   |
/// |-----------------------------|--------------------------------------------|
/// | 201                         | definitive: created                        |
/// | 200                         | definitive: already existing (idempotent)  |
/// | 400                         | definitive: invalid contract               |
/// | 409                         | definitive: conflict                       |
/// | 413                         | definitive: image too large                |
/// | 415                         | definitive: unsupported format             |
/// | 401                         | pause: authentication                      |
/// | 403                         | pause: access                              |
/// | 500–599                     | recoverable: server error                  |
/// | any other, including 3xx    | pause: unexpected response (keeps status)  |
abstract final class HttpDeliveryDecisionPolicy {
  static DeliveryDecision classify(int statusCode) {
    switch (statusCode) {
      case 201:
        return const DefinitiveDeliveryDecision(DeliveryDisposition.created);
      case 200:
        return const DefinitiveDeliveryDecision(
          DeliveryDisposition.alreadyExisting,
        );
      case 400:
        return const DefinitiveDeliveryDecision(
          DeliveryDisposition.invalidContract,
        );
      case 409:
        return const DefinitiveDeliveryDecision(DeliveryDisposition.conflict);
      case 413:
        return const DefinitiveDeliveryDecision(
          DeliveryDisposition.imageTooLarge,
        );
      case 415:
        return const DefinitiveDeliveryDecision(
          DeliveryDisposition.unsupportedFormat,
        );
      case 401:
        return PausedDeliveryDecision(DeliveryPauseReason.authentication);
      case 403:
        return PausedDeliveryDecision(DeliveryPauseReason.access);
    }
    if (statusCode >= 500 && statusCode <= 599) {
      return const RecoverableDeliveryDecision(
        RecoverableFailureCause.serverError,
      );
    }
    // Includes every other 1xx/2xx/4xx code, all 3xx redirects (never
    // followed), and values outside the HTTP range.
    return PausedDeliveryDecision(
      DeliveryPauseReason.unexpectedResponse,
      unexpectedStatusCode: statusCode,
    );
  }
}
