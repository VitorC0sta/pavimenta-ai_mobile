# Evidência da tarefa 51.1 — Preservação E0/E1 e atualização do APK E2

## Escopo executado

- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Subtarefa: **51.1 — Preservar o pacote histórico E0/E1, instalar E2 como atualização quando possível e registrar toolchain, hash, dispositivo e ausência de configuração de ocorrências.**
- Documentos consultados antes da execução: `requirements.md`, `design.md` e `tasks.md` da spec `mvp-app-flutter`.
- O diretório da spec não contém `.config` nem `.config.kiro`; trata-se de uma spec regular, não de bugfix.
- Limite: esta evidência não altera nem reclassifica evidências históricas E0/E1; não executa 51.2–51.9, não testa fila/captura, não revalida fisicamente E0/E1 e não aprova o Validation Gate E2.

## Preservação do pacote histórico E0/E1

A consulta anterior à instalação encontrou o mesmo pacote aprovado, `com.vitor.pavimenta_ai_mobile`, já presente no Galaxy S25+:

| Campo antes da atualização | Valor |
|---|---|
| `versionName` | `1.0.0` |
| `versionCode` | `1` |
| `firstInstallTime` | `2026-10-22 15:53:08` |
| `lastUpdateTime` | `2026-10-22 15:53:08` |

O APK E2 foi aplicado somente pelo modo de substituição preservadora `adb install -r`, sem `adb uninstall`, `pm clear`, limpeza de dados ou remoção do pacote. Após a instalação, `firstInstallTime` permaneceu inalterado em `2026-10-22 15:53:08`, enquanto `lastUpdateTime` mudou para `2026-10-24 16:59:39`. Essa diferença registra que o Android atualizou o pacote existente, em vez de criar uma instalação limpa.

As evidências históricas E0/E1, incluindo `task-15-validation-gate.md` e `task-34.6-validation-gate.md`, foram somente lidas e permanecem inalteradas. Não foi executada qualquer modificação nos seus conteúdos.

## APK E2 instalado

| Campo | Valor |
|---|---|
| Pacote | `com.vitor.pavimenta_ai_mobile` |
| APK usado | `build\app\outputs\flutter-apk\app-debug.apk` |
| Tamanho | `109795650` bytes |
| SHA-256 | `07004DF75C0AE00BC89EACF4BDA2C69E747F8357ACCC171000CE67B330F0F016` |
| Resultado de instalação | `Success` |
| `versionName` após instalação | `1.0.0` |
| `versionCode` após instalação | `1` |
| `firstInstallTime` após instalação | `2026-10-22 15:53:08` |
| `lastUpdateTime` após instalação | `2026-10-24 16:59:39` |

O hash foi recalculado localmente com `Get-FileHash -Algorithm SHA256` e coincide com `evidence/task-50.2-build-metadata-and-sha256.md`.

## Toolchain e dispositivo observados

| Item | Valor observado |
|---|---|
| Ambiente executor | Windows, sem WSL |
| Flutter | `3.24.3` stable (`2663184aa7`) |
| Dart | `3.5.3` |
| Android SDK | `34.0.0`, plataforma/build-tools `34` |
| Java | `21.0.2` |
| ADB efetivamente usado | `C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe` |
| Fabricante | `samsung` |
| Modelo | `SM-S936B` (Galaxy S25+) |
| Serial ADB | `RQGL701ZV7Z` |
| Estado ADB | `device` |
| Android | `17`, API `37` |

`flutter devices` também listou o destino Android `SM S936B` com o serial acima. `flutter doctor -v` identificou licenças Android pendentes e Android Studio ausente; não foram aceitas licenças, instalados componentes ou alterada qualquer configuração de toolchain nesta tarefa.

## Ausência de configuração de ocorrências

A inspeção estática de `lib/**/*.dart` não encontrou `BASE_URL`, `DEVICE_API_KEY`, `flutter_secure_storage`, API key, credencial, `Authorization`, `multipart`, endpoint de ocorrências, tela de configuração de ocorrências ou armazenamento de configuração.

Os únicos resultados aparentados foram classificados e excluídos corretamente:

1. `lib/e0/diagnostic_http_client.dart` contém somente a **rejeição** do caminho `/api/v1/occurrences` pelo diagnóstico HTTPS histórico E0; não configura nem chama esse endpoint.
2. `AppSettingsPort` e `OperationalAppSettings` abrem as configurações Android exclusivamente para recuperação manual de permissões de câmera/localização após negação permanente; não representam configuração de ocorrências, URL ou credencial.

`pubspec.yaml` contém os pins E0–E2 aprovados (`camera`, `geolocator`, `image`, `uuid`, `wakelock_plus`, `path_provider`, `sqflite`, `crypto`, `glados` e `sqflite_common_ffi` de desenvolvimento), sem pacote de armazenamento seguro, cliente HTTP de ocorrências, envio ou configuração E3.

## Comandos e verificações executados

```powershell
flutter --version
flutter doctor -v
flutter devices
Get-FileHash build\app\outputs\flutter-apk\app-debug.apk -Algorithm SHA256
C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe devices -l
C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe -s RQGL701ZV7Z shell dumpsys package com.vitor.pavimenta_ai_mobile
C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe -s RQGL701ZV7Z install -r build\app\outputs\flutter-apk\app-debug.apk
```

Foi emitido também um acionamento controlado de abertura via `adb shell monkey -p com.vitor.pavimenta_ai_mobile 1`, que retornou `Events injected: 1`. Esta subtarefa não o trata como observação física da interface e não infere qualquer cenário de 51.2–51.9 a partir dele.

## Resultado e limitações

**Sucesso no escopo da tarefa 51.1.** O APK E2 de hash registrado foi instalado como atualização do pacote histórico no Samsung Galaxy S25+, com preservação demonstrável do primeiro registro de instalação. Toolchain, dispositivo e ausência de configuração de ocorrências foram registrados de forma sanitizada.

A validação física de inicialização da fila, pendências, captura, recuperação, integridade, JPEG, backup, regressão E0/E1 e escopo negativo adicional permanece exclusivamente nas subtarefas 51.2–51.9. O Validation Gate E2 continua pendente e não foi aprovado por esta instalação.