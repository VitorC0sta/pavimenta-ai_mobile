import '../../domain/delivery/occurrence_transport_result.dart';
import '../../domain/delivery/occurrence_upload_request.dart';

/// Sends one occurrence to the remote API (design E4.4).
///
/// The contract is independent of any HTTP client. An implementation owns the
/// wire details (final address, credential header, body encoding, timeouts,
/// redirect handling) and reports only a sanitized [OccurrenceTransportResult].
abstract interface class OccurrenceTransportPort {
  /// Performs one attempt for [request].
  ///
  /// It never throws for network, timeout, cancellation, or local assembly
  /// problems: each is a distinct result variant. It must not retain the
  /// credential after the returned future completes.
  Future<OccurrenceTransportResult> send(OccurrenceUploadRequest request);

  /// Cancels the attempt in flight, if any.
  ///
  /// The pending [send] completes with `TransportCancelled` unless complete
  /// response headers had already arrived. Safe to call with nothing active.
  Future<void> cancelActive();
}
