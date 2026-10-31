# Evidência da tarefa 76 — Checkpoint físico de compatibilidade E5

> **Status:** concluído com **go** (76.7). Nenhum código E5 entrou no repositório durante o checkpoint.

## Ambiente

- Aparelho: Samsung Galaxy S25+ (`SM-S936B`, SoC `SM8750`), serial `RQGL701ZV7Z`.
- Toolchain: Flutter 3.32.8 / Dart 3.8.1 (tarefa 75).
- Modelo: `buraco.tflite`, 10.685.246 bytes, MD5 `e3e4997dcf5af5b592ea4532f3005dff`, SHA-256 `f6a69aa9595d54006ca2ddb7b1ed316bdee1852b79c5f68651c1af5d96434463`. O arquivo trazido do Colab em 2026-10-30 tem hash idêntico ao do descritor E5.4.
- Protótipo descartável: `C:\Users\vitor\Documents\tcc\e5_checkpoint76_prototype` (fora do repositório; nunca mergeado), com `ultralytics_yolo` 0.6.16, `camera` 0.11.0+2, `path_provider` 2.1.5, AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14, compileSdk 36, minSdk 24. O Gradle instalou automaticamente o Android SDK Platform 35, exigido por um plugin.
- Imagens de teste: seis imagens 640×640 de `pothole_detection_model/ds_a/test/images` (`0004`, `0040`, `0041`, `0081`, `0096`, `0107`), copiadas como `s01`–`s06` (lista em `assets/samples/SOURCES.txt` do protótipo).
- Coleta: `adb logcat` com o prefixo `CP76`.

## 76.1 Atualização preservadora do app

`adb install -r` do APK da tarefa 75.6 (SHA-256 `254AA47F…C8BEE6A847`): `Success`. `firstInstallTime` permaneceu `2026-10-24 18:33:58`; `lastUpdateTime` passou a `2026-10-30 16:07:18`. Os dados do app foram mantidos.

Regressão manual (registro manual, fila e reabertura, Configurações, Diagnóstico, envio E4): **feita pelo usuário** no aparelho, depois da atualização preservadora, e relatada sem problemas (2026-10-30). Os passos não foram acompanhados por log nesta evidência.

## Análise estática do plugin 0.6.16 (código nativo Android)

- `ObjectDetector.predict`: rotação conforme a câmera, letterbox com o mesmo arredondamento do `LetterBox` do Ultralytics, normalização `/255` (`INPUT_MEAN = 0`, `INPUT_STANDARD_DEVIATION = 255`) e escrita planar CHW quando `rtModel.inputUsesNchw`.
- NMS nativo (JNI) com `iouThreshold` padrão `0.7`.
- `Predictor.outputCoordinatesAreNormalized` detecta saída normalizada ou em pixels do modelo, e `inputRectFromOutputRect` desfaz o letterbox para o frame original.
- **Diferença em relação ao Colab:** o preenchimento do letterbox é **preto (0,0,0)** (`ImageUtils.clearLetterboxPadding` com `Color.BLACK`), não cinza 114. Isso não afeta imagens quadradas e precisa ser medido em frames da câmera (item 6).
- O redimensionamento usa `Canvas` com `FILTER_BITMAP_FLAG` (bilinear).

## Resultados no aparelho

### 76.2 Carregamento, metadados e detecções

`YOLO.inspectModel`: `task: detect`, `imgsz: [640, 640]`, `labels: [buraco]`, `end2end: false`, `stride: 32`, `channels: 3`. A entrada NCHW foi aceita sem reexport.

`predict` com `confidenceThreshold = 0.35` e `iouThreshold = 0.7`:

| Imagem | GPU: caixas (conf) | CPU: caixas (conf) | GPU ms | CPU ms |
|---|---|---|---|---|
| s01 | 0,6958; 0,3523 | 0,6955; 0,3545 | 1212 (aquecimento) | 100 |
| s02 | 0,6309 | 0,6313 | 18 | 45 |
| s03 | 0,6689; 0,5156 | 0,6672; 0,5123 | 13 | 35 |
| s04 | — | — | 24 | 42 |
| s05 | 0,5767; 0,4941; 0,4648; 0,3530 | 0,5796; 0,4895; 0,4687; 0,3595 | 11 | 56 |
| s06 | 0,8032 | 0,8032 | 16 | 41 |

GPU e CPU coincidem: diferença máxima de confiança 0,0065, diferença de caixa inferior a 5 px. Algumas caixas normalizadas saem levemente de [0, 1] (por exemplo `y1_norm = -0,0303`, `x2_norm = 1,0071`); o `DetectionFilter` deve recortar ou tolerar esses valores (ajuste para a tarefa 78.2).

**Paridade com o Colab:** pendente. Requer as caixas e confianças das mesmas seis imagens no Colab (`conf = 0.35`, `iou = 0.7`, `imgsz = 640`).

### 76.3 Cadência, frames vazios e FPS (YOLOView, 720p, câmera traseira)

| Limite (`maxFPS` = `inferenceFrequency`) | Resultados por segundo observados (janela 2 s) | Métrica do plugin |
|---|---|---|
| 5 | ~4,0 (2,0–4,0) | — |
| 10 | ~7,0–8,0 | `fps = 7,3`; total ~21 ms (pré ~14 ms, inferência ~7 ms, pós ~0,2 ms) |
| 2 | ~1,8–2,0 | `fps = 1,8`; total ~24–30 ms (pré ~17–21 ms, inferência ~7–8,5 ms, pós ~0,2 ms) |

- O plugin entrega resultados **vazios** (`n = 0`) em `onResult` (em 2 FPS, 92 de 140 callbacks vazios). A alternativa de frames sintetizados (E5.7) não é necessária.
- `onModelLoad` foi recebido.
- O custo por frame (~21 ms) permite mais que 10 FPS; a taxa observada é limitada pelo controle de ritmo do plugin. Registro sem meta numérica.

### 76.4 Captura e liberação da câmera

Executado em 2026-10-30, segunda sessão (18:07–18:08), com `YOLOView` em 2 FPS.

`capturePhoto(withOverlays: false)`:

| Foto | Orientação do aparelho | Dimensões | Bytes | Latência |
|---|---|---|---|---|
| 1 | retrato | 4080×3060 | 497.293 | 1607 ms |
| 2 | retrato | 4080×3060 | 395.351 | 2060 ms |
| 3 | paisagem | 3060×4080 | 2.291.301 | 1026 ms |
| 4 | paisagem | 3060×4080 | 2.189.503 | 1184 ms |
| 5 | paisagem | 3060×4080 | 2.430.692 | 1127 ms |

- Todas as capturas retornaram bytes válidos, sem overlay.
- **Observação para as tarefas 80 e 81:** a foto sai na resolução total do sensor (12 MP), com 0,4 a 2,4 MB e 1,0 a 2,1 s de latência. A captura deve ser assíncrona em relação ao pipeline. A E5 deve avaliar se a foto precisa ser reduzida antes do enfileiramento e envio (limites da E4).
- As dimensões ficam invertidas em relação à orientação física (retrato → 4080×3060). Os bytes JPEG/EXIF precisam ser conferidos na tarefa 80 antes de exibir a foto ou enviá-la.

Liberação para o plugin `camera`: `controller.stop()` + desmontagem do `YOLOView` em **349 ms**. Em seguida, `CameraController(ResolutionPreset.medium)` abriu a câmera traseira em **107 ms**, sem erro de câmera ocupada.

### 76.5 Observação térmica

Linha de base às 15:37: `Thermal Status: 0`, bateria 31,3 °C. Às ~16:15, depois de ~8 minutos de câmera e inferência: bateria 36,9 °C, nível 7%, **descarregando mesmo no USB do PC** (`current_avg` ≈ −600 mA). Na segunda sessão (18:08, 73%, carregando no USB), depois dos testes de 76.3 e 76.4: `Thermal Status: 0`, bateria 35,1 °C.

A observação contínua de 10 minutos foi **adiada pelo usuário** (2026-10-30). Fica pendente para uma sessão futura, antes do teste de campo da tarefa 86.

## Classificação (76.6)

| Item | Situação |
|---|---|
| 1. Carregamento, metadados e detecções | **Aprovado** |
| 2. Cadência, frames vazios e FPS | **Aprovado** em 2, 5 e 10 FPS |
| 3. `capturePhoto` | **Aprovado**, com a observação de resolução e latência |
| 4. Liberação da câmera e permissão | **Aprovado** (a permissão foi pedida e concedida pelo próprio `YOLOView`) |
| 5. GPU/CPU e térmica | GPU e CPU **aprovados**; observação de 10 minutos adiada pelo usuário |
| 6. Paridade com o Colab | **Não executado** (falta o lado Colab). O lado do aparelho está registrado em 76.2. |

Nenhum item foi reprovado e nenhuma alternativa foi aplicada. O modelo carrega com entrada NCHW, sem reexport.

Itens não executados e onde ficam cobertos:

- **Térmica de 10 minutos** (item 5): adiada pelo usuário. O roteiro físico 86 já inclui observação de 15–20 minutos com `dumpsys`.
- **Paridade com o Colab** (item 6): quando houver os números do Colab para `s01`–`s06`, comparar com a tabela de 76.2. Se a divergência de confiança for sistemática, aplica-se a alternativa pré-aprovada de recalibrar o limiar padrão. Divergência de caixas não tem alternativa pré-aprovada e exigiria revisão do design.

Recomendação apresentada ao usuário: **go** para a tarefa 77.

Decisão go/no-go (76.7): **go**, dada pelo usuário em 2026-10-30. Nenhuma alternativa fora das pré-aprovadas foi aplicada, então o design E5 não muda antes da tarefa 77. O protótipo permanece fora do repositório e não é mergeado.
