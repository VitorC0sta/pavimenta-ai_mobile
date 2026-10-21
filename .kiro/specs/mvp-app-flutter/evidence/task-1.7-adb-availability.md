# Evidência — Tarefa 1.7: disponibilidade do ADB no ambiente do Flutter

## Resultado

**Status: sucesso.** O Flutter executa no ambiente Windows e o ADB do Android SDK está presente e executável nesse mesmo ambiente.

O comando `adb` não está publicado no `PATH` da sessão, mas isso não constitui ausência do ADB: o executável localizado no SDK Android usado pelo Flutter foi chamado diretamente e terminou com código de saída `0`.

## Ambiente executor confirmado

- Sistema: Microsoft Windows `10.0.26300` (`win32`).
- Shell da verificação: Windows PowerShell Desktop `5.1.26100.9711`.
- Flutter resolvido nessa sessão como aplicação Windows: `C:\dev\flutter\bin\flutter.bat`.
- Android SDK já localizado pelo Flutter e confirmado na tarefa 1.6: `C:\Users\vitor\AppData\Local\Android\sdk`.
- Não foi usado WSL nesta verificação.

## ADB verificado no mesmo ambiente

- Resolução de `adb` pelo `PATH`: não encontrado.
- Executável do SDK: `C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe`.
- Arquivo do executável: presente.
- Execução direta: sucesso, código de saída `0`.
- Android Debug Bridge: `1.0.41`.
- Versão do pacote: `35.0.2-12147458`.
- Plataforma reportada pelo próprio ADB: Windows `10.0.26300`.

## Saída relevante registrada

```text
OS=Microsoft Windows 10.0.26300
PowerShellEdition=Desktop
PowerShellVersion=5.1.26100.9711
FlutterCommandType=Application
FlutterExecutable=C:\dev\flutter\bin\flutter.bat
ADBOnPath=not-found
AndroidSdkPath=C:\Users\vitor\AppData\Local\Android\sdk
ADBExecutable=C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe
ADBExecutableExists=True
Android Debug Bridge version 1.0.41
Version 35.0.2-12147458
Installed as C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe
Running on Windows 10.0.26300
ADBVersionExitCode=0
```

## Conclusão e limites

A disponibilidade requerida pela tarefa 1.7 está comprovada: Flutter e ADB são executáveis Windows e o ADB do SDK acessível ao Flutter responde corretamente no mesmo ambiente executor.

Nenhum bloqueio específico de disponibilidade do ADB foi identificado. A ausência de `adb` no `PATH` foi apenas registrada; nenhuma alteração de `PATH` é necessária para comprovar esta tarefa e nenhuma reconfiguração foi realizada.

Não foram executados `adb devices`, `flutter devices` ou qualquer outro comando de enumeração/acesso ao Samsung Galaxy S25+, pois reconhecimento do aparelho pertence exclusivamente à tarefa 1.8. Também não foi realizada comparação Windows/WSL, reservada à tarefa 1.9.

Nenhum projeto foi criado. Nenhuma instalação, atualização ou reconfiguração de Flutter, Android SDK, Gradle, Java, ADB, drivers USB, WSL ou ferramenta global foi executada. Nenhum teste automatizado foi criado ou executado, conforme as regras da E0.
