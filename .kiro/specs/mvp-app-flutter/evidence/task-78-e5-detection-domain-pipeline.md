# Evidência da tarefa 78: domínio e pipeline de detecção

Executada em 2026-10-30, na branch `feat/e5`.

## 78.1 Contratos e parâmetros

- `lib/domain/operational_configuration.dart` ganhou três parâmetros nomeados com padrão no código: `confirmationRequiredFrames = 2`, `confirmationWindowFrames = 3` e `maximumBoxAreaRatio = 0.20`. As construções E3 existentes continuam válidas e recebem esses padrões. Esses campos não são gravados nem lidos pelo armazenamento, `currentStorageVersion` continua `1` e a tela não muda. `defaultConfidenceThreshold` continua `0.5`; a troca para `0.35` é da tarefa de Configurações (E5.11).
- `lib/domain/detection/detection_frame.dart` cria `DetectionModelStatus`, `DetectionBox` (coordenadas normalizadas), `DetectionFrame` (`observedAt`, `imageWidth`/`imageHeight` positivos e lista imutável de caixas) e `ConfirmedDetection`.
- `lib/domain/detection/detection_parameters.dart` é o único leitor E5 dos campos operacionais:
  - FPS fora de 1–15 (ou não inteiro, ou não finito) vira 5, com `fpsFallbackApplied` para a tela de Configurações;
  - limiar inválido volta ao padrão;
  - janela inconsistente ou área fora de (0, 1] é erro de programação (`ArgumentError`), porque esses valores só existem no código.
- Os campos de `DetectionParameters` têm nomes próprios (`minimumConfidence`, `framesPerSecond`, `requiredHits`, `windowSize`, `maximumAreaRatio`). Assim, o teste de fronteira E5 continua garantindo que só os donos citam os nomes da configuração.

## 78.2 `DetectionFilter`

- Mantém somente as caixas da classe `0/buraco` (via `PotholeModelDescriptor.contractClassFor`), com confiança finita no intervalo [limiar, 1].
- Coordenadas: a tolerância é de **0,05** fora de [0, 1]. Dentro dela, a caixa é recortada para o frame; fora dela, ou com valor não finito, a caixa é descartada. A tolerância cobre os desvios medidos no checkpoint 76 (`-0,0303` e `1,0071`), conforme a nota registrada para esta tarefa.
- Caixa degenerada (largura ou altura ≤ 0 depois do recorte) é descartada.
- Área normalizada ≤ `maximumAreaRatio`; o limite exato de 20% é aceito.

## 78.3 `InferenceRateGate` e `InferenceFpsMeter`

- Gate: intervalo mínimo `0,85 × (1 / FPS)` desde o último frame aceito (170 ms em 5 FPS, 85 ms em 10 FPS).
  - Um frame descartado não move a referência.
  - Um timestamp anterior ao último aceito (relógio ajustado para trás) é aceito e vira a nova referência, para o gate não travar.
- Medidor: janela deslizante de 2 s. Guarda só os timestamps dos frames aceitos dentro da janela, nunca os frames. O valor cai a zero quando os frames param (`framesPerSecondAt(now)`).

## 78.4 `TemporalConfirmationTracker`

- A compatibilidade usa a distância entre centros em pixels do frame original, que deve ser menor que o maior lado das duas caixas. A distância igual ao lado não é compatível.
- A associação é gulosa pela menor distância; cada trilha e cada caixa entram em no máximo um par.
- Confirmação 2 de 3 frames processados, com frames vazios contando na janela. A confiança é a maior da trilha na janela.
- Uma trilha confirmada não emite de novo e é encerrada depois de 3 frames seguidos sem caixa compatível. Uma trilha não confirmada sai quando a janela fica sem acertos.
- Cada trilha guarda só a última caixa (centro, lados, confiança) e no máximo 3 confianças.

## 78.5 Portas e pipeline

- `lib/application/detection/automatic_detection_port.dart`: `frames`, `modelStatus` e `applyParameters`.
- `lib/application/detection/model_preflight_port.dart`: `ModelAvailable` / `ModelUnavailable(reason)`, com categorias fixas `model_metadata_mismatch`, `model_load_failed` e `model_load_timeout`, e timeout de 15 s.
- `lib/application/detection/detection_pipeline.dart` processa, na ordem, gate → medidor → filtro → tracker:
  - `process(frame)` é síncrono e devolve `DetectionStep` (aceito, confirmações, FPS medido);
  - `start(frames)` / `stop()` assinam o fluxo do adaptador e publicam `confirmations` e `measuredFps`;
  - `measuredFpsAt(now)` serve à exibição;
  - `applyParameters` reconstrói gate, filtro e tracker; `reset` limpa trilhas, gate e medidor;
  - nenhum frame é guardado.
- O descarte por ocupação (E5.7 passo 5) fica com o consumidor (controller, tarefa 81).

Domínio e aplicação de detecção importam só `dart:async`, `dart:collection`, `dart:math` e arquivos do próprio domínio. As fronteiras E4/E5 passam.

## 78.6 Testes

| Arquivo | Conteúdo |
|---|---|
| `test/domain/detection/detection_parameters_test.dart` | padrões D9, construção E3 sem os campos novos, FPS 1–15 e fallback, limiar inválido, janela e área inconsistentes |
| `test/domain/detection/detection_filter_test.dart` | limiar (inclusive o limite), classe, coordenadas inválidas, recorte dos desvios do plugin, área no limite de 20%; propriedade `glados` (200 casos) |
| `test/domain/detection/inference_rate_test.dart` | intervalos 5/10 FPS, referência no último aceito, relógio para trás, reset, medidor e decaimento; propriedade de jitter (150 casos) |
| `test/domain/detection/temporal_confirmation_tracker_test.dart` | 2 consecutivos, 2 de 3 com vazio, janela excedida, supressão e reinício, jitter, limite exato, frame não quadrado, caixas de tamanhos diferentes, associação gulosa, duas trilhas, reset; propriedades de presença aleatória (200 casos) e limite de trilhas (150 casos) |
| `test/application/detection/detection_pipeline_test.dart` | composição, frames descartados pelo gate, limiar, frames vazios e FPS, troca de parâmetros, reset, fluxo com `start`/`stop`/`close`, categorias do preflight; propriedade de chegada com jitter (150 casos) |
| `test/domain/detection/detection_test_support.dart` | auxiliares dos testes |

## Validação

| Verificação | Resultado |
|---|---|
| `dart format lib test` | 183 arquivos, 1 reformatado |
| `flutter analyze` | `No issues found!` |
| `flutter test test/domain/detection test/application/detection` | 52 testes, todos aprovados |
| `flutter test -j 4` | `All tests passed!`, **880 testes** |
| `flutter test` (concorrência padrão) | 879 aprovados, 1 timeout: `test/infrastructure/property_16_queue_count_test.dart` |

**Sobre o timeout:** `property_16_queue_count_test.dart` é um teste E2 de propriedade com SQLite (120 casos). Sozinho, passa em ~15 s. Na suíte completa com a concorrência padrão, a carga extra dos testes novos o leva além do limite de 30 s do pacote `test`. Não é falha de lógica, e o teste não foi alterado: os testes E2–E4 precisam ficar intactos para o Gate E5. A suíte completa passa com `-j 4`. Se o limite precisar mudar, isso fica para decisão do usuário.

## Resultado

**Tarefa 78 concluída.** As regras de detecção são determinísticas, foram testadas sem plugin e não armazenam nem acumulam frames.
