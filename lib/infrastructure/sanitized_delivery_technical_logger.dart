import '../application/delivery/delivery_technical_logger.dart';
import '../domain/delivery/delivery_decision.dart';

/// Receives one already-sanitized line of the E4 delivery technical log.
typedef DeliveryTechnicalLogSink = void Function(String line);

/// Fixed categories of the E4 delivery technical log.
///
/// The [code] values are the only event names that can ever be emitted.
enum DeliveryLogCategory {
  definitiveRejection('E4_DELIVERY_DEFINITIVE_REJECTION'),
  unexpectedResponse('E4_DELIVERY_UNEXPECTED_RESPONSE'),
  recoverableFailure('E4_DELIVERY_RECOVERABLE_FAILURE'),
  cleanupFailure('E4_DELIVERY_CLEANUP_FAILURE');

  const DeliveryLogCategory(this.code);

  final String code;
}

/// [DeliveryTechnicalLogger] that writes only fixed-vocabulary lines to a sink.
///
/// A line is `<category code>` optionally followed by one `key=value` pair
/// whose value is an enum name or a three-digit HTTP status. Nothing else is
/// representable: no credential, header, URL, body, multipart, image,
/// identifier, coordinate, occurrence time, file name, path, digest, or raw
/// exception can reach the sink, because the port has no parameter for them.
///
/// A failing sink never propagates into the delivery flow.
final class SanitizedDeliveryTechnicalLogger
    implements DeliveryTechnicalLogger {
  const SanitizedDeliveryTechnicalLogger(this._sink);

  /// Logger that discards every event.
  const SanitizedDeliveryTechnicalLogger.discarding() : _sink = _discard;

  final DeliveryTechnicalLogSink _sink;

  @override
  void definitiveRejection(DeliveryDisposition disposition) {
    // Accepted outcomes are not rejections and are never logged as such.
    if (disposition.isAccepted) return;
    _emit(
      DeliveryLogCategory.definitiveRejection,
      'disposition',
      disposition.name,
    );
  }

  @override
  void unexpectedResponse(int statusCode) {
    final valid = statusCode >= 100 && statusCode <= 599;
    _emit(
      DeliveryLogCategory.unexpectedResponse,
      'status',
      valid ? '$statusCode' : 'invalid',
    );
  }

  @override
  void recoverableFailure(RecoverableFailureCause cause) {
    _emit(DeliveryLogCategory.recoverableFailure, 'cause', cause.name);
  }

  @override
  void cleanupFailure() {
    _emit(DeliveryLogCategory.cleanupFailure);
  }

  void _emit(DeliveryLogCategory category, [String? key, String? value]) {
    final line = key == null ? category.code : '${category.code} $key=$value';
    try {
      _sink(line);
    } catch (_) {
      // Logging must never alter the delivery outcome.
    }
  }
}

void _discard(String _) {}
