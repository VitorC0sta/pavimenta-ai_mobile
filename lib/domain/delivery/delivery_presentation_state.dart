/// Aggregate phase of the delivery as shown on the Operation screen.
enum DeliveryPhase {
  configurationRequired,
  idle,
  ready,
  sending,
  waitingBackoff,
  pausedAuthentication,
  pausedAccess,
  pausedUnexpected,
  pausedLocalFailure,
  cleaning,
  queueUnavailable,
}

/// Visual weight of a [DeliveryPhase].
enum DeliveryTone { neutral, active, attention }

/// Sanitized, immutable projection of the delivery for presentation.
///
/// The [message] is chosen from a closed set keyed by [phase]; callers cannot
/// inject free text. The state has no field for a destination, credential,
/// response, identifier, coordinate, occurrence time, sequence, file name,
/// path, or digest. [nextRetryAt] is the next scheduled attempt time and is
/// present only while waiting for a backoff.
final class DeliveryPresentationState {
  DeliveryPresentationState({
    required this.phase,
    this.canRetry = false,
    this.nextRetryAt,
  }) {
    if (nextRetryAt != null && phase != DeliveryPhase.waitingBackoff) {
      throw ArgumentError('A retry time is only valid while waiting.');
    }
    if (canRetry && phase == DeliveryPhase.waitingBackoff) {
      throw ArgumentError('A manual retry never shortens a backoff.');
    }
  }

  final DeliveryPhase phase;
  final bool canRetry;
  final DateTime? nextRetryAt;

  String get message => switch (phase) {
        DeliveryPhase.configurationRequired =>
          'Configure o destino e a chave para enviar pendências.',
        DeliveryPhase.idle => 'Nenhuma pendência para envio.',
        DeliveryPhase.ready => 'Pendências aguardando o próximo envio.',
        DeliveryPhase.sending => 'Enviando uma ocorrência…',
        DeliveryPhase.waitingBackoff =>
          'Falha temporária. Nova tentativa em breve.',
        DeliveryPhase.pausedAuthentication =>
          'Chave ausente, malformada ou inválida.',
        DeliveryPhase.pausedAccess => 'Dispositivo inativo.',
        DeliveryPhase.pausedUnexpected =>
          'Resposta inesperada da API. Revise a configuração ou tente '
              'novamente.',
        DeliveryPhase.pausedLocalFailure =>
          'Não foi possível preparar uma pendência para envio.',
        DeliveryPhase.cleaning => 'Concluindo remoção local…',
        DeliveryPhase.queueUnavailable => 'Fila local indisponível.',
      };

  /// Short closed label of the phase, shown as the panel status.
  String get statusLabel => switch (phase) {
        DeliveryPhase.configurationRequired => 'Configuração necessária',
        DeliveryPhase.idle => 'Ocioso',
        DeliveryPhase.ready => 'Pronto',
        DeliveryPhase.sending => 'Enviando',
        DeliveryPhase.waitingBackoff => 'Aguardando nova tentativa',
        DeliveryPhase.pausedAuthentication => 'Autenticação',
        DeliveryPhase.pausedAccess => 'Acesso',
        DeliveryPhase.pausedUnexpected => 'Resposta inesperada',
        DeliveryPhase.pausedLocalFailure => 'Falha local',
        DeliveryPhase.cleaning => 'Limpeza',
        DeliveryPhase.queueUnavailable => 'Fila indisponível',
      };

  /// How much attention the phase deserves; never the only cue, since the
  /// label and message always state the phase in text.
  DeliveryTone get tone => switch (phase) {
        DeliveryPhase.sending ||
        DeliveryPhase.cleaning ||
        DeliveryPhase.waitingBackoff =>
          DeliveryTone.active,
        DeliveryPhase.pausedAuthentication ||
        DeliveryPhase.pausedAccess ||
        DeliveryPhase.pausedUnexpected ||
        DeliveryPhase.pausedLocalFailure ||
        DeliveryPhase.queueUnavailable =>
          DeliveryTone.attention,
        DeliveryPhase.configurationRequired ||
        DeliveryPhase.idle ||
        DeliveryPhase.ready =>
          DeliveryTone.neutral,
      };

  @override
  bool operator ==(Object other) =>
      other is DeliveryPresentationState &&
      other.phase == phase &&
      other.canRetry == canRetry &&
      other.nextRetryAt == nextRetryAt;

  @override
  int get hashCode => Object.hash(phase, canRetry, nextRetryAt);

  @override
  String toString() =>
      'DeliveryPresentationState(${phase.name}, canRetry: $canRetry)';
}
