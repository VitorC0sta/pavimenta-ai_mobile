# Evidência — Tarefa 34.4: JPEG privado, orientação, limites e limpeza

## Resultado

**Status da subtarefa 34.4: APROVADA POR EVIDÊNCIA FÍSICA E AUTOMATIZADA COMPLEMENTAR.**

No Samsung Galaxy S25+ foi criada e inspecionada uma captura real da Operação. O artefato permaneceu no namespace temporário privado E1, foi reconhecido como JPEG, apareceu orientado corretamente, respeitou `1280x720` e 2 MiB, substituiu a imagem anterior sem deixar `source` residual e foi removido quando terminou a responsabilidade da ocorrência em memória. Qualidade 85, tentativas internas, proporção por cálculo, rejeição sintética e invariantes de lease foram verificadas pela suíte direcionada, conforme a estratégia aprovada que reconhece que esses detalhes internos não são inferíveis visualmente.

Esta evidência cobre somente 34.4. Não valida lifecycle, wake lock, exclusão mútua de câmera/GPS ou regressão E0 de 34.5; não registra a decisão final de 34.6; não altera `tasks.md`; e não inicia E2.

## Dependências e histórico inspecionados

- `requirements.md`: RF-10.1–15, RF-11.6–8 e RNF-06.1–12.
- `design.md`: E1.13, E1.14, E1.24, E1.27–E1.29 e Correctness Properties 7–9.
- `tasks.md`: tarefas 21, 23, 25, 31–33 concluídas antes do gate; 34.1–34.3 possuem evidências próprias.
- `task-31-automated-test-suite.md`: suíte consolidada anterior com 82 testes aprovados.
- `task-33.3-physical-validation-script.md` e `task-33.3-evidence-record.md`: roteiro, limites de observabilidade e inventário sanitizado previstos para JPEG/ownership.
- O diretório da spec não contém `.config` nem `.config.kiro`; como registrado historicamente, o fluxo foi tratado como spec comum de feature com base nos três documentos normativos e em `tasks.meta.json`.

## Ambiente físico

- Data/hora local: `2026-10-22T12:57:17-03:00`.
- Dispositivo: Samsung Galaxy S25+ (`SM-S936B`), reconhecido como `device` pelo ADB Windows aprovado; serial omitido.
- Pacote: `com.vitor.pavimenta_ai_mobile`.
- Rota usada para a captura: **Operação**.
- Câmera traseira e GPS estavam prontos antes do acionamento.
- O responsável confirmou a disponibilidade de um alvo/cena neutra assimétrica antes da nova captura.
- Nenhuma instalação, atualização, reconfiguração de toolchain ou alteração de código foi realizada.

## Validação automatizada direcionada

Comando executado em modo único:

```text
C:\dev\flutter\bin\flutter.bat test test\infrastructure\private_image_pipeline_test.dart --reporter expanded
```

Resultado final:

```text
00:01 +12: All tests passed!
Exit Code: 0
```

A primeira invocação do runner terminou durante o carregamento com `exit -1`, sem produzir resultado de teste. Ela foi considerada inconclusiva. A repetição não interativa acima executou os 12 casos e terminou aprovada.

### Cobertura efetivamente executada

- decode e bake de orientação EXIF;
- não ampliação e proporção dentro do arredondamento inteiro;
- encaixe inicial em `1280x720`;
- JPEG e limite inclusivo exato de `2 * 1024 * 1024` bytes;
- qualidade exatamente 85 na codificação inicial e em todos os retries;
- redução estritamente monotônica somente de dimensões e terminação finita;
- rejeição em `1x1` quando 2 MiB é inalcançável;
- rejeição de entrada indecodificável;
- remoção de fonte e derivados nas rejeições;
- transferência única de ownership e `dispose` idempotente;
- substituição e encerramento da ocorrência em memória;
- varredura restrita de órfãos reconhecíveis;
- log de falha de limpeza sem path, bytes ou conteúdo;
- arquivos gerados somente sob o namespace privado injetado.

A subtarefa 34.4 não está identificada como tarefa PBT em `tasks.md`, e `tasks.meta.json` não registra PBT aplicável. Portanto, não houve atualização de status PBT. Os testes gerativos existentes usam loops determinísticos do próprio `flutter_test`, sem runner PBT separado.

## Inspeção física sanitizada

### Baseline antes da nova captura

A consulta ocorreu via `run-as` e registrou somente contagem, metadados e hash, sem divulgar o path privado ou copiar a imagem para o repositório.

| Medida | Resultado |
|---|---:|
| JPEG `prepared` reconhecível | 1 |
| captura `source` reconhecível | 0 |
| formato/assinatura | JPEG / `FFD8FF` |
| dimensões | `480x720` |
| tamanho | `15.767` bytes |
| SHA-256 | `E6127D8E8D59CEF0970CE7644C38D0AC3352F7C90965A00E658B7A2D969EB8DE` |

### Nova captura orientada

Foi enviado exatamente um acionamento ao botão **Registrar buraco** depois de câmera/GPS/readiness confirmados e com intervalo superior ao cooldown. Após a conclusão:

| Medida | Resultado |
|---|---:|
| JPEG `prepared` reconhecível | 1 |
| captura `source` reconhecível | 0 |
| formato reportado | JPEG |
| assinatura | `FFD8FF` |
| dimensões | `480x720` |
| tamanho | `79.725` bytes |
| dentro de `1280x720` | sim |
| dentro de `2.097.152` bytes | sim |
| tag EXIF Orientation residual | ausente após normalização |
| SHA-256 | `5DC001FE558CB7755D3C20619EA1F36066670422AB933689A9565AC865983F8D` |
| hash diferente do baseline | sim |

O hash novo, combinado com exatamente um `prepared`, comprova substituição do JPEG anterior em vez de acúmulo. Zero `source` comprova retirada da captura temporária após preparação.

### Orientação e proporção observadas

A cópia temporária fora do repositório foi aberta apenas durante a inspeção. A cena assimétrica mostrou o controle e o monitor na orientação esperada; o texto visível no monitor estava legível na horizontal, sem rotação de 90/180 graus nem espelhamento aparente. O JPEG final estava em retrato `480x720`, coerente com a captura orientada. Não houve estiramento visual observado.

A comparação matemática exata com dimensões da fonte não é possível no artefato físico porque a fonte é corretamente removida após a preparação. A preservação de proporção, a ausência de ampliação e os retries somente por dimensão foram, portanto, correlacionados aos testes direcionados aprovados, conforme o roteiro da tarefa 33.3.

A qualidade 85 não foi inferida visualmente. Ela foi comprovada pelo codec rastreável da suíte, que verificou `quality == 85` em todas as codificações.

### Rejeição controlada

Não foram corrompidos arquivos, reduzido espaço nem adulteradas permissões de filesystem no aparelho. A rejeição controlada foi comprovada pelos testes direcionados para:

- entrada indecodificável;
- JPEG ainda acima de 2 MiB ao alcançar `1x1`;
- laço finito;
- limpeza de todos os artefatos reconhecíveis;
- falha de limpeza com log sanitizado.

Essa composição segue o roteiro aprovado, que proíbe indução destrutiva no aparelho e define esses cenários como evidência automatizada.

### Encerramento de ownership e limpeza temporária

Depois da inspeção, foi usada a ação prevista de abrir o Diagnóstico somente para encerrar a responsabilidade da ocorrência E1; nenhum critério de navegação ou de recursos de 34.5 foi avaliado. O inventário registrou:

| Momento | Artefatos E1 reconhecíveis |
|---|---:|
| após a nova ocorrência | 1 `prepared`, 0 `source` |
| após encerrar a responsabilidade E1 | 0 |
| após retornar à Operação | 0 |

Isso comprova fisicamente a limpeza da imagem corrente ao fim da responsabilidade em memória. A transferência única, descarte do owner e idempotência também foram aprovados pela suíte.

## Privacidade e sanitização

- Nenhum serial, coordenada, path privado completo ou conteúdo de imagem foi registrado neste arquivo.
- A imagem privada e duas capturas de tela usadas apenas para inspeção permaneceram no diretório temporário local e foram removidas ao terminar.
- Verificação final: `LOCAL_TEMP_RETAINED=0`.
- Nenhuma mídia foi adicionada ao repositório.
- A aplicação gravou o artefato sob o cache privado acessível por `run-as`; não foi usada galeria ou armazenamento compartilhado.

## Matriz de decisão 34.4

| Critério | Evidência | Resultado |
|---|---|---|
| JPEG privado | artefato real sob namespace de cache privado + teste de namespace | Aprovado |
| orientação | inspeção visual real + bake EXIF automatizado | Aprovado |
| proporção/sem ampliação | inspeção visual + propriedade determinística | Aprovado |
| máximo `1280x720` | real `480x720` + teste de limites | Aprovado |
| qualidade 85 | codec rastreável em todas as tentativas | Aprovado |
| até 2 MiB | real `79.725` bytes + limite inclusivo automatizado | Aprovado |
| rejeição controlada | cenários automatizados não destrutivos | Aprovado |
| ownership | hash substituído, um único owner real + testes de lease | Aprovado |
| limpeza temporária | zero `source`; zero artefatos após fim da responsabilidade + testes | Aprovado |

## Conclusão para o orquestrador

A subtarefa 34.4 pode ser considerada concluída. A evidência física e automatizada complementar cobre todos os itens do texto da tarefa sem inventar observações internas. `tasks.md` e metadados de status não foram modificados por esta execução. O Validation Gate pai permanece pendente; 34.5 e 34.6 não foram executadas.