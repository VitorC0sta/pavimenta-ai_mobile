# Evidência da tarefa 32.2 — Metadados do build e hash do APK

## Escopo

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`
- Subtarefa exclusiva: **32.2 — Registrar versões da toolchain, resultado do build, caminho do artefato e hash criptográfico do APK**.
- Contexto normativo consultado: `requirements.md`, `design.md`, `tasks.md` e a evidência da tarefa 32.1 no spec `mvp-app-flutter`.
- Limite preservado: somente registro dos metadados do APK já produzido pela tarefa 32.1; nenhuma nova compilação, inspeção de identidade/escopo das tarefas 32.3–32.4, instalação física ou funcionalidade E2–E5 foi executada.

O diretório do spec não contém arquivo `.config`; conforme a convenção das evidências anteriores, esta execução foi tratada como spec comum, não bugfix.

## Resultado do build de origem

A tarefa 32.1 executou uma única vez, sem `--dart-define`, URL de produção, API key ou configuração de integração:

```powershell
flutter build apk --debug
```

Resultado conclusivo registrado pela tarefa 32.1:

```text
Running Gradle task 'assembleDebug'... 33.1s
√ Built build\app\outputs\flutter-apk\app-debug.apk
Exit Code: 0
```

Status do build: **sucesso**, código de saída `0`.

A tarefa 32.1 registrou também um aviso não bloqueante de versão do Android NDK: o projeto declara `23.1.7779620`, enquanto plugins resolvidos solicitam `26.1.10909125`. O build foi concluído apesar do aviso. Nenhuma configuração foi alterada nesta subtarefa.

## Versões da toolchain

Comandos executados para registrar o ambiente atual associado ao artefato:

```powershell
flutter --version
flutter doctor -v
java -version
.\android\gradlew.bat --version
```

Versões registradas:

| Componente | Versão/detalhe |
|---|---|
| Flutter | `3.24.3`, canal `stable`, framework revision `2663184aa7` |
| Flutter Engine | revision `36335019a8` |
| Dart | `3.5.3` |
| DevTools | `2.37.3` |
| Android SDK | `34.0.0` em `C:\Users\vitor\AppData\Local\Android\sdk` |
| Android Platform | `android-34` |
| Android Build Tools | `34.0.0` |
| Java/JVM | Oracle Java `21.0.2+13-LTS-58`, 64-bit |
| Gradle Wrapper | `8.7`, revision `650af14d7653aa949fce5e886e685efc9cf97c10` |
| Kotlin reportado pelo Gradle | `1.9.22` |
| Groovy reportado pelo Gradle | `3.0.17` |
| Ant reportado pelo Gradle | `1.10.13` |
| Ambiente | Windows 11/Windows `10.0.26300.9711`, `amd64` |

`flutter doctor -v` terminou com código `0`, mas registrou dois avisos ambientais já existentes: algumas licenças Android não aceitas e Android Studio ausente. Esses avisos não impediram o build já concluído e não foram corrigidos ou reconfigurados nesta tarefa.

## Artefato registrado

Caminho absoluto confirmado no filesystem:

```text
C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile\build\app\outputs\flutter-apk\app-debug.apk
```

Metadados confirmados sem reconstruir o APK:

| Campo | Valor |
|---|---|
| Nome | `app-debug.apk` |
| Tamanho | `109710705` bytes |
| Última modificação | `2026-10-22T11:19:25.4117618-03:00` |
| Algoritmo criptográfico | `SHA-256` |
| Hash | `FA8535852E4E5151B9F59EAB36D89047E54E4BE41DEA80F7347BDF74E1E2349F` |

## Comandos de verificação do artefato

A presença, os metadados e o hash foram obtidos com:

```powershell
$apk = Resolve-Path "build\app\outputs\flutter-apk\app-debug.apk" -ErrorAction Stop
$item = Get-Item $apk
$hash = Get-FileHash -Algorithm SHA256 $apk
```

O SHA-256 foi conferido por uma segunda implementação disponível no Windows:

```powershell
certutil -hashfile "build\app\outputs\flutter-apk\app-debug.apk" SHA256
```

Resultados normalizados:

```text
PowerShell SHA-256: FA8535852E4E5151B9F59EAB36D89047E54E4BE41DEA80F7347BDF74E1E2349F
CertUtil SHA-256:   fa8535852e4e5151b9f59eab36d89047e54e4be41dea80f7347bdf74e1e2349f
Correspondência:   True
Exit Code:          0
```

A diferença entre maiúsculas e minúsculas é apenas de representação hexadecimal; os valores são idênticos.

## Conclusão

**SUCESSO.** As versões da toolchain, o resultado bem-sucedido do build debug, o caminho absoluto do APK e seu hash criptográfico SHA-256 foram registrados e verificados. O APK não foi reconstruído nem modificado nesta subtarefa. Nenhuma tarefa irmã 32.3/32.4 ou etapa posterior à E1 foi executada.