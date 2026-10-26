import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../application/e1_ports.dart';
import 'image_artifacts.dart';
import 'private_image_store.dart';

const int e1JpegQuality = 85;
const int e1MaximumImageWidth = 1280;
const int e1MaximumImageHeight = 720;
const int e1MaximumJpegBytes = 2 * 1024 * 1024;
const int e1MaximumSourceBytes = 64 * 1024 * 1024;
const double _dimensionReductionFactor = 0.85;

/// Injectable image operations keep JPEG quality and resize attempts directly
/// observable without mocking filesystem or application behavior.
abstract interface class E1ImageCodec {
  image.Image? decode(Uint8List bytes);
  image.Image bakeOrientation(image.Image source);
  image.Image resize(image.Image source, int width, int height);
  Uint8List encodeJpeg(image.Image source, {required int quality});
}

final class DartE1ImageCodec implements E1ImageCodec {
  const DartE1ImageCodec();

  @override
  image.Image? decode(Uint8List bytes) => image.decodeImage(bytes);

  @override
  image.Image bakeOrientation(image.Image source) {
    return image.bakeOrientation(source);
  }

  @override
  image.Image resize(image.Image source, int width, int height) {
    return image.copyResize(
      source,
      width: width,
      height: height,
      interpolation: image.Interpolation.average,
    );
  }

  @override
  Uint8List encodeJpeg(image.Image source, {required int quality}) {
    return image.encodeJpg(source, quality: quality);
  }
}

/// Produces a private JPEG or rejects explicitly, always retiring its source.
final class PrivateJpegImagePreparer implements ImagePreparer {
  const PrivateJpegImagePreparer({
    required this.store,
    this.codec = const DartE1ImageCodec(),
  });

  final PrivateImageStore store;
  final E1ImageCodec codec;

  @override
  Future<OwnedPreparedImage> prepare(TemporaryCapture capture) async {
    if (capture is! PrivateTemporaryCapture || !capture.isActive) {
      throw const ImagePreparationException(
        ImagePreparationFailure.invalidCapture,
      );
    }

    PrivatePreparedImage? prepared;
    try {
      final sourceLength = await capture.file.length();
      if (sourceLength <= 0 || sourceLength > e1MaximumSourceBytes) {
        throw const ImagePreparationException(
          ImagePreparationFailure.invalidSourceSize,
        );
      }

      final bytes = await capture.file.readAsBytes();
      final image.Image? decoded;
      try {
        decoded = codec.decode(bytes);
      } catch (_) {
        throw const ImagePreparationException(
          ImagePreparationFailure.decodeFailed,
        );
      }
      if (decoded == null || decoded.width < 1 || decoded.height < 1) {
        throw const ImagePreparationException(
          ImagePreparationFailure.decodeFailed,
        );
      }

      final oriented = codec.bakeOrientation(decoded);
      var dimensions = fitImageDimensions(
        oriented.width,
        oriented.height,
        maxWidth: e1MaximumImageWidth,
        maxHeight: e1MaximumImageHeight,
      );
      var candidate = _resizeIfNeeded(oriented, dimensions);

      while (true) {
        final jpeg = codec.encodeJpeg(candidate, quality: e1JpegQuality);
        if (jpeg.length <= e1MaximumJpegBytes) {
          prepared = await store.writePreparedJpeg(
            bytes: jpeg,
            width: dimensions.width,
            height: dimensions.height,
            quality: e1JpegQuality,
          );
          return prepared;
        }

        final next = nextStrictlySmallerDimensions(
          dimensions.width,
          dimensions.height,
        );
        if (next == null) {
          throw const ImagePreparationException(
            ImagePreparationFailure.maximumSizeUnreachable,
          );
        }
        dimensions = next;
        candidate = codec.resize(oriented, next.width, next.height);
      }
    } on ImagePreparationException {
      rethrow;
    } on FileSystemException {
      throw const ImagePreparationException(
        ImagePreparationFailure.storageFailed,
      );
    } catch (_) {
      throw const ImagePreparationException(
        ImagePreparationFailure.processingFailed,
      );
    } finally {
      await capture.dispose();
      if (prepared != null && !prepared.isActive) {
        await prepared.dispose();
      }
    }
  }

  image.Image _resizeIfNeeded(
    image.Image source,
    ImageDimensions dimensions,
  ) {
    if (source.width == dimensions.width &&
        source.height == dimensions.height) {
      return source;
    }
    return codec.resize(source, dimensions.width, dimensions.height);
  }
}

final class ImageDimensions {
  const ImageDimensions(this.width, this.height);
  final int width;
  final int height;

  @override
  bool operator ==(Object other) {
    return other is ImageDimensions &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

ImageDimensions fitImageDimensions(
  int width,
  int height, {
  required int maxWidth,
  required int maxHeight,
}) {
  if (width < 1 || height < 1 || maxWidth < 1 || maxHeight < 1) {
    throw ArgumentError('Image dimensions must be positive.');
  }
  final scaleWidth = maxWidth / width;
  final scaleHeight = maxHeight / height;
  final scale = scaleWidth < scaleHeight ? scaleWidth : scaleHeight;
  if (scale >= 1) {
    return ImageDimensions(width, height);
  }
  return ImageDimensions(
    (width * scale).floor().clamp(1, maxWidth),
    (height * scale).floor().clamp(1, maxHeight),
  );
}

/// Returns a strictly smaller integer size while retaining the current aspect
/// ratio within unavoidable one-pixel rounding. Returning null proves the
/// finite loop reached its 1x1 lower bound.
ImageDimensions? nextStrictlySmallerDimensions(int width, int height) {
  if (width < 1 || height < 1) {
    throw ArgumentError('Image dimensions must be positive.');
  }
  if (width == 1 && height == 1) {
    return null;
  }

  const scale = _dimensionReductionFactor;
  var nextWidth = (width * scale).floor().clamp(1, width);
  var nextHeight = (height * scale).floor().clamp(1, height);

  if (nextWidth == width && width > 1) {
    nextWidth = width - 1;
  }
  if (nextHeight == height && height > 1) {
    nextHeight = height - 1;
  }

  return ImageDimensions(nextWidth, nextHeight);
}

enum ImagePreparationFailure {
  invalidCapture,
  invalidSourceSize,
  decodeFailed,
  maximumSizeUnreachable,
  storageFailed,
  processingFailed,
}

final class ImagePreparationException implements Exception {
  const ImagePreparationException(this.failure);
  final ImagePreparationFailure failure;

  @override
  String toString() => 'ImagePreparationException: ${failure.name}';
}
