# Evidência — Tarefa 1.6: Android SDK e componentes de build

## Resultado

**Status: bloqueio / etapa manual.** O Android SDK e os principais componentes locais necessários a um build Android estão instalados e são encontrados pelo Flutter, mas a Android toolchain não está integralmente pronta porque `flutter doctor -v` informa que algumas licenças Android não foram aceitas.

Nenhuma licença foi aceita e nenhuma instalação, atualização ou reconfiguração foi executada. A regularização das licenças deve ser uma ação manual/autorizada antes de considerar a toolchain aprovada para o build.

## Ambiente inspecionado

- Sistema executor: Windows (`win32`), a partir da raiz do repositório mobile.
- Flutter executado por: `C:\dev\flutter\bin\flutter.bat`.
- SDK efetivamente localizado pelo Flutter: `C:\Users\vitor\AppData\Local\Android\sdk`.
- `ANDROID_SDK_ROOT`: não definido.
- `ANDROID_HOME`: não definido.
- O SDK foi encontrado pelo caminho padrão do Windows; as variáveis ausentes não impediram sua descoberta pelo Flutter.

## Componentes encontrados

- Diretório do Android SDK: presente.
- Plataformas instaladas com `android.jar`:
  - `android-31`;
  - `android-34`.
- Build Tools instalados:
  - `30.0.3`;
  - `33.0.1`;
  - `35.0.0`.
- Em cada versão acima foram encontrados os componentes verificados: `aapt2`, `d8`, `zipalign` e `apksigner`.
- Command-line Tools: `cmdline-tools/latest` presente, incluindo `sdkmanager.bat`.
- Diretório local de licenças do SDK: presente.
- Java encontrado pelo Flutter/PATH: Oracle Java `21.0.2` LTS, em `C:\Program Files\Common Files\Oracle\Java\javapath\java.exe`.

O diagnóstico do Flutter selecionou **Platform `android-34`** e **Build Tools `35.0.0`**, registrando o SDK como versão `35.0.0`.

## Diagnóstico relevante do Flutter

```text
[!] Android toolchain - develop for Android devices (Android SDK version 35.0.0)
    • Android SDK at C:\Users\vitor\AppData\Local\Android\sdk
    • Platform android-34, build-tools 35.0.0
    • Java binary at: C:\Program Files\Common Files\Oracle\Java\javapath\java.exe
    • Java version Java(TM) SE Runtime Environment (build 21.0.2+13-LTS-58)
    ! Some Android licenses not accepted. To resolve this, run: flutter doctor --android-licenses
```

`flutter doctor -v` terminou com código de saída `0`, porém classificou a Android toolchain com aviso (`[!]`). O Android Studio também não está instalado, mas essa ausência não foi tratada como falta dos componentes de linha de comando inventariados acima; o bloqueio observado para a toolchain Android é o aceite pendente de licenças.

## Limites desta verificação

- Nenhum projeto Flutter foi criado e nenhum build foi iniciado, conforme o escopo da tarefa 1.6.
- Gradle wrapper e compatibilidade de dependências específicas não puderam ser exercitados porque o projeto ainda não existe; essas verificações pertencem às tarefas posteriores após liberação do bloqueio.
- ADB e reconhecimento do Samsung Galaxy S25+ não foram verificados, pois pertencem às tarefas 1.7 e 1.8.
- Não foram executados comandos de instalação, atualização, aceite de licenças ou reconfiguração de Flutter, Android SDK, Gradle, Java, ADB, drivers USB ou WSL.

## Ação manual necessária

Obter autorização explícita e então aceitar/revisar as licenças Android no ambiente Windows usado pelo Flutter. Depois, repetir `flutter doctor -v` e confirmar que a Android toolchain deixa de apresentar o aviso de licenças antes de liberar a criação e o build Android.
