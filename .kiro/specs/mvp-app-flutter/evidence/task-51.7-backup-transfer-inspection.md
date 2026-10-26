# Evidência da tarefa 51.7 — Inspeção de exclusão de backup e transferência

## Escopo

- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Tarefa executada: **51.7 — Inspecionar manifesto/regras para exclusão conjunta de banco, sidecars e imagens de backup/transferência; executar ciclo controlado somente se suportado e marcar honestamente como não executado quando indisponível.**
- Documentos consultados antes da execução: `requirements.md`, `design.md` e `tasks.md` da spec `mvp-app-flutter`.
- A diretiva E2 aplicável exige que banco, sidecars e JPEGs sejam excluídos em conjunto, nas regras legadas e nas regras Android 12+ para `cloud-backup` e `device-transfer`; o comportamento de backup/restauração não é funcionalidade da E2.
- A spec não contém `.config` nem `.config.kiro`; é uma spec regular, não bugfix.

Nenhum código de aplicativo, manifesto, XML de política, dependência, configuração de toolchain ou dado no sandbox Android foi modificado por esta tarefa. Alterações preexistentes no repositório foram preservadas.

## Inspeção das regras efetivas

O `<application>` em `android/app/src/main/AndroidManifest.xml` declara simultaneamente:

```xml
android:fullBackupContent="@xml/backup_rules"
android:dataExtractionRules="@xml/data_extraction_rules"
android:usesCleartextTraffic="false"
```

Não há `android:allowBackup="false"`; a política é seletiva e não desabilita indiscriminadamente o backup do aplicativo.

`android/app/src/main/res/xml/backup_rules.xml` exclui no `full-backup-content`:

| Domínio | Path relativo |
|---|---|
| `database` | `e2_occurrence_queue_v1.db` |
| `database` | `e2_occurrence_queue_v1.db-journal` |
| `database` | `e2_occurrence_queue_v1.db-wal` |
| `database` | `e2_occurrence_queue_v1.db-shm` |
| `file` | `e2_queue_images_v1/` |

`android/app/src/main/res/xml/data_extraction_rules.xml` declara exatamente o mesmo conjunto em **ambas** as seções `cloud-backup` e `device-transfer`. Os XMLs não possuem elementos `<include>`. Assim, a política evita backup/restauração parcial entre os metadados SQLite e os JPEGs associados.

O manifesto debug mesclado foi regenerado e inspecionado em `build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`. Ele mantém `android:fullBackupContent`, `android:dataExtractionRules` e `android:usesCleartextTraffic="false"` no elemento `<application>`.

## Validações executadas

Execução em `2026-10-24T17:51:28-03:00`:

```text
flutter test test/infrastructure/android_backup_policy_test.dart
```

Resultado:

```text
3 tests passed
All tests passed!
Exit Code: 0
```

A suíte confirmou que:

1. o manifesto referencia as duas políticas seletivas, sem `allowBackup=false`;
2. a regra legada, `cloud-backup` e `device-transfer` excluem o mesmo conjunto completo de banco, sidecars e diretório de imagens;
3. os paths relativos declarados correspondem aos nomes produzidos por `QueueDatabase` (`sqflite`) e `PrivateDurableImageStore` (`path_provider`).

Também foi executado:

```text
android\gradlew.bat app:processDebugMainManifest
```

Resultado:

```text
BUILD SUCCESSFUL
30 actionable tasks: 1 executed, 29 up-to-date
Exit Code: 0
```

O Gradle repetiu apenas os avisos preexistentes de diferença de versão de NDK e recursos depreciados; eles não impediram a geração do manifesto e não foram alterados por esta tarefa.

## Verificação de suporte no Galaxy S25+

O Galaxy S25+ estava conectado, autorizado por ADB e respondeu aos comandos de diagnóstico do Backup Manager. A plataforma reportou o Backup Manager como habilitado e ativado e listou transportes de backup, inclusive um transporte local de depuração, transportes de transferência entre dispositivos e o transporte de backup em nuvem configurado no aparelho.

Essa disponibilidade de comandos **não** torna seguro um ciclo end-to-end nesta tarefa. Um ciclo que demonstre restauração exige uma origem de backup isolada, uma restauração que substitua dados do pacote e, para `device-transfer`, um ambiente de origem/destino apropriado. O pacote debug instalado é o mesmo utilizado para as evidências físicas E0/E2; não foi criado um `applicationId` descartável, emulador isolado nem segundo dispositivo para essa finalidade.

Para preservar os dados e as evidências existentes, esta tarefa não executou:

- `bmgr backupnow`, `bmgr fullbackup`, `bmgr restore`, `bmgr wipe`, `bmgr init` ou troca de transporte;
- `pm clear`, desinstalação, restauração parcial ou acesso/manipulação direta do sandbox;
- backup em nuvem com os dados do aplicativo;
- transferência real para outro dispositivo.

## Classificação obrigatória

| Cenário | Resultado |
|---|---|
| Exclusões legadas de banco, sidecars e JPEGs | **Aprovado tecnicamente** por inspeção e teste automatizado |
| Exclusões Android 12+ em `cloud-backup` | **Aprovado tecnicamente** por inspeção e teste automatizado |
| Exclusões Android 12+ em `device-transfer` | **Aprovado tecnicamente** por inspeção e teste automatizado |
| Referências no manifesto debug mesclado | **Aprovado tecnicamente** por artefato gerado |
| Ciclo físico controlado de backup/restauração | **Não executado** |
| Transferência física entre dispositivos | **Não executado** |

O ciclo físico permanece **não executado**, e não é apresentado como aprovação de runtime. Para executá-lo futuramente sem expor ou sobrescrever dados existentes, será necessário um ambiente isolado e descartável (por exemplo, pacote de teste/emulador com transporte local) e, para transferência, dois dispositivos preparados. O Validation Gate E2 permanece pendente.
