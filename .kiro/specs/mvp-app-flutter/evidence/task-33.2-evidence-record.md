# Registro de evidências preparado — Tarefa 33.2

## Identificação da futura execução

> Modelo não preenchido. Completar somente quando a validação física 33.2 for executada no Samsung Galaxy S25+. Não inserir serial do aparelho, coordenadas integrais ou caminho privado de imagem.

| Campo | Valor |
|---|---|
| Data/hora da execução | Não executado |
| Responsável pela observação | Não executado |
| Dispositivo | Samsung Galaxy S25+ (`SM-S936B`) |
| Pacote | `com.vitor.pavimenta_ai_mobile` |
| SHA-256 esperado do APK | `6896EFDBFA40C80052B164B88B7DFFE9F201702C5CFDB9A4497A1F21D6D9B95B` |
| Roteiro usado | `task-33.2-physical-validation-script.md` |
| Resultado consolidado de 33.2 | **Não executado** |

Estados permitidos por item: **Aprovado**, **Reprovado** ou **Não executado**. Uma linha somente pode ser marcada como aprovada quando a fonte indicada realmente demonstrar o critério.

## Catálogo de evidências

| ID sugerido | Artefato | Conteúdo permitido | Estado |
|---|---|---|---|
| 33.2-S01 | `33.2-S01-fluxo-nominal.mp4` | abertura, readiness, toque único, processamento e contador; coordenadas devem ser redigidas antes de eventual inclusão | Não coletado |
| 33.2-E01 | `33.2-E01-abertura.png` | Operação, banner, textos manuais e contador inicial | Não coletado |
| 33.2-E02 | `33.2-E02-preview-traseiro.png` | preview de cena neutra e status da câmera | Não coletado |
| 33.2-E03 | `33.2-E03-gps-sanitizado.png` | rótulos GPS, precisão e velocidade/ausência; latitude/longitude ocultadas | Não coletado |
| 33.2-E04a | `33.2-E04a-botao-bloqueado.png` | botão desabilitado antes do readiness | Não coletado |
| 33.2-E04b | `33.2-E04b-botao-pronto.png` | botão habilitado após readiness | Não coletado |
| 33.2-E05 | `33.2-E05-registro-concluido.png` | processamento concluído, feedback em memória e contador `1` | Não coletado |
| 33.2-T01 | `task-31-automated-test-suite.md` | saída consolidada existente e suas ressalvas | Disponível; não reexecutado |

Arquivos de mídia não devem ser adicionados ao repositório sem revisão de privacidade. O catálogo pode apontar para armazenamento local controlado por identificador, hash ou referência sanitizada.

## Matriz de resultado

| Critério 33.2 | Estado | Tipo de evidência exigida | Referência | Observação factual |
|---|---|---|---|---|
| Aplicativo abre na rota Operação sem crash | Não executado | Observação física | 33.2-S01 / 33.2-E01 | — |
| Banner “Modo manual — YOLO ainda não configurado” visível | Não executado | Observação física | 33.2-E01 | — |
| Texto identifica confirmação manual, sem alegação automática | Não executado | Observação física | 33.2-E01 | — |
| Preview está pronto e usa câmera traseira | Não executado | Observação física | 33.2-S01 / 33.2-E02 | — |
| GPS chega a estado pronto com posição | Não executado | Observação física sanitizada | 33.2-E03 | — |
| Precisão reportada aparece em metros | Não executado | Observação física sanitizada | 33.2-E03 | — |
| Velocidade válida aparece em km/h ou ausência aparece como “Não fornecida” | Não executado | Observação física sanitizada | 33.2-E03 | Registrar qual alternativa ocorreu, sem inventar valor |
| Botão fica desabilitado sem readiness | Não executado | Observação física | 33.2-E04a / 33.2-S01 | — |
| Botão fica habilitado com câmera/GPS/rota/lifecycle aptos e sem busy | Não executado | Observação física | 33.2-E04b / 33.2-S01 | — |
| Um toque aceito inicia uma única operação visível | Não executado | Observação física | 33.2-S01 | Não testar repetição/cooldown em 33.2 |
| Botão fica indisponível e mostra “Registrando…” durante busy | Não executado | Observação física | 33.2-S01 | — |
| Processamento conclui com ocorrência somente em memória | Não executado | Observação física | 33.2-E05 / 33.2-S01 | — |
| Contador muda exatamente de `0` para `1` | Não executado | Observação física | 33.2-S01 / 33.2-E05 | — |
| `detectedAt` preserva o instante aceito antes de async | Não executado | Evidência técnica automatizada correlacionada ao toque físico | 33.2-S01 + testes de controlador/domínio | Não observável diretamente na UI |
| Identificador satisfaz UUID v4 | Não executado | Evidência técnica automatizada | testes de domínio/aplicação | Registrar apenas o padrão sanitizado, não inventar UUID runtime |
| `defectClass` é exatamente `pothole` | Não executado | Evidência técnica automatizada | testes de fonte/aplicação/domínio | Não observável diretamente na UI |
| `confidence` é exatamente `1.0` e representa confirmação humana | Não executado | Evidência técnica automatizada + texto da UI | 33.2-E01 + testes de fonte/aplicação/domínio | Não interpretar como confiança de modelo |

## Evidência técnica correlacionável já disponível

| Propriedade | Arquivos de teste existentes | Asserções relevantes esperadas |
|---|---|---|
| `detectedAt` original | `test/operation/operation_controller_test.dart`; `test/domain/in_memory_occurrence_test.dart` | relógio lido uma vez antes do fluxo assíncrono; ocorrência preserva o instante aceito |
| UUID v4 | `test/domain/in_memory_occurrence_test.dart`; `test/application/post_candidate_processor_test.dart` | identificador gerado uma vez e aceito somente com formato/versão v4 |
| Classe e confiança | `test/candidate/manual_candidate_source_test.dart`; `test/application/post_candidate_processor_test.dart`; `test/domain/in_memory_occurrence_test.dart` | `defectClass = pothole`; `confidence = 1.0` |
| Captura única e contador | `test/operation/operation_controller_test.dart` | single-flight; contador incrementa somente no sucesso |
| Banner, botão, GPS e feedback | `test/operation/operation_screen_test.dart` | textos, estados do botão, posição/velocidade e feedback visível |

A evidência consolidada existente informa `66 testes aprovados, zero falhas`, mas também registra lacunas próprias das tarefas 24 e 28. Ao referenciá-la, preservar integralmente essas ressalvas; não usá-la para declarar a tarefa 31 concluída nem para aprovar o Gate E1.

## Resultado a preencher após a execução

### Observações objetivas

- Abertura: não executado.
- Preview: não executado.
- Banner/modo manual: não executado.
- Readiness: não executado.
- GPS/precisão: não executado.
- Velocidade: não executado.
- Captura única: não executado.
- Processamento em memória: não executado.
- Contador: não executado.
- Correlação técnica de `detectedAt`, UUID, classe e confiança: não executada.

### Bloqueios ou limitações

- **Limitação conhecida:** `detectedAt`, UUID, `defectClass` e `confidence` não são exibidos pela tela Operação. Sem instrumentação adicional aprovada, sua evidência é técnica/automatizada, não observação direta da UI no aparelho.
- Outros bloqueios: nenhum registrado nesta preparação.

### Declaração de escopo

Este registro cobre apenas 33.2. Ele não contém decisão do Validation Gate, não aprova a E1, não altera `tasks.md` e não substitui os roteiros de 33.3, 33.4 ou 33.5. A decisão física consolidada permanece exclusiva da tarefa 34 e depende de aprovação explícita do usuário.
