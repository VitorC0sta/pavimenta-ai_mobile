# Evidência da tarefa 52.2 — Persistência, recuperação, integridade e contadores E2

## Escopo e limite

- Tarefa executada: **52.2 — Apresentar evidência de persistência antes do sucesso, recuperação após fechamento/force-stop, reconstrução íntegra com SHA-256, pendências corretas e contador da sessão separado.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Esta evidência consolida observações físicas já registradas nas tarefas 51.3–51.5 e a validação automatizada direcionada executada nesta tarefa. Nenhum código, banco, JPEG, configuração Android, estado do dispositivo ou evidência histórica E0/E1 foi alterado.
- Este registro **não aprova o Validation Gate E2**, não reclassifica a matriz da tarefa 51.9 e não executa as tarefas 52.3–52.7.

## Matriz de evidências

| Critério | Evidência | Resultado e limite |
|---|---|---|
| Persistência confirmada antes do sucesso | Implementação e testes dirigidos: o aceite durável precede `CandidateCreated`, `cooldown.commit`, incremento da sessão e feedback final. A observação física da 51.3 confirmou o feedback de fila local e os artefatos privados após o aceite. | **Confirmado tecnicamente.** A ordem temporal transitória não foi capturável na UI física (a primeira amostra, 50 ms após o toque, já mostrava sucesso); portanto, este documento não a apresenta como observação física direta. |
| Recuperação após fechamento/force-stop | Evidência física [51.4](task-51.4-e2-lifecycle-recovery-cooldown.md): após `am force-stop` e início frio, a UI exibiu fila pronta e `Pendências: 5`. | **Aprovado fisicamente.** A fila persistente não foi zerada na reabertura. |
| Reconstrução íntegra com SHA-256 | Evidência sanitizada [51.5](task-51.5-e2-sanitized-reconstruction.md) e integração SQLite/filesystem: reconstrução compara identidade, horário, coordenadas, velocidade opcional, classe, confiança, JPEG associado e digest SHA-256 por streaming sem expor os dados. | **Confirmado tecnicamente.** A reabertura física de pendências consta em 51.4; a inspeção granular no dispositivo não foi repetida e não é alegada aqui. |
| Pendências corretas | Evidência física [51.3](task-51.3-e2-local-save-cooldown.md): a sequência exibiu `Pendências: 4` e quatro JPEGs privados E2; [51.4](task-51.4-e2-lifecycle-recovery-cooldown.md) confirmou `Pendências: 5` após force-stop. | **Aprovado fisicamente.** A contagem é derivada de linhas confirmadas da fila, não de incremento otimista da interface. |
| Contador da sessão separado | Evidência física [51.3](task-51.3-e2-local-save-cooldown.md): na execução que criou pendências, a UI exibiu `4 registros criados` e `Pendências: 4`. Após início frio, [51.4](task-51.4-e2-lifecycle-recovery-cooldown.md) exibiu simultaneamente `0 registros criados` e `Pendências: 5`. | **Aprovado fisicamente.** Recuperação não incrementou o contador da nova sessão nem apagou a fila. |

## Validação automatizada atual

Comando executado em execução única:

```powershell
flutter test test/operation/operation_queue_screen_test.dart test/operation/operation_controller_test.dart test/infrastructure/e2_queue_integration_test.dart test/infrastructure/persistent_occurrence_queue_test.dart
```

Resultado: **44 testes aprovados**, término com código `0`.

A execução inclui, entre outros, cenários para:

- feedback de salvamento local somente após aceite, com a mensagem que descreve a fila local;
- pendências agregadas separadamente do contador da sessão;
- persistência de valores canônicos e digest do JPEG por abertura e reabertura de SQLite real em sandbox temporário;
- preservação de uma linha confirmada e reconstrução íntegra após reabertura;
- degradação controlada, sem descarte silencioso, quando imagem ou digest divergem;
- recuperação de artefatos de interrupção reconhecidos sem perder pendências confirmadas.

Os testes usam somente SQLite e filesystem temporários e removem o sandbox ao final. Este documento não contém UUIDs, horários, coordenadas, velocidades, digests, paths privados, nomes de imagem, bytes JPEG, URLs, chaves ou credenciais.

## Conclusão

A tarefa 52.2 possui evidência rastreável de: persistência durável como pré-condição técnica do sucesso, recuperação física após force-stop, reconstrução técnica com integridade SHA-256, contagem persistente correta e reinicialização independente do contador da sessão. A limitação da observação física direta da ordem transitória e da reconstrução granular permanece declarada conforme a matriz da tarefa 51.9; não foi ocultada nem substituída por alegação física.
