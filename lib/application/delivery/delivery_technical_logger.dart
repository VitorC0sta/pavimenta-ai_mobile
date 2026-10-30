import '../../domain/delivery/delivery_decision.dart';

/// Technical log of delivery events with a closed, sanitized vocabulary.
///
/// Every method accepts only enumerations or the numeric HTTP status of an
/// unexpected response. There is deliberately no parameter for free text, an
/// exception, a URL, a header, a body, a credential, an identifier, a
/// coordinate, a timestamp, a file name, or a path, so a caller cannot leak
/// them through this port. The concrete sink belongs to infrastructure.
abstract interface class DeliveryTechnicalLogger {
  /// The server rejected the occurrence for good (never an accepted outcome).
  void definitiveRejection(DeliveryDisposition disposition);

  /// The server answered with a status the contract does not cover.
  void unexpectedResponse(int statusCode);

  /// An attempt failed in a way a later attempt may overcome.
  void recoverableFailure(RecoverableFailureCause cause);

  /// Removing a decided item from the local queue failed.
  void cleanupFailure();
}
