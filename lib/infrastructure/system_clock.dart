import '../application/e1_ports.dart';

/// Production clock for accepted operational actions.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
