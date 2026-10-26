# Registro de evidências preparado — Tarefa 33.3

## Identificação da futura execução

> Modelo não preenchido. Completar somente quando os cenários 33.3 forem executados no Samsung Galaxy S25+. Não inserir serial, coordenadas integrais, caminho privado completo ou conteúdo da imagem.

| Campo | Valor |
|---|---|
| Data/hora da execução | Não executado |
| Responsável pela observação | Não executado |
| Dispositivo | Samsung Galaxy S25+ (`SM-S936B`) |
| Pacote | `com.vitor.pavimenta_ai_mobile` |
| SHA-256 esperado do APK | `6896EFDBFA40C80052B164B88B7DFFE9F201702C5CFDB9A4497A1F21D6D9B95B` |
| Roteiro usado | `task-33.3-physical-validation-script.md` |
| Resultado consolidado de 33.3 | **Não executado** |

Estados permitidos: **Aprovado**, **Reprovado**, **Inconclusivo** ou **Não executado**. Uma linha só pode ser aprovada quando a fonte indicada demonstra o critério. Evidência automatizada não deve ser rotulada como observação física.

## Catálogo de evidências sugeridas

| ID | Artefato/referência | Conteúdo permitido | Estado |
|---|---|---|---|
| 33.3-S01 | `33.3-S01-permissao-camera.mp4` | recusa de câmera, blocker e continuidade da UI; cena neutra | Não coletado |
| 33.3-S02 | `33.3-S02-permissao-gps.mp4` | recusa/redução/serviço/posição e blocker; coordenadas redigidas | Não coletado |
| 33.3-S03 | `33.3-S03-single-flight.mp4` | toques concorrentes, busy e contador `N + 1` | Não coletado |
| 33.3-S04 | `33.3-S04-cooldown-bloqueado.mp4` | segunda tentativa abaixo de tempo e distância, feedback e contador | Não coletado |
| 33.3-S05 | `33.3-S05-cooldown-tempo.mp4` | criação após 5 s com distância abaixo de 15 m | Não coletado |
| 33.3-S06 | `33.3-S06-cooldown-distancia.mp4` | opcional: distância >= 15 m antes de 5 s em percurso seguro | Não coletado |
| 33.3-E01 | `33.3-E01-camera-bloqueada.png` | mensagem/status da câmera e botão desabilitado | Não coletado |
| 33.3-E02a-e | capturas de GPS sanitizadas | recusa temporária/permanente, precisão reduzida, serviço e posição | Não coletado |
| 33.3-E03 | `33.3-E03-contador-unico.png` | conclusão de uma única operação concorrente | Não coletado |
| 33.3-E04 | `33.3-E04-cooldown.png` | status, descrição, feedback e contador inalterado | Não coletado |
| 33.3-E05 | `33.3-E05-tempo-permite.png` | conclusão e incremento por ramo temporal | Não coletado |
| 33.3-E06 | `33.3-E06-jpeg-metadata.txt` | formato, dimensões, bytes, hash e orientação observada; sem path | Não coletado |
| 33.3-E07 | `33.3-E07-orientacao-sanitizada.png` | alvo neutro corretamente orientado | Não coletado |
| 33.3-I01 | inventários privados sanitizados | contagem por tipo, tamanho e hash; sem path/conteúdo | Não coletado |
| 33.3-T01 | saída da validação direcionada | resultado dos cinco arquivos de teste pertinentes | A preencher nesta preparação |

Mídia e JPEG exportado não devem ser adicionados ao repositório sem revisão de privacidade. A cópia de inspeção deve permanecer fora do repositório e ser apagada após a coleta de metadados/hash.

## Matriz — permissões e blockers

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Câmera recusada mantém preview indisponível e botão bloqueado | Não executado | Física + inventário | S01/E01/I01 | — |
| Recusa temporária da câmera tem explicação clara | Não executado | Física | S01/E01 | Mensagem genérica não satisfaz o critério específico |
| Recusa permanente da câmera orienta configurações Android | Não executado | Física | S01/E01 | — |
| Falha de câmera não bloqueia GPS/interface | Não executado | Física | S01 | — |
| Localização recusada bloqueia registro e explica impossibilidade | Não executado | Física + inventário | S02/E02a/I01 | — |
| Recusa permanente orienta configurações Android | Não executado | Física | S02/E02b | — |
| Precisão reduzida é distinguida e exige localização precisa | Não executado | Física | S02/E02c | — |
| Serviço desligado é distinguido | Não executado | Física | S02/E02d | — |
| Posição indisponível não cria valores/ocorrência | Não executado | Física + inventário | S02/E02e/I01 | — |
| Blocker não incrementa contador nem cria arquivo | Não executado | Física + teste | S01/S02/I01/T01 | Botão desabilitado + chamada direta automatizada |
| Ordem serial câmera antes de localização quando há diálogo | Não executado | Física | S01/S02 | Registrar reprovação se houver diálogos concorrentes |

## Matriz — concorrência

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Toques concorrentes/repetidos iniciam no máximo uma operação | Não executado | Física + teste | S03/T01 | Contagem interna de captura é comprovada pelo teste |
| Botão fica desabilitado durante busy | Não executado | Física | S03 | — |
| Contador muda exatamente de `N` para `N + 1` | Não executado | Física | S03/E03 | — |
| Ao final não resta `source` nem segundo `prepared` novo | Não executado | Inventário + teste | I01/T01 | — |

## Matriz — cooldown

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Primeira ocorrência elegível é permitida | Não executado | Física + teste | S03/T01 | — |
| Ambos abaixo (`tempo < 5 s` e `distância < 15 m`) rejeitam | Não executado | Física + teste | S04/E04/T01 | GPS com jitter >=15 m torna tentativa inconclusiva |
| Rejeição mostra feedback explícito de tempo e distância | Não executado | Física | S04/E04 | — |
| Rejeição não altera contador nem artefatos | Não executado | Física + inventário + teste | S04/I01/T01 | — |
| Tempo >=5 s permite com distância <15 m | Não executado | Física + teste | S05/E05/T01 | — |
| Distância >=15 m permite com tempo <5 s | Não executado | Física opcional + teste | S06/T01 | Não dirigir; teste é evidência determinística se físico for impraticável |
| Limites exatos de 5 s e 15 m são inclusivos | Não executado | Teste automatizado | T01 | Não atribuir observação física exata |
| Regra OR vale para pares representativos | Não executado | Teste automatizado | T01 | — |
| Relógio regressivo é tratado abaixo do limiar temporal | Não executado | Teste automatizado | T01 | — |
| Rejeição/falha não faz commit da referência | Não executado | Teste automatizado | T01 | — |
| Bloqueio não invoca captura, UUID nem commit | Não executado | Inventário + teste | I01/T01 | UUID não é visível na UI |

## Matriz — JPEG e limites

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Artefato real é JPEG privado e não aparece na galeria | Não executado | Inspeção física privada | E06/I01 | — |
| EXIF/orientação resulta em imagem visualmente correta | Não executado | Inspeção física + teste | E07/T01 | Usar alvo assimétrico neutro |
| Resultado real tem largura <=1280 e altura <=720 | Não executado | Metadados físicos + teste | E06/T01 | — |
| Proporção é preservada sem ampliação | Não executado | Metadados quando observáveis + teste | E06/T01 | Aceitar arredondamento inteiro |
| Resultado real tem tamanho <=2.097.152 bytes | Não executado | Metadados físicos + teste | E06/T01 | — |
| Limite exatamente 2 MiB é aceito | Não executado | Teste automatizado | T01 | — |
| Toda codificação usa qualidade exatamente 85 | Não executado | Teste automatizado | T01 | Não inferível visualmente |
| Retry reduz estritamente somente dimensões e mantém qualidade | Não executado | Teste automatizado | T01 | — |
| Laço termina com sucesso ou rejeição em `1x1` | Não executado | Teste automatizado | T01 | — |

## Matriz — rejeição, ownership e limpeza

| Critério | Estado | Tipo de evidência | Referência | Observação factual |
|---|---|---|---|---|
| Fonte temporária é removida após preparação válida | Não executado | Inventário + teste | I01/T01 | Zero arquivos `source` após conclusão |
| Cooldown bloqueado não deixa novo artefato | Não executado | Inventário + teste | S04/I01/T01 | Inventário/hash inalterado |
| Nova ocorrência substitui e remove JPEG anterior | Não executado | Inventário + teste | S05/I01/T01 | Apenas novo `prepared` permanece |
| Encerramento da responsabilidade E1 remove JPEG corrente | Não executado | Inventário + teste | I01/T01 | Avaliar apenas limpeza; navegação/lifecycle ficam em 33.4 |
| Entrada indecodificável é rejeitada e removida | Não executado | Teste automatizado | T01 | Não corromper app físico |
| Limite inalcançável rejeita e limpa todos os artefatos | Não executado | Teste automatizado | T01 | — |
| Cada falha do processor limpa sem commit | Não executado | Teste automatizado | T01 | — |
| Ownership transfere uma vez e dispose é idempotente | Não executado | Teste automatizado | T01 | — |
| Varredura remove somente órfãos E1 reconhecíveis | Não executado | Teste automatizado | T01 | Não apagar arquivos alheios |
| Falha de limpeza gera log sanitizado | Não executado | Teste automatizado | T01 | Sem path, bytes, imagem ou segredo |
| Nenhuma imagem é gravada na galeria | Não executado | Física + teste/inspeção | E06/I01/T01 | — |

## Validação automatizada direcionada

Execução única realizada durante a preparação de 33.3:

```text
Comando: flutter test test/domain/cooldown_policy_test.dart test/application/post_candidate_processor_test.dart test/infrastructure/private_image_pipeline_test.dart test/operation/operation_controller_test.dart test/operation/operation_screen_test.dart
Resultado: 00:05 +53: All tests passed!
Exit Code: 0
```

**Resultado:** 53 testes direcionados aprovados, zero falhas. Essa execução comprova as regras automatizáveis, mas não muda os estados físicos da matriz, que permanecem não executados.

Arquivos cobertos:

1. `test/domain/cooldown_policy_test.dart`
2. `test/application/post_candidate_processor_test.dart`
3. `test/infrastructure/private_image_pipeline_test.dart`
4. `test/operation/operation_controller_test.dart`
5. `test/operation/operation_screen_test.dart`

## Bloqueios e limitações preparados

- `.config` e `.config.kiro` não foram encontrados no diretório do spec; o tipo foi inferido como feature pelos três documentos normativos.
- Qualidade JPEG 85, retries internos, ownership e falhas sintéticas não aparecem na UI; exigem evidência automatizada e, quando aplicável, inventário privado sanitizado.
- O ramo físico de distância antes de 5 s pode ser inconclusivo por segurança, atualização e jitter de GPS; não usar condução nem simulação no APK do gate.
- Mensagens específicas de permissão/serviço/precisão podem ser reduzidas a falhas genéricas pela implementação atual. A execução futura deve registrar o resultado real e reprovar critérios não distinguidos.
- Nenhum bloqueio autoriza alteração de requisito, fabricação de evidência, início da tarefa 34 ou início de E2.

## Resultado a preencher após execução

- Permissões e blockers: não executado.
- Concorrência: não executado.
- Cooldown por ambos abaixo: não executado.
- Cooldown por tempo: não executado.
- Cooldown por distância: não executado.
- JPEG real e metadados: não executado.
- Orientação/proporção: não executado.
- Rejeição e limpeza: não executado.
- Resultado consolidado 33.3: **Não executado**.

## Declaração de escopo

Este registro cobre somente 33.3. Não contém decisão do Validation Gate, não aprova E1, não altera status em `tasks.md` e não substitui 33.4/33.5. A aprovação física consolidada permanece exclusiva da tarefa 34 e depende de decisão explícita do usuário.
