import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Produces the boundary of one encoding (one transport attempt).
///
/// The returned value is validated by [StreamingMultipartEncoder]; tests may
/// inject a fixed boundary to obtain deterministic bytes.
typedef MultipartBoundaryGenerator = String Function();

/// Fixed categories of a local multipart assembly failure.
///
/// They carry no part value, file name, path, byte, or raw exception.
enum MultipartEncodingFailure {
  /// The boundary is empty, longer than 70 characters, or uses a character
  /// outside the controlled RFC 2046 token subset.
  invalidBoundary,

  /// No part was supplied.
  noParts,

  /// A part name is not controlled printable ASCII.
  invalidPartName,

  /// A file name is not controlled printable ASCII.
  invalidFilename,

  /// A content type is not a plain `type/subtype` ASCII token pair.
  invalidContentType,

  /// A text value contains an unpaired UTF-16 surrogate and cannot be encoded
  /// as UTF-8 without silently changing it.
  invalidTextValue,

  /// A text value contains the boundary delimiter.
  boundaryCollision,

  /// A declared file length is negative.
  invalidDeclaredLength,

  /// The file source emitted more or fewer bytes than declared.
  fileLengthMismatch,

  /// The file source failed while being read.
  fileSourceFailure,

  /// The encoded body was already opened once.
  bodyAlreadyConsumed,
}

/// Sanitized local failure of the multipart encoder.
final class MultipartEncodingException implements Exception {
  const MultipartEncodingException(this.failure);

  final MultipartEncodingFailure failure;

  @override
  String toString() => 'MultipartEncodingException(${failure.name})';
}

/// One part of a `multipart/form-data` body.
sealed class MultipartPart {
  const MultipartPart(this.name);

  /// Controlled ASCII form field name.
  final String name;
}

/// A text field whose value is written as UTF-8.
final class MultipartTextPart extends MultipartPart {
  const MultipartTextPart(super.name, this.value);

  final String value;

  @override
  String toString() => 'MultipartTextPart(<redacted>)';
}

/// A file field whose bytes are streamed from [source].
///
/// [length] is the declared byte count used for `Content-Length`; [source] is
/// consumed once, chunk by chunk, and is never buffered as a whole.
final class MultipartFilePart extends MultipartPart {
  const MultipartFilePart(
    super.name, {
    required this.filename,
    required this.contentType,
    required this.length,
    required this.source,
  });

  final String filename;
  final String contentType;
  final int length;
  final Stream<List<int>> source;

  @override
  String toString() => 'MultipartFilePart(<redacted>)';
}

/// A single-use encoded body with its precomputed length.
final class EncodedMultipartBody {
  EncodedMultipartBody._(this.boundary, this._segments, this.contentLength);

  /// Boundary of this encoding.
  final String boundary;

  /// Exact number of bytes [open] emits when every file matches its length.
  final int contentLength;

  /// Value for the request `Content-Type` header.
  String get contentType => 'multipart/form-data; boundary=$boundary';

  final List<Object> _segments;
  bool _opened = false;

  /// Returns the body stream. It may be called only once.
  ///
  /// The stream emits the controlled header/text bytes and forwards file
  /// chunks as they arrive. A file emitting a different number of bytes than
  /// declared, or failing, ends the stream with a sanitized
  /// [MultipartEncodingException]; excess bytes are never forwarded.
  Stream<List<int>> open() {
    if (_opened) {
      throw const MultipartEncodingException(
        MultipartEncodingFailure.bodyAlreadyConsumed,
      );
    }
    _opened = true;
    return _emit(_segments);
  }

  @override
  String toString() => 'EncodedMultipartBody(<redacted>)';
}

/// Small deterministic `multipart/form-data` encoder (design E4.3).
///
/// It writes controlled ASCII headers, CRLF line breaks, UTF-8 text values, and
/// streamed file bytes. `Content-Length` is computed from header/text bytes
/// plus the declared file lengths, so no file is read into memory and no
/// temporary multipart file is created.
final class StreamingMultipartEncoder {
  StreamingMultipartEncoder({MultipartBoundaryGenerator? boundaryGenerator})
      : _boundaryGenerator = boundaryGenerator ?? secureMultipartBoundary;

  /// RFC 2046 limit for a boundary.
  static const int maximumBoundaryLength = 70;

  final MultipartBoundaryGenerator _boundaryGenerator;

  /// Encodes [parts] in order with a fresh boundary.
  ///
  /// Throws [MultipartEncodingException] for invalid input; nothing is read
  /// from any file source at this point.
  EncodedMultipartBody encode(List<MultipartPart> parts) {
    final boundary = _boundaryGenerator();
    if (!isValidBoundary(boundary)) {
      throw const MultipartEncodingException(
        MultipartEncodingFailure.invalidBoundary,
      );
    }
    if (parts.isEmpty) {
      throw const MultipartEncodingException(MultipartEncodingFailure.noParts);
    }

    final delimiter = '--$boundary';
    final segments = <Object>[];
    var length = 0;

    void addBytes(Uint8List bytes) {
      segments.add(bytes);
      length += bytes.length;
    }

    for (final part in parts) {
      if (!_isControlledAscii(part.name)) {
        throw const MultipartEncodingException(
          MultipartEncodingFailure.invalidPartName,
        );
      }
      switch (part) {
        case MultipartTextPart(:final value):
          if (_hasUnpairedSurrogate(value)) {
            throw const MultipartEncodingException(
              MultipartEncodingFailure.invalidTextValue,
            );
          }
          if (value.contains(delimiter)) {
            throw const MultipartEncodingException(
              MultipartEncodingFailure.boundaryCollision,
            );
          }
          addBytes(
            _ascii(
              '$delimiter\r\n'
              'Content-Disposition: form-data; name="${part.name}"\r\n'
              '\r\n',
            ),
          );
          addBytes(Uint8List.fromList(utf8.encode(value)));
          addBytes(_ascii('\r\n'));
        case MultipartFilePart(
            :final filename,
            :final contentType,
            length: final declaredLength,
          ):
          if (!_isControlledAscii(filename)) {
            throw const MultipartEncodingException(
              MultipartEncodingFailure.invalidFilename,
            );
          }
          if (!_contentTypePattern.hasMatch(contentType)) {
            throw const MultipartEncodingException(
              MultipartEncodingFailure.invalidContentType,
            );
          }
          if (declaredLength < 0) {
            throw const MultipartEncodingException(
              MultipartEncodingFailure.invalidDeclaredLength,
            );
          }
          addBytes(
            _ascii(
              '$delimiter\r\n'
              'Content-Disposition: form-data; name="${part.name}"; '
              'filename="$filename"\r\n'
              'Content-Type: $contentType\r\n'
              '\r\n',
            ),
          );
          segments.add(part);
          length += declaredLength;
          addBytes(_ascii('\r\n'));
      }
    }
    addBytes(_ascii('$delimiter--\r\n'));

    return EncodedMultipartBody._(
      boundary,
      List<Object>.unmodifiable(segments),
      length,
    );
  }

  /// Whether [boundary] is 1–70 characters of the controlled token subset
  /// (`A-Z a-z 0-9 ' + _ - .`), safe unquoted in `Content-Type`.
  static bool isValidBoundary(String boundary) =>
      boundary.isNotEmpty &&
      boundary.length <= maximumBoundaryLength &&
      _boundaryPattern.hasMatch(boundary);
}

/// Default generator: 48 characters from [Random.secure] over `A-Z a-z 0-9`.
String secureMultipartBoundary() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return String.fromCharCodes(
    List<int>.generate(
      48,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ),
  );
}

final RegExp _boundaryPattern = RegExp(r"^[A-Za-z0-9'+_.\-]+$");

final RegExp _contentTypePattern = RegExp(
  r"^[A-Za-z0-9!#$&^_.+\-]+/[A-Za-z0-9!#$&^_.+\-]+$",
);

/// Printable ASCII (0x20–0x7E) without `"` or `\`, non-empty.
bool _isControlledAscii(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (final unit in value.codeUnits) {
    if (unit < 0x20 || unit > 0x7E || unit == 0x22 || unit == 0x5C) {
      return false;
    }
  }
  return true;
}

bool _hasUnpairedSurrogate(String value) {
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length) {
        return true;
      }
      final next = units[index + 1];
      if (next < 0xDC00 || next > 0xDFFF) {
        return true;
      }
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

Uint8List _ascii(String value) => Uint8List.fromList(ascii.encode(value));

Stream<List<int>> _emit(List<Object> segments) async* {
  for (final segment in segments) {
    if (segment is Uint8List) {
      yield segment;
    } else if (segment is MultipartFilePart) {
      yield* _emitFile(segment);
    }
  }
}

Stream<List<int>> _emitFile(MultipartFilePart part) async* {
  var emitted = 0;
  final iterator = StreamIterator<List<int>>(part.source);
  try {
    while (true) {
      final bool hasNext;
      try {
        hasNext = await iterator.moveNext();
      } catch (_) {
        throw const MultipartEncodingException(
          MultipartEncodingFailure.fileSourceFailure,
        );
      }
      if (!hasNext) {
        break;
      }
      final chunk = iterator.current;
      emitted += chunk.length;
      if (emitted > part.length) {
        throw const MultipartEncodingException(
          MultipartEncodingFailure.fileLengthMismatch,
        );
      }
      if (chunk.isNotEmpty) {
        yield chunk;
      }
    }
  } finally {
    await iterator.cancel();
  }
  if (emitted != part.length) {
    throw const MultipartEncodingException(
      MultipartEncodingFailure.fileLengthMismatch,
    );
  }
}
