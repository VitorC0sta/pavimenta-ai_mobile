import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/delivery_queue_head.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/non_printable_secret.dart';
import 'package:pavimenta_ai_mobile/domain/delivery/occurrence_upload_request.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/occurrence_multipart_mapper.dart';
import 'package:pavimenta_ai_mobile/infrastructure/delivery/streaming_multipart_encoder.dart';

const String _key = '3f2b8c1e-4d5a-4b6c-9d7e-8f9a0b1c2d3e';
const List<int> _jpeg = <int>[0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9];

OccurrenceUploadRequest _request({double? speedKmh}) => OccurrenceUploadRequest(
      baseUrl: Uri.parse('https://api.example.test'),
      credential: NonPrintableSecret('prefix.secret'),
      configurationRevision: 1,
      idempotencyKey: _key,
      payload: DeliveryOccurrencePayload(
        detectedAtIso8601: '2026-10-14T12:30:45.123-03:00',
        latitude: -23.5505,
        longitude: -46.6333,
        speedKmh: speedKmh,
        confidence: 1.0,
        defectClass: 'pothole',
        image: DeliveryImageRef(
          byteLength: _jpeg.length,
          opaqueHandle: Object(),
        ),
      ),
      imageStream: Stream<List<int>>.fromIterable(<List<int>>[
        _jpeg.sublist(0, 2),
        _jpeg.sublist(2),
      ]),
    );

Map<String, String> _texts(List<MultipartPart> parts) => <String, String>{
      for (final part in parts.whereType<MultipartTextPart>())
        part.name: part.value,
    };

void main() {
  // **Validates: Requirements RF-14.2–11, RNF-01.8–12**
  const mapper = OccurrenceMultipartMapper();

  test('maps exactly the canonical fields in a fixed order', () {
    final parts = mapper.partsFor(_request(speedKmh: 42.5));

    expect(parts.map((part) => part.name), <String>[
      'idempotencyKey',
      'latitude',
      'longitude',
      'confidence',
      'defectClass',
      'detectedAt',
      'speedKmh',
      'image',
    ]);
    expect(_texts(parts), <String, String>{
      'idempotencyKey': _key,
      'latitude': '-23.5505',
      'longitude': '-46.6333',
      'confidence': '1.0',
      'defectClass': 'pothole',
      'detectedAt': '2026-10-14T12:30:45.123-03:00',
      'speedKmh': '42.5',
    });
  });

  test('image part is a generic JPEG file with the persisted length', () {
    final image = mapper.partsFor(_request()).last as MultipartFilePart;

    expect(image.name, 'image');
    expect(image.filename, 'occurrence.jpg');
    expect(image.contentType, 'image/jpeg');
    expect(image.length, _jpeg.length);
  });

  test('omits speedKmh when absent and keeps an explicit zero', () {
    expect(
        _texts(mapper.partsFor(_request())).containsKey('speedKmh'), isFalse);
    expect(_texts(mapper.partsFor(_request(speedKmh: 0)))['speedKmh'], '0.0');
  });

  test('encoded body carries the mapped parts and streamed JPEG bytes',
      () async {
    final body = mapper.encode(
      _request(),
      StreamingMultipartEncoder(boundaryGenerator: () => 'B0undary'),
    );
    final bytes = <int>[];
    await for (final chunk in body.open()) {
      bytes.addAll(chunk);
    }

    expect(bytes.length, body.contentLength);
    final text = latin1.decode(bytes);
    expect(
      text,
      contains(
        'Content-Disposition: form-data; name="image"; '
        'filename="occurrence.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'
        '${latin1.decode(_jpeg)}\r\n--B0undary--\r\n',
      ),
    );
    expect(text, contains('name="idempotencyKey"\r\n\r\n$_key\r\n'));
    expect(text, isNot(contains('speedKmh')));
  });
}
