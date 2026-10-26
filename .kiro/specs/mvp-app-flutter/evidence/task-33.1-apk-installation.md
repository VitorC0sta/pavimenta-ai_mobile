# Evidência — Tarefa 33.1: instalação do APK E1 no Galaxy S25+

## Resultado

**Status: instalação concluída com sucesso no Samsung Galaxy S25+.** O aparelho foi localizado pelo modelo `SM-S936B` no ambiente Windows Flutter/ADB já aprovado, com estado ADB `device`. O APK debug preparado pela tarefa anterior foi instalado com substituição habilitada e o pacote `com.vitor.pavimenta_ai_mobile` foi confirmado no usuário Android principal.

Esta evidência cobre somente a tarefa 33.1. O aplicativo **não foi aberto**, nenhuma funcionalidade foi observada fisicamente, nenhuma aprovação física foi declarada e as tarefas 33.2 em diante não foram executadas.

## Ambiente utilizado

- Ambiente executor: Windows, sem WSL.
- Flutter aprovado: `C:\dev\flutter\bin\flutter.bat`.
- ADB aprovado: `C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe`.
- Dispositivo reconhecido pelo ADB e Flutter: Samsung `SM-S936B` (Galaxy S25+).
- Estado ADB no momento da instalação: `device`.
- Verificação concluída em: `2026-10-22T10:34:18.1813282-03:00`.
- O serial único do aparelho foi usado somente em memória para direcionar o comando e foi omitido desta evidência.

## APK instalado

- Caminho: `build/app/outputs/flutter-apk/app-debug.apk`.
- Tamanho: `107871584` bytes.
- SHA-256: `6896EFDBFA40C80052B164B88B7DFFE9F201702C5CFDB9A4497A1F21D6D9B95B`.
- Pacote esperado e confirmado: `com.vitor.pavimenta_ai_mobile`.

## Comandos sanitizados equivalentes

```powershell
$adb = 'C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe'
$apk = 'C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile\build\app\outputs\flutter-apk\app-debug.apk'

& $adb devices -l
& 'C:\dev\flutter\bin\flutter.bat' devices
& $adb -s '<SERIAL_EM_MEMORIA>' install -r $apk
& $adb -s '<SERIAL_EM_MEMORIA>' shell pm list packages --user 0 com.vitor.pavimenta_ai_mobile
& $adb -s '<SERIAL_EM_MEMORIA>' shell pm path --user 0 com.vitor.pavimenta_ai_mobile
```

## Saída relevante sanitizada

```text
ADB_TARGET_STATE=device
ADB_TARGET_MODEL=SM-S936B
FLUTTER_ANDROID_TARGET=SM S936B (mobile)
Performing Streamed Install
Success
INSTALL_EXIT=0
package:com.vitor.pavimenta_ai_mobile
PACKAGE_QUERY_USER0_EXIT=0
PACKAGE_PATH_USER0_EXIT=0
APP_LAUNCHED=false
```

A primeira consulta ampla do pacote também percorreu um usuário Android auxiliar e emitiu uma advertência de permissão do shell para esse usuário. A verificação direcionada ao usuário principal (`--user 0`) terminou sem esse problema e confirmou tanto o nome quanto o caminho instalado do pacote.

## Limites preservados

- Nenhum rebuild foi executado; foi usado o APK já preparado.
- Nenhuma instalação, atualização ou reconfiguração de Flutter, Android SDK, Gradle, Java, ADB, drivers USB ou WSL foi realizada.
- O aplicativo não foi iniciado.
- Preview, câmera, GPS, velocidade, captura, cooldown, JPEG, lifecycle, wake lock, navegação, acessibilidade e regressão E0 não foram validados nesta tarefa.
- Esta instalação não constitui aprovação física da E1 nem execução do Validation Gate.
- Nenhuma atividade das tarefas 33.2, 33.3, 33.4, 33.5 ou 34 foi executada.
