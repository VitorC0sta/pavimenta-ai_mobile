# Evidência — Tarefa 34.1: validação técnica, instalação, identidade e abertura E1

## Resultado

**Status da subtarefa 34.1: SUCESSO TÉCNICO, com confirmação visual humana ainda pendente para o Validation Gate E1.**

Foram confirmados no estado atual do repositório: `flutter analyze`, suíte completa `flutter test`, build Android debug, hash SHA-256 do APK, identidade Android compilada, identidade do dispositivo físico, instalação do mesmo APK no Samsung Galaxy S25+ e abertura da `MainActivity` via ADB.

Esta evidência não executa as tarefas 34.2–34.6, não aprova fisicamente a interface ou as funcionalidades E1 e não constitui aprovação explícita do usuário. O gate pai 34 deve permanecer pendente.

## Escopo e fontes confrontadas

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Spec comum: o diretório do spec não contém `.config`.
- Documentos lidos antes da execução: `requirements.md`, `design.md` e `tasks.md`.
- Evidências anteriores inspecionadas: tarefas 30, 31, 32.1–32.4 e 33.1.
- Dispositivo físico acessível pelo mesmo ambiente Windows de Flutter/ADB: fabricante `samsung`, modelo `SM-S936B` (Galaxy S25+), estado ADB `device`.
- O serial único foi usado somente em memória e foi omitido desta evidência.

A comparação das evidências anteriores mostrou hashes diferentes entre o APK originalmente registrado na tarefa 32 (`FA8535...`) e o APK posteriormente instalado na tarefa 33.1 (`6896EF...`). Para eliminar essa ambiguidade, esta execução gerou um APK atual, calculou seu hash e instalou exatamente esse mesmo arquivo antes da abertura.

## Diagnóstico inicial e correção mínima E1

A primeira execução de `flutter analyze` encontrou um único diagnóstico:

```text
warning - Unused import: 'package:flutter/widgets.dart' - test\infrastructure\operational_adapters_test.dart:5:8 - unused_import
1 issue found. (ran in 22.9s)
Exit Code: 1
```

A execução foi interrompida nesse ponto; teste, build, instalação e abertura ainda não haviam sido iniciados. Foi removido somente o import não utilizado de `test/infrastructure/operational_adapters_test.dart`. Nenhum cenário de teste ou código de produção foi alterado. O diagnóstico do arquivo após a edição retornou zero problemas.

## Execução consolidada aprovada

### Análise estática

Comando:

```powershell
flutter analyze
```

Resultado:

```text
Analyzing pavimenta-ai_mobile...
No issues found! (ran in 4.3s)
Exit Code: 0
```

### Suíte automatizada

Comando:

```powershell
flutter test --reporter expanded
```

Resultado conclusivo:

```text
00:05 +82: All tests passed!
Exit Code: 0
```

Foram aprovados os mesmos 82 testes distribuídos em 11 arquivos e já inventariados na evidência da tarefa 31, incluindo a regressão automatizada E0 e os testes E1 de domínio, aplicação, infraestrutura, operação, lifecycle e navegação.

### Build Android debug

Comando, sem `--dart-define`, URL de produção, API key ou configuração de integração de ocorrências:

```powershell
flutter build apk --debug
```

Resultado:

```text
Running Gradle task 'assembleDebug'... 14.0s
√ Built build\app\outputs\flutter-apk\app-debug.apk
Exit Code: 0
```

O build repetiu o aviso não bloqueante já conhecido: o projeto declara NDK `23.1.7779620`, enquanto os plugins resolvidos solicitam `26.1.10909125`. Nenhuma toolchain ou configuração Android foi alterada; o build terminou com sucesso.

## APK atual e hash

| Campo | Valor |
|---|---|
| Caminho | `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile\build\app\outputs\flutter-apk\app-debug.apk` |
| Tamanho | `109712781` bytes |
| Última modificação | `2026-10-22T11:55:40.1766820-03:00` |
| SHA-256 | `2255142CAB6D0238C582C0B0B7984BF4AA67F91B147F2B563570AFE7CFCDA199` |

Este é o APK usado nas verificações de identidade, instalação e abertura registradas abaixo.

## Identidade Android compilada

A inspeção do APK atual com `aapt2 dump badging` confirmou:

```text
package: name='com.vitor.pavimenta_ai_mobile' versionCode='1' versionName='1.0.0' platformBuildVersionName='14' platformBuildVersionCode='34' compileSdkVersion='34' compileSdkVersionCodename='14'
launchable-activity: name='com.vitor.pavimenta_ai_mobile.MainActivity' label='' icon=''
```

Resultado: `applicationId/package` e activity inicial correspondem à identidade aprovada.

## Instalação no Galaxy S25+

Identidade sanitizada do alvo:

```text
ADB_STATE=device
DEVICE_MANUFACTURER=samsung
DEVICE_MODEL=SM-S936B
```

O APK atual foi instalado com substituição habilitada:

```text
Performing Streamed Install
Success
INSTALLED_PACKAGE=package:com.vitor.pavimenta_ai_mobile
INSTALLED_PATH_PRESENT=True
```

Resultado: instalação aprovada no usuário Android principal; o package instalado corresponde ao package compilado.

## Abertura no aparelho

Após limpar o buffer de log relevante e executar `am force-stop`, a activity inicial foi aberta explicitamente no dispositivo físico:

```text
Starting: Intent { cmp=com.vitor.pavimenta_ai_mobile/.MainActivity }
Status: ok
LaunchState: UNKNOWN (0)
Activity: com.vitor.pavimenta_ai_mobile/.MainActivity
WaitTime: 3030
Complete
```

Resultado técnico: o Android aceitou e completou a abertura da `MainActivity` correta no Galaxy S25+.

Uma checagem suplementar planejada de PID, activity retomada e assinaturas fatais não foi concluída porque o script tentou atribuir à variável PowerShell reservada `$PID`. A falha ocorreu **depois** de o Android retornar `Status: ok` e `Complete`; não é uma falha do aplicativo nem da instalação. Não foi feita nova tentativa, e esta limitação permanece explícita.

## Bloqueio físico remanescente

Não houve observação visual humana fornecida nesta execução para confirmar o conteúdo efetivamente renderizado na tela do Galaxy S25+ após a abertura. A evidência ADB comprova abertura técnica da activity, mas não substitui:

- observação física dos itens das tarefas 34.2–34.5;
- apresentação integral e decisão explícita da tarefa 34.6;
- aprovação explícita do usuário para o Validation Gate E1.

Portanto, a subtarefa 34.1 possui resultado técnico positivo, mas o parent task 34 permanece obrigatoriamente pendente.

## Limites preservados

- Nenhuma tarefa 34.2–34.6 foi executada.
- Nenhuma etapa E2 foi iniciada.
- Nenhuma dependência, configuração Android ou toolchain foi instalada/atualizada.
- Nenhuma evidência histórica E0 foi alterada.
- `requirements.md`, `design.md` e `tasks.md` não foram alterados por esta execução.
- A única correção de arquivo funcional foi a remoção de um import não utilizado em um teste E1.
