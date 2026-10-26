# Registro de evidências preparado — Tarefa 33.4

## Identificação da futura execução

> Modelo não preenchido. Completar somente quando os cenários 33.4 forem executados no Samsung Galaxy S25+. Não inserir serial, coordenadas integrais, URL completa, caminho privado ou mídia sem revisão de privacidade.

| Campo | Valor |
|---|---|
| Data/hora da execução | Não executado |
| Responsável pela observação | Não executado |
| Dispositivo | Samsung Galaxy S25+ (`SM-S936B`) |
| Pacote | `com.vitor.pavimenta_ai_mobile` |
| SHA-256 esperado do APK | `6896EFDBFA40C80052B164B88B7DFFE9F201702C5CFDB9A4497A1F21D6D9B95B` |
| Roteiro usado | `task-33.4-physical-validation-script.md` |
| Resultado consolidado de 33.4 | **Não executado** |

Estados permitidos: **Aprovado**, **Reprovado**, **Inconclusivo** ou **Não executado**. Uma linha só pode ser aprovada quando a fonte indicada realmente demonstra o critério. Evidência automatizada não deve ser rotulada como observação física.

## Configuração controlada do aparelho

| Configuração | Valor original | Valor durante cenário | Restaurado? |
|---|---|---|---|
| Timeout da tela | Não registrado | Não executado | Não executado |
| Manter tela ligada ao carregar | Não registrado | Não executado | Não executado |
| Fonte | Não registrado | Não executado | Não executado |
| Zoom/tamanho da tela | Não registrado | Não executado | Não executado |
| Rotação automática | Não registrado | Não executado | Não executado |
| TalkBack | Não registrado | Não executado | Não executado |
| Correção de cor/tons de cinza | Não registrado | Não executado | Não executado |
| Estado de carregamento em WL01/WL02 | Não registrado | Não executado | Não executado |

## Catálogo de evidências sugeridas

| ID | Artefato/referência | Conteúdo permitido | Estado |
|---|---|---|---|
| 33.4-S01 | `33.4-S01-lifecycle-operacao.mp4` | três pausas/retomadas, reinicialização e recuperação; coordenadas redigidas | Não coletado |
| 33.4-S02 | `33.4-S02-cancelamento-lifecycle.mp4` | interrupção durante busy e contador antes/depois | Não coletado |
| 33.4-S03 | `33.4-S03-lifecycle-e0.mp4` | pausa/retomada dentro da rota E0 | Não coletado |
| 33.4-S04 | `33.4-S04-responsividade.mp4` | rolagem durante inicialização, busy e retomada | Não coletado |
| 33.4-S05 | `33.4-S05-navegacao-recursos.mp4` | Operação → E0 → Operação e recuperação funcional | Não coletado |
| 33.4-S06 | `33.4-S06-navegacao-repetida.mp4` | toque múltiplo e três ciclos de rota | Não coletado |
| 33.4-S07 | `33.4-S07-navegacao-durante-busy.mp4` | transição solicitada durante registro ativo | Não coletado |
| 33.4-S08 | `33.4-S08-regressao-e0.mp4` | painéis E0, preview, GPS e HTTPS controlado | Não coletado |
| 33.4-E01 | `33.4-E01-operacao-retomada.png` | câmera/GPS recuperados após lifecycle | Não coletado |
| 33.4-E02 | `33.4-E02-e0-retomada.png` | E0 recuperada após lifecycle | Não coletado |
| 33.4-E03 | `33.4-E03-wakelock-operacao.txt` | timeout, duração e condições de WL01 | Não coletado |
| 33.4-E04 | `33.4-E04-wakelock-liberado.txt` | timeout e duração nos ramos Diagnóstico/background | Não coletado |
| 33.4-E05a-d | capturas responsivas sanitizadas | retrato/paisagem e escala padrão/máxima | Não coletado |
| 33.4-E06 | `33.4-E06-talkback.txt` | ordem, labels, hints e feedback anunciados | Não coletado |
| 33.4-E07 | `33.4-E07-estados-sem-cor.png` | estados compreensíveis em tons de cinza | Não coletado |
| 33.4-E08 | `33.4-E08-e0-paineis.png` | três painéis E0 e aviso de escopo | Não coletado |
| 33.4-T01 | saída da validação automatizada direcionada | cinco arquivos de teste aplicáveis | Disponível: 33 testes aprovados |
| 33.4-H01 | `task-15-validation-gate.md` | histórico E0 já aprovado, somente referência imutável | Disponível; não alterado |

Mídias não devem ser adicionadas ao repositório sem revisão de privacidade. Gravação de tela não deve ser a única evidência de wake lock, pois pode influenciar o timeout.

## Matriz — lifecycle operacional e E0

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Operação bloqueia registros fora de `resumed` | Não executado | Física + teste | S01/T01 | A UI não mostra ações enquanto está em background; bloqueio direto é técnico |
| Pausa libera preview/GPS e retorno reinicializa antes do readiness | Não executado | Física + teste | S01/E01/T01 | — |
| Três ciclos não duplicam diálogo, preview ou atualização aparente | Não executado | Física + teste | S01/T01 | Quantidade interna de streams é técnica |
| Pausa nominal não altera contador nem cria ocorrência | Não executado | Física | S01/E01 | — |
| Interrupção durante busy não publica resultado tardio | Não executado | Física correlacionada + teste | S02/T01 | Se busy terminar antes da pausa, marcar Inconclusivo |
| Callback obsoleto não publica contador, commit ou ownership | Não executado | Teste automatizado | T01 | Não observável integralmente na UI |
| Retomada aguarda cleanup anterior antes de readquirir | Não executado | Teste automatizado + efeito físico | S01/T01 | Ordem exata não deve ser inferida só pela gravação |
| E0 pausa e retoma câmera/GPS sem crash ou diálogo duplicado | Não executado | Física + teste | S03/E02/T01 | — |
| E0 mantém cliente HTTPS e dados separados de ocorrência | Não executado | Física + teste/inspeção | S03/S08/T01 | — |

## Matriz — wake lock

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Operação ativa mantém tela além do timeout | Não executado | Efeito físico controlado | E03 | Repetir após retomada; excluir gravação/carregamento |
| Diagnóstico corrente não herda wake lock E1 | Não executado | Efeito físico controlado + teste | E04/T01 | Tela deve poder apagar após timeout |
| Segundo plano libera manutenção de tela | Não executado | Efeito físico controlado + teste | E04/T01 | — |
| Retorno à Operação readquire efeito de tela ligada | Não executado | Efeito físico controlado + teste | E03/E04/T01 | — |
| Wake lock segue somente visível + foreground + resumed + rota corrente | Não executado | Teste automatizado | T01 | Estado interno não é exibido |
| Enable/disable é idempotente e balanceado | Não executado | Teste automatizado | T01 | — |
| Falha de enable é compensada e falha de disable mantém bloqueio | Não executado | Teste automatizado | T01 | Não induzir falha no aparelho |

## Matriz — responsividade e layout

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| UI rola e atualiza durante inicialização | Não executado | Física | S04 | — |
| Busy bloqueia novo registro sem bloquear a interface | Não executado | Física + teste | S04/T01 | — |
| UI permanece responsiva durante retomada | Não executado | Física | S01/S04 | — |
| Retrato e paisagem mantêm conteúdo alcançável | Não executado | Física + widget test | E05a/E05b/T01 | — |
| Fonte/zoom maiores preservam rolagem, quebra e ações | Não executado | Física + widget test | E05c/E05d/T01 | Teste automatizado usa superfície 320x480 e escala 2x |
| Preview permanece delimitado sem expulsar controles | Não executado | Física + widget test | E05a-d/T01 | — |
| Rotação não duplica rota, diálogo ou stream aparente | Não executado | Física + teste | E05a-d/T01 | Contagem interna é técnica |
| Não há ANR, congelamento, crash ou overflow impeditivo | Não executado | Física | S04/E05a-d | — |

## Matriz — acessibilidade e clareza

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Ação Diagnóstico possui rótulo compreensível no TalkBack | Não executado | Física | E06 | — |
| Banner anuncia modo manual e ausência de detecção automática | Não executado | Física + widget test | E06/T01 | — |
| Preview anuncia disponibilidade/indisponibilidade | Não executado | Física + widget test | E06/T01 | — |
| Badges anunciam `Status` e texto significativo | Não executado | Física + widget test | E06/T01 | — |
| Botão anuncia confirmação manual, estado e hint | Não executado | Física + widget test | E06/T01 | — |
| Feedback é alcançável/anunciado e não depende só da cor | Não executado | Física + widget test | E06/T01 | — |
| Painéis E0 possuem rótulos semânticos de câmera/localização/rede | Não executado | Física + inspeção | E06/E08 | — |
| Estados continuam compreensíveis em tons de cinza | Não executado | Física | E07 | Texto/ícone/borda devem preservar significado |
| Combinações visuais permanecem legíveis | Não executado | Inspeção física | E05/E07 | Não alegar razão numérica de contraste |

## Matriz — navegação e exclusão mútua

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Operação é inicial e oferece `Abrir Diagnóstico` | Não executado | Física + widget test | S05/T01 | — |
| Diagnóstico abre somente após suspensão funcional da Operação | Não executado | Física correlacionada + teste | S05/T01 | Ordem interna completa vem do teste |
| E0 mostra sessão própria de câmera/GPS sem câmera ocupada | Não executado | Física + teste | S05/T01 | — |
| Pop aguarda dispose E0 antes de readquirir Operação | Não executado | Teste automatizado + efeito físico | S05/T01 | — |
| Toques repetidos abrem somente uma sessão Diagnóstico | Não executado | Física + teste | S06/T01 | — |
| Três ciclos usam sessões novas sem diálogo/stream duplicado | Não executado | Física + teste | S06/T01 | Máximo de um owner/stream é asserção técnica |
| Nenhuma câmera/GPS coexiste entre rotas | Não executado | Teste automatizado + ausência física de falha | S05/S06/T01 | UI sozinha não prova ausência instantânea de overlap |
| Navegação durante busy invalida ação e aguarda cleanup | Não executado | Física correlacionada + teste | S07/T01 | Timing pode tornar cenário inconclusivo |
| Retorno enquanto app não está resumed adia readquisição | Não executado | Teste automatizado | T01 | Cenário interno não observável com precisão pela UI |

## Matriz — regressão do Diagnóstico E0

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Título, aviso e três painéis E0 permanecem acessíveis | Não executado | Física | S08/E08 | — |
| Preview básico traseiro continua disponível | Não executado | Física + teste | S08/T01 | — |
| GPS mostra latitude, longitude, precisão e velocidade/ausência | Não executado | Física sanitizada + teste | S08/T01 | Redigir coordenadas |
| HTTPS continua manual, separado e sem corpo/credencial | Não executado | Física + teste | S08/T01 | APK usa destino fictício padrão |
| Configuração/destino fictício falha de forma controlada | Não executado | Física | S08 | Registrar mensagem real, sem URL |
| Sucesso HTTPS físico novo no APK E1 | **Bloqueado pelo artefato atual** | Não disponível em 33.4 | tarefa 32.1 | APK foi construído sem URL funcional; não reutilizar HTTP 204 histórico como observação nova |
| Validações HTTPS e caminho proibido permanecem | Não executado | Teste automatizado | T01 | Não alterar APK para forçar cenário |
| Mensagens controladas de GPS/TLS/rede permanecem | Não executado | Física quando ocorrer + teste | S03/S08/T01 | — |
| Lifecycle E0 libera e recupera recursos | Não executado | Física + teste | S03/E02/T01 | — |
| Histórico do Gate E0 permanece intacto | Disponível | Referência documental | H01 | Nenhuma alteração em `task-15-validation-gate.md` |

## Rastreabilidade requisito → cenário

| Requisito | Cenários/evidências |
|---|---|
| RF-00.2–5, RF-00.17–22 | NAV01–NAV02, E0REG01–E0REG03, H01/T01 |
| RF-00.6–10 e RF-00.15 | LC03, E0REG01–E0REG03, S03/S08/T01 |
| RF-03.9 e RF-03.11 | LC01–LC02, NAV01–NAV03 |
| RF-05.1–4 e RF-05.9–11 | RP01–RP02, A11Y01–A11Y02 |
| RF-21.1–7 | LC01–LC03, WL01–WL03, NAV01–NAV03 |
| RF-23.7, RF-23.19–20 | todo o roteiro 33.4 e declaração de escopo |
| RNF-04.1–3 e RNF-04.6 | LC01–LC03, RP01–RP02, NAV01–NAV02 |
| RNF-07.1–2 e RNF-07.10 | E0REG01–E0REG03, H01 e pacote físico futuro |
| RNF-08.1–14 | RP02, A11Y01–A11Y02 |

## Evidência técnica direcionada

Execução única realizada durante esta preparação:

```text
Comando: flutter test test/operation/operation_controller_test.dart test/operation/operation_screen_test.dart test/operation/operation_diagnostic_navigation_test.dart test/infrastructure/operational_adapters_test.dart test/e0/e0_regression_test.dart
Resultado: 00:07 +33: All tests passed!
Exit Code: 0
```

**Resultado:** 33 testes direcionados aprovados, zero falhas. A execução cobre os contratos automatizáveis de lifecycle, wake lock, responsividade/semântica, navegação/exclusão mútua, adaptadores operacionais e regressão E0. Ela não altera os estados físicos das matrizes, que permanecem não executados.

Arquivos executados:

1. `test/operation/operation_controller_test.dart`
2. `test/operation/operation_screen_test.dart`
3. `test/operation/operation_diagnostic_navigation_test.dart`
4. `test/infrastructure/operational_adapters_test.dart`
5. `test/e0/e0_regression_test.dart`

## Bloqueios e limitações preparados

- `.config` e `.config.kiro` não existem no diretório da spec; o tipo foi inferido como feature pelos documentos normativos.
- O estado interno do wake lock e a exclusão mútua em escala de callback não são visíveis; usar efeito físico mais testes, sem extrapolar.
- Gravação de tela, carregamento ou opção global podem invalidar o teste físico de timeout; repetir sob condições controladas ou marcar `Inconclusivo`.
- Interrupção durante busy pode concluir cedo demais; não tratar conclusão anterior à pausa/navegação como falha.
- O APK atual não possui URL E0 funcional. Nova prova física de HTTP de sucesso exige artefato autorizado distinto, com hash e instalação rastreados fora de 33.4.
- Nenhum bloqueio autoriza editar histórico E0, alterar requisitos, fabricar evidência, iniciar 33.5/34 ou antecipar E2–E5.

## Resultado a preencher após execução

- Lifecycle Operação: não executado.
- Lifecycle E0: não executado.
- Wake lock ativo/liberado: não executado.
- Responsividade e layouts: não executado.
- TalkBack e estados sem cor: não executado.
- Navegação e repetição: não executado.
- Exclusão mútua física correlacionada: não executado.
- Regressão E0 integrada: não executado.
- HTTPS E0 de sucesso no APK atual: bloqueado pelo artefato sem URL funcional.
- Resultado consolidado 33.4: **Não executado**.

## Declaração de escopo

Este registro cobre somente 33.4. Não contém decisão do Validation Gate, não aprova E1, não altera `tasks.md`, não executa 33.5 e não substitui evidência física. A aprovação consolidada permanece exclusiva da tarefa 34 e depende de decisão explícita do usuário.