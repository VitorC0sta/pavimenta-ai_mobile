# Evidência da tarefa 77: dependência, asset do modelo e fronteiras E5

Executada em 2026-10-30, depois do go do checkpoint 76.

## 77.1 Dependência

- `pubspec.yaml`: adicionado `ultralytics_yolo: 0.6.16`, versão exata aprovada no checkpoint 76.
- `flutter pub get` mudou 9 pacotes no `pubspec.lock`:
  - `ultralytics_yolo` 0.6.16, como `direct main`;
  - transitivas `url_launcher` 6.3.2, `url_launcher_android` 6.3.20, `url_launcher_ios` 6.3.4, `url_launcher_linux` 3.2.2, `url_launcher_macos` 3.2.3, `url_launcher_platform_interface` 2.3.2, `url_launcher_web` 2.4.1 e `url_launcher_windows` 3.1.5.
- As outras dependências do plugin (`plugin_platform_interface`, `path_provider` ^2.1.5, `shared_preferences` ^2.2.0 e `wakelock_plus` ^1.2.0) já estavam resolvidas nos pins existentes, sem mudança.
- Nenhum `tflite_flutter`, ML Kit, ONNX, isolate, worker ou pacote de conectividade entrou no lado Dart.

## 77.2 Asset e descritor

- `assets/models/buraco.tflite` foi copiado sem alteração: 10.685.246 bytes, SHA-256 `f6a69aa9595d54006ca2ddb7b1ed316bdee1852b79c5f68651c1af5d96434463`, igual ao descritor E5.4.
- O `pubspec.yaml` declara somente esse asset.
- `lib/domain/detection/pothole_model_descriptor.dart` guarda o path, o SHA-256, o tamanho, a tarefa `detect`, a entrada 640 e o mapeamento `0/buraco → pothole` (`contractClassFor`). O descritor não tem dependências.
- O APK debug empacota o modelo em `assets/flutter_assets/assets/models/buraco.tflite` com 10.685.246 bytes, junto com `lib/<abi>/libultralytics.so` do plugin.

## 77.3 Teste do asset

`test/domain/detection/pothole_model_descriptor_test.dart` verifica:

- o tamanho e o SHA-256 do asset, comparados com o descritor;
- que este é o único arquivo de modelo do projeto (ignorando `build`, `.dart_tool`, `.git`, `.gradle` e `.idea`);
- o mapeamento de classe e a rejeição de qualquer outro índice ou nome.

## 77.4 Manifesto mesclado

Depois do plugin, o manifesto mesclado (debug e release) passou a trazer 5 permissões novas. Nenhuma vem do código do `ultralytics_yolo`; todas chegam pelas dependências transitivas do LiteRT:

| Permissão | Origem (relatório do manifest merger) |
|---|---|
| `FOREGROUND_SERVICE` | `com.google.ai.edge.litert:litert:2.1.5` e `com.google.android.play:asset-delivery:2.3.0` |
| `FOREGROUND_SERVICE_DATA_SYNC` | idem |
| `WAKE_LOCK` | `androidx.work:work-runtime:2.9.1` |
| `ACCESS_NETWORK_STATE` | `androidx.work:work-runtime:2.9.1` e `androidx.media3:media3-common:1.9.0` |
| `RECEIVE_BOOT_COMPLETED` | `androidx.work:work-runtime:2.9.1` |

O app não tem serviço em primeiro plano, trabalho em segundo plano, wake lock próprio (o `wakelock_plus` usa `FLAG_KEEP_SCREEN_ON`, sem permissão) nem observação de rede. Por isso as 5 foram removidas em `android/app/src/main/AndroidManifest.xml` com `tools:node="remove"`, com comentário de justificativa.

Resultado no manifesto mesclado debug, depois da remoção:

- permissões `INTERNET`, `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` e `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, as mesmas da E4 (75.6);
- `fullBackupContent="@xml/backup_rules"`, `dataExtractionRules="@xml/data_extraction_rules"` e `usesCleartextTraffic="false"`, inalterados.

**Observação: componentes de biblioteca no manifesto mesclado.** A mesma cadeia (LiteRT → Play asset delivery, WorkManager, Room) acrescenta `service`, `receiver` e `provider`:

- `androidx.work.impl.*`: `SystemAlarmService`, `SystemJobService`, `SystemForegroundService` e os receivers `ConstraintProxy*`, `RescheduleReceiver`, `ForceStopRunnable$BroadcastReceiver` e `DiagnosticsReceiver`;
- `com.google.android.play.core.assetpacks.*`: `AssetPackExtractionService`, `ExtractionForegroundService` e `SessionStateBroadcastReceiver`;
- `androidx.room.MultiInstanceInvalidationService`.

O manifesto principal do app continua sem `<service>` e `<receiver>`, como exige E5.15. Esses componentes não foram removidos: a E5.13 trata só de permissões, e removê-los seria uma alternativa fora do design. Sem as permissões removidas, nenhum deles roda em primeiro plano nem recebe boot. O carregamento do modelo depois da remoção das permissões deve ser confirmado no aparelho (roteiro 86, ou antes dele com o APK da tarefa 77).

## 77.5 Fronteiras arquiteturais

- `test/architecture/e2_dependency_policy_test.dart`: pin `ultralytics_yolo: 0.6.16` aprovado como dependência `direct main`, com comentário, e retirado da lista de famílias proibidas. `tflite_flutter` continua proibido.
- `test/architecture/e3_configuration_boundaries_test.dart`: `lib/domain/detection/detection_parameters.dart` passou a ser dono autorizado dos parâmetros.
- `test/architecture/e4_delivery_boundaries_test.dart`, convertido em fronteiras positivas E5:
  - worker continua proibido em todo lugar;
  - o vocabulário de inferência (`tflite`, `inference`, `ModelLoader` etc.) é permitido somente nas zonas de detecção (`lib/{domain,application,infrastructure}/detection/` e `lib/candidate/yolo_candidate_source.dart`) e nas raízes de composição;
  - `package:ultralytics_yolo` só é aceito em `lib/infrastructure/detection/` e `lib/main.dart`;
  - texto "YOLO" só é aceito nas zonas de detecção, na apresentação da Operação e na composição;
  - o `pubspec` só aceita `ultralytics_yolo` como pacote de modelo e só o asset do modelo;
  - o único arquivo de modelo aceito é o asset;
  - a checagem do manifesto ignora as entradas de remoção (`tools:node="remove"`).
- `test/architecture/e5_detection_boundaries_test.dart` (novo) verifica cada regra da E5.15 com exemplos sintéticos permitidos e rejeitados:
  - `ultralytics_yolo` só nos adaptadores;
  - `tflite_flutter`, ML Kit, ONNX, conectividade, `Isolate.spawn`, `compute`, `startImageStream` e `CameraImage` proibidos;
  - `modelPath` só aceita `PotholeModelDescriptor.assetPath`;
  - `officialModels`, `defaultOfficialModel`, `switchModel` e URL de modelo proibidos;
  - os 5 parâmetros de detecção só são lidos pelos donos;
  - o código de detecção não faz desfoque, filtro nem redimensionamento próprio (`package:image`, `copyResize`, `gaussianBlur`, `ImageFilter`);
  - o `pubspec` declara só o asset do modelo;
  - o manifesto principal não declara `<service>`, `<receiver>`, `WAKE_LOCK` nem `FOREGROUND_SERVICE`, declara uma única `INTERNET` e remove as 5 permissões do LiteRT.
- As asserções E4 sobre o `ManualCandidateSource` e o contrato de candidato sem palavras YOLO continuam inalteradas.

## Validação

| Verificação | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | `Formatted 168 files (0 changed)` |
| `flutter analyze` | `No issues found!` |
| `flutter test` | `All tests passed!`, **832 testes**: 819 da baseline mais 4 do descritor e 9 das fronteiras E5 |
| `flutter build apk --debug` | Aprovado; 270.139.622 bytes; SHA-256 `2cf63bf253e5737a5c79213e50c483b9f1a729b5f2d7521df60064395d46737d` |
| `flutter build apk --release` | Aprovado (88,3 MB), usado só para inspecionar o manifesto mesclado de release |

O APK debug cresceu ~63 MB em relação à 75.6 (207.437.204 bytes). O aumento vem do modelo (10,7 MB) e das bibliotecas nativas LiteRT/plugin nas 4 ABIs.

## Resultado

**Tarefa 77 concluída.** O plugin e o modelo entram com versão e hash verificáveis. As permissões novas sem uso foram removidas, e as fronteiras automatizadas permitem a E5 somente nas zonas definidas. Nenhum código de detecção (filtro, pipeline, adaptador) foi criado; isso começa na tarefa 78.
