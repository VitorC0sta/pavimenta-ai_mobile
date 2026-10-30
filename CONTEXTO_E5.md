# Contexto para continuar a E5 (detecção automática com YOLO)

Documento de passagem para retomar o trabalho em outra máquina, escrito em 2026-10-30. Ele resume o estado do projeto, as decisões tomadas e o próximo passo. A fonte de verdade continua sendo `.kiro/specs/mvp-app-flutter/` (`requirements.md`, `design.md` e `tasks.md`) e as evidências em `.kiro/specs/mvp-app-flutter/evidence/`.

## 1. O projeto

`pavimenta_ai_mobile` é um app Flutter, só para Android, que registra ocorrências de buracos (foto, GPS, metadados) numa fila SQLite local e as envia ao back-end Pavimenta AI Analytics por multipart. As etapas E0–E4 estão concluídas e aprovadas: diagnóstico, registro manual, fila persistente, configurações e envio. Elas estão na `main`. A E5 acrescenta a detecção automática de buracos com o modelo YOLO `buraco.tflite`, rodando no aparelho pelo plugin `ultralytics_yolo`.

### Arquitetura (`lib/`)

| Pasta | Papel |
|---|---|
| `domain/` | Regras puras: ocorrência, cooldown, configuração, entrega (`delivery/`) e detecção (`detection/`, E5) |
| `application/` | Casos de uso e portas: pós-candidato, entrega (`delivery/`) e detecção (`detection/`, E5) |
| `infrastructure/` | SQLite (`queue_database.dart`), imagens, armazenamento, HTTP (`delivery/`) e o adaptador do plugin (`detection/`, ainda não existe) |
| `candidate/` | Fontes de candidato: `ManualCandidateSource` (intocável) e, futuramente, `yolo_candidate_source.dart` |
| `operation/`, `settings/`, `e0/` | Telas e controllers (`ChangeNotifier`), com DI manual em `main.dart` e `operation/e1_composition.dart` |

Os testes de arquitetura (`test/architecture/`) impõem fronteiras de import e de vocabulário. `e5_detection_boundaries_test.dart` define onde o código E5 pode existir: `ultralytics_yolo` só em `lib/infrastructure/detection/` e `lib/main.dart`. Os parâmetros `confidenceThreshold`, `maximumInferenceFps`, `confirmationRequiredFrames`, `confirmationWindowFrames` e `maximumBoxAreaRatio` só podem ser lidos pelos donos E3 e por `detection_parameters.dart`. As palavras `compute`, `blur` e `Isolate.spawn` são proibidas.

## 2. Branch e commits

- Branch de trabalho: **`feat/e5`**, criada a partir da `main` (`65e1561 feat: E4`).
- `b0889de`: toolchain, checkpoint 76 e fronteiras (tarefas 75–77).
- O commit seguinte contém as tarefas 78 e 79 (parcial) e este documento.
- A `main` não foi alterada. Os commits anteriores (E0–E4) foram feitos direto na `main`.

## 3. Preparar a máquina nova

1. **Flutter 3.32.8 / Dart 3.8.1** (obrigatório, porque o `ultralytics_yolo` 0.6.16 exige `>=3.32.1`):

   ```bash
   git clone https://github.com/flutter/flutter.git -b 3.32.8
   ```

   Coloque `flutter/bin` no `PATH`. Confirme com `flutter --version`.

2. **Android SDK:** `platforms;android-36` e `build-tools;36.0.0`:

   ```bash
   sdkmanager --install "platforms;android-36" "build-tools;36.0.0"
   ```

   O Gradle baixa sozinho o NDK `26.3.11579264`, o CMake `3.22.1` e a Platform 35. O aviso "plugins pedem NDK 27" não bloqueia.

3. **JDK:** foi usado o Java 21.0.2. O design pedia 17; o desvio foi aprovado.

4. **Validar o ambiente:**

   ```bash
   flutter pub get
   ```

   ```bash
   flutter analyze
   ```

   ```bash
   flutter test -j 4
   ```

   Resultado esperado: `No issues found!` e **880 testes** passando. Use `-j 4`: com a concorrência padrão, o teste antigo `test/infrastructure/property_16_queue_count_test.dart` estoura o timeout de 30 s por carga de CPU (sozinho, passa em ~15 s). Ele não foi alterado, porque os testes E2–E4 precisam ficar intactos para o Gate E5.

5. Build: `flutter build apk --debug`.

Toolchain do projeto: AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20, `compileSdk 36`, `minSdk 24` e `targetSdk 34` (não mudar o alvo na E5).

**O README ainda descreve a toolchain antiga (Flutter 3.24.3).** A atualização dele é a tarefa 85.

## 4. Modelo e plugin

- Modelo: `assets/models/buraco.tflite` (versionado no Git, sem LFS). Tem 10.685.246 bytes e SHA-256 `f6a69aa9595d54006ca2ddb7b1ed316bdee1852b79c5f68651c1af5d96434463`. É um YOLO11n float32, com entrada NCHW `[1,3,640,640]`, saída `[1,5,8400]`, sem NMS embutido, metadados `task: detect` e classe `{0: buraco}`. O descritor fica em `lib/domain/detection/pothole_model_descriptor.dart`.
- Plugin: `ultralytics_yolo: 0.6.16`, versão exata (a 0.7.x exige Flutter 3.41).
  - Faz letterbox (preenchimento **preto**, não cinza 114), normalização, NMS (IoU 0.7) e desfaz o letterbox.
  - Entrega também os frames sem detecção.
  - Pode devolver coordenadas normalizadas um pouco fora de [0, 1].
- O LiteRT do plugin acrescentava 5 permissões (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`). Todas foram removidas em `android/app/src/main/AndroidManifest.xml` com `tools:node="remove"`. **Ainda não foi confirmado no aparelho que o modelo carrega sem elas.** Isso pode ser checado depois da tarefa 80 ou no roteiro 86.
- Protótipo do checkpoint 76: `C:\Users\vitor\Documents\tcc\e5_checkpoint76_prototype`, **fora do repositório e não versionado**. É descartável; não precisa ser levado.

## 5. Decisões da E5 (resumo; detalhes em `design.md` E5.2)

| Tema | Decisão |
|---|---|
| Limiar padrão | `0.35`. No código ainda está `0.5`; a troca é na tarefa 82 (Configurações) |
| FPS | Inteiro de 1 a 15, padrão 5. Valor salvo fora disso é usado como 5 |
| Confirmação | 2 de 3 frames processados; compatibilidade quando a distância entre centros (em pixels) é menor que o maior lado das duas caixas |
| Cooldown | 5 s **ou** 15 m (já existia, `CooldownPolicy`) |
| Área máxima | 20% do frame |
| Horizonte / ROI | **Fora.** A câmera é posicionada no suporte enquadrando só a pista |
| Desfoque ou pré-processamento próprio | **Proibido** |
| Parâmetros novos | `confirmationRequiredFrames`, `confirmationWindowFrames` e `maximumBoxAreaRatio` ficam em `OperationalConfiguration`, só no código, sem persistência e sem tela |
| Manual | O botão continua com `confidence = 1.0` |
| Falha do modelo | Volta à composição manual E1–E4 sem mudanças |
| Licença | O plugin e o modelo são AGPL-3.0. Isso vai para o README na tarefa 85 |
| Vídeo | A avaliação por vídeo fica fora do escopo. O usuário vai gravar vídeos próprios depois |

## 6. Estado das tarefas E5 (`tasks.md`)

| Tarefa | Estado |
|---|---|
| 75 Toolchain | Concluída |
| 76 Checkpoint físico | Concluída, com **go**. Pendências abaixo |
| 77 Dependência, asset, fronteiras | Concluída |
| 78 Domínio e pipeline de detecção | Concluída |
| **79 Confiança do modelo e fila v3** | **Em andamento**: 79.1–79.4 implementadas, falta a 79.5 |
| 80 Adaptador YOLOView e preflight | Pendente |
| 81 Fonte YOLO no controller | Pendente |
| 82 Configurações de detecção | Pendente |
| 83 Apresentação da Operação | Pendente |
| 84 Integração e segurança | Pendente |
| 85 README e gate de desenvolvimento | Pendente |
| 86 Roteiro físico no S25+ | Pendente |
| 87 Validation Gate E5 | Pendente |

Cada tarefa concluída tem um arquivo em `evidence/task-<n>-...md`. As subtarefas concluídas estão marcadas com `[x]` no `tasks.md`. O `tasks.meta.json` é histórico do Kiro; não editar.

### Tarefa 79: o que já está feito (sem commit de evidência)

- **79.1:** `InMemoryOccurrence` guarda `confidence`. `InMemoryOccurrence.isValidConfidence` aceita valor finito em [0, 1] e é usado na fábrica e em `_hasValidCandidateFields` (`post_candidate_processor.dart`). `createManual` continua com `1.0`.
- **79.2:** `lib/infrastructure/queue_schema_v3_migration.dart`, `migrateQueueToSchemaV3`:
  - conexão dedicada com `foreign_keys = OFF`, uma transação, reconstrução de `pendingOccurrences` mantendo o `queueSequence`;
  - `sqlite_sequence` fica no maior valor entre o antigo e a maior linha;
  - `foreign_key_check` e `integrity_check` antes de `user_version = 3`;
  - recusa versão futura;
  - log só com as categorias `queue_migration_v3_completed` e `queue_migration_v3_failed`;
  - parâmetro `beforeCommit` para injetar falha nos testes.
- **79.3:** `queue_database.dart`:
  - `e2QueueDatabaseVersion = 3`;
  - `QueueDatabase.open` chama o migrador antes de abrir;
  - `onUpgrade` nunca migra (só lança erro);
  - banco novo usa `createQueuePendingTableV3`, com `CHECK (typeof(confidence) = 'real' AND confidence BETWEEN 0.0 AND 1.0)`;
  - `createE2QueueSchemaV1` continua existindo para os testes montarem bancos v1.
- **79.4:** `queue_record_mapper.dart` valida a confiança em [0, 1] na reconstrução. Fila, multipart e transporte já usavam o valor gravado e não mudaram.
- Testes ajustados para a v3:
  - `test/infrastructure/queue_database_test.dart`: versão por constante, `CHECK` com 1.01 e −0.01;
  - `test/infrastructure/delivery/queue_schema_v2_acceptance_test.dart`: a DDL é comparada normalizando o `CHECK` e o nome entre aspas que o `RENAME` gera.

### Tarefa 79: o que falta (79.5)

Criar `test/infrastructure/queue_schema_v3_migration_test.dart`, com bancos SQLite reais e temporários (`sqflite_common_ffi`):

1. Banco **v1** com pendências e JPEGs reais no `PrivateDurableImageStore`: migra para 3, mantém linhas, ordem e arquivos byte a byte, e cria as estruturas E4 com a âncora.
2. Banco **v2** com estados de entrega (`occurrence_delivery_state`), pausa (`occurrence_delivery_control`, por exemplo `unexpectedResponse` / 302 com `updated_at`), âncora, e `sqlite_sequence` acima da maior linha (insira e apague uma linha). Depois da migração:
   - estados, pausa e âncora intactos (nenhum `CASCADE` disparado);
   - a próxima inserção recebe `seq + 1`;
   - o `CHECK` aceita 0.42 e recusa 1.01;
   - FKs ligadas depois do `open` normal (o `CASCADE` funciona).
3. **Falha injetada** com `beforeCommit` lançando erro: o banco fica na versão anterior com o `CHECK (confidence = 1.0)`, o log registra `failed`, e uma nova tentativa migra.
4. **Reabertura idempotente:** o segundo `open` não migra nem registra log.
5. **Payload:** a ocorrência manual sai exatamente `1.0`, e uma confiança de modelo (por exemplo `0.42`, via `InMemoryOccurrenceFactory.create`) atravessa fila e `PersistentDeliveryQueue.nextHead` e chega ao campo `confidence` do `OccurrenceMultipartMapper.partsFor`.

O harness de `queue_schema_v2_acceptance_test.dart` (`_Lease`, `_jpeg`, `seedV1`, `_namespaceFiles`) serve de modelo. Depois: rodar format, analyze e `flutter test -j 4`, escrever `evidence/task-79-e5-model-confidence-queue-v3.md` e marcar 79.1–79.5.

## 7. Pendências e decisões em aberto

- **Checkpoint 76, itens não executados:**
  - observação térmica de 10 minutos (adiada pelo usuário; o roteiro 86 tem 15–20 minutos);
  - paridade com o Colab: rodar `model.predict` nas 6 imagens de `ds_a/test/images` (`0004`, `0040`, `0041`, `0081`, `0096`, `0107`) com `conf=0.35`, `iou=0.7`, `imgsz=640` e comparar com a tabela em `evidence/task-76-...md`. Se a confiança divergir sistematicamente, recalibrar o limiar (alternativa pré-aprovada).
- **`capturePhoto` do plugin:** sai em 12 MP (4080×3060), com 0,4 a 2,4 MB e 1 a 2 s por foto, e as dimensões ficam invertidas em relação à orientação física. Avaliar redução e orientação nas tarefas 80/81, respeitando o limite de imagem da E2/E4 (2 MB, 1280×720 na fila).
- **Componentes de biblioteca no manifesto mesclado:** WorkManager, Play asset delivery e Room. Foram mantidos, porque o design só manda remover permissões.
- **Não aprovados para a documentação** (o usuário ainda não decidiu):
  - limitações do modelo (falsos positivos com sombras, erro persistente parado no semáforo, validação com poucos vídeos públicos, trabalho futuro de fine-tuning);
  - um possível *speed gate* para não registrar com o veículo parado.
- Aparelho de teste: Samsung Galaxy S25+ (`SM-S936B`). A bateria descarrega mesmo no USB do PC com câmera e inferência ligadas; use carregador de tomada nos testes físicos.

## 8. Regras de trabalho combinadas

- Comunicação em português.
- Nunca reescrever specs por cima: complementar. Mostrar conflitos antes de alterar decisões.
- Commit só quando o usuário pedir.
- Não versionar URL real, chave, UUID real, coordenada real ou imagem real.
