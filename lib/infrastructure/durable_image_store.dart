import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image_codec;
import 'package:path_provider/path_provider.dart';

import '../application/e2_persistence_ports.dart';
import '../domain/persistent_occurrence.dart';
import 'image_artifacts.dart';
import 'private_jpeg_image_preparer.dart';

const String e2DurableImageNamespace = 'e2_queue_images_v1';
const int _maximumNameAttempts = 32;

final RegExp _stagingNamePattern = RegExp(r'^e2s_[0-9a-f]{32}\.staging$');
final RegExp _opaqueTokenPattern = RegExp(r'^[0-9a-f]{32}$');

typedef E2ImageTechnicalLogger = void Function(String message);
typedef E2ApplicationSupportDirectoryProvider = Future<Directory> Function();
typedef E2DurableFileDelete = Future<void> Function(File file);
typedef E2DurableFileFlush = Future<void> Function(RandomAccessFile file);
typedef E2OpaqueTokenGenerator = String Function();

/// Canonical, data-independent naming contract for durable E2 images.
///
/// Tokens are generated independently from occurrence metadata. The deleting
/// form contains only the already-opaque canonical token and a distinct
/// operation token, so it can be recognized and reversed during recovery.
final class E2DurableImageNameCodec {
  const E2DurableImageNameCodec();

  static final RegExp _canonicalPattern = RegExp(r'^e2i_([0-9a-f]{32})\.jpg$');
  static final RegExp _deletingPattern =
      RegExp(r'^e2d_([0-9a-f]{32})_([0-9a-f]{32})\.deleting$');

  String canonicalName(String opaqueToken) {
    _validateOpaqueToken(opaqueToken);
    return 'e2i_$opaqueToken.jpg';
  }

  String deletingMarker({
    required String canonicalName,
    required String operationToken,
  }) {
    final canonical = _canonicalPattern.firstMatch(canonicalName);
    if (canonical == null) {
      throw const DurableImageStorageException('invalid_relative_name');
    }
    _validateOpaqueToken(operationToken);
    return 'e2d_${canonical.group(1)}_$operationToken.deleting';
  }

  bool isCanonicalName(String name) => _canonicalPattern.hasMatch(name);

  /// Returns the canonical name encoded by a recognized marker.
  String? canonicalNameFromDeletingMarker(String name) {
    final deleting = _deletingPattern.firstMatch(name);
    if (deleting == null) {
      return null;
    }
    return canonicalName(deleting.group(1)!);
  }

  void _validateOpaqueToken(String token) {
    if (!_opaqueTokenPattern.hasMatch(token)) {
      throw const DurableImageStorageException('invalid_opaque_token');
    }
  }
}

const E2DurableImageNameCodec _imageNameCodec = E2DurableImageNameCodec();

/// Filesystem implementation of E2 private durable JPEG ownership.
///
/// Production instances are rooted strictly below the platform application
/// support directory. All public references are opaque direct-child names.
final class PrivateDurableImageStore implements DurableImageStore {
  PrivateDurableImageStore._(
    this._namespace, {
    required E2ImageTechnicalLogger logger,
    required E2DurableFileDelete deleteFile,
    required E2DurableFileFlush flushFile,
    required E2OpaqueTokenGenerator tokenGenerator,
  })  : _logger = logger,
        _deleteFile = deleteFile,
        _flushFile = flushFile,
        _tokenGenerator = tokenGenerator;

  static Future<PrivateDurableImageStore> create({
    E2ImageTechnicalLogger logger = _discardLog,
    E2ApplicationSupportDirectoryProvider supportDirectoryProvider =
        getApplicationSupportDirectory,
  }) async {
    final supportDirectory = await supportDirectoryProvider();
    final store = PrivateDurableImageStore.at(
      supportDirectory,
      logger: logger,
    );
    await store._ensureNamespace();
    return store;
  }

  /// Creates a store below an injected private support root for tests.
  static PrivateDurableImageStore at(
    Directory applicationSupportDirectory, {
    E2ImageTechnicalLogger logger = _discardLog,
    E2DurableFileDelete? deleteFile,
    E2DurableFileFlush? flushFile,
    E2OpaqueTokenGenerator? tokenGenerator,
  }) {
    return PrivateDurableImageStore._(
      Directory(
        _appendPath(applicationSupportDirectory.path, e2DurableImageNamespace),
      ),
      logger: logger,
      deleteFile: deleteFile ?? _deleteExistingFile,
      flushFile: flushFile ?? _flushRandomAccessFile,
      tokenGenerator: tokenGenerator ?? _SecureOpaqueTokenGenerator().next,
    );
  }

  final Directory _namespace;
  final E2ImageTechnicalLogger _logger;
  final E2DurableFileDelete _deleteFile;
  final E2DurableFileFlush _flushFile;
  final E2OpaqueTokenGenerator _tokenGenerator;

  @override
  Future<DurableImageStaging> stage(PreparedImageLease source) async {
    _validatePreparedSource(source);
    await _ensureNamespace();

    File? staging;
    try {
      staging = await _createExclusiveStaging();
      final copy = await _copyFlushAndHash(source, staging);
      await _validateCopiedJpeg(staging, source.metadata, copy);
      return _PrivateDurableImageStaging._(
        store: this,
        staging: staging,
        metadata: source.metadata,
        copy: copy,
      );
    } catch (error) {
      if (staging != null) {
        await _deleteSanitized(staging, operation: 'stage_cleanup');
      }
      _logFailure('stage', error);
      throw error is DurableImageStorageException
          ? error
          : const DurableImageStorageException('staging_failed');
    }
  }

  @override
  Future<PersistedImageProjection> promote(PreparedImageLease source) async {
    _validatePreparedSource(source);
    await _ensureNamespace();

    File? staging;
    File? published;
    var completed = false;
    try {
      staging = await _createExclusiveStaging();
      final copy = await _copyFlushAndHash(source, staging);
      await _validateCopiedJpeg(staging, source.metadata, copy);

      final canonical = await _chooseUnusedCanonical();
      await _renameWithoutReplacement(staging, canonical);
      published = canonical;
      staging = null;

      final projection = PersistedImageProjection(
        relativeName: _basename(canonical.path),
        mimeType: source.metadata.mimeType,
        byteLength: copy.byteLength,
        sha256: copy.sha256,
        width: source.metadata.width,
        height: source.metadata.height,
        quality: source.metadata.quality,
      );
      if (await inspect(projection) != DurableImageIntegrity.valid) {
        throw const DurableImageStorageException('durable_validation_failed');
      }

      await source.withdrawOwnership();
      completed = true;
      return projection;
    } catch (error) {
      _logFailure('promote', error);
      throw error is DurableImageStorageException
          ? error
          : const DurableImageStorageException('promotion_failed');
    } finally {
      if (!completed) {
        if (staging != null) {
          await _deleteSanitized(staging, operation: 'promote_staging_cleanup');
        }
        if (published != null) {
          await _deleteSanitized(
            published,
            operation: 'promote_canonical_rollback',
          );
        }
      }
    }
  }

  @override
  Stream<List<int>> openRead(PersistedImageProjection image) async* {
    _validateProjectionMetadata(image);
    await _ensureNamespace();
    final file = await _resolveCanonical(image.relativeName);
    if (file == null) {
      throw const DurableImageStorageException('durable_image_missing');
    }
    yield* file.openRead();
  }

  @override
  Future<DurableImageIntegrity> inspect(
    PersistedImageProjection image,
  ) async {
    try {
      _validateProjectionMetadata(image);
      await _ensureNamespace();
      final file = await _resolveCanonical(image.relativeName);
      if (file == null) {
        return DurableImageIntegrity.missing;
      }
      final copy = await _hashFile(file);
      if (copy.byteLength != image.byteLength || copy.sha256 != image.sha256) {
        return DurableImageIntegrity.invalid;
      }
      final bytes = await file.readAsBytes();
      final decoded = image_codec.decodeJpg(bytes);
      if (!_hasJpegEnvelope(bytes) ||
          decoded == null ||
          decoded.width != image.width ||
          decoded.height != image.height) {
        return DurableImageIntegrity.invalid;
      }
      return DurableImageIntegrity.valid;
    } on DurableImageStorageException {
      return DurableImageIntegrity.invalid;
    } on FileSystemException {
      return DurableImageIntegrity.invalid;
    } catch (_) {
      return DurableImageIntegrity.invalid;
    }
  }

  @override
  Future<void> delete(PersistedImageProjection image) async {
    _validateCanonicalName(image.relativeName);
    await _ensureNamespace();

    final canonical = await _resolveCanonical(image.relativeName);
    if (canonical != null) {
      final marker = await _chooseUnusedDeletingMarker(image.relativeName);
      try {
        await _renameWithoutReplacement(canonical, marker);
      } catch (error) {
        _logFailure('delete_mark', error);
        throw const DurableImageStorageException('deletion_failed');
      }
    }

    final markers = await _deletingMarkersFor(image.relativeName);
    for (final marker in markers) {
      final deleted = await _deleteSanitized(
        marker,
        operation: 'delete_marker_cleanup',
      );
      if (!deleted) {
        throw const DurableImageStorageException('deletion_failed');
      }
    }
  }

  @override
  Future<DurableImageDeletion> markForDeletion(
    PersistedImageProjection image,
  ) async {
    _validateProjectionMetadata(image);
    await _ensureNamespace();

    final canonical = await _resolveCanonical(image.relativeName);
    if (canonical == null) {
      throw const DurableImageStorageException('durable_image_missing');
    }
    final marker = await _chooseUnusedDeletingMarker(image.relativeName);
    try {
      await _renameWithoutReplacement(canonical, marker);
      return _PrivateDurableImageDeletion._(this, marker);
    } catch (error) {
      _logFailure('mark_for_deletion', error);
      throw const DurableImageStorageException('deletion_failed');
    }
  }

  /// Reconciles direct, recognized E2 artifacts only.
  ///
  /// Staging files are retired. Deleting markers are restored when their
  /// canonical name remains referenced, otherwise they are retired. Canonical
  /// JPEGs absent from [referencedCanonicalNames] are retired as orphans.
  @override
  Future<DurableImageSweepResult> sweep(
    Set<String> referencedCanonicalNames,
  ) async {
    for (final name in referencedCanonicalNames) {
      _validateCanonicalName(name);
    }
    await _ensureNamespace();

    var removedStaging = 0;
    var removedDeleting = 0;
    var removedCanonical = 0;
    var restoredDeleting = 0;
    var failedOperations = 0;

    await for (final entity in _namespace.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        continue;
      }
      // Never act on the path yielded by directory enumeration. Rebuild a
      // direct child from its basename so every recovery mutation is rooted in
      // this store's E2 namespace, even if a filesystem implementation yields
      // an unexpected path representation.
      final name = _basename(entity.path);
      final file = _directNamespaceFile(name);

      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }

      if (_stagingNamePattern.hasMatch(name)) {
        if (await _deleteSanitized(file, operation: 'sweep_staging')) {
          removedStaging++;
        } else {
          failedOperations++;
        }
        continue;
      }

      final canonicalName =
          _imageNameCodec.canonicalNameFromDeletingMarker(name);
      if (canonicalName != null) {
        if (!referencedCanonicalNames.contains(canonicalName)) {
          if (await _deleteSanitized(file, operation: 'sweep_deleting')) {
            removedDeleting++;
          } else {
            failedOperations++;
          }
          continue;
        }

        final destination = File(_appendPath(_namespace.path, canonicalName));
        try {
          await _renameWithoutReplacement(file, destination);
          restoredDeleting++;
        } catch (error) {
          failedOperations++;
          _logFailure('sweep_restore', error);
        }
        continue;
      }

      if (_imageNameCodec.isCanonicalName(name) &&
          !referencedCanonicalNames.contains(name)) {
        if (await _deleteSanitized(file, operation: 'sweep_canonical')) {
          removedCanonical++;
        } else {
          failedOperations++;
        }
      }
    }

    return DurableImageSweepResult(
      removedStaging: removedStaging,
      removedDeleting: removedDeleting,
      removedCanonical: removedCanonical,
      restoredDeleting: restoredDeleting,
      failedOperations: failedOperations,
    );
  }

  Future<void> _ensureNamespace() async {
    final existingType =
        await FileSystemEntity.type(_namespace.path, followLinks: false);
    if (existingType == FileSystemEntityType.link ||
        (existingType != FileSystemEntityType.notFound &&
            existingType != FileSystemEntityType.directory)) {
      throw const DurableImageStorageException('invalid_namespace');
    }
    if (existingType == FileSystemEntityType.notFound) {
      await _namespace.create(recursive: true);
    }
    final confirmedType =
        await FileSystemEntity.type(_namespace.path, followLinks: false);
    if (confirmedType != FileSystemEntityType.directory) {
      throw const DurableImageStorageException('invalid_namespace');
    }
  }

  Future<File> _createExclusiveStaging() async {
    for (var attempt = 0; attempt < _maximumNameAttempts; attempt++) {
      final name = 'e2s_${_nextToken()}.staging';
      final file = File(_appendPath(_namespace.path, name));
      try {
        await file.create(exclusive: true);
        return file;
      } on PathExistsException {
        continue;
      } on FileSystemException {
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type != FileSystemEntityType.notFound) {
          continue;
        }
        rethrow;
      }
    }
    throw const DurableImageStorageException('staging_name_exhausted');
  }

  Future<_CopyDigest> _copyFlushAndHash(
    PreparedImageLease source,
    File staging,
  ) async {
    final output = await staging.open(mode: FileMode.writeOnly);
    final sourceDigestReceiver = _DigestReceiver();
    final sourceDigestInput =
        sha256.startChunkedConversion(sourceDigestReceiver);
    var sourceDigestClosed = false;
    var byteLength = 0;
    try {
      await for (final chunk in source.openRead()) {
        if (chunk.isEmpty) {
          continue;
        }
        byteLength += chunk.length;
        if (byteLength > e1MaximumJpegBytes) {
          throw const DurableImageStorageException('image_too_large');
        }
        sourceDigestInput.add(chunk);
        await output.writeFrom(chunk);
      }
      sourceDigestInput.close();
      sourceDigestClosed = true;
      await _flushFile(output);
    } finally {
      if (!sourceDigestClosed) {
        sourceDigestInput.close();
      }
      await output.close();
    }

    if (byteLength != source.metadata.byteLength) {
      throw const DurableImageStorageException('byte_length_mismatch');
    }

    // Hash the flushed staging file, not only the incoming stream. Publication
    // must describe the exact bytes that reached durable E2 storage.
    final stagedDigest = await _hashFile(staging);
    if (stagedDigest.byteLength != byteLength ||
        stagedDigest.sha256 != sourceDigestReceiver.single.toString()) {
      throw const DurableImageStorageException('staged_content_mismatch');
    }
    return stagedDigest;
  }

  Future<void> _validateCopiedJpeg(
    File staging,
    PreparedImageMetadata metadata,
    _CopyDigest copy,
  ) async {
    if (copy.byteLength < 1 || copy.byteLength > e1MaximumJpegBytes) {
      throw const DurableImageStorageException('invalid_image_size');
    }
    final bytes = await staging.readAsBytes();
    final decoded = image_codec.decodeJpg(bytes);
    if (!_hasJpegEnvelope(bytes) ||
        decoded == null ||
        decoded.width != metadata.width ||
        decoded.height != metadata.height) {
      throw const DurableImageStorageException('jpeg_metadata_mismatch');
    }
  }

  Future<File> _chooseUnusedCanonical() async {
    for (var attempt = 0; attempt < _maximumNameAttempts; attempt++) {
      final name = _imageNameCodec.canonicalName(_nextToken());
      final file = File(_appendPath(_namespace.path, name));
      if (await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return file;
      }
    }
    throw const DurableImageStorageException('canonical_name_exhausted');
  }

  Future<File> _chooseUnusedDeletingMarker(String canonicalName) async {
    _validateCanonicalName(canonicalName);
    for (var attempt = 0; attempt < _maximumNameAttempts; attempt++) {
      final name = _imageNameCodec.deletingMarker(
        canonicalName: canonicalName,
        operationToken: _nextToken(),
      );
      final marker = File(_appendPath(_namespace.path, name));
      if (await FileSystemEntity.type(marker.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return marker;
      }
    }
    throw const DurableImageStorageException('deleting_name_exhausted');
  }

  File _directNamespaceFile(String name) =>
      File(_appendPath(_namespace.path, name));

  Future<File?> _resolveCanonical(String relativeName) async {
    _validateCanonicalName(relativeName);
    final candidate = _directNamespaceFile(relativeName);
    final type =
        await FileSystemEntity.type(candidate.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return null;
    }
    if (type != FileSystemEntityType.file) {
      throw const DurableImageStorageException('unsafe_image_reference');
    }
    return candidate;
  }

  Future<List<File>> _deletingMarkersFor(String canonicalName) async {
    final result = <File>[];
    await for (final entity in _namespace.list(followLinks: false)) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final encodedCanonical = _imageNameCodec
          .canonicalNameFromDeletingMarker(_basename(entity.path));
      if (encodedCanonical == canonicalName) {
        result.add(File(entity.path));
      }
    }
    return result;
  }

  Future<_CopyDigest> _hashFile(File file) async {
    final receiver = _DigestReceiver();
    final input = sha256.startChunkedConversion(receiver);
    var length = 0;
    await for (final chunk in file.openRead()) {
      length += chunk.length;
      if (length > e1MaximumJpegBytes) {
        return const _CopyDigest(byteLength: -1, sha256: '');
      }
      input.add(chunk);
    }
    input.close();
    return _CopyDigest(byteLength: length, sha256: receiver.single.toString());
  }

  Future<void> _renameWithoutReplacement(File source, File destination) async {
    final destinationType =
        await FileSystemEntity.type(destination.path, followLinks: false);
    if (destinationType != FileSystemEntityType.notFound) {
      throw const DurableImageStorageException('destination_exists');
    }
    await source.rename(destination.path);
  }

  Future<bool> _deleteSanitized(
    File file, {
    required String operation,
  }) async {
    try {
      await _deleteFile(file);
      return true;
    } catch (error) {
      _logFailure(operation, error);
      return false;
    }
  }

  String _nextToken() {
    final token = _tokenGenerator();
    if (!_opaqueTokenPattern.hasMatch(token)) {
      throw const DurableImageStorageException('invalid_opaque_token');
    }
    return token;
  }

  void _logFailure(String operation, Object error) {
    _logger(
      'E2_IMAGE_OPERATION_FAILED operation=$operation '
      'error=${error.runtimeType}',
    );
  }
}

final class DurableImageStorageException implements Exception {
  const DurableImageStorageException(this.code);

  final String code;

  @override
  String toString() => 'DurableImageStorageException: $code';
}

final class _CopyDigest {
  const _CopyDigest({required this.byteLength, required this.sha256});

  final int byteLength;
  final String sha256;
}

final class _DigestReceiver implements Sink<Digest> {
  Digest? _digest;

  Digest get single {
    final value = _digest;
    if (value == null) {
      throw StateError('Digest was not completed.');
    }
    return value;
  }

  @override
  void add(Digest data) {
    if (_digest != null) {
      throw StateError('More than one digest was produced.');
    }
    _digest = data;
  }

  @override
  void close() {}
}

final class _SecureOpaqueTokenGenerator {
  _SecureOpaqueTokenGenerator() : _random = Random.secure();

  final Random _random;

  String next() {
    final buffer = StringBuffer();
    for (var index = 0; index < 16; index++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

void _validatePreparedSource(PreparedImageLease source) {
  if (!source.hasOwnership) {
    throw const DurableImageStorageException('inactive_source_ownership');
  }
  final metadata = source.metadata;
  if (metadata.mimeType != 'image/jpeg' ||
      metadata.byteLength < 1 ||
      metadata.byteLength > e1MaximumJpegBytes ||
      metadata.width < 1 ||
      metadata.width > e1MaximumImageWidth ||
      metadata.height < 1 ||
      metadata.height > e1MaximumImageHeight ||
      metadata.quality != e1JpegQuality) {
    throw const DurableImageStorageException('invalid_source_metadata');
  }
}

void _validateProjectionMetadata(PersistedImageProjection image) {
  _validateCanonicalName(image.relativeName);
  if (image.mimeType != 'image/jpeg' ||
      image.byteLength < 1 ||
      image.byteLength > e1MaximumJpegBytes ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(image.sha256) ||
      image.width < 1 ||
      image.width > e1MaximumImageWidth ||
      image.height < 1 ||
      image.height > e1MaximumImageHeight ||
      image.quality != e1JpegQuality) {
    throw const DurableImageStorageException('invalid_image_metadata');
  }
}

void _validateCanonicalName(String name) {
  if (!_imageNameCodec.isCanonicalName(name) ||
      name.contains('/') ||
      name.contains(r'\') ||
      name.contains('..')) {
    throw const DurableImageStorageException('invalid_relative_name');
  }
}

bool _hasJpegEnvelope(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[bytes.length - 2] == 0xff &&
      bytes[bytes.length - 1] == 0xd9;
}

String _appendPath(String directory, String name) {
  if (directory.endsWith('/') || directory.endsWith(r'\')) {
    return '$directory$name';
  }
  return '$directory${Platform.pathSeparator}$name';
}

String _basename(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

Future<void> _deleteExistingFile(File file) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type == FileSystemEntityType.file) {
    await file.delete();
  }
}

Future<void> _flushRandomAccessFile(RandomAccessFile file) => file.flush();

void _discardLog(String _) {}

/// Retains the one marker created by a queue removal until SQLite commits.
final class _PrivateDurableImageDeletion implements DurableImageDeletion {
  _PrivateDurableImageDeletion._(this._store, this._marker);

  final PrivateDurableImageStore _store;
  File? _marker;

  @override
  Future<void> finalizeAfterCommit() async {
    final marker = _marker;
    if (marker == null) {
      return;
    }
    if (!await _store._deleteSanitized(
      marker,
      operation: 'removal_marker_cleanup',
    )) {
      throw const DurableImageStorageException('deletion_failed');
    }
    _marker = null;
  }
}

/// Holds one validated E2 staging file until the queue decides to publish it.
/// It deliberately never deletes a canonical image; rollback after publication
/// belongs to the queue's transaction protocol.
final class _PrivateDurableImageStaging implements DurableImageStaging {
  _PrivateDurableImageStaging._({
    required PrivateDurableImageStore store,
    required File staging,
    required PreparedImageMetadata metadata,
    required _CopyDigest copy,
  })  : _store = store,
        _staging = staging,
        _metadata = metadata,
        _copy = copy;

  final PrivateDurableImageStore _store;
  final PreparedImageMetadata _metadata;
  final _CopyDigest _copy;
  File? _staging;
  bool _published = false;

  @override
  Future<PersistedImageProjection> publishWithoutOverwrite() async {
    final staging = _staging;
    if (staging == null || _published) {
      throw const DurableImageStorageException('staging_not_available');
    }

    final canonical = await _store._chooseUnusedCanonical();
    await _store._renameWithoutReplacement(staging, canonical);
    _staging = null;
    _published = true;
    return PersistedImageProjection(
      relativeName: _basename(canonical.path),
      mimeType: _metadata.mimeType,
      byteLength: _copy.byteLength,
      sha256: _copy.sha256,
      width: _metadata.width,
      height: _metadata.height,
      quality: _metadata.quality,
    );
  }

  @override
  Future<void> discard() async {
    final staging = _staging;
    if (staging == null) {
      return;
    }
    _staging = null;
    if (!await _store._deleteSanitized(staging, operation: 'stage_discard')) {
      throw const DurableImageStorageException('staging_cleanup_failed');
    }
  }
}
