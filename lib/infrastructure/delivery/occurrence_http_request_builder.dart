import '../../domain/delivery/non_printable_secret.dart';
import 'streaming_multipart_encoder.dart';

/// Fixed categories of a local failure while building the wire request.
///
/// They carry no URL, host, header, credential, or raw exception.
enum OccurrenceHttpRequestFailure {
  /// The base URL is not an `http`/`https` origin, or carries a path other than
  /// `/`, a query, a fragment, or user information.
  invalidDestination,

  /// The credential cannot be sent as a single header token (empty, space,
  /// control character, or non-ASCII).
  invalidCredential,
}

/// Sanitized local failure of [OccurrenceHttpRequestBuilder]. No socket may be
/// opened for this attempt.
final class OccurrenceHttpRequestException implements Exception {
  const OccurrenceHttpRequestException(this.failure);

  final OccurrenceHttpRequestFailure failure;

  @override
  String toString() => 'OccurrenceHttpRequestException(${failure.name})';
}

/// The exact method, address, and headers of one occurrence upload.
///
/// Instances are created only by [OccurrenceHttpRequestBuilder]. The header map
/// is unmodifiable and holds exactly the credential header and the multipart
/// content type; `Content-Length` is declared separately through
/// [contentLength] so the transport adapter owns it.
///
/// Rendering never reveals the address or the headers.
final class OccurrenceHttpRequest {
  OccurrenceHttpRequest._({
    required this.method,
    required this.uri,
    required this.headers,
    required this.contentLength,
    required this.body,
  });

  /// Always `POST`.
  final String method;

  /// Always `{origin}/api/v1/occurrences`, with no query or fragment.
  final Uri uri;

  /// Exactly [OccurrenceHttpRequestBuilder.authorizationHeader] and
  /// [OccurrenceHttpRequestBuilder.contentTypeHeader].
  final Map<String, String> headers;

  /// Bytes [body] emits.
  final int contentLength;

  /// Single-use multipart stream.
  final Stream<List<int>> body;

  @override
  String toString() => 'OccurrenceHttpRequest(<redacted>)';
}

/// Builds the one request the MVP sends (design E4.7):
///
/// ```text
/// POST {BASE_URL}/api/v1/occurrences
/// Authorization: ApiKey {DEVICE_API_KEY}
/// Content-Type: multipart/form-data; boundary=<boundary>
/// ```
///
/// No `Bearer` scheme, `X-API-Key`, cookie, or alternative credential header
/// is ever produced, and the builder accepts no caller-supplied header, so none
/// can be added through it. Redirects are disabled by the transport adapter on
/// every request.
///
/// The credential is revealed once, inside [build], to compose the header.
/// Failures are sanitized and never include the destination or the credential.
final class OccurrenceHttpRequestBuilder {
  const OccurrenceHttpRequestBuilder();

  /// HTTP method of the occurrence upload.
  static const String method = 'POST';

  /// Path appended to the validated origin.
  static const String occurrencePath = '/api/v1/occurrences';

  /// Name of the single credential header.
  static const String authorizationHeader = 'Authorization';

  /// Name of the multipart content type header.
  static const String contentTypeHeader = 'Content-Type';

  /// Scheme token of the credential header value.
  static const String authorizationScheme = 'ApiKey';

  /// Returns the final address for [baseUrl], an origin already validated by
  /// the E3 rules.
  ///
  /// Throws [OccurrenceHttpRequestException] when [baseUrl] is not a plain
  /// `http`/`https` origin. Whether plain `http` is acceptable is the E3
  /// policy, already applied to the configuration snapshot.
  Uri endpointFor(Uri baseUrl) {
    final hasAllowedScheme =
        baseUrl.scheme == 'http' || baseUrl.scheme == 'https';
    final isPlainOrigin = baseUrl.host.isNotEmpty &&
        baseUrl.userInfo.isEmpty &&
        !baseUrl.hasQuery &&
        !baseUrl.hasFragment &&
        (baseUrl.path.isEmpty || baseUrl.path == '/');
    if (!hasAllowedScheme || !isPlainOrigin) {
      throw const OccurrenceHttpRequestException(
        OccurrenceHttpRequestFailure.invalidDestination,
      );
    }
    return baseUrl.replace(path: occurrencePath);
  }

  /// Returns the value `ApiKey {DEVICE_API_KEY}` for [credential].
  ///
  /// Throws [OccurrenceHttpRequestException] when the credential would not be
  /// a single header token.
  String authorizationValueFor(NonPrintableSecret credential) {
    final value = credential.reveal();
    final isHeaderToken = value.isNotEmpty &&
        value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7E);
    if (!isHeaderToken) {
      throw const OccurrenceHttpRequestException(
        OccurrenceHttpRequestFailure.invalidCredential,
      );
    }
    return '$authorizationScheme $value';
  }

  /// Builds the request for one attempt from the snapshot [baseUrl] and
  /// [credential] and the assembled multipart [body].
  ///
  /// Destination and credential are validated before [body] is opened, so a
  /// rejected attempt leaves the body (and its image read) untouched. On
  /// success [body] is marked opened, but its bytes are produced only when the
  /// returned request's stream is consumed by the transport adapter.
  OccurrenceHttpRequest build({
    required Uri baseUrl,
    required NonPrintableSecret credential,
    required EncodedMultipartBody body,
  }) {
    final uri = endpointFor(baseUrl);
    final authorization = authorizationValueFor(credential);
    return OccurrenceHttpRequest._(
      method: method,
      uri: uri,
      headers: Map<String, String>.unmodifiable(<String, String>{
        authorizationHeader: authorization,
        contentTypeHeader: body.contentType,
      }),
      contentLength: body.contentLength,
      body: body.open(),
    );
  }
}
