# Evidência da tarefa 62.2 — Inventário E4 dos pontos de integração existentes

## Escopo

- Tarefa: **62.2 — Inventariar composition root, fila/SQLite/filesystem E2, restauração do cooldown, configuração E3, secure storage, lifecycle, painel de Operação e cliente HTTP exclusivo do Diagnóstico.**
- Natureza: inventário somente leitura. Nenhum arquivo em `lib/`, `test/`, `android/`, `pubspec.yaml` ou `pubspec.lock` foi alterado (`git status --short -- lib test android pubspec.yaml pubspec.lock` sem saída). Nenhuma dependência foi adicionada e nenhum código E4 foi iniciado.
- Base: código no estado da baseline aprovada em [task-62.1-e4-baseline.md](task-62.1-e4-baseline.md) (Flutter 3.24.3, Dart 3.5.3, 265 testes).
- Documentos consultados: `requirements.md`, `design.md` (E0.x, E2.3, E2.11, E3.1–E3.2, seção de fronteiras) e `tasks.md` (seção 62).
- Todos os caminhos são relativos à raiz do repositório `pavimenta-ai_mobile`.

## 1. Composition root

| Item | Local |
|---|---|
| Entry point | `lib/main.dart` → `Future<void> main()` |
| Montagem do grafo E1 (sem DI) | `composeE1<TPreview, TOccurrence>(...)` em `lib/main.dart`, retornando `E1Composition` (`lib/operation/e1_composition.dart`) |
| Shell do aplicativo | `PavimentaAiMobileApp<TPreview>` / `_PavimentaAiMobileAppState` em `lib/main.dart`; `home` = `OperationScreen` |
| Sessão de Configurações | `_SettingsSession` (cria um `SettingsController` novo por entrada na rota `/settings`) |
| Sessão do Diagnóstico | `_E0Session` (cria `E0Controller` novo por entrada na rota `/diagnostic`) |

Ordem de montagem em `main()`:

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. `PrivateImageStore.create()` + `sweepRecognizedOrphans()` (imagens temporárias E1, namespace `e1_images_v1`).
3. `SharedPreferencesStore.create()` → `SharedPreferencesOperationalConfigurationStore` (`configurationRepository`).
4. `_loadInitialOperationalConfiguration(...)`: `load()` com fallback para `OperationalConfiguration.defaults()` em exceção.
5. `DeviceCredentialStore()` (`credentialStore`, instância única; implementa `DeviceCredentialStatusPort` e `DeviceCredentialReadPort`).
6. `_createQueueRuntime()`: `PrivateDurableImageStore.create()` + `CoordinatedPersistentOccurrenceQueue(imageStore:)`; em qualquer exceção usa `UnavailablePersistentOccurrenceQueue`. O resultado é `_QueueRuntime(queue, acceptancePort)`, em que ambos referenciam o mesmo objeto.
7. Adaptadores: `OperationalCamera`, `OperationalLocation`, `SystemClock` (`const`), `UuidV4Generator`, `HaversineDistanceCalculator`, `WakelockPlusScreenAwake`, `PrivateJpegImagePreparer`.
8. `CooldownPolicy` construída com `initialConfiguration.cooldown` e `minimumDistanceMeters`.
9. `E1PostCandidateProcessor(cooldown, imagePreparer, uuidGenerator, occurrenceAcceptancePort: queueRuntime.acceptancePort)`.
10. `OperationController<CameraController>` recebe `ManualCandidateSource`, processador, câmera, localização, wake lock, `Clock`, `queue`, `cooldownRestorer: cooldown`, `cooldownConfigurationUpdater: cooldown`, `appSettings`, `configurationRepository` e `credentialStore` (este tipado como `DeviceCredentialStatusPort`).
11. `runApp(PavimentaAiMobileApp(...))`.

Observações para a E4:

- O ponto natural de inserção de novos colaboradores E4 (fonte de envio, snapshot de configuração, leitura de credencial) é `main()` após o passo 6, antes do passo 10. `composeE1` e `E1Composition` cobrem apenas o grafo E1 e não precisam mudar.
- `queueRuntime.queue` é o único objeto que expõe `removeInternal`, `listPending` e `snapshots`. Hoje só `OperationController` o consome.
- Nenhum timer, worker, plugin de conectividade ou cliente de ocorrência existe no composition root.

## 2. Fila E2, SQLite e filesystem

### Portas (`lib/application/e2_persistence_ports.dart`)

| Tipo | Papel |
|---|---|
| `OccurrenceAcceptancePort.accept(InMemoryOccurrence)` | Aceite durável usado pelo `E1PostCandidateProcessor`. |
| `PersistentOccurrenceQueue` | `snapshots`, `bootstrap()`, `retryBootstrap()`, `persist()`, `listPending()`, `countPending()`, `removeInternal(idempotencyKey)`, `close()`. |
| `OccurrenceAcceptanceResult` (selada) | `OccurrencePersisted`, `OccurrenceAlreadyPersistedEquivalent`, `OccurrenceIdentityConflict`, `OccurrenceStorageUnavailable`, `OccurrenceInvalidData`, `OccurrenceImageFailure`, `OccurrenceTransactionalFailure`. |
| `QueueRemovalResult` (selada) | `QueueOccurrenceRemoved`, `QueueOccurrenceNotFound`, `QueueOccurrenceRemovalFailed`. |
| `DurableImageStore` | `stage`, `promote`, `openRead`, `inspect`, `delete`, `markForDeletion`, `sweep`. |
| `DurableImageStaging` / `DurableImageDeletion` | Publicação sem sobrescrita e remoção em duas fases (`.deleting` até o commit). |

### Domínio (`lib/domain/persistent_occurrence.dart`)

`QueueHealth { initializing, ready, degraded, unavailable }`, `QueueSnapshot` (somente agregados), `QueueRecordProjection`, `PersistedImageProjection` (nome relativo opaco), `ReconstructedPendingOccurrence` (envolve o registro recuperado; é o que `listPending()` devolve).

### Implementação (`lib/infrastructure/`)

| Arquivo | Classes e pontos de entrada |
|---|---|
| `persistent_occurrence_queue.dart` | `CoordinatedPersistentOccurrenceQueue` (região de escritor único `_AsyncSingleWriter`; `bootstrap`/`retryBootstrap` compartilham a execução em andamento; `persist`, `listPending`, `countPending`, `removeInternal`, `close`), `UnavailablePersistentOccurrenceQueue`, `QueueUnavailableException`, `QueueBootstrapRecovery` / `InitialQueueBootstrapRecovery`, `QueueMutationDriver` com `PreflightQueueMutationDriver` e `CrashConsistentQueueMutationDriver` (padrão em produção), `QueueRecoveryResult`. |
| `queue_database.dart` | `QueueDatabase.open`, `createE2QueueSchemaV1`, constantes `e2QueueDatabaseName = 'e2_occurrence_queue_v1.db'`, `e2QueueDatabaseVersion = 1`, tabela `pendingOccurrences`, `e2MaximumImageByteLength = 2 MiB`, `UnsupportedQueueSchemaVersion`. Migração não existe: `onUpgrade` e `onDowngrade` lançam. |
| `queue_record_mapper.dart` | `QueueRecordColumns`, `QueueRecordMapper`. |
| `durable_image_store.dart` | `PrivateDurableImageStore.create`, `E2DurableImageNameCodec`, `DurableImageStorageException`, namespace `e2DurableImageNamespace = 'e2_queue_images_v1'` sob o diretório de suporte da aplicação. |
| `private_image_store.dart`, `private_jpeg_image_preparer.dart`, `image_artifacts.dart` | Armazenamento temporário E1 (`e1_images_v1`), preparação JPEG (qualidade 85, máximo 1280×720) e contratos de lease (`PreparedImageLease`, `TemporaryCapture`, `OwnedPreparedImage`). |

Schema v1 (colunas relevantes para a E4): `queueSequence`, `idempotencyKey`, `detectedAtIso8601`, `latitude`, `longitude`, `accuracyMeters`, `speedKmh`, `confidence` (= 1.0), `defectClass` (= `pothole`), `imageRelativeName`, `imageMimeType`, `imageByteLength`, `imageSha256`, `imageWidth`, `imageHeight`, `imageQuality`. Não há colunas de tentativa, `nextAttemptAt` ou estado de envio; a E4 definirá isso explicitamente.

Política Android de backup: `android/app/src/main/res/xml/backup_rules.xml` e `data_extraction_rules.xml` excluem o banco E2 (e `-journal`, `-wal`, `-shm`), `e2_queue_images_v1/` e o arquivo `pavimenta_ai_mobile_secure_storage.xml`.

### Consumo atual

- Só `OperationController` usa a fila (`bootstrap`, `retryBootstrap`, `listPending`, `snapshots`).
- `removeInternal` não tem chamador de produção. É o ponto que a E4 usará para remoção após confirmação remota.
- Não existe leitura de bytes da imagem fora da fila e do `DurableImageStore.openRead`. A E4 precisará dele para o multipart.

## 3. Restauração do cooldown

- Definição: `lib/domain/cooldown_policy.dart`.
  - `CandidateCooldown` (`evaluate`, `commit`), `CooldownReferenceRestorer.restoreRecoveredPending(Iterable<ReconstructedPendingOccurrence>)`, `CooldownConfigurationUpdater.updateMinimums(...)`.
  - `CooldownPolicy` implementa as três. Uma única instância é criada em `main()` e passada ao processador (como `CandidateCooldown`) e ao controller (como restorer e updater).
- Regra: a referência é a ocorrência de maior `queueSequence` entre as pendentes. Sem pendentes, a referência é `null`. `detectedAt` vem de `DateTime.parse(detectedAtIso8601)`.
- Chamadores (ambos em `lib/operation/operation_controller.dart`):
  - `_startQueueBootstrapIfNeeded()`: após `queue.bootstrap()` com `snapshot.isReady`, chama `queue.listPending()` e `restoreRecoveredPending`.
  - `_retryQueueBootstrap(queue)`: o mesmo após `queue.retryBootstrap()`.
- Teste de propriedade existente: `test/domain/property_20_cooldown_reference_restoration_test.dart`; também `test/domain/cooldown_policy_test.dart` e `test/operation/operation_queue_bootstrap_test.dart`.
- Pendência de design registrada em `design.md` (E2, "Justificativa da restauração do cooldown"): quando a E4 puder remover a última pendência (confirmação remota ou descarte), o design E4 deve decidir como preservar ou encerrar a referência. Hoje a referência é derivada apenas das pendentes. Este é um risco conhecido para as tarefas de remoção da E4 e não foi tratado aqui.

## 4. Configuração E3

| Camada | Arquivo | Tipos |
|---|---|---|
| Domínio | `lib/domain/operational_configuration.dart` | `OperationalConfiguration` (`baseUrl: Uri?`, `cooldown`, `minimumDistanceMeters`, `confidenceThreshold`, `maximumInferenceFps`; `currentStorageVersion = 1`; defaults 5 s, 15 m, 0.5, 5), `SettingsDraft`, `DeviceCredentialStatus`. |
| Domínio | `lib/domain/configuration_validators.dart` | `ConfigurationValidators`, `ConfigurationValidationResult<T>`, `ConfigurationValidationIssue`, `ConfigurationBuildVariant { debug, release }`. |
| Portas | `lib/application/e3_storage_ports.dart` | `PreferencesStore`, `OperationalConfigurationRepository` (`load`, `save`). |
| Casos de uso | `lib/application/e3_configuration_use_cases.dart` | `SaveOperationalParameters`, `SaveOrReplaceDeviceCredential`, `RemoveDeviceCredential` e seus resultados selados. |
| Infraestrutura | `lib/infrastructure/shared_preferences_store.dart` | `SharedPreferencesStore` (envolve `shared_preferences`). |
| Infraestrutura | `lib/infrastructure/operational_configuration_store.dart` | `SharedPreferencesOperationalConfigurationStore`, chave `e3_operational_configuration_v1`, documento único versionado; documento ausente, corrompido ou de versão não suportada retorna defaults; falha de acesso lança `OperationalConfigurationStorageException`. |
| Apresentação | `lib/settings/` | `SettingsController`, `SettingsState`, `SettingsScreen`. |

Consumo atual:

- `OperationController.refreshCooldownConfiguration()` recarrega o cooldown e a distância e chama `updateMinimums`. Falha mantém os valores anteriores.
- `OperationController.refreshSendingConfigurationStatus()` lê `baseUrl` e, se existir, consulta `hasCredential()`. Publica `OperationSendingConfigurationStatus.pending|ready`. Não lê a credencial completa.
- `_PavimentaAiMobileAppState._reconcileOperationAfterRoute()` chama as duas após voltar de Configurações.
- `confidenceThreshold` e `maximumInferenceFps` são reservados à E5 e só podem aparecer nos arquivos listados em `test/architecture/e3_configuration_boundaries_test.dart`.
- Não existe hoje um "snapshot imutável" da configuração para a E4. O repositório é consultado por `load()` a cada uso. A tarefa 62.5 prevê um fake de snapshot de configuração.

## 5. Secure storage (credencial do dispositivo)

- Arquivo: `lib/infrastructure/device_credential_store.dart`.
  - `SecureCredentialBackend` (`containsKey`, `read`, `write`, `delete`) e `FlutterSecureCredentialBackend` (`EncryptedSharedPreferences`, arquivo `pavimenta_ai_mobile_secure_storage`, prefixo de chave `pavimenta_ai.`).
  - `DeviceCredentialStore` com chave `device_api_key_v1`. Implementa `DeviceCredentialStatusPort` (E3) e `DeviceCredentialReadPort` (E4).
- Portas em `lib/application/e3_storage_ports.dart`:
  - `DeviceCredentialStatusPort`: `hasCredential`, `saveCredential`, `removeCredential`. Usada por `SettingsController`, os casos de uso e `OperationController`.
  - `DeviceCredentialReadPort.readCredential()`: **sem consumidor em `lib/`**. É a porta restrita já reservada à E4.
- Em `main()` a mesma instância é entregue como `DeviceCredentialStatusPort`; nenhum widget ou estado recebe a porta de leitura.
- Ponto de atenção para a tarefa 62.3: o teste atual proíbe o literal `Authorization`/`ApiKey ` fora de `lib/e0/`, e o import `package:flutter_secure_storage/` só é aceito em `lib/infrastructure/`. A leitura completa da credencial deve ficar numa fronteira E4 explícita.

## 6. Lifecycle

Quem observa o ciclo de vida:

| Observador | Arquivo | Comportamento |
|---|---|---|
| `_OperationScreenState` (`WidgetsBindingObserver`) | `lib/operation/operation_screen.dart` | `initState` registra o observer e chama `controller.startOperationalLifecycle(...)`; `didChangeAppLifecycleState` chama `controller.updateOperationalContext(...)`; `dispose` remove o observer e atualiza o contexto como inativo. |
| `_E0ScreenState` (`WidgetsBindingObserver`) | `lib/e0/e0_screen.dart` | Chama `E0Controller.handleLifecycleState(...)`; `dispose` trata como `detached`. |

Coordenação em `lib/operation/operation_controller.dart`:

- `startOperationalLifecycle`, `updateOperationalContext` (serializa liberação/readquisição de câmera, GPS e wake lock por geração), `invalidatePendingOperation`, `suspendForDiagnostic()`, `suspendForSettings()` (ambos via `_suspendForRouteNavigation`), `retryCameraReadiness`, `retryLocationReadiness`, `retryQueueBootstrap`, `dispose`.
- `startOperationalLifecycle` dispara `_startQueueBootstrapIfNeeded()` e `refreshSendingConfigurationStatus()`. O bootstrap da fila é, portanto, acionado pela primeira entrada na Operação e não pela `main()`.
- `dispose()` cancela a assinatura de `queue.snapshots`, mas **não chama `queue.close()`**. Nenhum código de produção fecha a fila. Isso é relevante para qualquer coordenador de envio da E4 (encerrar trabalho em andamento ao sair).
- Navegação: `_openDiagnostic` e `_openSettings` em `lib/main.dart` suspendem a Operação, aguardam o retorno da rota (no caso do Diagnóstico, `DiagnosticSessionDisposal.completed` em `lib/operation/diagnostic_session_disposal.dart`) e reativam o contexto com `WidgetsBinding.instance.lifecycleState`.
- Estado de ciclo de vida exposto em `OperationState`: `lifecycleState`, `isVisible`, `isForeground`, `isCurrentRoute`, `isOperationallyActive`, `isDisposed` (`lib/operation/operation_state.dart`).
- Não há `AppLifecycleListener`, worker, serviço em segundo plano nem timer de produção no fluxo da Operação.

## 7. Painel de Operação

Arquivos: `lib/operation/operation_screen.dart` (`OperationScreen<TPreview>`), `operation_state.dart` (`OperationState`, `OperationFeedback`, `OperationOccurrenceSummary`, `OperationSendingConfigurationStatus`), `operation_controller.dart`, `operation_theme.dart`.

Painéis e chaves de teste existentes:

| Painel | Classe privada | Chaves |
|---|---|---|
| Câmera/preview | `_PreviewPanel`, `_CameraReadinessContent` | `camera-panel`, `camera-readiness-slot`, `retry-camera-button`, `open-camera-settings-button` |
| Localização | `_LocationPanel`, `_LocationReadinessContent` | `location-panel`, `location-readiness-slot`, `retry-location-button`, `open-location-settings-button` |
| Sessão | `_SessionPanel` | `session-panel`, `session-counter` |
| **Fila** | `_QueuePanel` | `queue-panel`, `pending-count`, `queue-message`, `retry-queue-button` |
| **Configuração para envio** | `_SendingConfigurationPanel` | `sending-configuration-panel`, `sending-configuration-label`, `sending-configuration-message` |
| Processamento | `_ProcessingPanel` | `processing-panel`, `processing-message` |
| Ações | `OperationScreen` | `register-pothole-button`, `open-diagnostic-button`, `open-settings-button`, `manual-mode-banner`, `manual-confirmation-label` |

Pontos de extensão para a E4:

- `OperationState` já traz `queueSnapshot`-derivados (`pendingCount`, `queueMessage`) e `sendingConfigurationStatus`. A E4 pode acrescentar estado de envio sem tocar nos painéis de câmera e localização.
- `OperationScreen` depende somente de `OperationController`. A tela não conhece fila, repositório nem credencial.
- Os painéis de fila e de configuração para envio são os candidatos naturais a exibir o resultado do envio. O `design.md` (E3) exige que o estado de Operação nunca contenha destino ou credencial; essa regra deve continuar valendo.

## 8. Cliente HTTP exclusivo do Diagnóstico

- Arquivo: `lib/e0/diagnostic_http_client.dart`.
  - `DiagnosticHttpClient` (usa `dart:io` `HttpClient`), `DiagnosticHttpResult`, `DiagnosticHttpOutcome { reachable, responded, invalidConfiguration, incompleteResponse, timeout, tlsFailure, unavailable, cancelled }`.
  - URL: `String.fromEnvironment('E0_DIAGNOSTIC_URL')`, padrão `https://e0-diagnostic.example.invalid/health`. Exige `https`, host, sem userInfo nem fragmento.
  - `_validatedDestination()` rejeita explicitamente `/api/v1/occurrences` e `/api/v1/occurrences/`.
  - Timeouts: conexão 4 s, cabeçalhos 6 s, corpo 3 s. Descarta até 8 KiB de corpo. `followRedirects = false`, `autoUncompress = false`.
  - Ciclo de vida: `cancelActive()` e `dispose()`.
- Consumidores: `E0Controller` (`lib/e0/e0_controller.dart`: `runHttpsDiagnostic`, `_performHttpsDiagnostic`, `cancelActive` em lifecycle, `dispose` em `shutdown`) e a construção em `_E0SessionState.initState()` em `lib/main.dart`.
- Testes: `test/e0/e0_regression_test.dart` (`_FakeHttpClient extends DiagnosticHttpClient`).
- Isolamento confirmado:
  - Nenhum arquivo fora de `lib/e0/` importa `diagnostic_http_client.dart`, exceto `lib/main.dart` (composição da sessão do Diagnóstico). Nenhum arquivo em `lib/application`, `lib/domain`, `lib/infrastructure`, `lib/operation`, `lib/settings` ou `lib/candidate` referencia `DiagnosticHttpClient`, `HttpClient` ou `package:http`.
  - `pubspec.yaml` não declara `http` nem `dio`. Dependências de runtime: `camera`, `geolocator`, `image`, `uuid`, `wakelock_plus`, `path_provider`, `shared_preferences`, `flutter_secure_storage`, `sqflite`, `crypto`.
  - O Diagnóstico não recebe fila, configuração, credencial ou snapshot; `E0Controller` só recebe `CameraDiagnostic`, `LocationDiagnostic` e `DiagnosticHttpClient`.
  - Permissão Android `INTERNET` e `usesCleartextTraffic="false"` estão em `android/app/src/main/AndroidManifest.xml`. O `design.md` (E2.3) registra que a permissão atual serve ao Diagnóstico.
- Decisão de fronteira para a E4: o cliente de ocorrências deve ser **um tipo novo**, fora de `lib/e0/`, que não reutiliza nem estende `DiagnosticHttpClient`. O Diagnóstico continua sem acesso à credencial, à fila e ao `baseUrl` configurado. Isso segue `design.md` ("o cliente diagnóstico da E0 não será tratado como essa integração") e a tarefa 62.3, que mantém o Diagnóstico proibido de usar transporte E4. O local do novo cliente (provavelmente `lib/infrastructure/`, com porta em `lib/application/`) será definido nas tarefas seguintes, não aqui.

## 9. Testes arquiteturais que condicionam a E4

| Arquivo | Efeito sobre a E4 |
|---|---|
| `test/architecture/e3_configuration_boundaries_test.dart` | Inspeção **negativa global**: proíbe `package:http/`, `package:dio/`, `workmanager` etc. em todo `lib/`; proíbe `/api/v1/occurrences`, `multipart/form-data`, `Authorization`, `ApiKey `, `MultipartRequest`, `MultipartFile`, `HttpClient` e `.post(`/`.send(` fora de `lib/e0/`; proíbe `Worker`, `backoff` etc. em todo `lib/`. É o teste que a tarefa 62.3 substituirá por uma versão positiva. |
| `test/architecture/e2_contract_boundaries_test.dart` | Vigia imports de `lib/application` e `lib/domain` (inclui `package:http/`, `package:dio/`, `dart:io`). |
| `test/architecture/e2_dependency_policy_test.dart` | Conjunto fechado de dependências diretas aprovadas (`_approvedMainDependencies`, `_approvedDevDependencies`) com versões exatas e conferência no `pubspec.lock`. Adicionar `http` (62.4) exige atualizar essa lista. |
| `test/architecture/e3_android_network_policy_test.dart` | Política Android de rede: HTTPS sem override de cleartext na release; exceção cleartext somente para `localhost` no debug. |
| `test/application/post_candidate_processor_test.dart` | Inspeciona que o processador não contém `HttpClient`. |
| `test/candidate/manual_candidate_source_test.dart` | Inspeciona que a fonte manual não referencia `HttpClient`. |
| `test/infrastructure/android_backup_policy_test.dart` | Exclusões de backup do banco, imagens e secure storage. |

Esses testes continuam válidos e passaram na baseline 62.1. `e2_dependency_policy_test.dart` exigirá atualização quando `http` for adicionado (62.4), e `e2_contract_boundaries_test.dart` deve continuar proibindo transporte em `lib/application` e `lib/domain`. Essa revisão pertence às tarefas 62.3/62.4 e não foi feita aqui.

## 10. Lacunas observadas para tarefas posteriores (sem ação nesta tarefa)

1. Não há timer, `Clock`-baseado em agendamento nem fake de transporte. `Clock` existe (`lib/application/e1_ports.dart`, `SystemClock`) e será preservado (62.5).
2. Não há "snapshot de configuração" imutável nem porta para a E4 consumi-lo.
3. `DeviceCredentialReadPort` não tem consumidor.
4. `removeInternal` não tem chamador de produção, e o cooldown é derivado apenas das pendentes (ver seção 3).
5. Nenhum código de produção chama `queue.close()`.
6. `OperationController.dispose()` não encerra operações de fila em andamento além da assinatura de snapshots.
7. O schema SQLite v1 não tem colunas de tentativa/estado de envio e não há migração; qualquer mudança exigirá decisão explícita de design E4.

## Resultado

**Inventário da tarefa 62.2 concluído.** Todos os itens pedidos foram mapeados com arquivos, classes e pontos de entrada. Confirmado que o cliente HTTP do Diagnóstico está isolado em `lib/e0/` e que o cliente de ocorrências E4 deve ser separado. Nenhum código, teste, dependência ou evidência histórica foi alterado, e nenhum comando de build ou teste foi necessário.
