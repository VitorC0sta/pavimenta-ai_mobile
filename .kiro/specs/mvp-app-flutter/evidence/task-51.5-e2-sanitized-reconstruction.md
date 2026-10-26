# Evidência da tarefa 51.5 — Reconstrução E2 sanitizada

## Escopo

- Tarefa executada: **51.5 — Confirmar por evidência técnica sanitizada a reconstrução de UUID, horário, coordenadas, velocidade opcional, classe, confiança, SHA-256 e JPEG associados, sem imprimir ou expor os valores sensíveis proibidos.**
- Este registro não altera código, dependências, configuração Android, banco local, JPEG, dados de fila, tarefas adjacentes ou o Validation Gate E2.
- A evidência usa somente resultados booleanos/estruturais de testes de SQLite e filesystem em sandbox temporário, além da observação física já registrada na tarefa 51.4. Não foram despejados banco, registros, bytes, conteúdo JPEG, logs de aplicação, caminhos privados, nomes de imagem, UUIDs, horários, coordenadas, velocidades ou digests.

## Confirmação técnica automatizada

Foi executado em execução única:

```powershell
flutter test test/infrastructure/e2_queue_integration_test.dart test/infrastructure/persistent_occurrence_queue_test.dart
```

Resultado: **24 testes aprovados**; término com código `0`.

Os testes usam SQLite real e um sandbox de filesystem descartado ao fim de cada cenário. A confirmação cobre:

| Elemento reconstruído | Evidência sanitizada |
|---|---|
| UUID de idempotência | O round-trip após fechar e reabrir a fila compara a identidade persistida e reconstruída por igualdade, sem registrá-la. |
| Horário | O instante serializado de detecção é comparado por igualdade antes/depois da reabertura, sem emitir sua representação. |
| Coordenadas | Latitude e longitude canônicas são comparadas por igualdade após a reconstrução, sem expor números. |
| Velocidade opcional | O cenário cobre preservação de velocidade presente, inclusive zero, e a fila mantém a distinção entre valor nulo e zero; nenhum valor é exibido. |
| Classe e confiança | A classe e a confiança persistidas são comparadas por igualdade após a reconstrução, sem imprimir os conteúdos. |
| SHA-256 | O digest calculado por streaming do JPEG reconstruído é comparado ao metadado persistido; somente o resultado da comparação é observado. |
| JPEG associado | O fluxo abre o JPEG privado associado ao registro reconstruído, valida tamanho/digest por streaming e mantém a referência associada; bytes e nome não são expostos. |

A integração cobre explicitamente a persistência dos valores canônicos e do digest através do fechamento/reabertura. Os cenários de recuperação ainda validam que imagem ausente, nome inválido, tamanho divergente ou digest divergente degradam a fila de forma controlada e preservam a linha/artefato para diagnóstico, sem descarte silencioso. Assim, uma imagem corrompida não é afirmada como associação íntegra.

## Correlação com a observação física anterior

A evidência física da tarefa 51.4 já registrou reabertura em início frio com pendências recuperadas e contador de sessão reiniciado, sem registrar valores do conteúdo. Esta tarefa acrescenta a verificação técnica reproduzível de que os campos canônicos e a associação JPEG/digest dessas pendências são reconstruídos e validados como descrito acima.

A reinspeção física granular dos campos não foi repetida nesta execução: o ambiente atual não disponibiliza `adb` no `PATH`, portanto a verificação sanitizada de disponibilidade retornou zero dispositivos acessíveis. Nenhum dado do dispositivo foi lido, copiado ou despejado. Essa limitação não é apresentada como observação física nova.

## Controle de sanitização

- Não foi executado `adb pull`, `run-as`, leitura de banco, consulta SQL, `cat`, dump de logs ou leitura de bytes JPEG.
- O comando de disponibilidade do dispositivo emitiu somente contagem agregada, sem serial, modelo, paths ou dados da fila.
- Este documento não contém valores de UUID, horário, coordenadas, velocidade, digest, nomes de JPEG, caminhos privados, conteúdo de imagem, API key, URL ou credencial.
- Os testes operam com dados de fixture apenas no sandbox temporário e o removem ao final.

## Resultado

**Confirmação técnica sanitizada: aprovada.** A reconstrução preserva os campos canônicos solicitados e só considera o JPEG associado íntegro quando sua validação de metadados e SHA-256 por streaming é bem-sucedida. A ausência de ADB impede somente uma nova observação física granular nesta execução; não invalida nem substitui a evidência física de recuperação já registrada na tarefa 51.4.
