/// Opaque capture owned by the infrastructure boundary.
///
/// Disposal is idempotent so application flows can guarantee cleanup without
/// depending on a concrete filesystem implementation.
abstract interface class TemporaryCapture {
  Future<void> dispose();
}

/// Opaque prepared image owned by the application flow.
///
/// A successful occurrence assumes this lease; every unsuccessful flow must
/// dispose it.
abstract interface class OwnedPreparedImage {
  Future<void> dispose();
}

/// Immutable metadata required to validate and persist a prepared JPEG.
final class PreparedImageMetadata {
  const PreparedImageMetadata({
    required this.mimeType,
    required this.byteLength,
    required this.width,
    required this.height,
    required this.quality,
  });

  final String mimeType;
  final int byteLength;
  final int width;
  final int height;
  final int quality;
}

/// Prepared E1 image lease that can be promoted to the durable E2 boundary.
///
/// The lease exposes streaming reads rather than a path or byte buffer.
/// Promotion invalidates the previous owner. Withdrawal is idempotent and
/// retains E1 cleanup semantics for every unsuccessful persistence path.
abstract interface class PreparedImageLease implements OwnedPreparedImage {
  PreparedImageMetadata get metadata;

  bool get hasOwnership;

  Stream<List<int>> openRead();

  PreparedImageLease promoteOwnership();

  Future<void> withdrawOwnership();
}
