import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'image_artifacts.dart';

const String e1ImageNamespace = 'e1_images_v1';

typedef ImageTechnicalLogger = void Function(String message);
typedef PrivateFileDelete = Future<void> Function(File file);

/// Private, temporary E1 image storage.
///
/// The store never writes to shared storage or the device gallery. Production
/// instances are rooted below the platform-provided application temporary
/// directory. Tests may inject an application-private sandbox directory.
final class PrivateImageStore {
  PrivateImageStore._(
    this._rootDirectory, {
    required ImageTechnicalLogger logger,
    required PrivateFileDelete deleteFile,
  })  : _logger = logger,
        _deleteFile = deleteFile;

  static Future<PrivateImageStore> create({
    ImageTechnicalLogger logger = _discardLog,
  }) async {
    final temporaryDirectory = await getTemporaryDirectory();
    return PrivateImageStore.at(temporaryDirectory, logger: logger);
  }

  static PrivateImageStore at(
    Directory applicationPrivateTemporaryDirectory, {
    ImageTechnicalLogger logger = _discardLog,
    PrivateFileDelete? deleteFile,
  }) {
    return PrivateImageStore._(
      Directory(
        '${applicationPrivateTemporaryDirectory.path}'
        '${Platform.pathSeparator}$e1ImageNamespace',
      ),
      logger: logger,
      deleteFile: deleteFile ?? _deleteExistingFile,
    );
  }

  final Directory _rootDirectory;
  final ImageTechnicalLogger _logger;
  final PrivateFileDelete _deleteFile;
  int _sequence = 0;

  Directory get namespaceDirectory => _rootDirectory;

  Future<PrivateTemporaryCapture> createCapture(Uint8List bytes) async {
    await _ensureNamespace();
    final file = File(_nextPath(kind: 'source', extension: 'capture'));
    await file.writeAsBytes(bytes, flush: true);
    return PrivateTemporaryCapture._(_newLease(file, ImageArtifactKind.source));
  }

  /// Copies a plugin capture into the E1 private namespace and removes the
  /// plugin file. Failure to remove the source rejects adoption and removes
  /// the derivative so ownership can never become ambiguous.
  Future<PrivateTemporaryCapture> adoptCapture(File pluginCapture) async {
    await _ensureNamespace();
    final destination = File(_nextPath(kind: 'source', extension: 'capture'));
    var copied = false;
    try {
      await pluginCapture.copy(destination.path);
      copied = true;
      await _deleteFile(pluginCapture);
      return PrivateTemporaryCapture._(
        _newLease(destination, ImageArtifactKind.source),
      );
    } catch (error) {
      if (copied) {
        await _deleteSanitized(
          destination,
          operation: 'adopt_rollback',
          kind: ImageArtifactKind.source,
        );
      }
      _logFailure('adopt_capture', ImageArtifactKind.source, error);
      throw const ImageStorageException('Private capture adoption failed.');
    }
  }

  Future<PrivatePreparedImage> writePreparedJpeg({
    required Uint8List bytes,
    required int width,
    required int height,
    required int quality,
  }) async {
    await _ensureNamespace();
    final file = File(_nextPath(kind: 'prepared', extension: 'jpg'));
    try {
      await file.writeAsBytes(bytes, flush: true);
      return PrivatePreparedImage._(
        _newLease(file, ImageArtifactKind.prepared),
        width: width,
        height: height,
        byteLength: bytes.length,
        quality: quality,
      );
    } catch (error) {
      await _deleteSanitized(
        file,
        operation: 'prepared_write_rollback',
        kind: ImageArtifactKind.prepared,
      );
      _logFailure('write_prepared', ImageArtifactKind.prepared, error);
      throw const ImageStorageException('Private JPEG write failed.');
    }
  }

  /// Removes only direct children whose names match the E1-owned pattern.
  /// Other files and nested directories are never traversed or removed.
  Future<int> sweepRecognizedOrphans() async {
    if (!await _rootDirectory.exists()) {
      return 0;
    }

    var removed = 0;
    await for (final entity in _rootDirectory.list(followLinks: false)) {
      if (entity is! File || !_isRecognizedName(_basename(entity.path))) {
        continue;
      }
      final deleted = await _deleteSanitized(
        entity,
        operation: 'orphan_sweep',
        kind: _kindFromName(_basename(entity.path)),
      );
      if (deleted) {
        removed++;
      }
    }
    return removed;
  }

  _FileLease _newLease(File file, ImageArtifactKind kind) {
    return _FileLease(
      _FileLeaseState(
        file,
        kind: kind,
        logger: _logger,
        deleteFile: _deleteFile,
      ),
      0,
    );
  }

  Future<void> _ensureNamespace() => _rootDirectory.create(recursive: true);

  String _nextPath({required String kind, required String extension}) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final sequence = _sequence++;
    return '${_rootDirectory.path}${Platform.pathSeparator}'
        'e1_${kind}_${timestamp}_$sequence.$extension';
  }

  Future<bool> _deleteSanitized(
    File file, {
    required String operation,
    required ImageArtifactKind kind,
  }) async {
    try {
      await _deleteFile(file);
      return true;
    } catch (error) {
      _logFailure(operation, kind, error);
      return false;
    }
  }

  void _logFailure(String operation, ImageArtifactKind kind, Object error) {
    _logger(
      'E1_IMAGE_CLEANUP_FAILED operation=$operation '
      'kind=${kind.name} error=${error.runtimeType}',
    );
  }
}

enum ImageArtifactKind { source, prepared, unknown }

/// Concrete private capture lease consumed by [PrivateJpegImagePreparer].
final class PrivateTemporaryCapture implements TemporaryCapture {
  PrivateTemporaryCapture._(this._lease);

  final _FileLease _lease;

  File get file => _lease.file;
  bool get isActive => _lease.isActive;

  @override
  Future<void> dispose() => _lease.dispose();
}

/// JPEG metadata plus an exclusive, idempotently withdrawable file lease.
final class PrivatePreparedImage implements PreparedImageLease {
  PrivatePreparedImage._(
    this._lease, {
    required this.width,
    required this.height,
    required this.byteLength,
    required this.quality,
  });

  final _FileLease _lease;
  final int width;
  final int height;
  final int byteLength;
  final int quality;

  String get mimeType => 'image/jpeg';
  File get file => _lease.file;
  bool get isActive => _lease.isActive;

  @override
  bool get hasOwnership => isActive;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: mimeType,
        byteLength: byteLength,
        width: width,
        height: height,
        quality: quality,
      );

  @override
  Stream<List<int>> openRead() => _lease.openRead();

  /// Promotes ownership without exposing a filesystem path to E2 contracts.
  @override
  PrivatePreparedImage promoteOwnership() {
    return PrivatePreparedImage._(
      _lease.transfer(),
      width: width,
      height: height,
      byteLength: byteLength,
      quality: quality,
    );
  }

  /// Backwards-compatible E1 handoff name.
  PrivatePreparedImage transferOwnership() => promoteOwnership();

  @override
  Future<void> withdrawOwnership() => _lease.dispose();

  @override
  Future<void> dispose() => withdrawOwnership();
}

/// Owns at most one prepared image for the current E1 in-memory session.
/// Replacing or ending the session deterministically releases the prior JPEG.
final class InMemoryImageOwner {
  PrivatePreparedImage? _current;
  bool _isDisposed = false;

  PrivatePreparedImage? get current => _current;

  Future<PrivatePreparedImage> replace(PrivatePreparedImage image) async {
    if (_isDisposed) {
      throw StateError('The in-memory image owner is disposed.');
    }
    final accepted = image.transferOwnership();
    final previous = _current;
    _current = accepted;
    await previous?.dispose();
    return accepted;
  }

  Future<void> clear() async {
    final previous = _current;
    _current = null;
    await previous?.dispose();
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await clear();
  }
}

final class ImageStorageException implements Exception {
  const ImageStorageException(this.message);
  final String message;

  @override
  String toString() => 'ImageStorageException: $message';
}

final class _FileLeaseState {
  _FileLeaseState(
    this.file, {
    required this.kind,
    required this.logger,
    required this.deleteFile,
  });

  final File file;
  final ImageArtifactKind kind;
  final ImageTechnicalLogger logger;
  final PrivateFileDelete deleteFile;
  int activeToken = 0;
  bool deleted = false;
}

final class _FileLease {
  _FileLease(this._state, this._token);

  final _FileLeaseState _state;
  final int _token;

  File get file => _state.file;
  bool get isActive => !_state.deleted && _state.activeToken == _token;

  Stream<List<int>> openRead() {
    if (!isActive) {
      throw StateError('Image ownership is no longer active.');
    }
    return _state.file.openRead();
  }

  _FileLease transfer() {
    if (!isActive) {
      throw StateError('Image ownership has already been transferred.');
    }
    final nextToken = ++_state.activeToken;
    return _FileLease(_state, nextToken);
  }

  Future<void> dispose() async {
    if (!isActive) {
      return;
    }
    _state.deleted = true;
    try {
      await _state.deleteFile(_state.file);
    } catch (error) {
      _state.logger(
        'E1_IMAGE_CLEANUP_FAILED operation=lease_dispose '
        'kind=${_state.kind.name} error=${error.runtimeType}',
      );
    }
  }
}

bool _isRecognizedName(String name) {
  return RegExp(r'^e1_(source|prepared)_\d+_\d+\.(capture|jpg)$')
      .hasMatch(name);
}

ImageArtifactKind _kindFromName(String name) {
  if (name.startsWith('e1_source_')) {
    return ImageArtifactKind.source;
  }
  if (name.startsWith('e1_prepared_')) {
    return ImageArtifactKind.prepared;
  }
  return ImageArtifactKind.unknown;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

Future<void> _deleteExistingFile(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

void _discardLog(String _) {}
