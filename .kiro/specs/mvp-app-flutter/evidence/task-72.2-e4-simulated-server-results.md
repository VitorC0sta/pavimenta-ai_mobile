# Evidência da tarefa 72.2 — Servidor simulado/controlado E4 (resultados sanitizados)

Data: 2026-10-29. Fonte: execução dos testes abaixo (mesma sessão da 72.1). Servidor: `HttpServer` em loopback com porta efêmera, mais cliente HTTP roteirizado para os cenários com fila e coordenador reais. Todos os valores são fictícios; nenhuma URL, chave, UUID, coordenada, imagem ou body real é registrado aqui.

## Matriz de resultados

| Área | Cobertura comprovada | Arquivo de teste (aprovados/falhas) |
|---|---|---|
| Matriz HTTP no transporte | `POST` único em `{BASE_URL}/api/v1/occurrences`; status 200, 201, 202, 204, 400, 401, 403, 404, 408, 409, 413, 415, 422, 429, 500, 502, 503, 504 devolvidos verbatim; redirects 301/302/303/307/308 nunca seguidos, nem para outra origem | `occurrence_transport_wire_test.dart` 26/0 |
| Decisão por status | 200/201 sucesso; 400/409/413/415 descarte; 401/403 pausa; 5xx e demais recuperáveis; 3xx tratado como resposta inesperada | `http_delivery_decision_policy_test.dart` 6/0; `e4_delivery_integration_test.dart` 25/0 |
| Autenticação exata | Header `Authorization: ApiKey <valor fictício>`; ausência de `Bearer`, `X-API-Key`, `Cookie`, `Proxy-Authorization`; cookie do servidor nunca reenviado; credencial inválida não abre socket | `occurrence_transport_wire_test.dart`, `occurrence_http_request_builder_test.dart` 23/0 |
| Payload | multipart com `idempotencyKey`, `latitude`, `longitude`, `confidence`, `defectClass`, `detectedAt`, `image` (+ `speedKmh` somente quando conhecido; zero é enviado); filename genérico, MIME `image/jpeg`; `Content-Length` igual ao corpo, sem `Transfer-Encoding`; bytes do JPEG idênticos; sem campos proibidos; mesma chave e dados em retries | `occurrence_transport_wire_test.dart`, `canonical_multipart_payload_test.dart` 12/0, `multipart_retry_stability_test.dart` 3/0, `streaming_multipart_encoder_test.dart` 14/0 |
| Backoff | Falha de rede e timeout mantêm o item na cabeça, progressão 5 s / 15 s, teto de 15 min, reenvio com mesma chave e imagem; backoff persistido e rearmado após reabertura; relógio regressivo persistido | `delivery_backoff_policy_test.dart` 7/0, `e4_delivery_integration_test.dart`, `e4_delivery_restart_test.dart` 16/0 |
| Timeouts e cancelamento | Servidor sem headers → `TransportTimeout`; upload travado → timeout; corpo grande ou lento após headers preserva o status; cancelamento antes dos headers → `TransportCancelled`; cancelamento posterior preserva o status; conexão recusada ou derrubada → falha de rede; uma tentativa por vez | `occurrence_transport_wire_test.dart`, `http_occurrence_transport_test.dart` 5/0, `bounded_occurrence_exchange_test.dart` 8/0 |
| Pausas | 401 pausa persistente, fila preservada, retomada com credencial corrigida sem misturar a antiga; 403 pausa por acesso e retry manual retoma; JPEG ausente pausa por falha local sem socket; secure storage ilegível pausa e só o retry manual limpa | `e4_delivery_integration_test.dart` (grupo "pauses", "configuration") |
| Retomada | Saída do foreground cancela sem registrar falha e a retomada reutiliza a chave; mudança de configuração durante upload cancela e reenvia só com o novo par; retorno de Configurações retoma somente quando relevante | `e4_delivery_integration_test.dart`, `occurrence_delivery_coordinator_test.dart` 104/0 |
| Crash consistency | Crash antes/depois da decisão durável e da remoção; decisão definitiva concluída localmente sem HTTP após reabertura; falha de remoção não repete HTTP; sem estado órfão (FK/cascade); contagem cai só após remoção confirmada; âncora de cooldown preservada | `e4_delivery_crash_consistency_test.dart` 28/0, `e4_delivery_restart_test.dart` 16/0, `persistent_delivery_queue_test.dart` 41/0 |
| Ausência de configuração sem socket | URL ou chave ausente nunca chega ao transporte; remoção posterior da chave não abre conexão; credencial malformada para antes da imagem e do socket; destino/credencial inválidos nunca chegam ao cliente; ocorrência permanece na fila | `e4_delivery_integration_test.dart` (grupo "configuration"), `occurrence_transport_wire_test.dart` ("invalid destination or credential never reaches the client") |
| Sanitização | Logs e estado renderizado emitem apenas categorias técnicas; sem chave, header, URL, body, multipart, imagem, UUID, coordenadas, horário, filename, path, digest ou exceção bruta | `e4_delivery_sanitization_inspection_test.dart` 11/0, `sanitized_delivery_technical_logger_test.dart` 10/0 |

## Resultado

Todos os arquivos acima aprovados (0 falhas); suíte completa 818/0. Ver `task-72.1-e4-development-gate-suite.md`.

## Limite explícito

Os resultados vêm de fakes e de servidor loopback controlado. **Aprovação simulada não substitui o recebimento pelo back-end real**; o Validation Gate real E4 permanece pendente das tarefas 73–74.
