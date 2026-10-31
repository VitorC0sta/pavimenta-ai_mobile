# Evidência da tarefa 75.3 — Matriz exata da toolchain E5

## Fontes consultadas (2026-10-30)

- `pub.dev/packages/ultralytics_yolo/versions` e changelog do pacote.
- `pubspec.yaml` e `android/build.gradle` do repositório `ultralytics/yolo-flutter-app` nas tags `v0.6.16` e `main` (0.7.1).
- `releases_windows.json` da infraestrutura de releases do Flutter.

## Plugin candidato

| Versão | Flutter mínimo | Dart | compileSdk | minSdk | Kotlin do plugin | AGP do plugin | LiteRT |
|---|---|---|---|---|---|---|---|
| **0.6.16** (escolhida) | `>=3.32.1` | `^3.8.1` | 36 | 23 | 2.2.20 | 8.11.1 | `litert` 2.1.5, `litert-metadata` 1.4.2 |
| 0.7.1 (descartada) | `>=3.41.0` | `^3.8.1` | 36 | 24 | 2.4.21 | 8.11.1 | `litert`/`litert-gpu`/`litert-metadata` 2.3.0 |

Funcionalidades confirmadas no changelog para a 0.6.16:

- 0.6.6: detecção automática de entrada NCHW ou NHWC no Android. O `buraco.tflite` tem entrada `[1, 3, 640, 640]` (NCHW);
- 0.6.8: pré-processamento escrito direto em CHW planar para modelos NCHW;
- 0.4.0: leitura de tarefa e classes pelos metadados anexados em ZIP do Ultralytics, que é o formato do `buraco.tflite` (`metadata.json` com `task: detect`, `imgsz: [640, 640]`, `names: {0: buraco}`);
- 0.4.0: `YOLOViewController.capturePhoto({withOverlays})`;
- 0.3.0: padrões oficiais `confidenceThreshold = 0.25` e `iouThreshold = 0.7`.

A 0.7.x foi descartada porque exige Flutter `>=3.41.0`, um salto maior que o necessário (regra E5.3: menor versão estável compatível).

## Matriz escolhida

| Componente | Antes (75.1) | Depois |
|---|---|---|
| Flutter | 3.24.3 | **3.32.8** (menor linha ≥ 3.32.1, último patch) |
| Dart | 3.5.3 | 3.8.1 |
| `ultralytics_yolo` | — | 0.6.16 (adicionado só na tarefa 77) |
| AGP | 8.5.1 | 8.11.1 |
| Gradle wrapper | 8.7 | 8.14 |
| Kotlin Gradle plugin | 1.8.22 | 2.2.20 |
| compileSdk / minSdk / targetSdk | padrões do Flutter | 36 / 24 / 34 (explícitos) |
| JDK | 21.0.2 | 21.0.2 (sem mudança) |
| Android SDK | `android-34`, build-tools 34.0.0 | + `android-36`, build-tools 36.0.0 |
| `path_provider` | 2.1.4 | 2.1.5 |

## Desvios registrados em relação ao D1

1. **Kotlin 2.2.20 em vez de ≥ 2.3.** O mínimo 2.3 do D1 vem da 0.7.x. A 0.6.16 é compilada com Kotlin 2.2.20, e essa é a menor versão compatível.
2. **JDK 21 em vez de 17.** O ambiente já usa Java 21, suportado por Gradle 8.14 e AGP 8.11. O bytecode Java 17 exigido pelo plugin é produzido normalmente. Não se instala um JDK adicional.

Os dois desvios foram apresentados ao usuário junto com a matriz e aprovados ("Aprovo, pode seguir").

## Resultado

Matriz registrada e aprovada. A aplicação acontece em 75.4–75.6.
