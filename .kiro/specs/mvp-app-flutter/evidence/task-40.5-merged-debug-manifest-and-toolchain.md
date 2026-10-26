# Evidência da tarefa 40.5 — Manifesto debug mesclado e limites da toolchain

## Escopo e critérios

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Tarefa executada: **40.5 — Verificar o manifesto mesclado de debug e registrar qualquer limitação da toolchain para testar backup/transferência sem substituir ausência de evidência por aprovação**.
- Requisitos consultados: RF-12.2, RF-12.4, RF-12.11, RNF-02.1, RNF-05.1–3, RNF-06.3 e RNF-06.9–12.
- Decisão de design aplicada: banco, sidecars e JPEGs E2 devem ser excluídos conjuntamente das regras legadas, de `cloud-backup` e de `device-transfer`; divergência entre os paths declarados e os produzidos impede aprovação; ciclo não suportado deve permanecer classificado como não executado.
- A spec não contém `.config`; `tasks.md` posiciona esta tarefa no fluxo regular E2, não como exploração de bugfix.

## Evidência verificada

### 1. Manifesto debug mesclado regenerado

Comando executado com sucesso a partir da raiz:

```text
android\gradlew.bat -p android app:processDebugMainManifest
```

Resultado:

```text
BUILD SUCCESSFUL in 4s
30 actionable tasks: 30 up-to-date
Exit Code: 0
```

Artefato inspecionado diretamente:

```text
build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml
```

O elemento `<application>` mesclado contém simultaneamente:

```xml
android:dataExtractionRules="@xml/data_extraction_rules"
android:fullBackupContent="@xml/backup_rules"
android:usesCleartextTraffic="false"
```

Também foi verificado no manifesto mesclado:

- pacote `com.vitor.pavimenta_ai_mobile`;
- `minSdkVersion="21"` e `targetSdkVersion="34"`;
- variante debug identificada por `android:debuggable="true"`;
- ausência de `android:allowBackup="false"`, portanto não houve desabilitação indiscriminada de todo backup;
- permissões de câmera, localização precisa/aproximada e internet presentes;
- ausência das permissões removidas de áudio e armazenamento;
- uma permissão de assinatura interna `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` foi adicionada pelo merge de dependência AndroidX, não pela política E2.

**Classificação:** verificado por artefato gerado pela toolchain Android.

### 2. Conjunto conjunto e simétrico de exclusões

Os XMLs versionados inspecionados são:

- `android/app/src/main/res/xml/backup_rules.xml`;
- `android/app/src/main/res/xml/data_extraction_rules.xml`.

A regra legada e cada seção moderna contêm exatamente o conjunto abaixo:

| Domínio | Path relativo |
|---|---|
| `database` | `e2_occurrence_queue_v1.db` |
| `database` | `e2_occurrence_queue_v1.db-journal` |
| `database` | `e2_occurrence_queue_v1.db-wal` |
| `database` | `e2_occurrence_queue_v1.db-shm` |
| `file` | `e2_queue_images_v1/` |

O mesmo conjunto aparece em `full-backup-content`, `cloud-backup` e `device-transfer`. Nenhum dos XMLs contém `<include>`. Assim, banco, sidecars e namespace de JPEGs são tratados conjuntamente nas duas gerações da política, sem restaurar seletivamente apenas um lado da associação.

**Classificação:** verificado por inspeção dos XMLs e teste automatizado.

### 3. Correspondência entre paths declarados e construção de produção

Comando válido executado:

```text
flutter test test/infrastructure/android_backup_policy_test.dart
```

Resultado:

```text
3 tests passed
All tests passed!
Exit Code: 0
```

O teste confirmou:

1. as duas políticas são referenciadas pelo manifesto-fonte sem `allowBackup=false` e sem alterar `usesCleartextTraffic=false`;
2. regras legadas, `cloud-backup` e `device-transfer` possuem exatamente o mesmo conjunto completo de cinco exclusões;
3. `QueueDatabase.open(factory: databaseFactoryFfi)` constrói o filho real do diretório privado de bancos com basename `e2_occurrence_queue_v1.db`, do qual derivam `-journal`, `-wal` e `-shm`;
4. `PrivateDurableImageStore.create()` usa por padrão `getApplicationSupportDirectory()` e cria seu filho direto com nome `e2_queue_images_v1`; o teste compara esse filho relativo com a exclusão do domínio `file`.

As constantes de produção confrontadas pelo teste são:

```text
lib/infrastructure/queue_database.dart:
  e2QueueDatabaseName = e2_occurrence_queue_v1.db

lib/infrastructure/durable_image_store.dart:
  e2DurableImageNamespace = e2_queue_images_v1
```

**Classificação:** o nome relativo do banco e a construção relativa do namespace de JPEGs foram verificados no runner host. A raiz nativa Android de `path_provider` não foi verificada em dispositivo: o teste chama a API de produção `getApplicationSupportDirectory()`, mas redireciona seu canal de plataforma para um sandbox temporário. Portanto, esta evidência valida o contrato relativo e a construção Dart, não constitui observação do path absoluto em Android real.

## Toolchain observada

```text
Flutter 3.24.3
Dart 3.5.3
Android SDK 34.0.0
Android platform/build-tools 34
Java 21.0.2
```

`flutter doctor -v` relatou:

- toolchain Android detectada;
- algumas licenças Android não aceitas;
- Android Studio não instalado;
- nenhum dispositivo Android conectado; somente Windows, Chrome e Edge foram detectados.

`adb devices -l` retornou lista vazia.

A geração do manifesto mesclado foi bem-sucedida apesar dessas limitações. O Gradle emitiu aviso de que o projeto declara NDK `23.1.7779620`, enquanto plugins solicitam `26.1.10909125`, além de aviso de recursos Gradle depreciados. Esses avisos não impediram `processDebugMainManifest`, mas não foram corrigidos porque isso excede a tarefa 40.5 e implicaria reconfiguração de toolchain/projeto.

## Evidência não obtida — não aprovada

Não foi executado nenhum dos seguintes cenários:

- Android Auto Backup real;
- cloud backup seguido de restore;
- `bmgr`/transport de backup em dispositivo;
- transferência real entre dois dispositivos;
- confirmação em Android real de que nenhum banco, sidecar ou JPEG E2 reaparece após restore/transferência.

Motivo objetivo: não havia dispositivo ou emulador Android conectado à toolchain (`flutter devices` sem Android e `adb devices -l` vazio). Uma transferência real também exigiria ambiente fonte/destino apropriado. Nenhum comando de backup foi disparado sem alvo e sem transporte controlado.

**Classificação obrigatória para o Validation Gate E2:** **não executado**. A ausência de ciclo real não demonstra exclusão em runtime e não pode ser registrada como aprovação física ou end-to-end. O que está aprovado por evidência nesta tarefa é somente: merge do manifesto, conteúdo/simetria das políticas e correspondência dos paths relativos exercitada no host.

## Histórico dos comandos desta execução

A primeira invocação do teste partiu de `android/` com caminho relativo inadequado e tentou localizar `android/test/infrastructure/android_backup_policy_test.dart`. Ela falhou com `Does not exist` antes de executar qualquer teste; não é evidência de falha da política nem foi contada como validação da configuração. A invocação foi corrigida para a raiz, onde os 3 testes passaram.

Comandos/checks efetivamente usados:

```text
git status --short
flutter --version
flutter doctor -v
flutter test test/infrastructure/android_backup_policy_test.dart
android\gradlew.bat -p android app:processDebugMainManifest
flutter devices
%LOCALAPPDATA%\Android\sdk\platform-tools\adb.exe devices -l
```

Além dos comandos, foram inspecionados o manifesto principal e debug, os dois XMLs, o manifesto mesclado, o teste de política e as implementações de `QueueDatabase` e `PrivateDurableImageStore`.

## Resultado da tarefa 40.5

**Sucesso no escopo da tarefa 40.5, com limitação explícita:** o manifesto debug mesclado foi regenerado e verificado; as regras legada e Android 12+ excluem conjuntamente banco, sidecars e JPEGs E2; `cloud-backup` e `device-transfer` são simétricos; e os paths relativos coincidem com a construção exercitada pelos componentes de produção no teste host.

**Sem aprovação de runtime:** o ciclo real de backup/restauração/transferência permanece não executado e não aprovado por falta de dispositivo/ambiente adequado. Esta conclusão não substitui ausência de evidência por aprovação.
