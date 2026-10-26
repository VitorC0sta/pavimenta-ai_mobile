# Evidência da tarefa 51.3 — Salvamento local, contadores e cooldown E2

## Escopo e preservação

- Subtarefa executada: **51.3 — Registrar ocorrências válidas respeitando cooldown e confirmar salvamento local antes do sucesso, contador da sessão e aumento derivado de pendências.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Dispositivo físico acessado: Samsung Galaxy S25+ (`SM-S936B`), Android 17 / API 37, reconhecido pelo Flutter e pelo ADB com serial já registrado nas evidências 51.1 e 51.2.
- As evidências históricas E0/E1 foram somente consultadas. Nenhuma foi alterada.
- Não foram iniciadas as subtarefas 51.4–51.9, o Gate E2, nem E3–E5.

## Observações físicas realizadas

O cenário partiu da fila pronta e vazia já comprovada na tarefa 51.2.

1. O primeiro acionamento físico de **Registrar buraco** retornou o feedback acessível `Sucesso: Buraco salvo na fila local.`.
2. Após esse sucesso, a inspeção técnica sanitizada do sandbox privado confirmou o banco `e2_occurrence_queue_v1.db` e exatamente um JPEG no namespace privado `files/e2_queue_images_v1`. Nenhum conteúdo de imagem, caminho completo, UUID, coordenada, horário ou digest foi registrado nesta evidência.
3. Um acionamento adicional posteriormente aceito foi observado com `Pendências: 2` e dois JPEGs privados E2. Isso confirma que a contagem publicada aumentou a partir da fila confirmada, sem contador otimista isolado.
4. Ao fim da sequência controlada de acionamentos válidos, a interface física mostrou `Buracos registrados: 4` / `4 registros criados`. A mesma sequência mostrou `Pendências: 4` e quatro JPEGs privados E2; portanto, contador da sessão e pendências permaneceram semanticamente distintos e coerentes para os novos aceites desta execução.

## Ordem persistência → sucesso

O estado transitório de persistência foi curto demais para ser capturado fisicamente: o primeiro dump observável, 50 ms após o toque, já tinha o feedback de sucesso. A ordem não foi inferida desse tempo.

A garantia foi corroborada pela implementação e pelos testes dirigidos executados nesta tarefa:

- `OperationController` mantém contador da sessão e feedback de sucesso inalterados enquanto a aceitação durável está pendente; só os publica após `CandidateCreated` resultante do aceite.
- `E1PostCandidateProcessor` executa aceite durável antes de `cooldown.commit`.
- O teste de widget adicionado para E2 protege a mensagem final `A ocorrência foi salva na fila local.` e impede a mensagem histórica incorreta de que a ocorrência existiria somente em memória.
- Os testes dirigidos listados abaixo foram aprovados.

Também foi corrigida a descrição residual do estado `Concluído`: ela dizia que a ocorrência havia sido criada somente em memória, o que contradizia E2. A fonte agora declara que foi salva na fila local. A correção foi validada por teste de widget; este registro não a apresenta como uma nova observação física, pois o APK atualizado ainda não foi reinstalado durante esta subtarefa.

## Cooldown: limitação explícita

Não foi possível produzir um bloqueio físico determinístico no aparelho durante esta execução. Toques subsequentes foram aceitos; como a regra aprovada permite novo registro quando **tempo OU distância** atinge o mínimo, e a posição física variava entre tentativas, a observação não permite concluir se cada aceite decorreu do tempo ou do deslocamento.

Assim, esta evidência **não afirma** que o cenário físico de rejeição por cooldown foi aprovado. A regra permanece comprovada de modo determinístico pelos testes de domínio dirigidos, incluindo rejeição somente quando tempo e distância estão abaixo dos mínimos e manutenção da referência após rejeição. Uma nova tentativa física estacionária, com ambos os limites observavelmente abaixo do mínimo, será necessária para encerrar esse aspecto da subtarefa.

## Validação automatizada dirigida

Comando executado após a correção de mensagem:

```powershell
flutter test test/operation/operation_queue_screen_test.dart test/operation/operation_controller_test.dart test/domain/cooldown_policy_test.dart
```

Resultado: **35 testes aprovados**.

A cobertura dirigida inclui:

- progresso de persistência e feedback somente após aceite;
- contador de sessão separado das pendências;
- texto de sucesso coerente com salvamento E2;
- contador de pendências derivado da fila;
- cooldown padrão de 5 s / 15 m, regra tempo **OU** distância, limites inclusivos, rejeição quando ambos os limites não são atingidos e ausência de avanço após rejeição.

## Resultado da subtarefa

- **Salvamento local antes do sucesso:** corroborado por implementação/testes e pela existência física dos artefatos privados após sucesso.
- **Contador da sessão e pendências derivadas:** observado fisicamente com total 4 / 4 nesta execução.
- **Bloqueio físico por cooldown:** não confirmado; requer repetição física controlada. Não é substituído por alegação baseada apenas em testes.

A tarefa 51.3 não deve ser classificada como integralmente aprovada sem a observação física controlada de rejeição por cooldown. O Gate E2 permanece pendente.
