import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'e0_controller.dart';
import 'e0_state.dart';

class E0Screen extends StatefulWidget {
  const E0Screen({
    required this.controller,
    super.key,
  });

  final E0Controller controller;

  @override
  State<E0Screen> createState() => _E0ScreenState();
}

class _E0ScreenState extends State<E0Screen> with WidgetsBindingObserver {
  static const double _panelSpacing = 16;
  static const double _maximumContentWidth = 1400;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState != null) {
        unawaited(widget.controller.handleLifecycleState(lifecycleState));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(widget.controller.handleLifecycleState(state));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      widget.controller.handleLifecycleState(AppLifecycleState.detached),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final state = widget.controller.state;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Pavimenta AI — E0'),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding =
                    constraints.maxWidth < 400 ? 12.0 : 24.0;
                final availableWidth =
                    (constraints.maxWidth - (horizontalPadding * 2))
                        .clamp(0.0, _maximumContentWidth)
                        .toDouble();
                final columnCount = switch (availableWidth) {
                  >= 1100 => 3,
                  >= 680 => 2,
                  _ => 1,
                };
                final panelWidth =
                    (availableWidth - (_panelSpacing * (columnCount - 1))) /
                        columnCount;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    20,
                    horizontalPadding,
                    32,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maximumContentWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'E0 — Diagnóstico Android',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          const _ScopeNotice(),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: _panelSpacing,
                            runSpacing: _panelSpacing,
                            children: [
                              SizedBox(
                                width: panelWidth,
                                child: _buildCameraPanel(context, state),
                              ),
                              SizedBox(
                                width: panelWidth,
                                child: _buildLocationPanel(context, state),
                              ),
                              SizedBox(
                                width: panelWidth,
                                child: _buildNetworkPanel(context, state),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraPanel(BuildContext context, E0State state) {
    final isProgress =
        state.cameraStatus == CameraDiagnosticStatus.initializing;

    return _DiagnosticPanel(
      semanticLabel: 'Painel de diagnóstico da câmera',
      title: 'Câmera traseira',
      icon: Icons.videocam_outlined,
      status: state.cameraMessage ?? _cameraStatusMessage(state.cameraStatus),
      statusIcon: _cameraStatusIcon(state.cameraStatus),
      isProgress: isProgress,
      action: OutlinedButton.icon(
        onPressed: widget.controller.canRetryCameraDiagnostic
            ? () => unawaited(widget.controller.retryCameraDiagnostic())
            : null,
        icon: const Icon(Icons.refresh),
        label: const Text('Tentar câmera novamente'),
      ),
      children: [
        if (state.cameraController case final controller?) ...[
          _CameraPreviewFrame(controller: controller),
          const SizedBox(height: 16),
        ],
        Text(
          'Preview básico, sem áudio e sem processamento de imagens.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildLocationPanel(BuildContext context, E0State state) {
    final isProgress = switch (state.locationStatus) {
      LocationDiagnosticStatus.checking ||
      LocationDiagnosticStatus.waitingForPosition =>
        true,
      _ => false,
    };

    return _DiagnosticPanel(
      semanticLabel: 'Painel de diagnóstico da localização',
      title: 'Localização precisa',
      icon: Icons.location_on_outlined,
      status:
          state.locationMessage ?? _locationStatusMessage(state.locationStatus),
      statusIcon: _locationStatusIcon(state.locationStatus),
      isProgress: isProgress,
      action: OutlinedButton.icon(
        onPressed: widget.controller.canRetryLocationDiagnostic
            ? () => unawaited(widget.controller.retryLocationDiagnostic())
            : null,
        icon: const Icon(Icons.my_location),
        label: const Text('Verificar localização novamente'),
      ),
      children: [
        _DiagnosticValue(
          label: 'Latitude',
          value: state.latitude == null
              ? 'Não disponível'
              : '${state.latitude!.toStringAsFixed(6)}°',
        ),
        _DiagnosticValue(
          label: 'Longitude',
          value: state.longitude == null
              ? 'Não disponível'
              : '${state.longitude!.toStringAsFixed(6)}°',
        ),
        _DiagnosticValue(
          label: 'Precisão reportada',
          value: state.accuracyMeters == null
              ? 'Não disponível'
              : '${state.accuracyMeters!.toStringAsFixed(1)} m',
        ),
        _DiagnosticValue(
          label: 'Velocidade',
          value: switch (state.speedMetersPerSecond) {
            final speed? when speed.isFinite && speed >= 0 =>
              '${speed.toStringAsFixed(1)} m/s',
            _ => 'Não fornecida',
          },
        ),
        const SizedBox(height: 4),
        Text(
          'Leitura diagnóstica em primeiro plano.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildNetworkPanel(BuildContext context, E0State state) {
    return _DiagnosticPanel(
      semanticLabel: 'Painel de diagnóstico da rede HTTPS',
      title: 'Rede e destino HTTPS',
      icon: Icons.public_outlined,
      status: state.httpsMessage ?? _httpsStatusMessage(state.httpsStatus),
      statusIcon: _httpsStatusIcon(state.httpsStatus),
      isProgress: state.isHttpsRequestInProgress,
      action: FilledButton.icon(
        onPressed: state.isHttpsRequestInProgress
            ? null
            : () => unawaited(widget.controller.runHttpsDiagnostic()),
        icon: const Icon(Icons.lock_outline),
        label: Text(
          state.isHttpsRequestInProgress
              ? 'Verificando destino...'
              : 'Executar diagnóstico HTTPS',
        ),
      ),
      children: [
        _DiagnosticValue(
          label: 'Código HTTP',
          value: state.httpStatusCode?.toString() ?? 'Não disponível',
        ),
        const SizedBox(height: 4),
        Text(
          'A verificação é manual, usa HTTPS e não envia corpo ou credenciais.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _cameraStatusMessage(CameraDiagnosticStatus status) {
    return switch (status) {
      CameraDiagnosticStatus.initial =>
        'Aguardando início do diagnóstico da câmera.',
      CameraDiagnosticStatus.initializing => 'Inicializando câmera traseira.',
      CameraDiagnosticStatus.available => 'Câmera traseira disponível.',
      CameraDiagnosticStatus.permissionDenied => 'Permissão de câmera negada.',
      CameraDiagnosticStatus.permissionDeniedPermanently =>
        'Permissão de câmera negada permanentemente. Habilite-a nas configurações do Android.',
      CameraDiagnosticStatus.noRearCamera =>
        'Nenhuma câmera traseira foi encontrada.',
      CameraDiagnosticStatus.cameraInUse =>
        'Câmera ocupada por outro aplicativo.',
      CameraDiagnosticStatus.initializationFailed =>
        'Falha ao inicializar a câmera traseira.',
      CameraDiagnosticStatus.paused =>
        'Câmera pausada enquanto o aplicativo está em segundo plano.',
    };
  }

  IconData _cameraStatusIcon(CameraDiagnosticStatus status) {
    return switch (status) {
      CameraDiagnosticStatus.available => Icons.check_circle_outline,
      CameraDiagnosticStatus.initial ||
      CameraDiagnosticStatus.initializing ||
      CameraDiagnosticStatus.paused =>
        Icons.info_outline,
      _ => Icons.error_outline,
    };
  }

  String _locationStatusMessage(LocationDiagnosticStatus status) {
    return switch (status) {
      LocationDiagnosticStatus.waitingForCamera =>
        'Aguardando conclusão da permissão de câmera.',
      LocationDiagnosticStatus.checking =>
        'Verificando serviço e permissão de localização.',
      LocationDiagnosticStatus.waitingForPosition => 'Aguardando posição.',
      LocationDiagnosticStatus.available => 'Localização precisa disponível.',
      LocationDiagnosticStatus.serviceDisabled =>
        'Serviço de localização desativado.',
      LocationDiagnosticStatus.permissionDenied =>
        'Permissão de localização negada.',
      LocationDiagnosticStatus.permissionDeniedPermanently =>
        'Permissão de localização negada permanentemente. Habilite-a nas configurações do Android.',
      LocationDiagnosticStatus.reducedAccuracy =>
        'Localização precisa não autorizada.',
      LocationDiagnosticStatus.positionUnavailable => 'Posição indisponível.',
      LocationDiagnosticStatus.paused =>
        'Localização pausada enquanto o aplicativo está em segundo plano.',
    };
  }

  IconData _locationStatusIcon(LocationDiagnosticStatus status) {
    return switch (status) {
      LocationDiagnosticStatus.available => Icons.check_circle_outline,
      LocationDiagnosticStatus.waitingForCamera ||
      LocationDiagnosticStatus.checking ||
      LocationDiagnosticStatus.waitingForPosition ||
      LocationDiagnosticStatus.paused =>
        Icons.info_outline,
      _ => Icons.error_outline,
    };
  }

  String _httpsStatusMessage(HttpsDiagnosticStatus status) {
    return switch (status) {
      HttpsDiagnosticStatus.notChecked =>
        'Diagnóstico HTTPS ainda não executado.',
      HttpsDiagnosticStatus.invalidConfiguration =>
        'Configuração HTTPS ausente ou inválida.',
      HttpsDiagnosticStatus.checking => 'Verificando destino HTTPS de teste.',
      HttpsDiagnosticStatus.reachable => 'Destino de teste acessível.',
      HttpsDiagnosticStatus.responded =>
        'Destino de teste respondeu com código HTTP.',
      HttpsDiagnosticStatus.incompleteResponse =>
        'Resposta excessiva ou incompleta.',
      HttpsDiagnosticStatus.timeout =>
        'Tempo limite do diagnóstico HTTPS excedido.',
      HttpsDiagnosticStatus.tlsFailure =>
        'Falha na validação TLS do destino de teste.',
      HttpsDiagnosticStatus.unavailable =>
        'Rede indisponível ou destino de teste inacessível.',
      HttpsDiagnosticStatus.lifecycleCancelled =>
        'Diagnóstico HTTPS cancelado pelo ciclo de vida.',
    };
  }

  IconData _httpsStatusIcon(HttpsDiagnosticStatus status) {
    return switch (status) {
      HttpsDiagnosticStatus.reachable => Icons.check_circle_outline,
      HttpsDiagnosticStatus.notChecked ||
      HttpsDiagnosticStatus.checking ||
      HttpsDiagnosticStatus.lifecycleCancelled =>
        Icons.info_outline,
      _ => Icons.error_outline,
    };
  }
}

class _ScopeNotice extends StatelessWidget {
  const _ScopeNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: 'Aviso de escopo do smoke test E0',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: colors.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Smoke test E0: nenhum dado de ocorrência é criado ou enviado.',
                  style: TextStyle(color: colors.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagnosticPanel extends StatelessWidget {
  const _DiagnosticPanel({
    required this.semanticLabel,
    required this.title,
    required this.icon,
    required this.status,
    required this.statusIcon,
    required this.isProgress,
    required this.children,
    required this.action,
  });

  final String semanticLabel;
  final String title;
  final IconData icon;
  final String status;
  final IconData statusIcon;
  final bool isProgress;
  final List<Widget> children;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: semanticLabel,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(status)),
                ],
              ),
              if (isProgress) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 16),
              ...children,
              const SizedBox(height: 20),
              action,
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraPreviewFrame extends StatelessWidget {
  const _CameraPreviewFrame({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = controller.value.aspectRatio;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspectRatio > 0 ? aspectRatio : 4 / 3,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _DiagnosticValue extends StatelessWidget {
  const _DiagnosticValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
