import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:pavimenta_ai_mobile/application/e2_persistence_ports.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/infrastructure/durable_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';

void main() {
  late Directory sandbox;
  late Directory namespace;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e2_durable_store_');
    namespace = Directory(
      '${sandbox.path}${Platform.pathSeparator}$e2DurableImageNamespace',
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('durable promotion', () {
    test('streams, flushes, hashes, validates, and promotes a valid JPEG',
        () async {
      final bytes = _jpeg(width: 17, height: 11);
      final source = _MemoryPreparedLease(
        bytes,
        width: 17,
        height: 11,
        chunkSize: 7,
      );
      var flushCount = 0;
      final store = PrivateDurableImageStore.at(
        sandbox,
        flushFile: (file) async {
          flushCount++;
          await file.flush();
        },
        tokenGenerator: _tokens(<String>[_token('a'), _token('b')]),
      );

      final projection = await store.promote(source);
      final streamed =
          await store.openRead(projection).expand((e) => e).toList();

      expect(flushCount, 1);
      expect(source.openReadCount, 1);
      expect(source.emittedChunkCount, greaterThan(1));
      expect(source.hasOwnership, isFalse);
      expect(source.withdrawCount, 1);
      expect(streamed, bytes);
      expect(projection.relativeName, 'e2i_${_token('b')}.jpg');
      expect(projection.relativeName, isNot(contains(source.occurrenceMarker)));
      expect(projection.sha256, sha256.convert(bytes).toString());
      expect(projection.mimeType, 'image/jpeg');
      expect(projection.byteLength, bytes.length);
      expect(projection.width, 17);
      expect(projection.height, 11);
      expect(projection.quality, 85);
      expect(await store.inspect(projection), DurableImageIntegrity.valid);
      expect(await _directFiles(namespace), hasLength(1));
    });

    test('keeps validated staging private until non-overwriting publication',
        () async {
      final bytes = _jpeg(width: 7, height: 5);
      final source = _MemoryPreparedLease(bytes, width: 7, height: 5);
      final store = PrivateDurableImageStore.at(
        sandbox,
        tokenGenerator: _tokens(<String>[_token('a'), _token('b')]),
      );

      final staging = await store.stage(source);
      expect(await _directFiles(namespace), hasLength(1));
      expect((await _directFiles(namespace)).single.path, endsWith('.staging'));
      expect(source.hasOwnership, isTrue);

      final projection = await staging.publishWithoutOverwrite();
      await staging.discard();

      expect(projection.relativeName, 'e2i_${_token('b')}.jpg');
      expect(await store.inspect(projection), DurableImageIntegrity.valid);
      expect(source.hasOwnership, isTrue);
      expect(await _directFiles(namespace), hasLength(1));
      expect((await _directFiles(namespace)).single.path, endsWith('.jpg'));
    });

    test('uses exclusive staging and leaves colliding artifacts untouched',
        () async {
      await namespace.create(recursive: true);
      final stagingCollision = File(
        '${namespace.path}${Platform.pathSeparator}e2s_${_token('a')}.staging',
      );
      final canonicalCollision = File(
        '${namespace.path}${Platform.pathSeparator}e2i_${_token('c')}.jpg',
      );
      await stagingCollision.writeAsString('existing staging');
      await canonicalCollision.writeAsString('existing canonical');
      final store = PrivateDurableImageStore.at(
        sandbox,
        tokenGenerator: _tokens(<String>[
          _token('a'),
          _token('b'),
          _token('c'),
          _token('d'),
        ]),
      );

      final projection = await store.promote(
        _MemoryPreparedLease(_jpeg(width: 4, height: 3), width: 4, height: 3),
      );

      expect(projection.relativeName, 'e2i_${_token('d')}.jpg');
      expect(await stagingCollision.readAsString(), 'existing staging');
      expect(await canonicalCollision.readAsString(), 'existing canonical');
    });

    test('rejects invalid MIME, dimensions, quality, size, and byte count',
        () async {
      final valid = _jpeg(width: 4, height: 3);
      final invalidSources = <_MemoryPreparedLease>[
        _MemoryPreparedLease(valid, width: 4, height: 3, mimeType: 'image/png'),
        _MemoryPreparedLease(valid, width: 0, height: 3),
        _MemoryPreparedLease(valid, width: 1281, height: 3),
        _MemoryPreparedLease(valid, width: 4, height: 721),
        _MemoryPreparedLease(valid, width: 4, height: 3, quality: 84),
        _MemoryPreparedLease(valid, width: 4, height: 3, declaredLength: 0),
        _MemoryPreparedLease(
          valid,
          width: 4,
          height: 3,
          declaredLength: 2 * 1024 * 1024 + 1,
        ),
        _MemoryPreparedLease(
          valid,
          width: 4,
          height: 3,
          declaredLength: valid.length + 1,
        ),
        _MemoryPreparedLease(valid, width: 5, height: 3),
      ];

      for (var index = 0; index < invalidSources.length; index++) {
        final store = PrivateDurableImageStore.at(
          sandbox,
          tokenGenerator: _tokens(<String>[
            _tokenChar(index),
            _tokenChar(index + 10),
          ]),
        );
        await expectLater(
          store.promote(invalidSources[index]),
          throwsA(isA<DurableImageStorageException>()),
        );
        expect(invalidSources[index].hasOwnership, isTrue);
      }

      final files = await _directFiles(namespace);
      expect(files.where((file) => file.path.endsWith('.staging')), isEmpty);
      expect(files.where((file) => file.path.endsWith('.jpg')), isEmpty);
    });

    test('flush failure rolls back only its staging and logs no sensitive data',
        () async {
      final logs = <String>[];
      final source = _MemoryPreparedLease(
        _jpeg(width: 3, height: 2),
        width: 3,
        height: 2,
      );
      final store = PrivateDurableImageStore.at(
        sandbox,
        logger: logs.add,
        flushFile: (_) async => throw const FileSystemException(
          'private-path digest bytes coordinates occurrence',
        ),
        tokenGenerator: _tokens(<String>[_token('a')]),
      );

      await expectLater(
        store.promote(source),
        throwsA(isA<DurableImageStorageException>()),
      );

      expect(source.hasOwnership, isTrue);
      expect(await _directFiles(namespace), isEmpty);
      expect(logs, hasLength(1));
      _expectSanitized(logs.single, sandbox.path, source.bytes);
    });

    test('rejects staging bytes changed during flush before publication',
        () async {
      final bytes = _jpeg(width: 8, height: 6);
      final source = _MemoryPreparedLease(bytes, width: 8, height: 6);
      final changedOffset = bytes.length ~/ 2;
      final store = PrivateDurableImageStore.at(
        sandbox,
        flushFile: (file) async {
          await file.setPosition(changedOffset);
          await file.writeByte(bytes[changedOffset] ^ 0xff);
          await file.flush();
        },
        tokenGenerator: _tokens(<String>[_token('a')]),
      );

      await expectLater(
        store.promote(source),
        throwsA(
          isA<DurableImageStorageException>().having(
            (error) => error.code,
            'code',
            'staged_content_mismatch',
          ),
        ),
      );

      expect(source.hasOwnership, isTrue);
      expect(await _directFiles(namespace), isEmpty);
    });
  });

  group('relative-name and link safety', () {
    test('rejects traversal, separators, unknown and absolute names', () async {
      final store = PrivateDurableImageStore.at(sandbox);
      final names = <String>[
        '../e2i_${_token('a')}.jpg',
        'nested/e2i_${_token('a')}.jpg',
        'nested\\e2i_${_token('a')}.jpg',
        '${sandbox.absolute.path}${Platform.pathSeparator}outside.jpg',
        'e2i_${_token('a')}..jpg',
        'unknown.jpg',
        '',
      ];

      for (final name in names) {
        final projection = _projection(name);
        await expectLater(
          store.openRead(projection),
          emitsError(isA<DurableImageStorageException>()),
        );
        await expectLater(
          store.delete(projection),
          throwsA(isA<DurableImageStorageException>()),
        );
      }
      expect(await store.sweep(<String>{}), isA<DurableImageSweepResult>());
    });

    test('does not follow a canonical-looking symlink', () async {
      await namespace.create(recursive: true);
      final outside = File(
        '${sandbox.path}${Platform.pathSeparator}outside.jpg',
      );
      final bytes = _jpeg(width: 2, height: 2);
      await outside.writeAsBytes(bytes);
      final name = 'e2i_${_token('a')}.jpg';
      final link = Link('${namespace.path}${Platform.pathSeparator}$name');
      try {
        await link.create(outside.path);
      } on FileSystemException {
        return; // Symlink creation can be unavailable on locked-down Windows.
      }
      final store = PrivateDurableImageStore.at(sandbox);
      final projection = _projection(
        name,
        bytes: bytes,
        width: 2,
        height: 2,
      );

      expect(await store.inspect(projection), DurableImageIntegrity.invalid);
      await expectLater(
        store.delete(projection),
        throwsA(isA<DurableImageStorageException>()),
      );
      final result = await store.sweep(<String>{});

      expect(result.removedCanonical, 0);
      expect(await link.exists(), isTrue);
      expect(await outside.readAsBytes(), bytes);
    });

    test('rejects a namespace that is itself a symlink', () async {
      final realDirectory = Directory(
        '${sandbox.path}${Platform.pathSeparator}real_namespace',
      );
      await realDirectory.create();
      try {
        await Link(namespace.path).create(realDirectory.path);
      } on FileSystemException {
        return;
      }
      final store = PrivateDurableImageStore.at(sandbox);

      await expectLater(
        store.promote(
          _MemoryPreparedLease(_jpeg(width: 2, height: 2), width: 2, height: 2),
        ),
        throwsA(isA<DurableImageStorageException>()),
      );
      expect(await realDirectory.list().toList(), isEmpty);
    });
  });

  group('canonical names, deletion, and sweeping', () {
    test('recognizes and reverses only canonical opaque name formats', () {
      const codec = E2DurableImageNameCodec();
      final canonical = codec.canonicalName(_token('a'));
      final marker = codec.deletingMarker(
        canonicalName: canonical,
        operationToken: _token('b'),
      );

      expect(canonical, 'e2i_${_token('a')}.jpg');
      expect(codec.isCanonicalName(canonical), isTrue);
      expect(
        marker,
        'e2d_${_token('a')}_${_token('b')}.deleting',
      );
      expect(codec.canonicalNameFromDeletingMarker(marker), canonical);

      for (final unknown in <String>[
        'e2i_${_token('a')}.jpeg',
        'e2i_${_token('a').toUpperCase()}.jpg',
        'e2d_${_token('a')}.deleting',
        'e2d_${_token('a')}_${_token('b')}.deleting.extra',
        'pothole-2025-01-01.jpg',
      ]) {
        expect(codec.isCanonicalName(unknown), isFalse);
        expect(codec.canonicalNameFromDeletingMarker(unknown), isNull);
      }
      expect(
        () => codec.canonicalName('not-an-opaque-token'),
        throwsA(isA<DurableImageStorageException>()),
      );
      expect(
        () => codec.deletingMarker(
          canonicalName: '../$canonical',
          operationToken: _token('b'),
        ),
        throwsA(isA<DurableImageStorageException>()),
      );
    });

    test('retries a colliding deleting marker without replacing it', () async {
      final bytes = _jpeg(width: 5, height: 4);
      final store = PrivateDurableImageStore.at(
        sandbox,
        deleteFile: (_) async => throw const FileSystemException('blocked'),
        tokenGenerator: _tokens(<String>[
          _token('a'),
          _token('b'),
          _token('c'),
          _token('d'),
        ]),
      );
      final projection = await store.promote(
        _MemoryPreparedLease(bytes, width: 5, height: 4),
      );
      final collidingMarker = File(
        '${namespace.path}${Platform.pathSeparator}'
        'e2d_${_token('b')}_${_token('c')}.deleting',
      );
      await collidingMarker.writeAsBytes(<int>[7, 7, 7]);

      await expectLater(
        store.delete(projection),
        throwsA(isA<DurableImageStorageException>()),
      );

      final selectedMarker = File(
        '${namespace.path}${Platform.pathSeparator}'
        'e2d_${_token('b')}_${_token('d')}.deleting',
      );
      expect(await collidingMarker.readAsBytes(), <int>[7, 7, 7]);
      expect(await selectedMarker.readAsBytes(), bytes);
      expect(await _directNames(namespace), hasLength(2));
    });

    test('uses opaque canonical and deleting names and retries cleanup',
        () async {
      final logs = <String>[];
      var failDelete = true;
      final bytes = _jpeg(width: 6, height: 5);
      final digest = sha256.convert(bytes).toString();
      final store = PrivateDurableImageStore.at(
        sandbox,
        logger: logs.add,
        deleteFile: (file) async {
          if (failDelete && file.path.endsWith('.deleting')) {
            throw FileSystemException(
              'secret ${file.path} $digest ${bytes.take(4).toList()}',
            );
          }
          if (await file.exists()) {
            await file.delete();
          }
        },
        tokenGenerator: _tokens(<String>[
          _token('a'),
          _token('b'),
          _token('c'),
        ]),
      );
      final projection = await store.promote(
        _MemoryPreparedLease(
          bytes,
          width: 6,
          height: 5,
          occurrenceMarker: 'pothole--23.5--2025-01-01--uuid',
        ),
      );

      await expectLater(
        store.delete(projection),
        throwsA(isA<DurableImageStorageException>()),
      );
      final namesAfterFailure = await _directNames(namespace);
      expect(namesAfterFailure, hasLength(1));
      expect(
        namesAfterFailure.single,
        matches(RegExp(r'^e2d_[0-9a-f]{32}_[0-9a-f]{32}\.deleting$')),
      );
      for (final forbidden in <String>[
        'pothole',
        '2025',
        '23.5',
        'uuid',
        digest,
      ]) {
        expect(projection.relativeName, isNot(contains(forbidden)));
        expect(namesAfterFailure.single, isNot(contains(forbidden)));
      }
      expect(logs, hasLength(1));
      _expectSanitized(logs.single, sandbox.path, bytes, digest: digest);

      failDelete = false;
      await store.delete(projection);
      await store.delete(projection);
      expect(await _directFiles(namespace), isEmpty);
    });

    // **Validates: Requirements RF-12.3–5, RNF-03.5, RNF-05.2–4, RNF-06.3, RNF-06.9–11**
    test('recovery is idempotent and only mutates direct recognized E2 files',
        () async {
      await namespace.create(recursive: true);
      final retainedName = 'e2i_${_token('a')}.jpg';
      final orphanName = 'e2i_${_token('b')}.jpg';
      final deletingName = 'e2d_${_token('a')}_${_token('c')}.deleting';
      final orphanDeletingName = 'e2d_${_token('f')}_${_token('a')}.deleting';
      final stagingName = 'e2s_${_token('d')}.staging';
      const unknownName = 'notes.txt';
      const e1Name = 'e1_prepared_123_0.jpg';
      final e1Namespace = Directory(
        '${sandbox.path}${Platform.pathSeparator}e1_temporary_images_v1',
      );
      final nested = Directory(
        '${namespace.path}${Platform.pathSeparator}nested',
      );
      final outside =
          File('${sandbox.path}${Platform.pathSeparator}$orphanName');
      final e1Temporary = File(
        '${e1Namespace.path}${Platform.pathSeparator}$e1Name',
      );

      await File('${namespace.path}${Platform.pathSeparator}$deletingName')
          .writeAsBytes([1]);
      await File(
        '${namespace.path}${Platform.pathSeparator}$orphanDeletingName',
      ).writeAsBytes([8]);
      await File('${namespace.path}${Platform.pathSeparator}$orphanName')
          .writeAsBytes([2]);
      await File('${namespace.path}${Platform.pathSeparator}$stagingName')
          .writeAsBytes([3]);
      await File('${namespace.path}${Platform.pathSeparator}$unknownName')
          .writeAsBytes([4]);
      await File('${namespace.path}${Platform.pathSeparator}$e1Name')
          .writeAsBytes([5]);
      await e1Temporary.parent.create(recursive: true);
      await e1Temporary.writeAsBytes([6]);
      await nested.create();
      final nestedRecognized = File(
        '${nested.path}${Platform.pathSeparator}e2s_${_token('e')}.staging',
      );
      await nestedRecognized.writeAsBytes([7]);
      await outside.writeAsBytes([8]);

      final store = PrivateDurableImageStore.at(sandbox);
      final result = await store.sweep(<String>{retainedName});

      expect(result.removedStaging, 1);
      expect(result.removedCanonical, 1);
      expect(result.restoredDeleting, 1);
      expect(result.removedDeleting, 1);
      expect(result.failedOperations, 0);
      expect(
        await File('${namespace.path}${Platform.pathSeparator}$retainedName')
            .readAsBytes(),
        [1],
      );
      expect(
        await File('${namespace.path}${Platform.pathSeparator}$unknownName')
            .exists(),
        isTrue,
      );
      expect(
        await File('${namespace.path}${Platform.pathSeparator}$e1Name')
            .exists(),
        isTrue,
      );
      expect(await e1Temporary.readAsBytes(), [6]);
      expect(await nestedRecognized.exists(), isTrue);
      expect(await outside.readAsBytes(), [8]);

      final repeated = await store.sweep(<String>{retainedName});
      expect(repeated.removedStaging, 0);
      expect(repeated.removedCanonical, 0);
      expect(repeated.restoredDeleting, 0);
      expect(repeated.removedDeleting, 0);
      expect(repeated.failedOperations, 0);
      expect(await e1Temporary.readAsBytes(), [6]);
      expect(await nestedRecognized.exists(), isTrue);
      expect(await outside.readAsBytes(), [8]);
    });

    test('sweep cleanup failures are counted and logs remain sanitized',
        () async {
      await namespace.create(recursive: true);
      final staging = File(
        '${namespace.path}${Platform.pathSeparator}e2s_${_token('a')}.staging',
      );
      await staging.writeAsBytes([9, 8, 7]);
      final logs = <String>[];
      final store = PrivateDurableImageStore.at(
        sandbox,
        logger: logs.add,
        deleteFile: (_) async => throw FileSystemException(
          'private ${staging.path} bytes 9,8,7',
        ),
      );

      final result = await store.sweep(<String>{});

      expect(result.failedOperations, 1);
      expect(await staging.exists(), isTrue);
      expect(logs, hasLength(1));
      _expectSanitized(logs.single, sandbox.path, [9, 8, 7]);
    });

    test('inspect detects byte and digest corruption without exposing either',
        () async {
      final store = PrivateDurableImageStore.at(
        sandbox,
        tokenGenerator: _tokens(<String>[_token('a'), _token('b')]),
      );
      final projection = await store.promote(
        _MemoryPreparedLease(_jpeg(width: 3, height: 3), width: 3, height: 3),
      );
      final durable = File(
        '${namespace.path}${Platform.pathSeparator}${projection.relativeName}',
      );
      await durable.writeAsBytes(_jpeg(width: 2, height: 2), flush: true);

      expect(await store.inspect(projection), DurableImageIntegrity.invalid);
    });
  });
}

final class _MemoryPreparedLease implements PreparedImageLease {
  _MemoryPreparedLease(
    this.bytes, {
    required this.width,
    required this.height,
    this.mimeType = 'image/jpeg',
    this.quality = 85,
    this.declaredLength,
    this.chunkSize = 1024,
    this.occurrenceMarker = 'occurrence-sensitive-data',
  });

  final List<int> bytes;
  final int width;
  final int height;
  final String mimeType;
  final int quality;
  final int? declaredLength;
  final int chunkSize;
  final String occurrenceMarker;
  bool _owns = true;
  int openReadCount = 0;
  int emittedChunkCount = 0;
  int withdrawCount = 0;

  @override
  bool get hasOwnership => _owns;

  @override
  PreparedImageMetadata get metadata => PreparedImageMetadata(
        mimeType: mimeType,
        byteLength: declaredLength ?? bytes.length,
        width: width,
        height: height,
        quality: quality,
      );

  @override
  Stream<List<int>> openRead() async* {
    if (!_owns) {
      throw StateError('inactive');
    }
    openReadCount++;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      emittedChunkCount++;
      yield bytes.sublist(offset, end);
    }
  }

  @override
  PreparedImageLease promoteOwnership() {
    if (!_owns) {
      throw StateError('inactive');
    }
    return this;
  }

  @override
  Future<void> withdrawOwnership() async {
    if (!_owns) {
      return;
    }
    withdrawCount++;
    _owns = false;
  }

  @override
  Future<void> dispose() => withdrawOwnership();
}

List<int> _jpeg({required int width, required int height}) {
  final source = image_codec.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      source.setPixelRgba(x, y, x * 17, y * 19, (x + y) * 13, 255);
    }
  }
  return image_codec.encodeJpg(source, quality: 85);
}

PersistedImageProjection _projection(
  String name, {
  List<int>? bytes,
  int width = 1,
  int height = 1,
}) {
  final content = bytes ?? _jpeg(width: width, height: height);
  return PersistedImageProjection(
    relativeName: name,
    mimeType: 'image/jpeg',
    byteLength: content.length,
    sha256: sha256.convert(content).toString(),
    width: width,
    height: height,
    quality: 85,
  );
}

String _token(String character) => character * 32;

String _tokenChar(int value) {
  const characters = '0123456789abcdef';
  return _token(characters[value % characters.length]);
}

E2OpaqueTokenGenerator _tokens(List<String> values) {
  var index = 0;
  return () {
    if (index >= values.length) {
      throw StateError('Token fixture exhausted.');
    }
    return values[index++];
  };
}

Future<List<File>> _directFiles(Directory directory) async {
  if (!await directory.exists()) {
    return <File>[];
  }
  final result = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (await FileSystemEntity.type(entity.path, followLinks: false) ==
        FileSystemEntityType.file) {
      result.add(File(entity.path));
    }
  }
  return result;
}

Future<List<String>> _directNames(Directory directory) async {
  return (await _directFiles(directory))
      .map((file) => file.path.replaceAll('\\', '/').split('/').last)
      .toList();
}

void _expectSanitized(
  String log,
  String privatePath,
  Iterable<int> bytes, {
  String? digest,
}) {
  expect(log, contains('E2_IMAGE_OPERATION_FAILED'));
  expect(log, isNot(contains(privatePath)));
  expect(log, isNot(contains('private-path')));
  expect(log, isNot(contains('coordinates')));
  expect(log, isNot(contains('occurrence')));
  expect(log, isNot(contains(bytes.take(4).join(','))));
  if (digest != null) {
    expect(log, isNot(contains(digest)));
  }
}
