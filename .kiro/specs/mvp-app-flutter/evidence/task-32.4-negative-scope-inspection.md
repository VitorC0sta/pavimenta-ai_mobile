# Evidência da tarefa 32.4 — Inspeção negativa de escopo E0/E1

## Escopo

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`
- Subtarefa exclusiva: **32.4 — Confirmar por inspeção negativa a ausência de fila, banco, cliente de ocorrências, multipart, credencial, envio, modelo, inferência e FPS**.
- Documentos normativos consultados: `.kiro/specs/mvp-app-flutter/requirements.md`, `design.md` e `tasks.md`.
- Evidências anteriores confrontadas: `task-32.1-android-debug-build.md`, `task-32.2-build-metadata-and-sha256.md` e `task-32.3-artifact-dependencies-and-android-identity.md`.
- Requisitos verificados: RF-00.5, RF-01.1–3, RF-23.7–8 e RNF-07.2.
- O diretório da spec não contém `.config`; a execução foi tratada como spec comum, não bugfix.
- Limite preservado: somente inspeção do estado existente e criação desta evidência. Nenhum código, dependência, configuração Android, documento normativo, teste, build ou funcionalidade E2–E5 foi criado ou alterado.

## Continuidade e disponibilidade do APK debug

Artefato inspecionado:

```text
C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile\build\app\outputs\flutter-apk\app-debug.apk
```

Metadados observados diretamente nesta subtarefa:

| Campo | Valor |
|---|---|
| Arquivo | `app-debug.apk` |
| Tamanho | `109710705` bytes |
| Última modificação | `2026-10-22T11:19:25.4117618-03:00` |
| SHA-256 | `FA8535852E4E5151B9F59EAB36D89047E54E4BE41DEA80F7347BDF74E1E2349F` |
| Entradas ZIP | `211` |

O hash coincide exatamente com os registros das tarefas 32.2 e 32.3. A inspeção incidiu, portanto, sobre o mesmo artefato produzido com sucesso na tarefa 32.1 por `flutter build apk --debug`, sem `--dart-define`, URL de produção, API key ou configuração de integração de ocorrências. O comando de build e a toolchain estão registrados nas evidências anteriores, permitindo reproduzir o build; a tarefa 32.4 não reconstruiu nem modificou o APK.

## Identidade e plataforma compiladas

A inspeção direta por `aapt2 dump badging` confirmou:

| Campo | Valor observado |
|---|---|
| package/applicationId | `com.vitor.pavimenta_ai_mobile` |
| versionCode | `1` |
| versionName | `1.0.0` |
| compileSdk | `34` |
| minSdk | `21` |
| targetSdk | `34` |
| label | `pavimenta_ai_mobile` |
| activity inicial | `com.vitor.pavimenta_ai_mobile.MainActivity` |

Os valores são consistentes com `android/app/build.gradle`, `android/app/src/main/AndroidManifest.xml` e `build/app/outputs/apk/debug/output-metadata.json`, que registra `variantName: debug`, `applicationId: com.vitor.pavimenta_ai_mobile` e `outputFile: app-debug.apk`.

Permissões compiladas, obtidas por `aapt2 dump permissions`:

- `android.permission.INTERNET`;
- `android.permission.CAMERA`;
- `android.permission.ACCESS_FINE_LOCATION`;
- `android.permission.ACCESS_COARSE_LOCATION`;
- permissão de assinatura AndroidX `com.vitor.pavimenta_ai_mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.

Não há permissões de armazenamento, microfone, localização em segundo plano, foreground service ou outra declaração que indique fila, banco, credencial, upload, inferência ou execução persistente. O manifesto principal mantém a câmera como recurso não obrigatório e `android:usesCleartextTraffic="false"`, preservando falha controlada e o escopo Android aprovado.

## Inspeção negativa dos fontes e da composição

Foram inspecionados:

- árvore `lib/`;
- composition root `lib/main.dart`;
- imports e assinaturas em `lib/**/*.dart`;
- `pubspec.yaml` e `pubspec.lock`;
- Gradle e manifesto Android;
- `.flutter-plugins-dependencies`;
- `GeneratedPluginRegistrant.java`.

A árvore funcional contém somente:

- `lib/e0/`, para o Diagnóstico aprovado;
- `lib/operation/`, `lib/candidate/`, `lib/application/`, `lib/domain/` e `lib/infrastructure/`, para Operação, candidato manual, processamento, ocorrência em memória, câmera/GPS, JPEG privado, UUID e wake lock da E1;
- `lib/main.dart`, que compõe explicitamente apenas a Operação E1 e uma sessão nova do Diagnóstico E0.

Buscas por declarações, classes, contratos, imports e métodos de fila, banco, repositório persistente, cliente de ocorrências, uploader/sender, multipart, credencial, modelo, detector ou inferência não encontraram implementação. Também não foram encontrados imports de `package:http`, `package:dio`, pacotes de banco, armazenamento seguro, TFLite ou YOLO.

As únicas ocorrências relevantes que exigem classificação são permitidas e esperadas:

1. `lib/e0/diagnostic_http_client.dart` usa `dart:io` exclusivamente para o GET HTTPS diagnóstico preservado da E0. O caminho `/api/v1/occurrences` aparece somente em uma validação local que o rejeita antes de abrir conexão. Esse cliente não recebe imagem, ocorrência, UUID ou credencial e não é cliente de ocorrências.
2. `lib/operation/operation_screen.dart` contém o banner “Modo manual — YOLO ainda não configurado”. É uma comunicação obrigatória de ausência do modelo, não implementação de YOLO, TFLite ou inferência.
3. `lib/domain/in_memory_occurrence.dart` e o estado operacional representam somente a ocorrência corrente em memória e o contador da sessão, exatamente no limite E1. Não há persistência, fila ou envio.
4. Métodos internos `_enqueueResourceTransition` em `OperationController` serializam transições de lifecycle em memória; o nome não representa fila persistente de ocorrências.

## Dependências e plugins efetivamente incorporados

`pubspec.yaml` e a árvore resolvida por `dart pub deps --style=compact` confirmam como dependências diretas de aplicação somente os seis pins aprovados:

- `camera 0.11.0+2`;
- `geolocator 13.0.2`;
- `image 4.2.0`;
- `uuid 4.6.0`;
- `wakelock_plus 1.2.8`;
- `path_provider 2.1.4`.

Não foram encontrados pacotes `sqflite`, Hive, Drift, Isar, Dio, armazenamento seguro, TFLite, TensorFlow ou `ultralytics_yolo` no manifesto de dependências ou lockfile.

A árvore contém `http 1.6.0` somente como dependência transitiva de `package_info_plus`, que é transitiva de `wakelock_plus`. A aplicação não importa `package:http`, não instancia cliente desse pacote e não possui contrato ou código de envio de ocorrência. Dependência transitiva não equivale a capacidade funcional implementada.

O registrador Android contém exatamente:

1. `camera_android_camerax`;
2. `flutter_plugin_android_lifecycle`;
3. `geolocator_android`;
4. `package_info_plus`;
5. `path_provider_android`;
6. `wakelock_plus`.

Não há plugin de banco, fila, armazenamento seguro, rede de ocorrências, upload, modelo ou inferência.

## Inspeção direta do conteúdo do APK

A listagem das 211 entradas internas foi filtrada por nomes associados a fila, banco, SQLite, Hive, multipart, credencial/API key, upload, TFLite, YOLO, TensorFlow, inferência e FPS. Resultado: **nenhum nome de entrada suspeito**.

Também foram procurados assets com extensões de banco ou modelo (`.db`, `.sqlite`, `.sqlite3`, `.tflite`, `.onnx`, `.pt`, `.pth`, `.weights`). Resultado: **nenhum asset desse tipo**.

Foram examinados `kernel_blob.bin` e os sete arquivos DEX presentes no APK em busca de assinaturas funcionais específicas, incluindo:

- `OccurrenceQueue`, `PersistentQueue`, `QueueRepository`;
- `sqflite`, `hive_flutter`, `HiveInterface`, `driftDatabase`;
- `OccurrenceApiClient`, `OccurrenceClient`, `sendOccurrence`, `uploadOccurrence`;
- `multipart/form-data`, `MultipartRequest`;
- `DEVICE_API_KEY`, `BASE_URL`, `Authorization: ApiKey`, `X-API-Key`, `Bearer `;
- `ultralytics_yolo`, `tensorflow_lite`, `.tflite`, `runInference`, `inferenceFps`, `maxInferenceFps`.

Nenhuma dessas assinaturas funcionais foi encontrada, com duas correspondências lexicais genéricas que foram triadas:

- `sqlite` apareceu em `classes.dex` e `kernel_blob.bin` como string de runtime/código transitivo, mas não existe pacote, plugin, import, classe da aplicação, arquivo ou asset SQLite;
- `Isar` apareceu em DEX por busca de substring sem limite de palavra; não existe pacote, plugin, import, classe ou asset Isar. A busca exata com limites nos fontes, lockfile, manifesto e plugins retornou zero resultados.

Essas strings isoladas não constituem capacidade de banco. A ausência foi confirmada pela concordância entre fontes, dependências, plugins, nomes/ativos do APK e composition root.

As assinaturas esperadas da E0/E1 foram observadas no `kernel_blob.bin`: destino fictício `e0-diagnostic.example.invalid`, chave `E0_DIAGNOSTIC_URL`, rejeição de `/api/v1/occurrences` e texto de modo manual. Isso demonstra que a inspeção alcançou o código Flutter empacotado e que as referências encontradas pertencem aos limites aprovados.

## Matriz de resultado negativo

| Capacidade proibida na E1 | Resultado | Evidência principal |
|---|---|---|
| Fila de ocorrências | Ausente | sem módulo/contrato/pacote/plugin/asset; somente serialização efêmera de lifecycle |
| Banco/persistência | Ausente | sem sqflite/Hive/Drift/Isar, plugin, arquivo `.db/.sqlite` ou repositório persistente |
| Cliente de ocorrências | Ausente | único cliente é o diagnóstico E0; endpoint de ocorrências é explicitamente rejeitado |
| Multipart | Ausente | sem pacote/import/classe/assinatura `multipart/form-data` ou `MultipartRequest` |
| Credencial/API key | Ausente | sem `DEVICE_API_KEY`, `BASE_URL`, armazenamento seguro ou headers de autenticação |
| Envio/upload | Ausente | sem sender/uploader/método de envio, chamada POST ou integração real |
| Modelo | Ausente | sem TFLite/ONNX/PT/weights, pacote, plugin ou asset de modelo |
| Inferência/detector | Ausente | sem biblioteca, classe, método ou runtime de inferência; apenas fonte manual |
| FPS de inferência | Ausente | sem indicador, configuração ou assinatura funcional de FPS |

## Comandos e inspeções executados

Comandos executados em `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`:

```powershell
git status --short
git rev-parse --show-toplevel
flutter pub deps --style=compact
dart pub deps --style=compact
Get-Item build\app\outputs\flutter-apk\app-debug.apk
Get-FileHash -Algorithm SHA256 build\app\outputs\flutter-apk\app-debug.apk
C:\Users\vitor\AppData\Local\Android\sdk\build-tools\34.0.0\aapt2.exe dump badging build\app\outputs\flutter-apk\app-debug.apk
C:\Users\vitor\AppData\Local\Android\sdk\build-tools\34.0.0\aapt2.exe dump permissions build\app\outputs\flutter-apk\app-debug.apk
```

A listagem ZIP, a busca de assets e a inspeção de assinaturas em DEX/kernel foram executadas em memória com `System.IO.Compression`, sem extrair ou alterar o APK.

A primeira chamada isolada a `flutter pub deps --style=compact` foi interrompida pelo ambiente e terminou com código `-1`, sem alterar arquivos. A mesma árvore foi obtida com sucesso por `dart pub deps --style=compact` dentro da inspeção consolidada, que terminou com código `0`. Todas as demais verificações conclusivas do artefato também terminaram com código `0`.

Além dos comandos, foram feitas buscas estruturadas nos arquivos de aplicação, dependências e Android para classes, imports, endpoints, credenciais, métodos e nomes de pacote proibidos. O estado Git inicial mostrou alterações anteriores já existentes; nenhuma delas foi revertida ou incorporada por esta subtarefa.

## Conclusão

**SUCESSO.** A inspeção negativa confirma que o APK debug existente, identificável e reconstruível pelo comando registrado permanece limitado às capacidades E0/E1. A identidade compilada é `com.vitor.pavimenta_ai_mobile`, os metadados e o SHA-256 permanecem consistentes com as evidências 32.1–32.3, e o artefato não contém implementação de fila, banco, cliente de ocorrências, multipart, credencial, envio, modelo, inferência ou FPS.

A presença do Diagnóstico HTTPS E0 e da ocorrência temporária em memória E1 é intencional e não amplia o escopo. Nenhuma capacidade E2–E5 foi implementada, simulada ou configurada. A inspeção técnica não substitui o roteiro físico de RNF-07.2 nem aprova o Validation Gate E1.
