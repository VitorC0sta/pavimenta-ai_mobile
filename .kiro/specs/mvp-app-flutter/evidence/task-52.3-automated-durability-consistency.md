# Evidência da tarefa 52.3 — Consistência durável automatizada E2

## Escopo e limite

- Tarefa executada: **52.3 — Apresentar evidência automatizada de idempotência equivalente, conflito preservador, no-overwrite, single-writer, crash consistency, ownership/lease, rollback, remoção interna e recuperação idempotente.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- A evidência abaixo foi obtida exclusivamente com SQLite temporário real e filesystem sandbox, sem dispositivo, rede, URL, API key, imagem real ou dados persistentes do aplicativo.
- Nenhum código de produção, banco, JPEG, configuração Android, evidência histórica E0/E1, status de tarefa ou decisão do Validation Gate foi alterado.
- Este documento registra somente evidência automatizada; ele **não aprova** o Validation Gate E2, cuja aprovação ainda exige validação física aplicável e decisão explícita do usuário.

## Comando executado

```powershell
flutter test test/infrastructure/property_15_idempotent_uniqueness_test.dart test/infrastructure/property_17_exclusive_ownership_test.dart test/infrastructure/property_18_consistent_removal_test.dart test/infrastructure/property_19_idempotent_recovery_test.dart test/infrastructure/persistent_occurrence_queue_test.dart test/infrastructure/crash_consistent_queue_mutation_driver_test.dart test/infrastructure/fault_injected_queue_mutation_driver_test.dart test/infrastructure/queue_removal_protocol_test.dart test/infrastructure/durable_image_store_test.dart
```

Resultado do runner:

```text
All tests passed!
Exit Code: 0
```

A execução concluiu **57 testes**. As Properties 15, 17, 18 e 19 foram executadas com `glados`, cada uma configurada para **120 casos** (acima do mínimo de 100), usando entradas geradas e sandboxes descartados ao término.

## Matriz de garantias verificadas

| Garantia solicitada | Evidência automatizada | Resultado |
|---|---|---|
| Idempotência equivalente | `property_15_idempotent_uniqueness_test.dart` exerce persistências serializadas e concorrentes com a mesma `idempotencyKey` e conteúdo canônico equivalente. Exige exatamente um novo aceite, uma linha, um JPEG canônico e uma confirmação equivalente. | **Aprovado — 120 casos PBT.** |
| Conflito preservador | A mesma Property 15 cobre divergência de bytes JPEG e de metadados para a mesma chave. `persistent_occurrence_queue_test.dart` e `fault_injected_queue_mutation_driver_test.dart` confirmam resultado de conflito sem alterar a primeira linha. | **Aprovado.** |
| No-overwrite | Property 15 lê o JPEG retido, verifica SHA-256 e exige bytes da ocorrência canônica vencedora. `durable_image_store_test.dart` cobre colisões de staging/canônico e preserva os artefatos preexistentes. | **Aprovado.** |
| Single-writer | `persistent_occurrence_queue_test.dart` verifica bootstrap compartilhado, bloqueio de leituras/mutações até snapshot confirmado, serialização de persistência/remoção e fechamento somente após trabalho adquirido. | **Aprovado.** |
| Crash consistency | `crash_consistent_queue_mutation_driver_test.dart` confirma a ordem staging → publicação → linha confirmada/integridade → retirada da lease. `fault_injected_queue_mutation_driver_test.dart` injeta falhas em preflight, staging, cópia, flush, hash, destino, rename, inserção, commit, rechecagem e retirada da lease. | **Aprovado.** |
| Ownership/lease | `property_17_exclusive_ownership_test.dart` exige que aceite retire a lease exatamente uma vez e deixe apenas JPEG canônico pertencente à fila; rejeição não deixa JPEG E2 referenciado. | **Aprovado — 120 casos PBT.** |
| Rollback preservador | Os testes de falha injetada exigem ausência de aceite, de linha e de JPEG canônico após falhas anteriores ao commit, mantendo a lease ativa. Após commit já confirmado, uma falha de limpeza não desfaz o estado íntegro e recuperável. | **Aprovado.** |
| Remoção interna | `property_18_consistent_removal_test.dart` cobre remoção concluída e interrupções antes/depois do commit; `queue_removal_protocol_test.dart` cobre chave ausente, referência inválida, falhas, colisão, limpeza pós-commit e repetição idempotente. A operação continua sem chamador funcional de produção conforme a evidência 49.6. | **Aprovado — Property 18 com 120 casos PBT.** |
| Recuperação idempotente | `property_19_idempotent_recovery_test.dart` gera estados alcançáveis de staging, canônico órfão, marcador `.deleting`, confirmado, ausência e divergência de JPEG. Duas recuperações consecutivas precisam convergir para o mesmo estado, preservar degradação e não tocar arquivo externo. `durable_image_store_test.dart` reforça o limite ao namespace e a não remoção de artefatos desconhecidos. | **Aprovado — Property 19 com 120 casos PBT.** |

## Rastreabilidade ao design e aos requisitos

- **Property 15 — Unicidade idempotente:** RF-08.3, RF-08.4, RF-12.4, RNF-05.3.
- **Property 17 — Ownership exclusivo após aceite:** RF-11.8, RF-12.2, RF-12.10, RF-12.11, RNF-06.3, RNF-06.9, RNF-06.10.
- **Property 18 — Remoção consistente:** RF-12.9, RNF-05.4, RNF-06.2, RNF-06.10.
- **Property 19 — Recuperação idempotente:** RF-12.3, RF-12.8, RNF-05.3, RNF-06.3, RNF-06.11.
- Os testes adicionais de protocolo de commit, falhas injetadas, armazenamento e coordenador cobrem as invariantes operacionais das tarefas 39, 41, 42 e 44, sem acrescentar comportamento de E3–E5.

## Conclusão

A evidência automatizada da tarefa 52.3 está disponível e passou integralmente. Ela comprova, em SQLite e filesystem temporários, que a fila E2 preserva a primeira pendência diante de repetição/conflito, não sobrescreve artefatos canônicos, serializa operações, mantém transições recuperáveis diante de falhas, transfere ownership somente após confirmação, executa remoção interna consistente e converge de forma idempotente após recuperação.

Esta conclusão não substitui a validação física restante, não altera os itens 52.4–52.7 e não registra aprovação do gate E2.
