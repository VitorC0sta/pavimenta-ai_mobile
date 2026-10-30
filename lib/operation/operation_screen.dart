import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/delivery/delivery_presentation_state.dart';
import '../domain/location_snapshot.dart';
import '../domain/persistent_occurrence.dart';
import 'operation_controller.dart';
import 'operation_state.dart';
import 'operation_theme.dart';

typedef OperationPreviewBuilder<TPreview extends Object> = Widget Function(
  BuildContext context,
  TPreview preview,
);

typedef OpenDiagnostic = Future<void> Function(BuildContext context);
typedef OpenSettings = Future<void> Function(BuildContext context);

/// E1 operational presentation. Business decisions stay in [OperationController].
final class OperationScreen<TPreview extends Object> extends StatefulWidget {
  const OperationScreen({
    required this.controller,
    required this.previewBuilder,
    required this.onOpenDiagnostic,
    this.onOpenSettings,
    super.key,
  });

  final OperationController<TPreview> controller;
  final OperationPreviewBuilder<TPreview> previewBuilder;
  final OpenDiagnostic onOpenDiagnostic;
  final OpenSettings? onOpenSettings;

  @override
  State<OperationScreen<TPreview>> createState() =>
      _OperationScreenState<TPreview>();
}

final class _OperationScreenState<TPreview extends Object>
    extends State<OperationScreen<TPreview>> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    unawaited(
      widget.controller.startOperationalLifecycle(
        lifecycleState: lifecycle,
        isVisible: _isVisible(lifecycle),
        isForeground: _isForeground(lifecycle),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      widget.controller.updateOperationalContext(
        lifecycleState: state,
        isVisible: _isVisible(state),
        isForeground: _isForeground(state),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      widget.controller.updateOperationalContext(
        isVisible: false,
        isForeground: false,
      ),
    );
    super.dispose();
  }

  bool _isVisible(AppLifecycleState state) =>
      state != AppLifecycleState.hidden &&
      state != AppLifecycleState.paused &&
      state != AppLifecycleState.detached;

  bool _isForeground(AppLifecycleState state) =>
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Scaffold(
          key: const Key('operation-screen'),
          appBar: AppBar(
            title: const Text('Operação'),
            actions: [
              if (widget.onOpenSettings case final onOpenSettings?)
                IconButton(
                  key: const Key('open-settings-button'),
                  tooltip: 'Abrir configurações',
                  onPressed: () => unawaited(onOpenSettings(context)),
                  icon: const Icon(Icons.settings_outlined),
                ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                final preview = _PreviewPanel<TPreview>(
                  state: state,
                  previewBuilder: widget.previewBuilder,
                  onRetry: () {
                    unawaited(controller.retryCameraReadiness());
                  },
                  onOpenSettings: () {
                    unawaited(controller.openCameraPermissionSettings());
                  },
                );
                final details = _OperationDetails(
                  state: state,
                  onRegister: () {
                    unawaited(controller.registerManualPothole());
                  },
                  onRetryQueue: () {
                    unawaited(controller.retryQueueBootstrap());
                  },
                  onRetryDelivery: () {
                    unawaited(controller.retryDeliveryManually());
                  },
                  onRetryLocation: () {
                    unawaited(controller.retryLocationReadiness());
                  },
                  onOpenLocationSettings: () {
                    unawaited(controller.openLocationPermissionSettings());
                  },
                );

                return SingleChildScrollView(
                  key: const Key('operation-scroll-view'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              key: const Key('open-diagnostic-button'),
                              onPressed: () {
                                unawaited(widget.onOpenDiagnostic(context));
                              },
                              icon: const Icon(Icons.monitor_heart_outlined),
                              label: const Text('Abrir Diagnóstico'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _ManualModeBanner(),
                          const SizedBox(height: 16),
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 6, child: preview),
                                const SizedBox(width: 16),
                                Expanded(flex: 5, child: details),
                              ],
                            )
                          else ...[
                            preview,
                            const SizedBox(height: 16),
                            details,
                          ],
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
}

final class _ManualModeBanner extends StatelessWidget {
  const _ManualModeBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Modo de registro manual. Detecção automática indisponível.',
      child: Container(
        key: const Key('manual-mode-banner'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: OperationPalette.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.touch_app,
              color: OperationPalette.background,
              semanticLabel: 'Confirmação manual',
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Modo manual — YOLO ainda não configurado',
                style: TextStyle(
                  color: OperationPalette.background,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PreviewPanel<TPreview extends Object> extends StatelessWidget {
  const _PreviewPanel({
    required this.state,
    required this.previewBuilder,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final OperationState state;
  final OperationPreviewBuilder<TPreview> previewBuilder;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final preview = state.previewHandle;
    final hasPreview = state.cameraStatus == OperationCameraStatus.ready &&
        preview is TPreview;

    return _Panel(
      key: const Key('camera-panel'),
      title: 'Câmera traseira',
      status: _cameraStatusLabel(state.cameraStatus),
      statusKind: _cameraStatusKind(state.cameraStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: hasPreview
                ? 'Preview da câmera traseira disponível'
                : 'Preview da câmera traseira indisponível',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: OperationPalette.background,
                  child: hasPreview
                      ? previewBuilder(context, preview)
                      : const Center(
                          child: Icon(
                            Icons.videocam_off_outlined,
                            size: 48,
                            color: OperationPalette.foreground,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CameraReadinessContent(
            state: state,
            onRetry: onRetry,
            onOpenSettings: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

final class _CameraReadinessContent extends StatelessWidget {
  const _CameraReadinessContent({
    required this.state,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final OperationState state;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      key: const Key('camera-readiness-slot'),
      index: state.cameraStatus.index,
      sizing: StackFit.loose,
      children: [
        _ReadinessContent(
          message: state.cameraMessage,
          guidance: 'Aguarde a verificação da permissão e da câmera traseira.',
          isProgress: true,
        ),
        _ReadinessContent(message: state.cameraMessage),
        _ReadinessContent(
          message: state.cameraMessage,
          guidance:
              'Autorize a câmera quando o Android solicitar. Sem essa permissão, ocorrências não podem ser criadas.',
          action: OutlinedButton.icon(
            key: const Key('retry-camera-button'),
            onPressed: state.canRetryCameraReadiness ? onRetry : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar câmera novamente'),
          ),
        ),
        _ReadinessContent(
          message: state.cameraMessage,
          guidance:
              'A permissão não pode mais ser solicitada pelo aplicativo. Abra as configurações do Android e habilite Câmera.',
          action: OutlinedButton.icon(
            key: const Key('open-camera-settings-button'),
            onPressed: state.canOpenCameraSettings ? onOpenSettings : null,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Abrir configurações da câmera'),
          ),
        ),
        _ReadinessContent(
          message: state.cameraMessage,
          guidance:
              'O registro manual ficará indisponível até a câmera ser autorizada e ficar pronta.',
          action: OutlinedButton.icon(
            key: const Key('retry-camera-button'),
            onPressed: state.canRetryCameraReadiness ? onRetry : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Verificar câmera novamente'),
          ),
        ),
        _ReadinessContent(
          message: state.cameraMessage,
          guidance:
              'Retorne ao aplicativo para reativar a câmera com segurança.',
        ),
        _ReadinessContent(
          message: 'Habilite a câmera nas configurações do Android',
          guidance:
              'A permissão não pode mais ser solicitada pelo aplicativo. Abra as configurações do Android e habilite Câmera.',
          action: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Abrir configurações da câmera'),
          ),
        ),
      ],
    );
  }
}

final class _ReadinessContent extends StatelessWidget {
  const _ReadinessContent({
    required this.message,
    this.guidance,
    this.action,
    this.isProgress = false,
  });

  final String message;
  final String? guidance;
  final Widget? action;
  final bool isProgress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isProgress) ...[
              const Icon(Icons.schedule, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                message,
                key: const Key('readiness-message'),
                softWrap: true,
              ),
            ),
          ],
        ),
        if (guidance != null) ...[
          const SizedBox(height: 8),
          Text(guidance!, softWrap: true),
        ],
        if (action != null) ...[
          const SizedBox(height: 12),
          action!,
        ],
      ],
    );
  }
}

final class _OperationDetails extends StatelessWidget {
  const _OperationDetails({
    required this.state,
    required this.onRegister,
    required this.onRetryQueue,
    required this.onRetryDelivery,
    required this.onRetryLocation,
    required this.onOpenLocationSettings,
  });

  final OperationState state;
  final VoidCallback onRegister;
  final VoidCallback onRetryQueue;
  final VoidCallback onRetryDelivery;
  final VoidCallback onRetryLocation;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final lifecycleMessage = _lifecycleMessage(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LocationPanel(
          state: state,
          onRetry: onRetryLocation,
          onOpenSettings: onOpenLocationSettings,
        ),
        const SizedBox(height: 12),
        _SessionPanel(state: state),
        const SizedBox(height: 12),
        _QueuePanel(state: state, onRetry: onRetryQueue),
        const SizedBox(height: 12),
        _SendingConfigurationPanel(state: state, onRetry: onRetryDelivery),
        const SizedBox(height: 12),
        _ProcessingPanel(state: state),
        if (lifecycleMessage != null) ...[
          const SizedBox(height: 12),
          _Notice(
            key: const Key('lifecycle-message'),
            kind: OperationFeedbackKind.information,
            message: lifecycleMessage,
          ),
        ],
        if (state.feedback case final feedback?) ...[
          const SizedBox(height: 12),
          _Notice(
            key: const Key('operation-feedback'),
            kind: feedback.kind,
            message: feedback.message,
          ),
        ],
        const SizedBox(height: 16),
        Semantics(
          button: true,
          enabled: state.canRegister,
          excludeSemantics: true,
          label: state.isBusy
              ? 'Registro manual em processamento'
              : 'Registrar buraco por confirmação manual',
          hint: state.canRegister
              ? 'Inicia uma única captura manual'
              : 'Disponível quando câmera, GPS e aplicativo estiverem prontos',
          child: ElevatedButton.icon(
            key: const Key('register-pothole-button'),
            onPressed: state.canRegister ? onRegister : null,
            icon: state.isBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: OperationPalette.foreground,
                    ),
                  )
                : const Icon(Icons.add_a_photo_outlined),
            label: Text(
              state.isBusy ? 'Registrando…' : 'Registrar buraco',
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Confirmação manual de um buraco observado. Não é detecção automática.',
          key: Key('manual-confirmation-label'),
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(color: OperationPalette.foreground),
        ),
      ],
    );
  }
}

final class _LocationPanel extends StatelessWidget {
  const _LocationPanel({
    required this.state,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final OperationState state;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.locationSnapshot;
    final speedKmh = speedMetersPerSecondToKmh(
      snapshot?.speedMetersPerSecond,
    );

    return _Panel(
      key: const Key('location-panel'),
      title: 'GPS e localização',
      status: _locationStatusLabel(state.locationStatus),
      statusKind: _locationStatusKind(state.locationStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LocationReadinessContent(
            state: state,
            onRetry: onRetry,
            onOpenSettings: onOpenSettings,
          ),
          const SizedBox(height: 12),
          _ValueRow(
            label: 'Latitude',
            value:
                snapshot?.point.latitude.toStringAsFixed(6) ?? 'Não disponível',
          ),
          _ValueRow(
            label: 'Longitude',
            value: snapshot?.point.longitude.toStringAsFixed(6) ??
                'Não disponível',
          ),
          _ValueRow(
            label: 'Precisão',
            value: snapshot?.accuracyMeters == null
                ? 'Não disponível'
                : '${snapshot!.accuracyMeters!.toStringAsFixed(1)} m',
          ),
          _ValueRow(
            label: 'Velocidade',
            value: speedKmh == null
                ? 'Não fornecida'
                : '${speedKmh.toStringAsFixed(1)} km/h',
          ),
        ],
      ),
    );
  }
}

final class _LocationReadinessContent extends StatelessWidget {
  const _LocationReadinessContent({
    required this.state,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final OperationState state;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      key: const Key('location-readiness-slot'),
      index: state.locationStatus.index,
      sizing: StackFit.loose,
      children: [
        _ReadinessContent(
          message: state.locationMessage,
          guidance: 'Aguarde a verificação do GPS e da localização precisa.',
          isProgress: true,
        ),
        _ReadinessContent(message: state.locationMessage),
        _ReadinessContent(
          message: state.locationMessage,
          guidance:
              'Ative o serviço de localização do Android e verifique novamente.',
          action: OutlinedButton.icon(
            key: const Key('retry-location-button'),
            onPressed: state.canRetryLocationReadiness ? onRetry : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Verificar GPS novamente'),
          ),
        ),
        _ReadinessContent(
          message: state.locationMessage,
          guidance:
              'Autorize a localização precisa quando o Android solicitar. Sem ela, ocorrências não podem ser criadas.',
          action: OutlinedButton.icon(
            key: const Key('retry-location-button'),
            onPressed: state.canRetryLocationReadiness ? onRetry : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar GPS novamente'),
          ),
        ),
        _ReadinessContent(
          message: state.locationMessage,
          guidance:
              'A permissão não pode mais ser solicitada pelo aplicativo. Abra as configurações do Android e habilite Localização precisa.',
          action: OutlinedButton.icon(
            key: const Key('open-location-settings-button'),
            onPressed: state.canOpenLocationSettings ? onOpenSettings : null,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Abrir configurações do GPS'),
          ),
        ),
        _ReadinessContent(
          message: state.locationMessage,
          guidance:
              'Selecione localização precisa no Android e verifique novamente.',
          action: OutlinedButton.icon(
            key: const Key('retry-location-button'),
            onPressed: state.canRetryLocationReadiness ? onRetry : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Verificar GPS novamente'),
          ),
        ),
        _ReadinessContent(
          message: state.locationMessage,
          guidance: 'Aguarde uma posição válida e verifique o GPS novamente.',
          action: OutlinedButton.icon(
            key: const Key('retry-location-button'),
            onPressed: state.canRetryLocationReadiness ? onRetry : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Verificar GPS novamente'),
          ),
        ),
        _ReadinessContent(
          message: state.locationMessage,
          guidance:
              'Retorne ao aplicativo para reativar a localização com segurança.',
        ),
        _ReadinessContent(
          message: 'Habilite a localização nas configurações do Android',
          guidance:
              'A permissão não pode mais ser solicitada pelo aplicativo. Abra as configurações do Android e habilite Localização precisa.',
          action: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Abrir configurações do GPS'),
          ),
        ),
      ],
    );
  }
}

final class _SessionPanel extends StatelessWidget {
  const _SessionPanel({required this.state});

  final OperationState state;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      key: const Key('session-panel'),
      title: 'Sessão atual',
      status: state.sessionOccurrenceCount == 1
          ? '1 registro criado'
          : '${state.sessionOccurrenceCount} registros criados',
      statusKind: state.sessionOccurrenceCount > 0
          ? _VisualStatus.success
          : _VisualStatus.neutral,
      child: Row(
        children: [
          const Icon(
            Icons.format_list_numbered,
            color: OperationPalette.foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Buracos registrados: ${state.sessionOccurrenceCount}',
              key: const Key('session-counter'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

final class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.state, required this.onRetry});

  final OperationState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      key: const Key('queue-panel'),
      title: 'Fila local',
      status: _queueStatusLabel(state.queueHealth),
      statusKind: _queueStatusKind(state.queueHealth),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label:
            'Pendências: ${state.pendingCount}. ${_queueStatusLabel(state.queueHealth)}. ${state.queueMessage}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pendências: ${state.pendingCount}',
              key: const Key('pending-count'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              state.queueMessage,
              key: const Key('queue-message'),
              softWrap: true,
            ),
            if (state.queueHealth == QueueHealth.unavailable) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('retry-queue-button'),
                onPressed: state.canRetryQueueBootstrap ? onRetry : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar fila novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Envio" panel (design E4.11).
///
/// With a composed delivery it shows only the closed message of the aggregate
/// phase and, when a new evaluation can be requested, the retry action. It
/// never renders a destination, credential, response, identifier, coordinate,
/// occurrence time, sequence, file name, path or digest. Without a composed
/// delivery it falls back to the sanitized configuration readiness.
final class _SendingConfigurationPanel extends StatelessWidget {
  const _SendingConfigurationPanel({
    required this.state,
    required this.onRetry,
  });

  final OperationState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final presentation = state.deliveryPresentation;
    if (presentation != null) {
      return _DeliveryPanel(
        state: state,
        presentation: presentation,
        onRetry: onRetry,
      );
    }
    final isReady = state.sendingConfigurationStatus ==
        OperationSendingConfigurationStatus.ready;
    final label = isReady
        ? 'Configuração para envio pronta'
        : 'Configuração para envio pendente';
    final description = isReady
        ? 'Destino e credencial estão configurados para uso futuro.'
        : 'Configure destino e credencial para habilitar o envio futuro.';

    return _Panel(
      key: const Key('sending-configuration-panel'),
      title: 'Envio',
      status: isReady ? 'Pronta' : 'Pendente',
      statusKind: isReady ? _VisualStatus.success : _VisualStatus.neutral,
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: '$label. $description',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              key: const Key('sending-configuration-label'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              key: const Key('sending-configuration-message'),
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}

final class _DeliveryPanel extends StatelessWidget {
  const _DeliveryPanel({
    required this.state,
    required this.presentation,
    required this.onRetry,
  });

  final OperationState state;
  final DeliveryPresentationState presentation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final status = presentation.statusLabel;
    final message = presentation.message;
    return _Panel(
      key: const Key('delivery-panel'),
      title: 'Envio',
      status: status,
      statusKind: _deliveryStatusKind(presentation.tone),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            excludeSemantics: true,
            liveRegion: true,
            label: 'Envio: $status. $message',
            child: Text(
              message,
              key: const Key('delivery-message'),
              softWrap: true,
            ),
          ),
          if (state.canRetryDelivery) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('retry-delivery-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar envio novamente'),
            ),
          ],
        ],
      ),
    );
  }
}

_VisualStatus _deliveryStatusKind(DeliveryTone tone) => switch (tone) {
      DeliveryTone.neutral => _VisualStatus.neutral,
      DeliveryTone.active => _VisualStatus.active,
      DeliveryTone.attention => _VisualStatus.error,
    };

final class _ProcessingPanel extends StatelessWidget {
  const _ProcessingPanel({required this.state});

  final OperationState state;

  @override
  Widget build(BuildContext context) {
    final isPersisting = state.isBusy && state.isPersisting;
    final label = isPersisting
        ? 'Salvando na fila local'
        : _processingLabel(state.processingStatus);
    return _Panel(
      key: const Key('processing-panel'),
      title: 'Processamento',
      status: label,
      statusKind: isPersisting
          ? _VisualStatus.active
          : _processingStatusKind(state.processingStatus),
      child: Row(
        children: [
          if (state.isBusy) ...[
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ] else ...[
            Icon(
              _processingIcon(state.processingStatus),
              color: _statusColor(
                _processingStatusKind(state.processingStatus),
              ),
              semanticLabel: label,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              isPersisting
                  ? 'Persistindo a ocorrência e a imagem na fila local.'
                  : state.isBusy
                      ? 'Aguarde a conclusão do registro atual.'
                      : _processingDescription(state.processingStatus),
              key: const Key('processing-message'),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

enum _VisualStatus { neutral, active, success, error }

final class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.status,
    required this.statusKind,
    required this.child,
    super.key,
  });

  final String title;
  final String status;
  final _VisualStatus statusKind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                _StatusBadge(label: status, kind: statusKind),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.kind});

  final String label;
  final _VisualStatus kind;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(kind);
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: OperationPalette.background,
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_statusIcon(kind), size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: const TextStyle(
                  color: OperationPalette.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _Notice extends StatelessWidget {
  const _Notice({required this.kind, required this.message, super.key});

  final OperationFeedbackKind kind;
  final String message;

  @override
  Widget build(BuildContext context) {
    final visualStatus = switch (kind) {
      OperationFeedbackKind.success => _VisualStatus.success,
      OperationFeedbackKind.error => _VisualStatus.error,
      OperationFeedbackKind.cooldown => _VisualStatus.active,
      OperationFeedbackKind.information => _VisualStatus.neutral,
    };
    final prefix = switch (kind) {
      OperationFeedbackKind.success => 'Sucesso',
      OperationFeedbackKind.error => 'Erro',
      OperationFeedbackKind.cooldown => 'Cooldown',
      OperationFeedbackKind.information => 'Informação',
    };
    final color = _statusColor(visualStatus);

    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: '$prefix: $message',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: OperationPalette.panel,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _statusIcon(visualStatus),
              color: color,
              semanticLabel: prefix,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$prefix: $message',
                softWrap: true,
                style: const TextStyle(color: OperationPalette.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value, softWrap: true)),
        ],
      ),
    );
  }
}

String _queueStatusLabel(QueueHealth health) => switch (health) {
      QueueHealth.initializing => 'Inicializando',
      QueueHealth.ready => 'Pronta',
      QueueHealth.degraded => 'Degradada',
      QueueHealth.unavailable => 'Indisponível',
    };

_VisualStatus _queueStatusKind(QueueHealth health) => switch (health) {
      QueueHealth.initializing => _VisualStatus.active,
      QueueHealth.ready => _VisualStatus.success,
      QueueHealth.degraded || QueueHealth.unavailable => _VisualStatus.error,
    };

String _cameraStatusLabel(OperationCameraStatus status) => switch (status) {
      OperationCameraStatus.initializing => 'Inicializando',
      OperationCameraStatus.ready => 'Pronta',
      OperationCameraStatus.permissionDenied => 'Permissão negada',
      OperationCameraStatus.permissionDeniedPermanently =>
        'Permissão bloqueada',
      OperationCameraStatus.unavailable => 'Indisponível',
      OperationCameraStatus.paused => 'Pausada',
    };

_VisualStatus _cameraStatusKind(OperationCameraStatus status) =>
    switch (status) {
      OperationCameraStatus.initializing => _VisualStatus.active,
      OperationCameraStatus.ready => _VisualStatus.success,
      OperationCameraStatus.permissionDenied ||
      OperationCameraStatus.permissionDeniedPermanently ||
      OperationCameraStatus.unavailable =>
        _VisualStatus.error,
      OperationCameraStatus.paused => _VisualStatus.neutral,
    };

String _locationStatusLabel(OperationLocationStatus status) => switch (status) {
      OperationLocationStatus.initializing => 'Inicializando',
      OperationLocationStatus.ready => 'GPS pronto',
      OperationLocationStatus.serviceDisabled => 'Serviço desativado',
      OperationLocationStatus.permissionDenied => 'Permissão negada',
      OperationLocationStatus.permissionDeniedPermanently =>
        'Permissão bloqueada',
      OperationLocationStatus.reducedAccuracy => 'Precisão reduzida',
      OperationLocationStatus.unavailable => 'Posição indisponível',
      OperationLocationStatus.paused => 'GPS pausado',
    };

_VisualStatus _locationStatusKind(OperationLocationStatus status) =>
    switch (status) {
      OperationLocationStatus.initializing => _VisualStatus.active,
      OperationLocationStatus.ready => _VisualStatus.success,
      OperationLocationStatus.serviceDisabled ||
      OperationLocationStatus.permissionDenied ||
      OperationLocationStatus.permissionDeniedPermanently ||
      OperationLocationStatus.reducedAccuracy ||
      OperationLocationStatus.unavailable =>
        _VisualStatus.error,
      OperationLocationStatus.paused => _VisualStatus.neutral,
    };

String _processingLabel(OperationProcessingStatus status) => switch (status) {
      OperationProcessingStatus.idle => 'Pronto',
      OperationProcessingStatus.validating => 'Validando',
      OperationProcessingStatus.processing => 'Processando',
      OperationProcessingStatus.succeeded => 'Concluído',
      OperationProcessingStatus.blockedByCooldown => 'Ignorado por cooldown',
      OperationProcessingStatus.cancelled => 'Cancelado',
      OperationProcessingStatus.failed => 'Falha controlada',
    };

String _processingDescription(OperationProcessingStatus status) =>
    switch (status) {
      OperationProcessingStatus.idle => 'Nenhum registro em processamento.',
      OperationProcessingStatus.validating => 'Validando o candidato manual.',
      OperationProcessingStatus.processing =>
        'Capturando e preparando a imagem privada.',
      OperationProcessingStatus.succeeded =>
        'A ocorrência foi salva na fila local.',
      OperationProcessingStatus.blockedByCooldown =>
        'Nenhuma imagem, UUID ou ocorrência foi criada.',
      OperationProcessingStatus.cancelled =>
        'O registro foi encerrado com limpeza controlada.',
      OperationProcessingStatus.failed =>
        'O registro terminou sem criar uma ocorrência parcial.',
    };

_VisualStatus _processingStatusKind(OperationProcessingStatus status) =>
    switch (status) {
      OperationProcessingStatus.idle ||
      OperationProcessingStatus.cancelled =>
        _VisualStatus.neutral,
      OperationProcessingStatus.validating ||
      OperationProcessingStatus.processing ||
      OperationProcessingStatus.blockedByCooldown =>
        _VisualStatus.active,
      OperationProcessingStatus.succeeded => _VisualStatus.success,
      OperationProcessingStatus.failed => _VisualStatus.error,
    };

IconData _processingIcon(OperationProcessingStatus status) => switch (status) {
      OperationProcessingStatus.idle => Icons.hourglass_empty,
      OperationProcessingStatus.validating => Icons.fact_check_outlined,
      OperationProcessingStatus.processing => Icons.image_outlined,
      OperationProcessingStatus.succeeded => Icons.check_circle_outline,
      OperationProcessingStatus.blockedByCooldown => Icons.timer_outlined,
      OperationProcessingStatus.cancelled => Icons.cancel_outlined,
      OperationProcessingStatus.failed => Icons.error_outline,
    };

String? _lifecycleMessage(OperationState state) {
  if (state.isDisposed) {
    return 'Operação encerrada; novos registros estão bloqueados.';
  }
  if (!state.isCurrentRoute || !state.isVisible) {
    return 'Operação fora da rota atual; novos registros estão bloqueados.';
  }
  if (state.lifecycleState != AppLifecycleState.resumed) {
    return 'Aplicativo fora do estado ativo; retorne para registrar com segurança.';
  }
  return null;
}

Color _statusColor(_VisualStatus kind) => switch (kind) {
      _VisualStatus.neutral => OperationPalette.foreground,
      _VisualStatus.active => OperationPalette.accent,
      _VisualStatus.success => OperationPalette.success,
      _VisualStatus.error => OperationPalette.error,
    };

IconData _statusIcon(_VisualStatus kind) => switch (kind) {
      _VisualStatus.neutral => Icons.info_outline,
      _VisualStatus.active => Icons.schedule,
      _VisualStatus.success => Icons.check_circle_outline,
      _VisualStatus.error => Icons.error_outline,
    };
