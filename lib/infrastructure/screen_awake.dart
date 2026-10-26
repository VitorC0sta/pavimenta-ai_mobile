import 'package:wakelock_plus/wakelock_plus.dart';

import '../application/e1_ports.dart';

/// Android screen-awake adapter used only by the active Operation route.
final class WakelockPlusScreenAwake implements ScreenAwakePort {
  const WakelockPlusScreenAwake();

  @override
  Future<void> setEnabled(bool enabled) {
    return enabled ? WakelockPlus.enable() : WakelockPlus.disable();
  }
}
