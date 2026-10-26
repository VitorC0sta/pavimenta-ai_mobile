# Evidência — Tarefa 34.2: observação física nominal E1

## Resultado

**Status da subtarefa 34.2: PARCIALMENTE OBSERVADA / BLOQUEADA PARA CONCLUSÃO INTEGRAL.**

A execução física no Samsung Galaxy S25+ confirmou o fluxo nominal visível de Operação, preview traseiro, banner manual, GPS/velocidade, readiness, processamento, captura única, contador e responsividade. Entretanto, `detectedAt`, UUID v4, `defectClass` e `confidence` não são exibidos pela interface atual e, portanto, não puderam ser observados fisicamente sem instrumentação adicional. Os blockers específicos por câmera indisponível e GPS inválido também não receberam evidência física conclusiva nesta execução; o blocker durante processamento foi observado.

Esta evidência cobre somente a tarefa 34.2. Não aprova o Validation Gate E1, não executa 34.3–34.6, não inicia E2 e não altera `tasks.md`.

## Ambiente e pré-condições efetivamente confirmados

- Execução em ambiente Windows aprovado, usando Flutter e o executável ADB já existente no Android SDK; nenhuma instalação ou reconfiguração global foi feita.
- Dispositivo físico reconhecido: Samsung `SM-S936B` (Galaxy S25+), estado ADB `device`; serial omitido.
- Pacote em primeiro plano durante a coleta: `com.vitor.pavimenta_ai_mobile/.MainActivity`.
- Permissões de câmera e localização precisa estavam concedidas no fluxo nominal.
- Após tentativa controlada de observar blockers, o estado do app foi restaurado: câmera concedida, localização precisa concedida e app-op de câmera em `allow/foreground`.
- O spec não contém `.config`; a execução seguiu o spec comum descrito em `requirements.md`, `design.md` e `tasks.md`.

## Observações físicas aprovadas

| Item da tarefa 34.2 | Resultado | Evidência factual |
|---|---|---|
| Tela Operação | Aprovado | `MainActivity` permaneceu retomada e a tela exibiu o título “Operação”. |
| Banner manual | Aprovado | Banner “Modo manual — YOLO ainda não configurado” visível; texto auxiliar “Confirmação manual de um buraco observado. Não é detecção automática.” visível. |
| Preview | Aprovado | Painel “Câmera traseira” em “Pronta”, preview visível e frames coletados em instantes distintos mostraram atualização da cena. O usuário confirmou visualmente que a cena correspondia à câmera traseira. |
| GPS e precisão | Aprovado | Painel em “GPS pronto”/“GPS disponível”, latitude e longitude preenchidas e precisão exibida em metros. Coordenadas foram deliberadamente omitidas deste documento. |
| Velocidade | Aprovado | O provedor apresentou velocidade válida na UI em `km/h` (incluindo resultado de repouso `0.0 km/h`, que é válido pelo spec). |
| Botão pronto | Aprovado | Com câmera e GPS prontos, rota corrente, app em `resumed` e processamento ocioso, “Registrar buraco” apareceu habilitado. |
| Blocker durante processamento | Aprovado | Após o toque, o botão ficou indisponível e mudou para “Registrando…”, enquanto o painel mostrou “Processando” e “Aguarde a conclusão do registro atual.” |
| Captura única | Aprovado | Em sessão limpa, o contador estava em `0`; foi enviado exatamente um toque ADB no botão e uma única operação visível foi processada. |
| Resultado em memória | Aprovado | O painel terminou em “Concluído”, exibiu “A ocorrência foi criada somente em memória.” e o feedback “Sucesso: Buraco registrado em memória.” |
| Contador | Aprovado | Na coleta controlada de um único toque, “Buracos registrados” mudou exatamente de `0` para `1`. |
| Responsividade | Aprovado | Rolagem, atualização do preview, atualização dos indicadores e transição busy → concluído responderam no aparelho sem crash ou congelamento observado. O usuário confirmou visualmente a responsividade. |

Uma coleta anterior em que ocorreu um toque ADB e um toque manual simultâneo foi descartada como evidência de single-flight, após o usuário confirmar a segunda interação. A coleta aprovada acima foi repetida em sessão limpa, sem toque manual concorrente.

## Artefatos locais sanitizáveis

A mídia bruta permaneceu fora do repositório em `%TEMP%`, pois contém cena de câmera e coordenadas visíveis. Somente hashes são registrados aqui; os arquivos não devem ser versionados sem revisão/redação de privacidade.

| Artefato local | Conteúdo | SHA-256 |
|---|---|---|
| `task-34.2-single-before.png` | Estado pronto, contador `0` | `A9F052B68034519107677B1D10B0738F7CD8C6044EF681BD50647376AB7E1C75` |
| `task-34.2-single-busy.png` | Estado “Processando/Registrando…” | `85151AD2B1DBF83BB85C751032BAC46FEBC5B0F33CE988925511A0DE51F2D799` |
| `task-34.2-single-after.png` | Estado concluído, contador `1` | `2F5555290CEB682C5026A043D46E0BF5868FBB1A2426194C324C74FC46D90E17` |
| `task-34.2-single.mp4` | Sequência física contínua da sessão limpa | `C7FF5C392EC002981240EBA81D4B0BC66C5F0D5545DA8769E9F65BAB936A9526` |

As árvores de acessibilidade locais correlacionaram os estados antes/depois e confirmaram textos, status, contador e feedback. Seus valores de coordenadas não foram transcritos para esta evidência.

## Itens bloqueados ou não conclusivos

### Campos internos não observáveis fisicamente

A tela Operação atual não renderiza:

- o valor runtime de `detectedAt`;
- o UUID v4 runtime;
- `defectClass = pothole`;
- `confidence = 1.0`.

A suíte consolidada já existente (`task-31-automated-test-suite.md`) registra 82 testes aprovados e cobre tecnicamente horário original, UUID v4, classe e confiança. Essa evidência pode ser correlacionada ao fluxo físico, mas não foi tratada como observação física direta. Concluir esses quatro itens como “fisicamente observados” exigiria instrumentação adicional aprovada ou aceitação explícita, no gate, da composição entre fluxo físico e evidência automatizada; nenhuma instrumentação foi adicionada nesta tarefa.

### Blockers de câmera e GPS

O blocker de busy foi observado. Não foi obtida evidência física conclusiva, nesta sessão, de:

- câmera indisponível mantendo o botão desabilitado;
- GPS inválido/indisponível mantendo o botão desabilitado.

Uma tentativa temporária de alterar somente a autorização do app não produziu estado indisponível confiável, pois o Android restabeleceu a autorização na retomada. O estado foi restaurado e nenhum resultado inconclusivo foi marcado como aprovado. Lifecycle fora de `resumed` pertence também ao escopo específico de 34.5 e não foi antecipado aqui.

## Conclusão para o orquestrador

A tarefa 34.2 **não deve ser marcada como integralmente concluída**: há sucesso físico comprovado para o fluxo nominal e para o blocker de processamento, mas permanecem sem observação física direta os campos internos (`detectedAt`, UUID, classe e confiança) e sem evidência conclusiva os blockers de câmera/GPS. O gate pai 34 deve permanecer pendente. Nenhuma tarefa posterior foi executada.
