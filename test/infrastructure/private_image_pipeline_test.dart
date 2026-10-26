import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pavimenta_ai_mobile/infrastructure/private_image_store.dart';
import 'package:pavimenta_ai_mobile/infrastructure/private_jpeg_image_preparer.dart';

void main() {
  late Directory sandbox;
  late PrivateImageStore store;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('pavimenta_e1_image_test_');
    store = PrivateImageStore.at(sandbox);
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('private JPEG preparation', () {
    test('decodes, bakes EXIF orientation and never enlarges', () async {
      final sourceImage = image.Image(width: 2, height: 3);
      sourceImage.exif.imageIfd.orientation = 6;
      final codec = _TrackingCodec(decodedImage: sourceImage);
      final capture = await store.createCapture(Uint8List.fromList([1]));

      final prepared = await PrivateJpegImagePreparer(
        store: store,
        codec: codec,
      ).prepare(capture) as PrivatePreparedImage;

      expect(codec.orientationCalls, 1);
      expect(codec.encodedDimensions, [const ImageDimensions(3, 2)]);
      expect(prepared.width, 3);
      expect(prepared.height, 2);
      expect(codec.resizeCalls, isEmpty);
      expect(capture.isActive, isFalse);
      await prepared.dispose();
    });

    test('preserves ratio and initially fits inside 1280x720', () async {
      final original = image.Image(width: 2000, height: 1000);
      final capture = await store.createCapture(
        Uint8List.fromList(image.encodePng(original)),
      );

      final prepared = await PrivateJpegImagePreparer(store: store)
          .prepare(capture) as PrivatePreparedImage;
      final decoded = image.decodeJpg(await prepared.file.readAsBytes())!;

      expect(decoded.width, 1280);
      expect(decoded.height, 640);
      expect(decoded.width / decoded.height, closeTo(2, 0.01));
      expect(prepared.byteLength, lessThanOrEqualTo(e1MaximumJpegBytes));
      expect(prepared.quality, e1JpegQuality);
      expect(prepared.mimeType, 'image/jpeg');
      expect(_isInside(prepared.file, store.namespaceDirectory), isTrue);
      await prepared.dispose();
    });

    test('accepts an encoded result exactly at the 2 MiB boundary', () async {
      final codec = _TrackingCodec(
        decodedImage: image.Image(width: 10, height: 10),
        encodedLength: (_) => e1MaximumJpegBytes,
      );
      final capture = await store.createCapture(Uint8List.fromList([1]));

      final prepared = await PrivateJpegImagePreparer(
        store: store,
        codec: codec,
      ).prepare(capture) as PrivatePreparedImage;

      expect(prepared.byteLength, e1MaximumJpegBytes);
      expect(codec.qualities, [85]);
      await prepared.dispose();
    });

    test('rejects undecodable input and removes the private source', () async {
      final capture = await store.createCapture(Uint8List.fromList([1, 2, 3]));
      final source = capture.file;

      await expectLater(
        PrivateJpegImagePreparer(store: store).prepare(capture),
        throwsA(
          isA<ImagePreparationException>().having(
            (error) => error.failure,
            'failure',
            ImagePreparationFailure.decodeFailed,
          ),
        ),
      );

      expect(await source.exists(), isFalse);
      expect(await _recognizedFiles(store), isEmpty);
    });
  });

  group('dimension reduction properties', () {
    // **Validates: Requirements 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 10.8**
    test('all generated aspect ratios fit without enlargement', () {
      for (var width = 1; width <= 2200; width += 73) {
        for (var height = 1; height <= 1400; height += 61) {
          final fitted = fitImageDimensions(
            width,
            height,
            maxWidth: e1MaximumImageWidth,
            maxHeight: e1MaximumImageHeight,
          );
          expect(fitted.width, inInclusiveRange(1, 1280));
          expect(fitted.height, inInclusiveRange(1, 720));
          expect(fitted.width, lessThanOrEqualTo(width));
          expect(fitted.height, lessThanOrEqualTo(height));
          final crossProductError =
              (fitted.width * height - fitted.height * width).abs();
          expect(
            crossProductError,
            lessThanOrEqualTo(width + height),
          );
        }
      }
    });

    // **Validates: Requirements 10.3, 10.4, 10.5, 10.8**
    test('every retry uses quality 85 and shrinks monotonically to terminate',
        () async {
      final codec = _TrackingCodec(
        decodedImage: image.Image(width: 1280, height: 720),
        encodedLength: (value) =>
            value.width > 300 ? e1MaximumJpegBytes + 1 : e1MaximumJpegBytes,
      );
      final capture = await store.createCapture(Uint8List.fromList([1]));

      final prepared = await PrivateJpegImagePreparer(
        store: store,
        codec: codec,
      ).prepare(capture) as PrivatePreparedImage;

      expect(codec.qualities, isNotEmpty);
      expect(codec.qualities.every((quality) => quality == 85), isTrue);
      for (var index = 1; index < codec.encodedDimensions.length; index++) {
        final previous = codec.encodedDimensions[index - 1];
        final current = codec.encodedDimensions[index];
        expect(current.width, lessThan(previous.width));
        expect(current.height, lessThan(previous.height));
        expect(current.width / current.height,
            closeTo(previous.width / previous.height, 0.02));
      }
      expect(prepared.byteLength, lessThanOrEqualTo(e1MaximumJpegBytes));
      await prepared.dispose();
    });

    test('finite reduction rejects at 1x1 and cleans every artifact', () async {
      final codec = _TrackingCodec(
        decodedImage: image.Image(width: 4, height: 3),
        encodedLength: (_) => e1MaximumJpegBytes + 1,
      );
      final capture = await store.createCapture(Uint8List.fromList([1]));

      await expectLater(
        PrivateJpegImagePreparer(store: store, codec: codec).prepare(capture),
        throwsA(
          isA<ImagePreparationException>().having(
            (error) => error.failure,
            'failure',
            ImagePreparationFailure.maximumSizeUnreachable,
          ),
        ),
      );

      expect(codec.encodedDimensions.last, const ImageDimensions(1, 1));
      expect(codec.encodedDimensions.length, lessThan(20));
      expect(await _recognizedFiles(store), isEmpty);
    });
  });

  group('ownership and cleanup', () {
    // **Validates: Requirements 10.11, 10.12, 10.13, 10.14, 10.15, 11.6, 11.7, 11.8**
    test('ownership transfers exactly once and disposal is idempotent',
        () async {
      final prepared = await store.writePreparedJpeg(
        bytes: Uint8List.fromList([1, 2]),
        width: 1,
        height: 1,
        quality: 85,
      );
      final file = prepared.file;
      final transferred = prepared.transferOwnership();

      expect(prepared.isActive, isFalse);
      expect(transferred.isActive, isTrue);
      expect(() => prepared.transferOwnership(), throwsStateError);
      await prepared.dispose();
      expect(await file.exists(), isTrue);
      await transferred.dispose();
      await transferred.dispose();
      expect(await file.exists(), isFalse);
    });

    test('session replacement and dispose release each current image',
        () async {
      final owner = InMemoryImageOwner();
      final first = await _newPrepared(store, 1);
      final firstFile = first.file;
      await owner.replace(first);
      final second = await _newPrepared(store, 2);
      final secondFile = second.file;

      await owner.replace(second);
      expect(await firstFile.exists(), isFalse);
      expect(await secondFile.exists(), isTrue);

      await owner.dispose();
      await owner.dispose();
      expect(await secondFile.exists(), isFalse);
      expect(await _recognizedFiles(store), isEmpty);
    });

    test('orphan sweep is namespace-restricted and ignores unrelated files',
        () async {
      await store.namespaceDirectory.create(recursive: true);
      final orphan = File(
        '${store.namespaceDirectory.path}${Platform.pathSeparator}'
        'e1_prepared_123_0.jpg',
      );
      final unrelated = File(
        '${store.namespaceDirectory.path}${Platform.pathSeparator}notes.txt',
      );
      final outside = File(
        '${sandbox.path}${Platform.pathSeparator}e1_source_123_0.capture',
      );
      await orphan.writeAsBytes([1]);
      await unrelated.writeAsString('keep');
      await outside.writeAsBytes([1]);

      expect(await store.sweepRecognizedOrphans(), 1);
      expect(await orphan.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
      expect(await outside.exists(), isTrue);
    });

    test('cleanup failure log is sanitized and contains no path or bytes',
        () async {
      final logs = <String>[];
      final failingStore = PrivateImageStore.at(
        sandbox,
        logger: logs.add,
        deleteFile: (_) async => throw const FileSystemException(
          'failure containing secret-path-and-image-bytes',
        ),
      );
      final capture = await failingStore.createCapture(
        Uint8List.fromList([9, 8, 7]),
      );
      final privatePath = capture.file.path;

      await capture.dispose();

      expect(logs, hasLength(1));
      expect(logs.single, contains('operation=lease_dispose'));
      expect(logs.single, contains('kind=source'));
      expect(logs.single, isNot(contains(privatePath)));
      expect(logs.single, isNot(contains('secret-path')));
      expect(logs.single, isNot(contains('9, 8, 7')));
    });

    test('all generated files remain under injected private namespace',
        () async {
      final capture = await store.createCapture(Uint8List.fromList([1]));
      final prepared = await _newPrepared(store, 3);

      expect(_isInside(capture.file, store.namespaceDirectory), isTrue);
      expect(_isInside(prepared.file, store.namespaceDirectory), isTrue);
      expect(store.namespaceDirectory.path, endsWith(e1ImageNamespace));
      await capture.dispose();
      await prepared.dispose();
    });
  });
}

final class _TrackingCodec implements E1ImageCodec {
  _TrackingCodec({required this.decodedImage, this.encodedLength});

  final image.Image decodedImage;
  final int Function(image.Image image)? encodedLength;
  final List<int> qualities = <int>[];
  final List<ImageDimensions> encodedDimensions = <ImageDimensions>[];
  final List<ImageDimensions> resizeCalls = <ImageDimensions>[];
  int orientationCalls = 0;

  @override
  image.Image? decode(Uint8List bytes) => decodedImage.clone();

  @override
  image.Image bakeOrientation(image.Image source) {
    orientationCalls++;
    return image.bakeOrientation(source);
  }

  @override
  image.Image resize(image.Image source, int width, int height) {
    resizeCalls.add(ImageDimensions(width, height));
    return image.copyResize(source, width: width, height: height);
  }

  @override
  Uint8List encodeJpeg(image.Image source, {required int quality}) {
    qualities.add(quality);
    encodedDimensions.add(ImageDimensions(source.width, source.height));
    final length = encodedLength?.call(source) ?? 64;
    return Uint8List(length);
  }
}

Future<PrivatePreparedImage> _newPrepared(
  PrivateImageStore store,
  int marker,
) {
  return store.writePreparedJpeg(
    bytes: Uint8List.fromList([marker]),
    width: 1,
    height: 1,
    quality: 85,
  );
}

Future<List<File>> _recognizedFiles(PrivateImageStore store) async {
  if (!await store.namespaceDirectory.exists()) {
    return <File>[];
  }
  return store.namespaceDirectory
      .list(followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
}

bool _isInside(File file, Directory directory) {
  final root = '${directory.absolute.path}${Platform.pathSeparator}';
  return file.absolute.path.startsWith(root);
}
