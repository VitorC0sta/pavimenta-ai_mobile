/// Outcome of one transport attempt.
///
/// Variants carry no header, URL, body, image, or raw exception. The only data
/// is the numeric status of a complete HTTP response.
sealed class OccurrenceTransportResult {
  const OccurrenceTransportResult();
}

/// Complete response headers were received. Once this exists the status is
/// authoritative, regardless of what happens to the response body.
final class TransportHttpResponse extends OccurrenceTransportResult {
  const TransportHttpResponse(this.statusCode);

  final int statusCode;

  @override
  bool operator ==(Object other) =>
      other is TransportHttpResponse && other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash(TransportHttpResponse, statusCode);

  @override
  String toString() => 'TransportHttpResponse($statusCode)';
}

/// Network, DNS, socket, or TLS failure before complete response headers.
final class TransportNetworkFailure extends OccurrenceTransportResult {
  const TransportNetworkFailure();

  @override
  String toString() => 'TransportNetworkFailure()';
}

/// Connection, upload, or wait for headers exceeded its deadline.
final class TransportTimeout extends OccurrenceTransportResult {
  const TransportTimeout();

  @override
  String toString() => 'TransportTimeout()';
}

/// The attempt was cancelled (lifecycle or disposal) before complete headers.
final class TransportCancelled extends OccurrenceTransportResult {
  const TransportCancelled();

  @override
  String toString() => 'TransportCancelled()';
}

/// The request could not be assembled or the image could not be read.
final class TransportLocalFailure extends OccurrenceTransportResult {
  const TransportLocalFailure();

  @override
  String toString() => 'TransportLocalFailure()';
}
