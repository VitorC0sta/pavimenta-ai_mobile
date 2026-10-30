import 'dart:async';

import '../../domain/delivery/occurrence_upload_request.dart';
import '../../domain/in_memory_occurrence.dart';
import 'occurrence_multipart_mapper.dart';
import 'streaming_multipart_encoder.dart';

/// Fixed categories of a local failure found before the socket is opened.
///
/// They carry no field value, identifier, path, URL, credential, byte, or raw
/// exception, so they are safe for local state and technical logs.
enum OccurrenceMultipartPreparationFailure {
  /// A persisted field violates the RF-14 contract (UUID, coordinate range,
  /// confidence range, `defectClass`, ISO 8601 with offset, speed range).
  invalidMetadata,

  /// The declared JPEG length is above 2 MiB.
  imageTooLarge,

  /// The image is too short to be a JPEG or does not start with the JPEG
  /// start-of-image signature.
  imageNotJpeg,

  /// The image stream failed or ended before its declared length while it
  /// was being inspected.
  imageUnreadable,

  /// The multipart body could not be assembled.
  assemblyFailure,
}

/// Sanitized error raised inside the image stream when the JPEG ends without
/// its end-of-image marker. The encoder turns it into a body failure.
final class OccurrenceImageRevalidationException implements Exception {
  const OccurrenceImageRevalidationException(this.failure);

  final OccurrenceMultipartPreparationFailure failure;

  @override
  String toString() => 'OccurrenceImageRevalidationException(${failure.name})';
}

/// Outcome of [OccurrenceMultipartPreparer.prepare].
sealed class OccurrenceMultipartPreparation {
  const OccurrenceMultipartPreparation();
}

/// The request passed every local check; [body] may be written to a socket.
///
/// The image read is already open (its first bytes were inspected). The
/// owner must either open and consume [body] or call [discard] so the private
/// file is not left open.
final class PreparedOccurrenceMultipart extends OccurrenceMultipartPreparation {
  PreparedOccurrenceMultipart._(this.body, this._image);

  final EncodedMultipartBody body;
  final _InspectedImage _image;

  /// Releases the image read when [body] was never opened. Idempotent and
  /// harmless after the body was opened (the body stream then owns cleanup).
  Future<void> discard() => _image.discardIfUnused();

  @override
  String toString() => 'PreparedOccurrenceMultipart(<redacted>)';
}

/// A local check failed. No socket may be opened for this attempt.
///
/// The occurrence is untouched: the preparer has no access to the queue, so
/// the row, its JPEG, its `idempotencyKey`, and its retry state stay exactly
/// as persisted.
final class OccurrenceMultipartPreparationRejected
    extends OccurrenceMultipartPreparation {
  const OccurrenceMultipartPreparationRejected(this.failure);

  final OccurrenceMultipartPreparationFailure failure;

  @override
  bool operator ==(Object other) =>
      other is OccurrenceMultipartPreparationRejected &&
      other.failure == failure;

  @override
  int get hashCode =>
      Object.hash(OccurrenceMultipartPreparationRejected, failure);

  @override
  String toString() =>
      'OccurrenceMultipartPreparationRejected(${failure.name})';
}

/// Revalidates one attempt and assembles its multipart body before any
/// network use (design E4.7, E4.8, E4.9).
///
/// The queue already guarantees these invariants when it selects the head,
/// but the persisted data and the private file outlive that check. Right
/// before the socket the preparer therefore verifies again:
///
/// 1. the persisted metadata against RF-14;
/// 2. the declared image length (1 byte to 2 MiB);
/// 3. the JPEG signature in the first bytes of the stream, without buffering
///    the rest of the file;
/// 4. that the canonical multipart can be assembled.
///
/// While the body streams, the image must also end with the JPEG end-of-image
/// marker; otherwise the body fails with a sanitized error.
final class OccurrenceMultipartPreparer {
  const OccurrenceMultipartPreparer({
    OccurrenceMultipartMapper mapper = const OccurrenceMultipartMapper(),
  }) : _mapper = mapper;

  /// Largest accepted JPEG (`2 * 1024 * 1024` bytes).
  static const int maximumImageByteLength = 2 * 1024 * 1024;

  /// Smallest byte count holding both JPEG markers (SOI and EOI).
  static const int minimumImageByteLength = 4;

  /// RF-14.8 class of the MVP.
  static const String expectedDefectClass = 'pothole';

  /// RF-14.9 speed range in km/h.
  static const double maximumSpeedKmh = 300;

  final OccurrenceMultipartMapper _mapper;

  /// Validates [request] and returns the encoded body or a fixed failure.
  ///
  /// Never throws. On rejection the image stream of [request] is released
  /// and no byte has been forwarded anywhere.
  Future<OccurrenceMultipartPreparation> prepare(
    OccurrenceUploadRequest request,
    StreamingMultipartEncoder encoder,
  ) async {
    if (!_hasValidMetadata(request)) {
      return const OccurrenceMultipartPreparationRejected(
        OccurrenceMultipartPreparationFailure.invalidMetadata,
      );
    }
    final declaredLength = request.payload.image.byteLength;
    if (declaredLength > maximumImageByteLength) {
      return const OccurrenceMultipartPreparationRejected(
        OccurrenceMultipartPreparationFailure.imageTooLarge,
      );
    }
    if (declaredLength < minimumImageByteLength) {
      return const OccurrenceMultipartPreparationRejected(
        OccurrenceMultipartPreparationFailure.imageNotJpeg,
      );
    }

    final image = _InspectedImage(request.imageStream, declaredLength);
    final EncodedMultipartBody body;
    try {
      body = _mapper.encode(
        OccurrenceUploadRequest(
          baseUrl: request.baseUrl,
          credential: request.credential,
          configurationRevision: request.configurationRevision,
          idempotencyKey: request.idempotencyKey,
          payload: request.payload,
          imageStream: image.stream(),
        ),
        encoder,
      );
    } catch (_) {
      await image.discardIfUnused();
      return const OccurrenceMultipartPreparationRejected(
        OccurrenceMultipartPreparationFailure.assemblyFailure,
      );
    }

    final imageFailure = await image.inspectSignature();
    if (imageFailure != null) {
      await image.discardIfUnused();
      return OccurrenceMultipartPreparationRejected(imageFailure);
    }
    return PreparedOccurrenceMultipart._(body, image);
  }

  static bool _hasValidMetadata(OccurrenceUploadRequest request) {
    final payload = request.payload;
    final speedKmh = payload.speedKmh;
    return isUuidV4(request.idempotencyKey) &&
        _inRange(payload.latitude, -90, 90) &&
        _inRange(payload.longitude, -180, 180) &&
        _inRange(payload.confidence, 0, 1) &&
        payload.defectClass == expectedDefectClass &&
        _isIso8601WithOffset(payload.detectedAtIso8601) &&
        (speedKmh == null || _inRange(speedKmh, 0, maximumSpeedKmh));
  }

  static bool _inRange(double value, double minimum, double maximum) =>
      value.isFinite && value >= minimum && value <= maximum;

  /// Strict check: `DateTime.tryParse` alone would normalize out-of-range
  /// fields (month 13, day 32) instead of rejecting them.
  static bool _isIso8601WithOffset(String value) {
    final match = _iso8601WithOffset.firstMatch(value);
    if (match == null) {
      return false;
    }
    int field(int group) => int.parse(match.group(group)!);
    final year = field(1);
    final month = field(2);
    final day = field(3);
    final offsetHours = match.group(7) == null ? 0 : field(7);
    final offsetMinutes = match.group(8) == null ? 0 : field(8);
    return month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        DateTime.utc(year, month, day).day == day &&
        field(4) <= 23 &&
        field(5) <= 59 &&
        field(6) <= 59 &&
        offsetHours <= 23 &&
        offsetMinutes <= 59;
  }
}

/// Date, time, optional fraction, and a mandatory `Z` or `±HH:MM` offset.
final RegExp _iso8601WithOffset = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?'
  r'(?:Z|[+-](\d{2}):(\d{2}))$',
);

const int _jpegMarker = 0xFF;
const int _startOfImage = 0xD8;
const int _endOfImage = 0xD9;

/// Single-use view of the private JPEG stream.
///
/// [inspectSignature] reads only enough leading chunks to see the first three
/// bytes; [stream] replays those chunks and then forwards the remaining ones
/// as they arrive, so the file is never buffered as a whole.
final class _InspectedImage {
  _InspectedImage(Stream<List<int>> source, this._declaredLength)
      : _iterator = StreamIterator<List<int>>(source);

  final StreamIterator<List<int>> _iterator;
  final int _declaredLength;
  final List<List<int>> _leading = <List<int>>[];
  bool _sourceEnded = false;
  bool _streamStarted = false;
  bool _released = false;

  Future<OccurrenceMultipartPreparationFailure?> inspectSignature() async {
    var inspected = 0;
    try {
      while (inspected < 3) {
        if (!await _iterator.moveNext()) {
          _sourceEnded = true;
          break;
        }
        final chunk = _iterator.current;
        if (chunk.isEmpty) {
          continue;
        }
        _leading.add(chunk);
        inspected += chunk.length;
      }
    } catch (_) {
      return OccurrenceMultipartPreparationFailure.imageUnreadable;
    }
    if (inspected > _declaredLength ||
        (_sourceEnded && inspected != _declaredLength)) {
      return OccurrenceMultipartPreparationFailure.imageUnreadable;
    }
    final signature = _leading.expand((chunk) => chunk).take(3).toList();
    if (signature.length < 3 ||
        signature[0] != _jpegMarker ||
        signature[1] != _startOfImage ||
        signature[2] != _jpegMarker) {
      return OccurrenceMultipartPreparationFailure.imageNotJpeg;
    }
    return null;
  }

  Stream<List<int>> stream() async* {
    _streamStarted = true;
    int? previous;
    int? last;
    void track(List<int> chunk) {
      if (chunk.length >= 2) {
        previous = chunk[chunk.length - 2];
        last = chunk[chunk.length - 1];
      } else if (chunk.length == 1) {
        previous = last;
        last = chunk[0];
      }
    }

    try {
      for (final chunk in _leading) {
        track(chunk);
        yield chunk;
      }
      _leading.clear();
      while (!_sourceEnded) {
        final bool hasNext;
        try {
          hasNext = await _iterator.moveNext();
        } catch (_) {
          throw const OccurrenceImageRevalidationException(
            OccurrenceMultipartPreparationFailure.imageUnreadable,
          );
        }
        if (!hasNext) {
          break;
        }
        final chunk = _iterator.current;
        track(chunk);
        yield chunk;
      }
    } finally {
      await _release();
    }
    if (previous != _jpegMarker || last != _endOfImage) {
      throw const OccurrenceImageRevalidationException(
        OccurrenceMultipartPreparationFailure.imageNotJpeg,
      );
    }
  }

  Future<void> discardIfUnused() async {
    if (!_streamStarted) {
      _leading.clear();
      await _release();
    }
  }

  Future<void> _release() async {
    if (_released) {
      return;
    }
    _released = true;
    try {
      await _iterator.cancel();
    } catch (_) {
      // Releasing a failed read reveals nothing and changes no decision.
    }
  }
}
