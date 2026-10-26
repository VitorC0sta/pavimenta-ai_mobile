# Evidência da tarefa 40 — Exclusão Android de backup e transferência

## Escopo

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`
- Tarefa exclusiva: **40 — Configurar a exclusão Android de backup e transferência**.
- Artefatos protegidos: banco `e2_occurrence_queue_v1.db`, sidecars `-journal`, `-wal` e `-shm`, e namespace durável `e2_queue_images_v1/`.
- Nenhuma permissão, configuração de cleartext/TLS, integração de rede, fila funcional adicional ou comportamento E0/E1 foi introduzido.

## Implementação

### Regras legadas

`android/app/src/main/res/xml/backup_rules.xml` usa `full-backup-content` e exclui:

- domínio `database`: `e2_occurrence_queue_v1.db`;
- domínio `database`: `e2_occurrence_queue_v1.db-journal`;
- domínio `database`: `e2_occurrence_queue_v1.db-wal`;
- domínio `database`: `e2_occurrence_queue_v1.db-shm`;
- domínio `file`: `e2_queue_images_v1/`.

### Regras Android 12+

`android/app/src/main/res/xml/data_extraction_rules.xml` contém exclusões idênticas em `cloud-backup` e `device-transfer`. Não existem regras `include`, portanto a alteração é seletiva para os artefatos E2 listados e não desabilita genericamente todo backup do aplicativo.

### Manifesto

O elemento `<application>` referencia:

```xml
android:fullBackupContent="@xml/backup_rules"
android:dataExtractionRules="@xml/data_extraction_rules"
```

`android:usesCleartextTraffic="false"` permaneceu inalterado. Nenhum `android:allowBackup="false"` foi adicionado. As permissões ativas declaradas no manifesto-fonte permanecem somente câmera, localização precisa/aproximada e internet; as declarações existentes de remoção de permissões de áudio/armazenamento também permaneceram intactas.

### Correspondência com paths de produção

O teste de integração usa os contratos concretos de produção:

- `QueueDatabase.open(factory: databaseFactoryFfi)` resolve o banco a partir de `getDatabasesPath()` e confirma que o filho relativo efetivo é `e2_occurrence_queue_v1.db`; os três sidecars são derivados desse nome real.
- `PrivateDurableImageStore.create()` continua usando `getApplicationSupportDirectory` por padrão. Foi adicionado apenas um provider opcional de diretório para permitir a execução no runner host; o teste injeta a raiz equivalente fornecida pelo adapter, executa a mesma construção de produção e confirma que o filho direto efetivo é `e2_queue_images_v1/`.
- Os dois conjuntos de paths efetivos são comparados com as exclusões XML.

O seam não altera a raiz de produção, o namespace, o ownership, a visibilidade de paths nem o comportamento do armazenamento.

## Validações executadas

### Formatação

```text
dart format lib/infrastructure/durable_image_store.dart test/infrastructure/android_backup_policy_test.dart
Formatted 2 files (0 changed)
Exit Code: 0
```

### Testes direcionados

Comando final:

```text
flutter test test/infrastructure/android_backup_policy_test.dart test/infrastructure/durable_image_store_test.dart
```

Resultado:

```text
17 tests passed
All tests passed!
Exit Code: 0
```

Cobertura específica da nova política:

1. manifesto referencia as duas políticas seletivas, preserva cleartext desabilitado e não acrescenta permissão ativa;
2. regras legadas, `cloud-backup` e `device-transfer` excluem exatamente o mesmo conjunto completo de banco, sidecars e imagens;
3. paths relativos resolvidos pelos adapters de armazenamento coincidem com os paths declarados.

Os 14 testes existentes de `durable_image_store_test.dart` também passaram, cobrindo a regressão do armazenamento afetado pelo seam.

### Análise estática

```text
flutter analyze
No issues found! (ran in 7.6s)
Exit Code: 0
```

### Build Android debug

```text
flutter build apk --debug
Built build\app\outputs\flutter-apk\app-debug.apk
Exit Code: 0
```

O build repetiu o aviso histórico não bloqueante: o projeto declara NDK `23.1.7779620`, enquanto plugins resolvidos solicitam `26.1.10909125`. Nenhuma toolchain ou configuração NDK foi alterada dentro da tarefa 40.

### Manifesto debug mesclado

Arquivo inspecionado:

```text
build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml
```

O manifesto mesclado confirma:

- `android:dataExtractionRules="@xml/data_extraction_rules"`;
- `android:fullBackupContent="@xml/backup_rules"`;
- `android:usesCleartextTraffic="false"`;
- `minSdkVersion="21"` e `targetSdkVersion="34"`;
- presença das permissões aprovadas de câmera, localização e internet;
- ausência das permissões de áudio e armazenamento removidas pelo manifesto principal.

O merger também mantém uma permissão de assinatura interna gerada por dependência AndroidX (`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`), não adicionada pela tarefa 40. Nenhuma permissão do manifesto-fonte foi acrescentada por esta implementação.

## Limitações e classificação da evidência

- O runner host de `flutter test` não registra uma implementação real do plugin `path_provider`; uma tentativa direta retornou `MissingPlatformDirectoryException`. Por isso, o teste usa o provider injetável descrito acima para validar a mesma resolução relativa, mantendo `getApplicationSupportDirectory` como default de produção.
- Não foi executado ciclo real de Android Auto Backup, cloud restore ou transferência entre dispositivos. A toolchain usada nesta tarefa produziu e permitiu inspecionar o manifesto mesclado, mas não forneceu evidência física de backup/restauração/transferência.
- Consequentemente, a configuração, os paths, os testes host, a análise e o build estão **aprovados tecnicamente**, enquanto o comportamento de um ciclo real de backup/transferência permanece **não executado**, devendo ser registrado assim no Validation Gate E2. Esta ausência não é tratada como aprovação física.

## Resultado

A tarefa 40 está implementada e validada no alcance automatizável disponível: banco, sidecars e JPEGs E2 estão excluídos conjuntamente nas regras legadas, em `cloud-backup` e em `device-transfer`; o manifesto mesclado referencia ambas as políticas; e os paths declarados coincidem com os contratos concretos de armazenamento. A limitação de ciclo real Android permanece explicitamente registrada, sem presumir evidência inexistente.
