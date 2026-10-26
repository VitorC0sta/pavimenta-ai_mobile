import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavimenta_ai_mobile/domain/location_snapshot.dart';
import 'package:pavimenta_ai_mobile/domain/persistent_occurrence.dart';
import 'package:pavimenta_ai_mobile/operation/operation_state.dart';

void main() {
  // **Validates: Requirements 03.6, 05.5, 12.3, 12.5**
  test('projects queue recovery health, aggregate pending count, and message',
      () {
    final recovering = OperationState.initial(
      queueSnapshot: const QueueSnapshot.initializing(),
    );

    expect(recovering.queueHealth, QueueHealth.initializing);
    expect(recovering.pendingCount, 0);
    expect(recovering.isQueueRecovering, isTrue);
    expect(recovering.isQueueReady, isFalse);
    expect(recovering.queueMessage, 'Recuperando fila local.');
    expect(recovering.canRegister, isFalse);

    final degraded = recovering.withQueueSnapshot(
      const QueueSnapshot(
        health: QueueHealth.degraded,
        pendingCount: 3,
      ),
    );

    expect(degraded.queueHealth, QueueHealth.degraded);
    expect(degraded.pendingCount, 3);
    expect(
        degraded.queueMessage, 'Atenção: a fila local precisa de recuperação.');
    expect(degraded.canRegister, isFalse);
  });

  // **Validates: Requirements 03.6, 12.3**
  test('requires a ready queue and no persistence operation to register', () {
    final ready = OperationState.initial(
      queueSnapshot: const QueueSnapshot(
        health: QueueHealth.ready,
        pendingCount: 2,
      ),
    ).copyWith(
      cameraStatus: OperationCameraStatus.ready,
      previewHandle: Object(),
      locationStatus: OperationLocationStatus.ready,
      locationSnapshot: ImmutableLocationSnapshot(
        point: ImmutableGeoPoint(latitude: -23.5505, longitude: -46.6333),
      ),
      lifecycleState: AppLifecycleState.resumed,
    );

    expect(ready.isQueueReady, isTrue);
    expect(ready.pendingCount, 2);
    expect(ready.canRegister, isTrue);
    expect(ready.copyWith(isPersisting: true).canRegister, isFalse);
  });
}
