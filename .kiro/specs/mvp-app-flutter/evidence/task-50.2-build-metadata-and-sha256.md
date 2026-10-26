# Evidência da tarefa 50.2 — Metadados, pins e SHA-256 do APK E2

## Escopo

- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Subtarefa executada: **50.2 — Registrar versões da toolchain, pins diretos, resultado, caminho, tamanho e SHA-256 do APK, preservando o `applicationId` aprovado.**
- Documentos consultados antes da execução: `requirements.md`, `design.md` e `tasks.md` do spec `mvp-app-flutter`.
- O diretório do spec não contém `.config`; portanto, esta é uma spec comum, não uma spec de bugfix.
- Limite preservado: esta subtarefa somente registra o APK debug já gerado pela 50.1. Não recompila o aplicativo, não inspeciona o manifesto/APK para o escopo da 50.3, não instala no aparelho (50.4) e não altera código, dependências, configuração Android ou evidências históricas E0/E1.

## Resultado do build de origem

A tarefa 50.1 está registrada como concluída em `tasks.md` e gerou o APK debug E2 em execução única, sem URL/API key de ocorrências nem configuração E3–E5. O artefato esperado está presente no caminho abaixo.

**Resultado registrado da 50.1: sucesso.** Esta subtarefa não repetiu o build; ela verificou os metadados do arquivo produzido, preservando o limite de responsabilidade entre as tarefas 50.1 e 50.2.

## Toolchain registrada

A consulta atual de `flutter --version` retornou:

| Componente | Versão/detalhe |
|---|---|
| Flutter | `3.24.3`, canal `stable`, framework revision `2663184aa7` |
| Flutter Engine | revision `36335019a8` |
| Dart | `3.5.3` |
| DevTools | `2.37.3` |

A evidência de toolchain E2 previamente registrada em `evidence/task-40.5-merged-debug-manifest-and-toolchain.md`, mantida sem alteração, identifica também o ambiente usado pelo projeto como Windows, Android SDK `34.0.0`/platform-build tools `34` e Java `21.0.2`. O wrapper versionado continua apontando para Gradle `8.7` em `android/gradle/wrapper/gradle-wrapper.properties`.

A consulta `flutter doctor -v` desta execução foi interrompida pelo executor antes de produzir uma saída utilizável; ela não instalou, atualizou ou reconfigurou nenhum componente. Assim, este registro não a apresenta como uma nova validação bem-sucedida e preserva o diagnóstico já documentado da toolchain.

## Dependências diretas efetivas

`pubspec.yaml` continua declarando as dependências diretas abaixo. Os pins exatos aprovados para E1/E2 permanecem inalterados:

| Grupo | Dependência | Declaração |
|---|---|---|
| Produção | `camera` | `0.11.0+2` |
| Produção | `geolocator` | `13.0.2` |
| Produção | `image` | `4.2.0` |
| Produção | `uuid` | `4.6.0` |
| Produção | `wakelock_plus` | `1.2.8` |
| Produção | `path_provider` | `2.1.4` |
| Produção | `sqflite` | `2.4.1` |
| Produção | `crypto` | `3.0.7` |
| Desenvolvimento | `glados` | `1.1.7` |
| Desenvolvimento | `sqflite_common_ffi` | `2.3.4+4` |

As entradas de SDK (`flutter` e `flutter_test`) continuam provenientes do Flutter SDK. `flutter_lints: ^4.0.0` permanece a constraint de lint do template, não um pin funcional E1/E2. Nenhuma dependência de configuração, credencial, envio, worker, YOLO, TFLite ou inferência foi adicionada nesta subtarefa.

## APK debug registrado

| Campo | Valor |
|---|---|
| Caminho absoluto | `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile\build\app\outputs\flutter-apk\app-debug.apk` |
| Caminho relativo à raiz | `build\app\outputs\flutter-apk\app-debug.apk` |
| Tamanho | `109795650` bytes |
| Algoritmo | `SHA-256` |
| SHA-256 | `07004DF75C0AE00BC89EACF4BDA2C69E747F8357ACCC171000CE67B330F0F016` |

Os metadados foram lidos diretamente do arquivo existente, sem reconstruí-lo:

```powershell
Get-Item -LiteralPath '.\build\app\outputs\flutter-apk\app-debug.apk' |
  Select-Object FullName, Length, LastWriteTimeUtc

Get-FileHash -LiteralPath '.\build\app\outputs\flutter-apk\app-debug.apk' -Algorithm SHA256
```

Ambos os comandos concluíram com código de saída `0`.

## Identidade Android preservada

A configuração Android versionada em `android/app/build.gradle` mantém:

```groovy
namespace = "com.vitor.pavimenta_ai_mobile"
applicationId = "com.vitor.pavimenta_ai_mobile"
```

Logo, o `applicationId` aprovado permanece exatamente **`com.vitor.pavimenta_ai_mobile`**. Esta confirmação se limita à configuração de build, conforme o escopo da 50.2; a inspeção do artefato/manifesto mesclado pertence exclusivamente à tarefa 50.3.

## Conclusão

**SUCESSO no escopo da tarefa 50.2.** Foram registrados o resultado bem-sucedido do build de origem, as versões disponíveis da toolchain, os pins diretos efetivos, o caminho, tamanho e SHA-256 do APK debug E2, além da preservação do `applicationId` aprovado. Nenhuma tarefa irmã ou posterior foi executada.