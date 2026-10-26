# Evidência da tarefa 50.4 — Instalação do APK debug E2 no Galaxy S25+

## Escopo executado

- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Subtarefa: **50.4 — Instalar o APK no Galaxy S25+ pelo ambiente Flutter/ADB aprovado quando disponível; se indisponível, registrar bloqueio manual sem alterar toolchain ou presumir validação física.**
- Documentos consultados: `requirements.md`, `design.md` e `tasks.md` da spec `mvp-app-flutter`.
- O diretório da spec não contém `.config`; as evidências anteriores da E2 (`task-40.5` e `task-50.2`) já classificam o fluxo como spec regular, não bugfix.
- Nenhum código, dependência, manifesto, configuração Android, SDK, Flutter, Java, Gradle, driver, WSL ou ADB foi alterado.

## Artefato E2 disponível para instalação

| Campo | Evidência |
|---|---|
| APK debug | `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile\build\app\outputs\apk\debug\app-debug.apk` |
| Tamanho | `109795650` bytes |
| SHA-256 | `07004DF75C0AE00BC89EACF4BDA2C69E747F8357ACCC171000CE67B330F0F016` |
| Identidade configurada | `com.vitor.pavimenta_ai_mobile` |

O SHA-256 acima foi recalculado diretamente do APK de `build\app\outputs\apk\debug` nesta execução e coincide com a evidência da tarefa 50.2. `android/app/build.gradle` mantém `namespace` e `applicationId` exatamente como `com.vitor.pavimenta_ai_mobile`.

O manifesto principal referencia `@xml/backup_rules` e `@xml/data_extraction_rules`, com `usesCleartextTraffic="false"`. As duas políticas excluem conjuntamente a base E2, sidecars (`-journal`, `-wal`, `-shm`) e `e2_queue_images_v1/`; em `data_extraction_rules.xml`, esse conjunto está presente tanto em `cloud-backup` quanto em `device-transfer`. A evidência já aprovada da tarefa 50.3/40.5 permanece a fonte para a inspeção do APK/manifesto mesclado e do escopo negativo E0–E2; esta tarefa não a substitui nem reexecuta outros escopos.

## Verificação do ambiente aprovado

Ambiente Windows, sem WSL:

- Flutter executável: `C:\dev\flutter\bin\flutter.bat`.
- ADB do Android SDK aprovado: `C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe`.
- Data/hora da enumeração: `2026-10-24T16:51:34.3782754-03:00`.

Resultados observados:

```text
flutter devices --machine
=> Windows, Chrome e Edge somente; nenhum destino Android.

C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe devices -l
List of devices attached
ADB_DEVICES_EXIT_CODE=0
```

O ADB respondeu corretamente, mas não listou qualquer serial Android — nem `device`, `unauthorized` ou `offline`. Portanto, não há Galaxy S25+ acessível/autorizado neste ambiente no momento. Como o Flutter também não listou Android, não existe alvo aprovado para uma instalação por Flutter/ADB.

## Resultado: bloqueio manual explícito

**A instalação não foi executada.** Não foi emitido `adb install`, `flutter install`, `flutter run`, nem qualquer comando de abertura ou validação física. Assim, esta evidência **não** afirma instalação, abertura, funcionamento físico ou aprovação do Validation Gate E2.

O bloqueio é limitado à indisponibilidade atual do aparelho no ambiente Windows aprovado; ele não é falha do APK e não autoriza alteração de toolchain.

### Ação manual necessária antes de repetir somente esta subtarefa

1. Conectar o Galaxy S25+ ao Windows por cabo/porta com transferência de dados.
2. Desbloquear o aparelho, habilitar depuração USB e aceitar a autorização RSA deste computador, se solicitada.
3. Confirmar, no mesmo ambiente Windows, que `adb.exe devices -l` apresenta um serial com estado `device` e que `flutter devices` lista o destino Android correspondente.
4. Repetir a instalação do APK com SHA-256 acima pelo Flutter/ADB já aprovado e registrar apenas o resultado da instalação. A validação física continua pertencendo às tarefas 51 e 52.

## Conclusão

A tarefa 50.4 foi executada até a condição de bloqueio prevista: o APK debug E2 reproduzível, identidade e políticas de backup foram identificados, mas a instalação no Galaxy S25+ está **bloqueada manualmente** pela ausência de dispositivo Android enumerado pelo Flutter/ADB aprovado. Nenhuma mudança de toolchain foi realizada e nenhuma validação física foi presumida.
