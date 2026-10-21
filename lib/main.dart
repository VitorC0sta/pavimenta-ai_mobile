import 'package:flutter/material.dart';

import 'e0/camera_diagnostic.dart';
import 'e0/diagnostic_http_client.dart';
import 'e0/e0_controller.dart';
import 'e0/e0_screen.dart';
import 'e0/location_diagnostic.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PavimentaAiMobileApp());
}

class PavimentaAiMobileApp extends StatefulWidget {
  const PavimentaAiMobileApp({super.key});

  @override
  State<PavimentaAiMobileApp> createState() => _PavimentaAiMobileAppState();
}

class _PavimentaAiMobileAppState extends State<PavimentaAiMobileApp> {
  late final E0Controller _controller;

  @override
  void initState() {
    super.initState();
    _controller = E0Controller(
      cameraDiagnostic: const CameraDiagnostic(),
      locationDiagnostic: LocationDiagnostic(),
      diagnosticHttpClient: DiagnosticHttpClient(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pavimenta AI — E0',
      home: E0Screen(controller: _controller),
    );
  }
}
