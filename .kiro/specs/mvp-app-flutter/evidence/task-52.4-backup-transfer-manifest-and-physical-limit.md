# Evidência da tarefa 52.4 — Manifesto mesclado, exclusões E2 e limite físico

## Escopo e classificação

- Tarefa executada: **52.4 — Apresentar manifesto mesclado e regras Android que excluem conjuntamente banco, sidecars e JPEGs E2 de backup e transferência, registrando como não executado qualquer ciclo físico não suportado.**
- Spec: `mvp-app-flutter`; não há arquivo `.config`, portanto não é uma spec de bugfix.
- Escopo preservado: somente evidência do Gate E2. Não foram alterados código Flutter, manifesto-fonte, XMLs de backup, permissões, dependências, configuração de toolchain, sandbox Android ou tarefas adjacentes.
- Regras aplicadas: a política deve excluir em conjunto o banco SQLite, seus sidecars e o diretório privado de JPEGs, sem desabilitar indiscriminadamente o backup do aplicativo.

## Manifesto debug mesclado atual

A geração `app:processDebugMainManifest` foi concluída com sucesso. O artefato efetivo de merge inspecionado é:

```text
build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml
```

No elemento `<application>`, o manifesto mesclado contém simultaneamente:

```xml
android:dataExtractionRules="@xml/data_extraction_rules"
android:fullBackupContent="@xml/backup_rules"
android:usesCleartextTraffic="false"
```

Também foram confirmados no mesmo artefato:

- pacote `com.vitor.pavimenta_ai_mobile`;
- variante debug (`android:debuggable="true"`), `minSdkVersion="21"` e `targetSdkVersion="34"`;
- permissões declaradas de câmera, localização precisa/aproximada e internet;
- ausência de `android:allowBackup="false"`, mantendo política seletiva em vez de desabilitar todo backup;
- a permissão interna de assinatura `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` resulta de dependência AndroidX, não das regras E2.

O caminho de estágio `build/app/intermediates/merged_manifest/debug/AndroidManifest.xml` não deve ser usado como evidência final após esta execução, pois é uma cópia intermediária sem os atributos de backup. Os artefatos por tarefa `processDebugMainManifest`, `processDebugManifest` e o manifesto empacotado preservam as duas referências acima.

## Regras Android apresentadas

### Backup legado

`android/app/src/main/res/xml/backup_rules.xml` usa `full-backup-content` e exclui:

| Domínio | Path relativo |
| --- | --- |
| `database` | `e2_occurrence_queue_v1.db` |
| `database` | `e2_occurrence_queue_v1.db-journal` |
| `database` | `e2_occurrence_queue_v1.db-wal` |
| `database` | `e2_occurrence_queue_v1.db-shm` |
| `file` | `e2_queue_images_v1/` |

### Android 12+ — backup em nuvem e transferência

`android/app/src/main/res/xml/data_extraction_rules.xml` repete exatamente o mesmo conjunto em **ambas** as seções `cloud-backup` e `device-transfer`. Nenhum XML contém `<include>`.

Assim, as três políticas relevantes — legado, backup em nuvem Android 12+ e transferência entre dispositivos Android 12+ — excluem conjuntamente:

1. `e2_occurrence_queue_v1.db`;
2. `e2_occurrence_queue_v1.db-journal`;
3. `e2_occurrence_queue_v1.db-wal`;
4. `e2_occurrence_queue_v1.db-shm`;
5. `e2_queue_images_v1/`, que contém os JPEGs privados E2.

A exclusão conjunta evita restaurar linhas SQLite sem JPEGs associados ou JPEGs sem suas linhas de fila.

## Correspondência com os paths de produção

O teste usa as constantes e os construtores concretos de produção:

- `QueueDatabase.open()` usa o basename `e2_occurrence_queue_v1.db` abaixo do diretório privado de bancos do `sqflite`; os três sidecars são derivados desse mesmo nome.
- `PrivateDurableImageStore.create()` usa `getApplicationSupportDirectory()` como padrão de produção e cria o namespace filho direto `e2_queue_images_v1` para os JPEGs.

Logo, os nomes relativos produzidos pelos componentes E2 correspondem aos paths excluídos nas regras Android. A raiz nativa absoluta do `path_provider` não foi exposta nem registrada.

## Validações executadas

```text
flutter test test/infrastructure/android_backup_policy_test.dart
```

Resultado:

```text
3 tests passed
All tests passed!
Exit Code: 0
```

A suíte verificou que o manifesto-fonte referencia as duas políticas sem `allowBackup=false`, que as regras legado/cloud-backup/device-transfer são simétricas e que os paths relativos reais de SQLite e do armazenamento de JPEGs correspondem às exclusões.

```text
android\gradlew.bat -p android app:processDebugMainManifest
```

Resultado:

```text
BUILD SUCCESSFUL in 7s
30 actionable tasks: 1 executed, 29 up-to-date
Exit Code: 0
```

O Gradle repetiu os avisos já conhecidos de versão NDK solicitada por plugins e recursos depreciados. Eles não impediram a geração do manifesto, e nenhuma toolchain foi modificada nesta tarefa.

## Ciclos físicos: não executados

O shell atual não disponibiliza `adb` no `PATH` (`ADB_NOT_AVAILABLE_ON_PATH`). Portanto, não havia meio suportado nesta execução para confirmar dispositivo, transporte ou executar uma observação física controlada.

Além disso, um ciclo de backup/restauração ou de transferência que prove a exclusão exigiria ambiente isolado e descartável: origem de backup controlada e restauração que não sobrescreva as evidências/dados existentes; para `device-transfer`, também dois dispositivos preparados. Nenhuma ação destrutiva ou potencialmente sobrescrevente foi realizada.

| Cenário | Classificação |
| --- | --- |
| Regras legadas para banco, sidecars e JPEGs | **Aprovado tecnicamente** por XML, teste e merge |
| Regras Android 12+ em `cloud-backup` | **Aprovado tecnicamente** por XML e teste |
| Regras Android 12+ em `device-transfer` | **Aprovado tecnicamente** por XML e teste |
| Referências no manifesto debug mesclado | **Aprovado tecnicamente** por artefato Gradle atual |
| Backup/restauração físico controlado | **Não executado** |
| Transferência física entre dispositivos | **Não executado** |

A ausência de ciclo físico não é apresentada como aprovação de runtime. O Gate E2 permanece pendente até as tarefas e a decisão explícita aplicáveis.