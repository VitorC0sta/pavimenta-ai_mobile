import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/infrastructure/image_artifacts.dart';
import 'package:pavimenta_ai_mobile/infrastructure/private_image_store.dart';

void main() {
  late Directory sandbox;
  late PrivateImageStore store;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('e2_lease_contract_');
    store = PrivateImageStore.at(sandbox);
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('PreparedImageLease ownership contract', () {
    test('streams bytes and immutable metadata while ownership is active',
        () async {
      final PreparedImageLease lease = await store.writePreparedJpeg(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        width: 2,
        height: 2,
        quality: 85,
      );

      final streamed = await lease.openRead().expand((chunk) => chunk).toList();

      expect(streamed, [1, 2, 3, 4]);
      expect(lease.hasOwnership, isTrue);
      expect(lease.metadata.mimeType, 'image/jpeg');
      expect(lease.metadata.byteLength, 4);
      expect(lease.metadata.width, 2);
      expect(lease.metadata.height, 2);
      expect(lease.metadata.quality, 85);

      await lease.withdrawOwnership();
    });

    test('promotion invalidates the old owner and preserves the new owner',
        () async {
      final original = await store.writePreparedJpeg(
        bytes: Uint8List.fromList([7, 8, 9]),
        width: 3,
        height: 1,
        quality: 85,
      );
      final file = original.file;

      final promoted = original.promoteOwnership();

      expect(original.hasOwnership, isFalse);
      expect(promoted.hasOwnership, isTrue);
      expect(() => original.openRead(), throwsStateError);
      await original.withdrawOwnership();
      expect(await file.exists(), isTrue);
      expect(await promoted.openRead().expand((chunk) => chunk).toList(),
          [7, 8, 9]);

      await promoted.withdrawOwnership();
      await promoted.withdrawOwnership();
      expect(promoted.hasOwnership, isFalse);
      expect(await file.exists(), isFalse);
    });

    test('E1 dispose remains an idempotent ownership withdrawal', () async {
      final OwnedPreparedImage image = await store.writePreparedJpeg(
        bytes: Uint8List.fromList([5]),
        width: 1,
        height: 1,
        quality: 85,
      );
      final concrete = image as PrivatePreparedImage;
      final file = concrete.file;

      await image.dispose();
      await image.dispose();

      expect(concrete.hasOwnership, isFalse);
      expect(await file.exists(), isFalse);
    });
  });
}
