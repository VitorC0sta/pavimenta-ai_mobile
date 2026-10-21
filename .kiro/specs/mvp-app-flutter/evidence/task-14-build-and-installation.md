# Evidência — Tarefa 14: build e preparação da instalação

## Resultado objetivo

**Status atual: build Android debug gerado e instalado com sucesso no Samsung Galaxy S25+.** O aparelho foi reconfirmado no estado ADB `device`, o APK foi instalado com `adb install -r` e o `applicationId` `com.vitor.pavimenta_ai_mobile` foi confirmado por inspeção do APK e consulta ao gerenciador de pacotes do aparelho.

O aplicativo **não foi aberto** e nenhuma observação física foi feita. Esta evidência não executa nem aprova o Validation Gate da tarefa 15. Câmera, GPS, rede, permissões, responsividade e ciclo de vida permanecem **não validados fisicamente**.

## Causa raiz e correção aplicada

A falha histórica ocorreu em `:camera_android_camerax:compileDebugJavaWithJavac` durante `JdkImageTransform`, ao processar `core-for-system-modules.jar` com:

- Android Gradle Plugin `8.1.0`;
- Gradle `8.3`;
- Oracle JDK `21.0.2`.

A investigação local confirmou que não há JDK 17 completo disponível para reutilização. O caminho alternativo `C:\Program Files\Android\jdk` não contém um Java executável válido. Também confirmou que Android Gradle Plugin `8.5.1` e Gradle `8.7` já estavam integralmente disponíveis no cache local.

A causa raiz foi confirmada operacionalmente como incompatibilidade da configuração antiga AGP/Gradle com o processamento modular do JDK 21: o mesmo JDK 21.0.2 concluiu o build após a atualização local do AGP e do Gradle.

Correção mínima aplicada:

- `android/settings.gradle`: Android Gradle Plugin `8.1.0` → `8.5.1`;
- `android/gradle/wrapper/gradle-wrapper.properties`: Gradle `8.3-all` → `8.7-bin`.

A seleção de Java foi feita somente no processo de build com `JAVA_HOME=C:\Program Files\Java\jdk-21`; nenhum caminho Java específico da máquina foi persistido no projeto. Não houve instalação ou atualização global de Flutter, Java, Gradle, ADB, drivers, Windows ou WSL.

## URL diagnóstica fornecida fora do repositório

- Origem do valor: selecionado e verificado externamente durante a sessão; não lido de arquivo do projeto e não gravado no repositório.
- Representação sanitizada: `https://<servico-publico-de-teste>/<endpoint-de-status>`.
- Finalidade confirmada: serviço público destinado a testes de clientes HTTP, sem semântica de produção ou ocorrência.
- Verificação operacional: resposta HTTPS `204`, com corpo vazio/não utilizado.
- Estrutura verificada: HTTPS absoluto; sem usuário/senha; sem query string; sem fragmento; caminho diferente de `/api/v1/occurrences`.
- Credenciais: nenhuma API key, token, cookie configurado, usuário ou senha foi fornecido.
- Injeção no build: variável de ambiente temporária do processo, expandida em `--dart-define` e removida no bloco `finally` após o comando.
- Persistência: o valor funcional não foi escrito em código, configuração, documentação ou outro arquivo versionável. O APK contém necessariamente o valor recebido no `dart-define`, para uso exclusivo deste build de teste.

A confirmação de que o destino é de teste é operacional e humana; o aplicativo não tenta inferir se um host arbitrário pertence a produção.

## Histórico das tentativas de build

### Tentativa histórica anterior — falha de `JdkImageTransform`

Comando sanitizado:

```powershell
flutter build apk --debug "--dart-define=E0_DIAGNOSTIC_URL=<URL_HTTPS_EXCLUSIVA_DE_TESTE>"
```

- Resultado: falha, código `1`.
- Duração informada: aproximadamente `43,2 s`.
- Falha: `:camera_android_camerax:compileDebugJavaWithJavac` / `JdkImageTransform` usando AGP 8.1.0, Gradle 8.3 e JDK 21.0.2.
- APK: não produzido.

### Primeira execução da retomada autorizada — variável Java inválida

A primeira execução após a correção de AGP/Gradle terminou antes da compilação porque o processo herdou temporariamente `JAVA_HOME=C:\Program Files\Android\jdk`, caminho inválido usado durante uma inspeção anterior.

- URL temporária: validada externamente; resposta `204`.
- Resultado: falha, código `1`.
- Duração da tarefa Gradle informada: `65 ms`.
- Motivo: `JAVA_HOME` inválido; nenhuma compilação Java/Android foi iniciada e nenhum APK foi produzido.
- Correção: seleção explícita, somente no processo, do Oracle JDK existente em `C:\Program Files\Java\jdk-21`.

### Segunda execução da retomada — sucesso

Comando sanitizado equivalente:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21'
$env:E0_DIAGNOSTIC_URL = '<URL_HTTPS_EXCLUSIVA_DE_TESTE>'
try {
  flutter build apk --debug "--dart-define=E0_DIAGNOSTIC_URL=$env:E0_DIAGNOSTIC_URL"
} finally {
  Remove-Item Env:E0_DIAGNOSTIC_URL -ErrorAction SilentlyContinue
}
```

- Resultado: sucesso, código `0`.
- Gradle task: `assembleDebug`.
- Duração informada pelo Flutter: aproximadamente `146,5 s`.
- Avisos não bloqueantes: source/target Java 8 obsoletos e `ndkVersion` do projeto inferior ao indicado pelos plugins. Nenhuma alteração de NDK foi necessária para gerar o APK.
- Efeito automático observado: o Gradle provisionou Android SDK Build Tools `34.0.0` no SDK local durante o build porque esse componente não estava presente. Essa alteração ambiental não foi solicitada por comando separado nem ocultada; Build Tools `35.0.0` já existia. Não foi feita remoção posterior.

Contagem consolidada: uma tentativa histórica e duas execuções nesta retomada; somente a última alcançou e concluiu a compilação.

## APK produzido

- Caminho: `build/app/outputs/flutter-apk/app-debug.apk`.
- Tamanho: `90.075.154 bytes` (aproximadamente `85,90 MiB`).
- SHA-256: `E9FB2F248A46E713982C00C6A6A276293E1928C8B7485548E05EE5071548EA50`.
- `applicationId` inspecionado com `aapt`: `com.vitor.pavimenta_ai_mobile`.

## Toolchain efetivamente usada

- Ambiente executor: Windows `10.0.26300.9711` (`win32`), sem WSL.
- Flutter: `3.24.3`, canal `stable`, revisão `2663184aa7`.
- Dart: `3.5.3`.
- DevTools: `2.37.3`.
- Android Gradle Plugin: `8.5.1`.
- Gradle: `8.7`.
- Kotlin reportado pelo Gradle: `1.9.22`.
- Java: Oracle JDK `21.0.2` LTS, selecionado no processo por `JAVA_HOME`.
- Android SDK: `C:\Users\vitor\AppData\Local\Android\sdk`.
- Plataforma Android: `android-34`.
- Android Build Tools usados/disponibilizados pelo build: `34.0.0`; `35.0.0` já estava instalado.
- ADB: executável `platform-tools` do mesmo SDK Windows.
- Avisos de ambiente preservados: algumas licenças Android permanecem não aceitas e Android Studio não está instalado; isso não bloqueou este build.

## Instalação no Samsung Galaxy S25+

Antes da instalação, o aparelho foi localizado pelo modelo no mesmo ADB Windows e confirmado no estado `device`. O serial real foi usado somente no comando em memória e não foi registrado nesta evidência.

Comandos sanitizados equivalentes:

```powershell
adb devices
adb -s '<SERIAL_REAL>' install -r 'build\app\outputs\flutter-apk\app-debug.apk'
adb -s '<SERIAL_REAL>' shell pm list packages com.vitor.pavimenta_ai_mobile
```

Resultados sanitizados:

```text
ADB_TARGET_STATE=device
ADB_TARGET_MODEL=SM-S936B
Performing Streamed Install
Success
ADB_INSTALL_EXIT_CODE=0
PACKAGE_QUERY=package:com.vitor.pavimenta_ai_mobile
APP_LAUNCHED=false
```

Uma consulta secundária de caminho do pacote emitiu aviso de permissão do shell para um usuário Android auxiliar, mas retornou caminho presente. Isso não afetou a instalação: `adb install -r` retornou sucesso e a consulta principal confirmou o pacote. Nenhum identificador único do aparelho ou transporte foi persistido.

## Validações após a correção

- `flutter analyze`: sucesso, `No issues found`.
- `aapt dump badging`: confirmou `com.vitor.pavimenta_ai_mobile` no APK.
- `git diff --check`: sucesso, sem erro de whitespace.
- Build Android debug: sucesso.
- Instalação ADB: sucesso.
- Consulta do pacote instalado: sucesso.
- Abertura do aplicativo: **não executada**, pois pertence à validação física da tarefa 15.

## Arquivos e configurações alterados

- `android/settings.gradle` — versão do Android Gradle Plugin.
- `android/gradle/wrapper/gradle-wrapper.properties` — distribuição Gradle.
- `.kiro/specs/mvp-app-flutter/evidence/task-14-build-and-installation.md` — esta evidência consolidada.
- `.kiro/specs/mvp-app-flutter/evidence/task-14-physical-validation-checklist.md` — estado técnico de prontidão atualizado.

`tasks.md` não foi alterado.

## Limites e bloqueios restantes

Não há bloqueio técnico restante para iniciar posteriormente a tarefa 15. Permanecem deliberadamente pendentes e fora desta tarefa:

- abrir o aplicativo e observar a tela inicial;
- validar ordem e comportamento das permissões;
- validar preview da câmera traseira;
- validar GPS, precisão e velocidade;
- executar e observar o diagnóstico HTTPS dentro do aplicativo;
- validar indisponibilidades, responsividade e ciclo de vida;
- reunir evidências físicas e obter decisão explícita do Validation Gate.

Build e instalação isoladamente **não aprovam câmera, GPS ou rede** e não abrem nem aprovam o Validation Gate.
