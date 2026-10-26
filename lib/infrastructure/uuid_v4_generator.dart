import 'package:uuid/uuid.dart';

import '../application/e1_ports.dart';

/// UUID version 4 generator used after an E1 image has been prepared.
final class UuidV4Generator implements UuidGenerator {
  const UuidV4Generator({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  @override
  String newV4() => _uuid.v4();
}
