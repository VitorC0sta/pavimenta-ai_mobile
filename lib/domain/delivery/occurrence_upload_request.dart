import 'delivery_configuration.dart';
import 'delivery_queue_head.dart';
import 'non_printable_secret.dart';

/// Everything the transport needs for one attempt.
///
/// [baseUrl] and [credential] come from the same configuration snapshot
/// ([configurationRevision]). The transport adapter derives the final address
/// from [baseUrl]. The same [idempotencyKey], [payload], and image bytes are
/// used on every retry of the same occurrence.
///
/// Rendering the request never reveals the credential, the destination, or any
/// occurrence value.
final class OccurrenceUploadRequest {
  OccurrenceUploadRequest({
    required this.baseUrl,
    required this.credential,
    required this.configurationRevision,
    required this.idempotencyKey,
    required this.payload,
    required this.imageStream,
  });

  /// Builds a request using the destination and credential of one snapshot.
  factory OccurrenceUploadRequest.fromConfiguration({
    required DeliveryConfiguration configuration,
    required String idempotencyKey,
    required DeliveryOccurrencePayload payload,
    required Stream<List<int>> imageStream,
  }) =>
      OccurrenceUploadRequest(
        baseUrl: configuration.baseUrl,
        credential: configuration.credential,
        configurationRevision: configuration.revision,
        idempotencyKey: idempotencyKey,
        payload: payload,
        imageStream: imageStream,
      );

  /// Builds the request of one attempt for the persisted [eligible] head.
  ///
  /// The idempotency key and every transmitted value come only from the
  /// persisted representation selected by the queue, so each retry of the
  /// same occurrence reuses the same key, field values, and image reference.
  /// Nothing is generated here: no new UUID, no new `detectedAt`, and no image
  /// re-encoding. [imageStream] must be the queue stream of the persisted
  /// JPEG of [eligible]. Sequence and retry state stay in the queue head and
  /// are not carried by the request.
  factory OccurrenceUploadRequest.forEligibleHead({
    required DeliveryConfiguration configuration,
    required DeliveryHeadEligible eligible,
    required Stream<List<int>> imageStream,
  }) =>
      OccurrenceUploadRequest.fromConfiguration(
        configuration: configuration,
        idempotencyKey: eligible.head.idempotencyKey,
        payload: eligible.payload,
        imageStream: imageStream,
      );

  final Uri baseUrl;
  final NonPrintableSecret credential;
  final int configurationRevision;
  final String idempotencyKey;
  final DeliveryOccurrencePayload payload;

  /// Single-subscription stream of the JPEG bytes; its total length is
  /// `payload.image.byteLength`.
  final Stream<List<int>> imageStream;

  @override
  String toString() => 'OccurrenceUploadRequest(<redacted>)';
}
