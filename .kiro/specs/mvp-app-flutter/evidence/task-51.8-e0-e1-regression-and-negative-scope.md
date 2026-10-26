# Evidência da tarefa 51.8 — Regressão física E0/E1 e ausência dinâmica de envio/E3–E5

## Escopo e documentos consultados

- Tarefa executada: **51.8 — Reexecutar regressão física essencial E0/E1 e inspecionar tráfego/interface/dependências para ausência de envio e de funcionalidades E3–E5.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Foram lidos antes da execução `requirements.md`, `design.md`, `tasks.md`, `tasks.meta.json` e as evidências E2 relevantes, especialmente `task-49.6-e2-validation-evidence.md`, `task-51.2-e2-queue-bootstrap-physical-revalidation.md` e `task-51.6-privacy-responsiveness-navigation.md`.
- O diretório da spec não contém `.config`; trata-se de spec regular, não de bugfix.
- A execução foi não destrutiva: não limpou dados, não desinstalou/reinstalou o APK, não alterou permissões, não criou ocorrência, não removeu pendência e não leu banco/JPEG.
- Nenhum código, dependência, manifesto ou documento normativo foi alterado. Este arquivo é a única evidência nova da execução.

## Alvo físico e abertura

O ADB aprovado foi chamado pelo caminho absoluto `C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe`, pois `adb` não está no `PATH`. O dispositivo retornou:

```text
serial: RQGL701ZV7Z
estado: device
fabricante: samsung
modelo: SM-S936B (Galaxy S25+)
Android: 17
pacote: com.vitor.pavimenta_ai_mobile
versionCode: 1
versionName: 1.0.0
UID Android: 10475
```

A abertura fria por `am start -W` terminou com `Status: ok`, atividade `com.vitor.pavimenta_ai_mobile/.MainActivity`, `LaunchState: COLD` e `TotalTime: 812 ms`. A janela permaneceu focada no pacote durante toda a rota.

## Resolução do bloqueio de acessibilidade

O bloqueio anterior foi reproduzido e resolvido sem correção de fonte. O aparelho estava em paisagem, com viewport lógica `2340 x 1080`, orientação de display `3`. Nessa condição, o `SingleChildScrollView` expunha inicialmente somente parte dos cartões. Além disso, widgets Flutter apareciam como `content-desc`, não como nós `text`.

A rolagem física foi feita dentro dos limites acessíveis do `ScrollView` (`[0,242][2246,1038]`):

```powershell
& $adb shell input touchscreen swipe 2200 300 2200 1000 800
```

Após três gestos, a árvore expôs:

```text
content-desc="Abrir Diagnóstico" bounds="[1688,264][2201,399]"
content-desc="Modo de registro manual. Detecção automática indisponível."
content-desc contendo câmera traseira Pronta e preview disponível
content-desc contendo GPS pronto e valores disponíveis
```

O toque foi calculado pelo centro dos limites acessíveis e executado em `(1944,331)`. Não foi necessária alteração de semântica, layout ou fonte.

## Rota física dinâmica executada

### 1. Operação E1/E2 antes do Diagnóstico

A árvore física confirmou:

- tela `Operação`;
- banner `Modo de registro manual. Detecção automática indisponível.`;
- câmera traseira `Pronta`, com preview disponível;
- GPS `pronto`, com latitude, longitude, precisão e velocidade disponíveis (valores não transcritos para preservar a sanitização exigida pela spec);
- fila local `Pronta`;
- `Pendências: 11`;
- processamento `Pronto`;
- controle acessível `Registrar buraco por confirmação manual` disponível.

Nenhum registro foi acionado nesta tarefa.

### 2. Diagnóstico E0

Após tocar `Abrir Diagnóstico`, a árvore física confirmou:

- app bar `Pavimenta AI — E0`;
- título `E0 — Diagnóstico Android`;
- aviso `Smoke test E0: nenhum dado de ocorrência é criado ou enviado.`;
- `Câmera traseira disponível.` com preview básico;
- `Localização precisa disponível.` com posição, precisão e velocidade presentes, sem registrar os valores;
- botão Android de retorno disponível.

A inspeção de recursos mostrou um cliente de câmera do pacote e uma única solicitação ativa de localização de alta precisão atribuída ao UID/pacote durante a sessão E0.

### 3. HTTPS diagnóstico manual E0

Após rolar o E0, a árvore expôs:

```text
Painel de diagnóstico da rede HTTPS
Diagnóstico HTTPS ainda não executado.
Código HTTP: Não disponível
A verificação é manual, usa HTTPS e não envia corpo ou credenciais.
Executar diagnóstico HTTPS bounds="[113,768][1056,903]"
```

O controle foi tocado no centro `(584,835)`. O APK instalado usa o destino fictício padrão da E0, e o resultado físico controlado foi:

```text
Rede indisponível ou destino de teste inacessível.
Código HTTP: Não disponível
```

Assim, a ação manual e sua falha controlada foram reexecutadas. Não se afirma sucesso de conectividade a um servidor funcional nesta execução, pois nenhuma URL funcional externa foi fornecida ao build; a indisponibilidade controlada é comportamento previsto pelo RF-00.15.

### 4. Retorno E0 → Operação

O retorno foi executado com `adb shell input keyevent 4`. Após oito segundos, a árvore física voltou a confirmar:

- `Operação` e `Abrir Diagnóstico`;
- banner manual;
- GPS pronto com valores disponíveis;
- câmera novamente pertencente ao pacote;
- exatamente uma solicitação ativa de localização do aplicativo;
- fila `Pronta` e `Pendências: 11`;
- processamento `Pronto`;
- controle `Registrar buraco por confirmação manual` disponível.

A contagem agregada permaneceu **11 antes e 11 depois** da rota. Não houve criação, remoção ou envio de ocorrência. Logs do processo desde o início da rota apresentaram:

```text
FATAL_ANR_UNHANDLED_COUNT=0
```

## Inspeção dinâmica de tráfego

Foi forçado um snapshot por `dumpsys netstats --poll` e consultado `dumpsys netstats detail` para o UID `10475`.

1. Antes de acionar o HTTPS E0, não havia histórico de bytes do UID no snapshot (`UID_HISTORY_RECORDS=0`).
2. Depois da única ação manual E0, o registro foreground mostrou `rb=610`, `rp=4`, `tb=310`, `tp=4`. A rede/SSID foi deliberadamente omitida desta evidência.
3. Após retornar à Operação e permanecer dez segundos em idle, novo poll mostrou exatamente os mesmos contadores: `rb=610`, `rp=4`, `tb=310`, `tp=4`.

O registro com tag e o registro sem tag carregavam os mesmos totais e são duas visões contábeis do mesmo tráfego, não bytes a serem somados. A evidência demonstra: ausência de tráfego do UID antes da ação explícita; tráfego pequeno somente após o HTTPS diagnóstico manual E0; e ausência de incremento automático depois do retorno à Operação. Não houve log de endpoint de ocorrência, upload, multipart, autenticação ou envio.

## Inspeção dinâmica da interface

Foram agregados seis dumps físicos da rota: Operação inicial, E0 inicial, painel HTTPS antes/depois da ação e Operação após retorno. A busca de controles/estados futuros retornou:

```text
Configurações=0
API key=0
Enviar=0
Envio=0
Upload=0
Modelo carregado=0
Inferência=0
FPS=0
Detecção automática ativa=0
Remover pendência=0
Listar pendências=0
EXPECTED_MANUAL_UNAVAILABLE_BANNER=2
EXPECTED_E0_NO_SEND_NOTICE=1
```

A menção a YOLO observada é exclusivamente o banner negativo aprovado (`YOLO ainda não configurado`/detecção automática indisponível), não funcionalidade de modelo.

## Inspeção estática de fontes, artefato e dependências

A busca em `lib`, `android`, `pubspec.yaml` e `pubspec.lock` pelo conjunto `BASE_URL`, `DEVICE_API_KEY`, `flutter_secure_storage`, cliente/envio de ocorrência, multipart, upload, WorkManager, `ultralytics_yolo`, TFLite/TensorFlow, inferência/FPS e `ApiKey` retornou:

```text
E3_E5_SOURCE_DEPENDENCY_MATCHES=0
MODEL_ASSET_COUNT=0
```

A única referência a `/api/v1/occurrences` está em `lib/e0/diagnostic_http_client.dart:194–196`, onde o caminho é explicitamente rejeitado antes de abrir conexão. Não há `package:http` importado pela aplicação. Os identificadores `HttpClient` encontrados pertencem ao cliente diagnóstico E0 ou à sua composição/controlador; a criação concreta do cliente ocorre somente em `lib/e0/diagnostic_http_client.dart`.

Dependências diretas de produção resolvidas:

```text
camera 0.11.0+2
geolocator 13.0.2
image 4.2.0
uuid 4.6.0
wakelock_plus 1.2.8
path_provider 2.1.4
sqflite 2.4.1
crypto 3.0.7
```

Dependências diretas de desenvolvimento:

```text
flutter_lints 4.0.0
glados 1.1.7
sqflite_common_ffi 2.3.4+4
```

`http 1.6.0` aparece apenas de forma transitiva via `package_info_plus`/tooling resolvido; não é dependência direta nem é importado por `lib`. Não existem secure storage, worker, YOLO ou runtime de modelo.

O APK declara somente INTERNET, CAMERA, ACCESS_FINE_LOCATION e ACCESS_COARSE_LOCATION, além da permissão signature gerada pelo AndroidX. O manifesto mesclado contém os componentes técnicos dos plugins/framework (serviço de localização do geolocator, metadata service desabilitado do CameraX e provider/receiver AndroidX); não contém WorkManager, serviço de envio, worker, autenticação ou componente de inferência E3–E5. Cleartext permanece desabilitado.

## Comandos e verificações executados

Os comandos efetivos, com scripts PowerShell apenas para filtrar/sanitizar saídas, foram:

```powershell
adb devices -l # tentativa inicial; falhou porque adb não está no PATH
$adb='C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe'
& $adb devices -l
& $adb shell getprop ro.product.manufacturer
& $adb shell getprop ro.product.model
& $adb shell getprop ro.build.version.release
& $adb shell dumpsys package com.vitor.pavimenta_ai_mobile
& $adb shell pm list packages -U com.vitor.pavimenta_ai_mobile
& $adb shell am force-stop com.vitor.pavimenta_ai_mobile
& $adb shell am start -W -n com.vitor.pavimenta_ai_mobile/.MainActivity
& $adb shell dumpsys input
& $adb shell dumpsys window
& $adb shell uiautomator dump --compressed /sdcard/task518*.xml
& $adb exec-out cat /sdcard/task518*.xml
& $adb shell input touchscreen swipe 2200 300 2200 1000 800
& $adb shell input touchscreen swipe 2200 950 2200 300 700
& $adb shell input tap 1944 331
& $adb shell input tap 584 835
& $adb shell input keyevent 4
& $adb shell dumpsys media.camera
& $adb shell dumpsys location
& $adb shell dumpsys netstats --poll
& $adb shell dumpsys netstats detail
& $adb logcat -d -T '2026-10-24 18:20:10.000' --pid=<PID_DO_APP>
git grep -n -I -E <PADRÕES_E3_E5> -- lib android pubspec.yaml pubspec.lock
git grep -n -I -E 'HttpClient' -- lib
git status --short
C:\dev\flutter\bin\flutter.bat pub deps --style=compact
C:\Users\vitor\AppData\Local\Android\sdk\build-tools\34.0.0\aapt2.exe dump permissions build\app\outputs\flutter-apk\app-debug.apk
```

Também foram lidos `pubspec.yaml`, o manifesto principal e `build/app/intermediates/merged_manifest/debug/AndroidManifest.xml`. Não foi executada suíte de testes nesta tarefa porque nenhum código foi modificado; as validações pertinentes foram a rota física completa, os snapshots dinâmicos e as inspeções estáticas reproduzíveis.

## Resultado

**APROVADO para a tarefa 51.8.** A rota dinâmica não destrutiva Operação E1/E2 → Diagnóstico E0 → HTTPS diagnóstico manual → retorno à Operação foi concluída fisicamente no Galaxy S25+. Câmera, GPS, banner manual, navegação e retorno foram preservados; a fila permaneceu em 11; não houve crash/ANR; o único incremento de tráfego ocorreu após a ação HTTPS manual E0 e permaneceu estável depois do retorno; interface, fontes, dependências, assets e manifesto não apresentam funcionalidades E3–E5 nem envio de ocorrências.

Não resta bloqueio para a 51.8. Limitação registrada, sem impedir a conclusão: o HTTPS E0 foi validado no caminho controlado de destino fictício inacessível, e não contra servidor funcional, porque o APK não foi compilado com URL funcional de teste nesta execução. Esta aprovação é exclusiva da subtarefa 51.8; não aprova a tarefa 51 inteira nem o Validation Gate E2.