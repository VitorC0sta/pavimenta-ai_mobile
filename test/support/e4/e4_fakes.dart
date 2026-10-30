/// Minimal E4 test doubles (task 62.5).
///
/// All fakes are plain Dart: no mock framework, no network, no timers, no
/// SQLite, no filesystem, no secure storage and no hardware.
///
/// Production E4 contracts do not exist yet (task 63). Every `Fake*` model in
/// these files is therefore defined locally to the tests and is deliberately
/// named differently from the production types planned by tasks 63.1/63.4, so
/// task 63 can introduce them without collisions and later point the fakes at
/// the real ports. The existing production `Clock` port (and the E2
/// `QueueRemovalResult`/`QueueSnapshot` types) are reused, not recreated.
library;

export 'fake_clock.dart';
export 'fake_delivery_configuration_snapshot.dart';
export 'fake_delivery_queue.dart';
export 'fake_delivery_timer.dart';
export 'fake_occurrence_transport.dart';
