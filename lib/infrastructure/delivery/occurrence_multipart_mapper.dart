import '../../domain/delivery/occurrence_upload_request.dart';
import 'streaming_multipart_encoder.dart';

/// Maps one [OccurrenceUploadRequest] to the canonical RF-14 multipart parts
/// (design E4.7).
///
/// Only these parts are produced, in this fixed order:
///
/// - `idempotencyKey`, `latitude`, `longitude`, `confidence`, `defectClass`,
///   `detectedAt` (always);
/// - `speedKmh` (only when a value is persisted, including `0`);
/// - `image`, streamed with the generic filename [imageFilename] and
///   [imageContentType].
///
/// Values are written exactly as carried by the request: the persisted UUID,
/// the persisted ISO 8601 text, and the shortest round-trip decimal of each
/// persisted number. No path, digest, sequence, retry state, `highway`, `km`,
/// `source`, or `accuracyMeters` is ever mapped.
final class OccurrenceMultipartMapper {
  const OccurrenceMultipartMapper();

  /// Form field of the JPEG file.
  static const String imageFieldName = 'image';

  /// Generic filename; never derived from the private storage name or path.
  static const String imageFilename = 'occurrence.jpg';

  /// MIME type of the image part.
  static const String imageContentType = 'image/jpeg';

  /// Returns the ordered parts for [request].
  ///
  /// The image stream of [request] is attached, not read; it is consumed only
  /// when the encoded body is opened.
  List<MultipartPart> partsFor(OccurrenceUploadRequest request) {
    final payload = request.payload;
    final speedKmh = payload.speedKmh;
    return List<MultipartPart>.unmodifiable(<MultipartPart>[
      MultipartTextPart('idempotencyKey', request.idempotencyKey),
      MultipartTextPart('latitude', _number(payload.latitude)),
      MultipartTextPart('longitude', _number(payload.longitude)),
      MultipartTextPart('confidence', _number(payload.confidence)),
      MultipartTextPart('defectClass', payload.defectClass),
      MultipartTextPart('detectedAt', payload.detectedAtIso8601),
      if (speedKmh != null) MultipartTextPart('speedKmh', _number(speedKmh)),
      MultipartFilePart(
        imageFieldName,
        filename: imageFilename,
        contentType: imageContentType,
        length: payload.image.byteLength,
        source: request.imageStream,
      ),
    ]);
  }

  /// Maps and encodes [request] with [encoder] in one step.
  EncodedMultipartBody encode(
    OccurrenceUploadRequest request,
    StreamingMultipartEncoder encoder,
  ) =>
      encoder.encode(partsFor(request));

  /// Shortest decimal that parses back to the same double (`1.0`, `0.0`,
  /// `-23.5`). Accepted by the API's `Number(...)` parsing.
  static String _number(double value) => value.toString();
}
