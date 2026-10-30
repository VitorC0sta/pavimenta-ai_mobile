/// Remote outcome that ends the life of a queued occurrence.
///
/// The enum names are the stable values persisted as the pending local
/// disposition. They describe the remote decision, never a response body.
enum DeliveryDisposition {
  /// HTTP 201: the occurrence was created.
  created,

  /// HTTP 200: the occurrence already existed (idempotent repetition).
  alreadyExisting,

  /// HTTP 400: invalid contract, field, or media type.
  invalidContract,

  /// HTTP 409: protected conflict.
  conflict,

  /// HTTP 413: image above the accepted limit.
  imageTooLarge,

  /// HTTP 415: unsupported format.
  unsupportedFormat;

  /// Whether the server accepted the occurrence (as opposed to rejecting it).
  bool get isAccepted => this == created || this == alreadyExisting;
}

/// Why a delivery stopped until an explicit resume.
enum DeliveryPauseReason {
  authentication,
  access,
  unexpectedResponse,
  localFailure,
}

/// Why an attempt failed in a way that a later attempt may overcome.
enum RecoverableFailureCause { serverError, network, timeout }

/// Result of classifying one attempt.
///
/// Decisions carry only closed values (and, for an unexpected response, the
/// numeric status). They never carry headers, URLs, bodies, or exceptions.
sealed class DeliveryDecision {
  const DeliveryDecision();
}

/// The remote side reached a final verdict: the item must be removed locally
/// and never resent.
final class DefinitiveDeliveryDecision extends DeliveryDecision {
  const DefinitiveDeliveryDecision(this.disposition);

  final DeliveryDisposition disposition;

  @override
  bool operator ==(Object other) =>
      other is DefinitiveDeliveryDecision && other.disposition == disposition;

  @override
  int get hashCode => Object.hash(DefinitiveDeliveryDecision, disposition);

  @override
  String toString() => 'DefinitiveDeliveryDecision(${disposition.name})';
}

/// The item is preserved and the attempt is repeated after a backoff.
final class RecoverableDeliveryDecision extends DeliveryDecision {
  const RecoverableDeliveryDecision(this.cause);

  final RecoverableFailureCause cause;

  @override
  bool operator ==(Object other) =>
      other is RecoverableDeliveryDecision && other.cause == cause;

  @override
  int get hashCode => Object.hash(RecoverableDeliveryDecision, cause);

  @override
  String toString() => 'RecoverableDeliveryDecision(${cause.name})';
}

/// The item is preserved and automation stops until an explicit resume.
final class PausedDeliveryDecision extends DeliveryDecision {
  /// [unexpectedStatusCode] is allowed only for
  /// [DeliveryPauseReason.unexpectedResponse].
  PausedDeliveryDecision(this.reason, {this.unexpectedStatusCode}) {
    if ((unexpectedStatusCode != null) !=
        (reason == DeliveryPauseReason.unexpectedResponse)) {
      throw ArgumentError(
        'A status code is required for, and only for, an unexpected response.',
      );
    }
  }

  final DeliveryPauseReason reason;
  final int? unexpectedStatusCode;

  @override
  bool operator ==(Object other) =>
      other is PausedDeliveryDecision &&
      other.reason == reason &&
      other.unexpectedStatusCode == unexpectedStatusCode;

  @override
  int get hashCode =>
      Object.hash(PausedDeliveryDecision, reason, unexpectedStatusCode);

  @override
  String toString() => unexpectedStatusCode == null
      ? 'PausedDeliveryDecision(${reason.name})'
      : 'PausedDeliveryDecision(${reason.name}, $unexpectedStatusCode)';
}
