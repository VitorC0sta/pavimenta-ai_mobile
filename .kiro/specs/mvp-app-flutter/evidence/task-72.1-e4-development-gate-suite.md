# Evidência da tarefa 72.1 — Formatação, análise, suíte completa e testes dirigidos E4

Data: 2026-10-29. Ambiente: Flutter 3.24.3 (stable), Windows/PowerShell. Dados: apenas valores fictícios.

## Resultados

| Verificação | Comando | Resultado |
|---|---|---|
| Formatação | `dart format --output=none --set-exit-if-changed lib test` | 165 arquivos, 0 alterações, exit 0 |
| Análise | `flutter analyze` | `No issues found!`, exit 0 |
| Suíte completa (1ª execução) | `flutter test` | 817 aprovados, **1 falha intermitente** |
| Suíte completa (após correção) | `flutter test` | **818 aprovados, 0 falhas**, exit 0 |
| Testes dirigidos | `flutter test <arquivo>` por arquivo (44 arquivos) | todos aprovados, 0 falhas |

## Falha encontrada e correção

- Teste: `test/infrastructure/delivery/http_occurrence_transport_test.dart`, caso `task 67.5 ... cancelling before headers yields TransportCancelled, repeatedly`.
- Sintoma: falha em 2 de 5 execuções isoladas (`HttpException: Connection closed while receiving data` não tratada).
- Causa: defeito de harness. O handler do servidor de teste (`request.drain<void>()` sem tratamento) recebia o erro quando o cliente abortava a conexão ou quando `server.close(force: true)` do `tearDown` a derrubava. O comportamento de produção (`TransportCancelled`) estava correto.
- Correção (somente teste E4): o tipo de `onRequest` passou a `FutureOr<void> Function(HttpRequest)` e o `listen` envolve o handler em `Future.sync(...).catchError(...)`, com `unawaited`. Nenhum código em `lib/` foi alterado.
- Verificação: 12/12 execuções isoladas aprovadas; análise do arquivo sem problemas; suíte completa aprovada.

## Testes dirigidos por categoria (aprovados / falhas)

**Políticas**
- `domain/delivery/delivery_backoff_policy_test.dart` 7/0
- `domain/delivery/http_delivery_decision_policy_test.dart` 6/0
- `domain/delivery/delivery_models_test.dart` 9/0
- `domain/delivery/delivery_sanitization_test.dart` 8/0

**Migração e fila**
- `infrastructure/delivery/queue_schema_v2_acceptance_test.dart` 11/0
- `infrastructure/delivery/persistent_delivery_queue_test.dart` 41/0
- `infrastructure/delivery/e4_delivery_crash_consistency_test.dart` 28/0
- `infrastructure/delivery/e4_delivery_restart_test.dart` 16/0
- `infrastructure/delivery/process_delivery_timer_test.dart` 5/0

**Configuração**
- `application/delivery/delivery_configuration_change_service_test.dart` 29/0
- `application/delivery/exclusive_delivery_configuration_snapshot_test.dart` 17/0
- `infrastructure/delivery/delivery_configuration_consistency_test.dart` 39/0
- `infrastructure/operational_configuration_store_test.dart` 8/0

**Multipart**
- `canonical_multipart_payload_test.dart` 12/0
- `multipart_retry_stability_test.dart` 3/0
- `occurrence_multipart_mapper_test.dart` 4/0
- `occurrence_multipart_preparer_test.dart` 8/0
- `streaming_multipart_encoder_test.dart` 14/0

**Transporte**
- `http_occurrence_transport_test.dart` 5/0
- `occurrence_http_request_builder_test.dart` 23/0
- `occurrence_transport_failure_classifier_test.dart` 16/0
- `occurrence_transport_wire_test.dart` 26/0
- `bounded_occurrence_exchange_test.dart` 8/0
- `streamed_http_client_adapter_test.dart` 6/0

**Coordenador e integração**
- `application/delivery/occurrence_delivery_coordinator_test.dart` 104/0
- `infrastructure/delivery/e4_delivery_integration_test.dart` 25/0
- `infrastructure/delivery/e4_delivery_sanitization_inspection_test.dart` 11/0
- `infrastructure/sanitized_delivery_technical_logger_test.dart` 10/0
- `support/e4/e4_fakes_test.dart` 17/0

**Widgets e lifecycle (Operação)**
- `operation/operation_controller_test.dart` 17/0
- `operation/operation_delivery_composition_test.dart` 10/0
- `operation/operation_screen_test.dart` 15/0
- `operation/operation_queue_screen_test.dart` 5/0
- `operation/operation_queue_bootstrap_test.dart` 6/0
- `operation/operation_diagnostic_navigation_test.dart` 7/0
- `operation/operation_permission_denial_test.dart` 6/0
- `operation/operation_state_test.dart` 2/0

**Arquitetura**
- `architecture/e4_delivery_boundaries_test.dart` 16/0
- `architecture/e1_contracts_test.dart` 3/0, `e2_contract_boundaries_test.dart` 6/0, `e2_dependency_policy_test.dart` 3/0
- `architecture/e3_android_network_policy_test.dart` 3/0, `e3_configuration_boundaries_test.dart` 1/0

## Limite

Resultado de gate de desenvolvimento com fakes e servidor loopback. Não comprova recebimento pelo back-end real.
