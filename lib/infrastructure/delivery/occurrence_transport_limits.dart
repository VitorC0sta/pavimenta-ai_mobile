/// Fixed technical limits of one occurrence upload attempt (design E4.8).
///
/// The values are constants of the MVP. The constructor exists only so tests
/// can use short deadlines against a local server; production code uses
/// [standard].
final class OccurrenceTransportLimits {
  const OccurrenceTransportLimits({
    this.connectionTimeout = const Duration(seconds: 10),
    this.attemptTimeout = const Duration(seconds: 45),
    this.bodyDrainTimeout = const Duration(seconds: 5),
    this.maxDrainedBodyBytes = 64 * 1024,
  });

  /// The E4 production limits.
  static const OccurrenceTransportLimits standard = OccurrenceTransportLimits();

  /// Longest wait to establish the socket (and TLS session).
  final Duration connectionTimeout;

  /// Longest time from the start of the attempt until complete response
  /// headers arrive, covering connection, upload, and the wait for headers.
  final Duration attemptTimeout;

  /// Longest time spent draining the response body after the headers.
  final Duration bodyDrainTimeout;

  /// Most response-body bytes read before the body is abandoned (64 KiB).
  final int maxDrainedBodyBytes;

  /// Uploads allowed at the same time.
  static const int maxConcurrentUploads = 1;

  /// Redirects followed. A `3xx` is an ordinary response.
  static const int maxRedirects = 0;
}
