# Evidência das tarefas 75.4–75.6 — Atualização da toolchain E5

## 75.4 SDK e Gradle

### Ambiente global

| Componente | Ação | Resultado |
|---|---|---|
| Flutter (`C:\dev\flutter`) | `git fetch` da tag `3.32.8` e `git checkout 3.32.8` | Flutter `3.32.8` (framework `edada7c56e`, engine `ef0cd00091`), Dart `3.8.1`, DevTools `2.45.1`. O canal aparece como `[user-branch]` porque o checkout é por tag. |
| Android SDK | `sdkmanager --install "platforms;android-36" "build-tools;36.0.0"` | `android-36` e build-tools `36.0.0` instalados. |
| Android NDK | Baixado automaticamente pelo Gradle no primeiro build | NDK `26.3.11579264` (padrão do Flutter 3.32). |
| CMake | Baixado automaticamente pelo Gradle no primeiro build | CMake `3.22.1`. |
| JDK | Sem mudança | Java `21.0.2`. |

Reversão: checkout da tag `3.24.3` em `C:\dev\flutter` (ver [task-75.2-e5-sdk-installation-method.md](task-75.2-e5-sdk-installation-method.md)). Os pacotes do Android SDK novos podem permanecer instalados.

### Arquivos do projeto

| Arquivo | Antes | Depois |
|---|---|---|
| `android/settings.gradle` | AGP `8.5.1`, Kotlin `1.8.22` | AGP `8.11.1`, Kotlin `2.2.20` |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle `8.7` | Gradle `8.14` |
| `android/app/build.gradle` | `compileSdk`, `minSdk` e `targetSdk` herdados do Flutter | `compileSdk = 36`, `minSdk = 24`, `targetSdk = 34`, explícitos |

O `pubspec.yaml` mantém `sdk: ^3.5.3`. `sourceCompatibility`, `targetCompatibility` e `jvmTarget` permanecem `1.8`; o build só emite avisos de opção obsoleta (`source value 8 is obsolete`), sem falha.

## 75.5 Pins

- `path_provider`: `2.1.4` → `2.1.5` no `pubspec.yaml` e em `test/architecture/e2_dependency_policy_test.dart`, com comentário de justificativa (exigência `^2.1.5` do `ultralytics_yolo`).
- Nenhum outro pin direto mudou. `ultralytics_yolo` não foi adicionado (tarefa 77).
- `pubspec.lock`: 26 mudanças transitivas causadas pelo SDK novo (pacotes fixados pelo `flutter_test` e pela toolchain, como `vm_service`, `test_api`, `matcher` e `leak_tracker`; remoção de `_macros` e `macros`), além de `path_provider` 2.1.5.

## 75.6 Correções e validação

### Única correção de código

`lib/operation/operation_theme.dart:44`: `const CardTheme(...)` → `const CardThemeData(...)`. No Flutter 3.32, `ThemeData.cardTheme` exige `CardThemeData`. Os mesmos valores (cor, elevação e margem) foram mantidos, sem mudança de comportamento.

### Resultados na toolchain nova

| Verificação | Comando | Resultado |
|---|---|---|
| Formatação | `dart format --output=none --set-exit-if-changed lib test` | Aprovada: `Formatted 165 files (0 changed)`. |
| Análise estática | `flutter analyze` | Antes da correção: 1 erro (`CardTheme`). Depois: `No issues found!`. |
| Suíte completa | `flutter test` | Aprovada: `All tests passed!` com **819 testes**, o mesmo total da baseline 75.1. |
| Build Android debug | `flutter build apk --debug` | Aprovado: `Built build\app\outputs\flutter-apk\app-debug.apk`. |

As mensagens `Unsupported queue schema version: found 3, supported 2` e `table accepted_occurrence_anchor already exists` nos logs da suíte vêm de testes negativos que provocam esses erros de propósito (por exemplo, `queue_database_test.dart`: "refuses a future schema version without resetting its data"). Os testes passam.

### APK

| Campo | Valor |
|---|---|
| APK | `build\app\outputs\flutter-apk\app-debug.apk` |
| Tamanho | `207437204` bytes |
| SHA-256 | `254AA47F5490D863DA489AB904409F916187ED67404CC6CC9FC391C8BEE6A847` |
| `compileSdkVersion` | 36 |
| `targetSdkVersion` | 34 |

O APK debug cresceu de ~126 MB (75.1) para ~207 MB. A diferença está nas bibliotecas nativas de debug do engine Flutter 3.32 para as quatro ABIs (`lib/arm64-v8a` 55,2 MB, `lib/x86_64` 41,5 MB, `lib/x86` 41,3 MB, `lib/armeabi-v7a` 34,8 MB, comprimidos). Nenhum asset ou código novo foi adicionado.

Aviso não bloqueante: alguns plugins pedem NDK `27.0.12077973`; o build usa o `26.3.11579264` padrão do Flutter 3.32. É o mesmo tipo de aviso já registrado na baseline (antes pedia `26.1.10909125`) e não foi alterado.

### Manifestos e backup

| Atributo | Debug (APK) | Release (manifesto mesclado) | E4 (72.3) |
|---|---|---|---|
| `debuggable` | `true` | ausente | igual |
| `usesCleartextTraffic` | `false` | `false` | igual |
| `networkSecurityConfig` | presente (config de debug) | ausente | igual |
| `fullBackupContent` | `@xml/backup_rules` | `@xml/backup_rules` | igual |
| `dataExtractionRules` | `@xml/data_extraction_rules` | `@xml/data_extraction_rules` | igual |
| Permissões | INTERNET, CAMERA, FINE/COARSE_LOCATION, `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | idem | igual |
| minSdk / targetSdk | 24 / 34 | 24 / 34 | 21 / 34 (minSdk elevado por D1) |

Os componentes `<service>` e `<receiver>` do manifesto mesclado vêm de bibliotecas já presentes na E4 (`androidx.camera.core.impl.MetadataHolderService`, `com.baseflow.geolocator.GeolocatorLocationService`, `androidx.profileinstaller.ProfileInstallReceiver`). O manifesto principal do app continua sem `<service>` e `<receiver>`. As regras de backup e transferência não foram alteradas.

## Resultado

**Tarefas 75.4–75.6 aprovadas.** A toolchain Flutter 3.32.8 / AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20 / compileSdk 36 compila, analisa e passa os 819 testes E0–E4. Única mudança de código: a troca de API `CardTheme` → `CardThemeData`. Permissões e regras de backup não mudaram. Nenhum código ou dependência E5 entrou. A regressão física no S25+ é a tarefa 76.1.
