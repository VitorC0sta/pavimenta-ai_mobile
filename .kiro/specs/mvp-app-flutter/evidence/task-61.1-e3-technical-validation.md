# Evidência da tarefa 61.1 — Análise, testes, build e artefato E3

## Escopo

- Tarefa executada: **61.1 — Apresentar análise/testes/build, inspeção de dependências/manifests/backup, APK e hash E3.**
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- O diretório da spec não contém `.config`; é uma spec regular, não um bugfix.
- Limite observado: esta tarefa somente renovou e consolidou evidências técnicas do Gate E3. Não alterou código de produção, dependências, manifestos ou configuração Android. Não executou tarefas 61.2–61.6 nem iniciou E4/E5.

## Validação renovada

A execução única abaixo terminou com código de saída `0`:

```text
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
android\gradlew.bat -p android app:processDebugMainManifest app:processReleaseMainManifest
```

| Verificação | Resultado concreto |
|---|---|
| Formatação | `Formatted 94 files (0 changed) in 1.71 seconds.` |
| Análise estática | `No issues found! (ran in 50.5s)` |
| Suíte completa | `265` testes concluídos, com `All tests passed!` |
| Propriedades | A suíte incluiu propriedades E2 e E3, inclusive conjuntos de 80 e 120 entradas; todas passaram. |
| APK debug | `Built build\app\outputs\flutter-apk\app-debug.apk` |
| Manifestos por variante | `app:processDebugMainManifest` e `app:processReleaseMainManifest` concluíram com `BUILD SUCCESSFUL`. |

Durante um teste negativo de versão futura do schema E2, o runner registrou `Unsupported queue schema version: found 2, supported 1.` como comportamento esperado. A suíte permaneceu aprovada, portanto não é uma falha de validação.

O build reiterou o aviso conhecido de que plugins requerem NDK `26.1.10909125`, enquanto o projeto declara `23.1.7779620`. O aviso não bloqueou o APK nem o processamento dos manifestos. Nenhuma toolchain ou versão de NDK foi modificada.

## Dependências diretas inspecionadas

`pubspec.yaml` mantém pins funcionais exatos para as etapas E0–E3:

| Dependência | Versão |
|---|---:|
| `camera` | `0.11.0+2` |
| `geolocator` | `13.0.2` |
| `image` | `4.2.0` |
| `uuid` | `4.6.0` |
| `wakelock_plus` | `1.2.8` |
| `path_provider` | `2.1.4` |
| `shared_preferences` | `2.5.2` |
| `flutter_secure_storage` | `9.2.4` |
| `sqflite` | `2.4.1` |
| `crypto` | `3.0.7` |
| `glados` (desenvolvimento) | `1.1.7` |
| `sqflite_common_ffi` (desenvolvimento) | `2.3.4+4` |

`flutter_lints: ^4.0.0` é a constraint de lint do template, não um pin funcional E3. A inspeção automatizada de arquitetura passou e confirma que `shared_preferences` e `flutter_secure_storage` são permitidos apenas na infraestrutura E3. Ela também rejeita pacotes e implementação de transporte de ocorrências, worker, backoff, YOLO/TFLite e inferência antes das etapas E4/E5.

## Manifestos, transporte e backup

Os manifestos mesclados produzidos nesta execução foram inspecionados em:

- debug: `build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`;
- release: `build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`.

Ambos confirmam a identidade `com.vitor.pavimenta_ai_mobile`, versão `1.0.0` (código `1`), `minSdk=21`, `targetSdk=34`, permissões de câmera, localização precisa/aproximada e internet, e câmera não obrigatória.

| Controle | Debug | Release/produção |
|---|---|---|
| Cleartext global | Bloqueado por `android:usesCleartextTraffic="false"` | Bloqueado por `android:usesCleartextTraffic="false"` |
| Exceção de desenvolvimento | Referência exclusiva a `@xml/network_security_config_debug` | Ausente |
| HTTP permitido | Somente `localhost`, sem subdomínios, no XML debug | Nenhum |
| Regras de backup | `@xml/backup_rules` e `@xml/data_extraction_rules` | As mesmas duas referências |

A política legada e as seções Android 12+ `cloud-backup` e `device-transfer` excluem de forma simétrica:

- banco `e2_occurrence_queue_v1.db` e os sidecars `-journal`, `-wal` e `-shm`;
- diretório `e2_queue_images_v1/`;
- artefato protegido `pavimenta_ai_mobile_secure_storage.xml` no domínio `sharedpref`.

O teste `android_backup_policy_test.dart`, incluído na suíte aprovada, verifica tanto as exclusões quanto a correspondência dos paths relativos de banco/imagens com os componentes de produção. Este escopo prova as regras versionadas, o manifesto mesclado e o contrato relativo no runner host. Não substitui um ciclo real de backup, restauração ou transferência Android, que permanece uma limitação física já declarada.

## APK E3 rastreável

| Campo | Valor |
|---|---|
| Variante | `debug` |
| Caminho | `build\app\outputs\flutter-apk\app-debug.apk` |
| Tamanho | `125953478` bytes |
| Hash | `SHA-256` |
| SHA-256 | `175131A96F789807EEA81471A2EE1BFB4671E4487335E9BFC7426A6200360D9A` |

## Resultado da tarefa 61.1

**Aprovado tecnicamente no escopo de 61.1.** Formatação, análise, testes, build, dependências, manifestos mesclados, política de backup/transferência e integridade do APK foram apresentados com evidência sanitizada. Esta conclusão não aprova o Validation Gate E3 e não substitui as evidências e a decisão exigidas nas tarefas 61.2–61.6.
