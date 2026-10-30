# Evidência da tarefa 72.5 — Gate de desenvolvimento E4: consolidação

Data: 2026-10-29. Esta tarefa só reúne as evidências 72.1–72.4. Nenhum código, dependência ou configuração foi alterado e nenhum teste novo foi executado.

## Evidências reunidas

| Tarefa | Arquivo | Conclusão |
|---|---|---|
| 72.1 | [task-72.1-e4-development-gate-suite.md](task-72.1-e4-development-gate-suite.md) | Formatação sem alterações (165 arquivos), `flutter analyze` sem problemas, suíte completa 818 aprovados e 0 falhas, 44 arquivos dirigidos aprovados. Uma falha intermitente de harness de teste foi corrigida em `http_occurrence_transport_test.dart`; `lib/` não foi tocado. |
| 72.2 | [task-72.2-e4-simulated-server-results.md](task-72.2-e4-simulated-server-results.md) | Matriz HTTP, autenticação exata, payload multipart, backoff, pausas, retomada, crash consistency e ausência de configuração sem socket aprovados contra fakes e servidor loopback. |
| 72.3 | [task-72.3-e4-debug-apk-and-manifests.md](task-72.3-e4-debug-apk-and-manifests.md) | APK debug `com.vitor.pavimenta_ai_mobile` 1.0.0 (1), 126325365 bytes, SHA-256 `434DB52C642F8324E12437C7CEFE6E5233E46193DAED435A4E5E4D21EA1CA669`. Toolchain: Flutter 3.24.3, Dart 3.5.3, Java 21.0.2, Gradle 8.7. Manifestos debug e release inspecionados; backup e transferência excluem fila, JPEGs e credencial. |
| 72.4 | [task-72.4-e4-secret-url-and-negative-scope-inspection.md](task-72.4-e4-secret-url-and-negative-scope-inspection.md) | Sem segredo nem URL real; HTTP release bloqueado; `localhost` limitado ao debug; sem E5, worker, modelo ou inferência. Testes dirigidos de arquitetura e sanitização: 28 aprovados. |

## Declaração do limite do gate

**A aprovação simulada não substitui o recebimento pelo back-end real.** Tudo acima foi obtido com fakes e servidor loopback controlado, sem aparelho, sem Analytics real e sem chave real de dispositivo. O gate de desenvolvimento E4 está concluído. O **Validation Gate E4 real não foi executado nem aprovado**.

## O que continua pendente

- 73.1: confirmar URL de teste acessível, API key válida de dispositivo de teste e meio de verificar o recebimento no back-end. Sem esses insumos, registrar exatamente `Validation Gate E4 não executado` e parar o ramo 73.2–74.8.
- 73.2–73.9: instalação do APK no Samsung Galaxy S25+, envio autenticado real, idempotência, falhas controláveis, remoção do JPEG após decisão definitiva e regressão E0–E3, sempre com evidência sanitizada.
- Nenhum cenário real pode ser classificado como aprovado por presunção.

## Resultado

**SUCESSO no escopo da 72.5.** Evidências do gate de desenvolvimento reunidas e limite declarado explicitamente. Nenhuma tarefa do grupo 73 foi iniciada.
