# Evidência consolidada — Tarefa 34.6: Validation Gate E1

## Estado atual do gate

**APROVADO EXPLICITAMENTE PELO USUÁRIO.** A reprovação anterior identificou um defeito físico no Galaxy S25+ ao negar câmera e/ou GPS. A correção autorizada foi limitada à E1, foi validada automaticamente, instalada no aparelho e aprovada na repetição física dirigida dos cenários afetados. Após a apresentação do gate atualizado, o usuário respondeu exatamente **“APROVAR”**.

A tarefa para obrigatoriamente no encerramento da E1. Esta aprovação não inicia E2; qualquer avanço depende de solicitação posterior e da sequência própria da próxima etapa.

## Escopo normativo e baseline

Foram relidos `requirements.md`, `design.md` e `tasks.md` antes da alteração. O diretório da spec não contém `.config` nem `.config.kiro`; trata-se do fluxo de feature E1. Foram preservados os requisitos RF-03.6–10, RF-05.1–4, RF-06.3–4, RF-20.1–7, RF-21 e os limites negativos da E1.

O `git status --short` inicial já continha alterações e arquivos E1 não rastreados produzidos pelas tarefas anteriores, além das evidências do gate. Nenhuma dessas alterações preexistentes foi descartada ou sobrescrita fora dos arquivos listados nesta correção.

## Reprodução anterior à alteração e causa real

### Defeito físico confirmado

No Galaxy S25+, após negar câmera e/ou GPS, os botões de nova verificação não apresentavam recuperação acionável estável; câmera e GPS piscavam/reconstruíam em momentos diferentes e o conteúdo oscilava verticalmente. Esse relato físico foi tratado como reprovação real, não substituído por teste automatizado.

### Reprodução no baseline automatizado

Comando executado antes da correção:

```powershell
flutter test test/operation/operation_permission_denial_test.dart
```

Resultado do baseline: **6 testes aprovados**. O resultado não contradizia o defeito: o teste de “ambas negadas” codificava o comportamento incorreto, pois após tocar no retry de câmera esperava simultaneamente `camera.acquireCount == 2` e `location.acquireCount == 2`.

### Causa confirmada

1. Os dois botões dos cards chamavam o mesmo `OperationController.retryReadiness()`.
2. Esse método executava `updateOperationalContext(forceResourceSync: true)`, que publicava câmera e GPS como `initializing`, removia ambos os snapshots/preview e chamava novamente o fluxo completo `_activateResources()`.
3. Portanto, retry de um card reinicializava e readquiria os dois recursos; como câmera e localização assentavam em momentos diferentes, os cards piscavam independentemente.
4. Os textos e botões condicionais tinham alturas diferentes entre `initializing`, negação temporária, negação permanente e sucesso; a reinicialização conjunta alterava a geometria vertical.
5. Na negação permanente havia somente texto e um botão de “verificar novamente”; não existia ação para abrir as configurações Android.
6. A proteção de lifecycle da correção anterior evitava parte do churn de `inactive`, mas não eliminava o retry global, que era a causa direta reproduzida.

## Correção E1 aplicada

### Produção

- `lib/application/e1_ports.dart`
  - adiciona a porta mínima `AppSettingsPort` para a ação explícita de recuperação após negação permanente.
- `lib/infrastructure/operational_app_settings.dart`
  - adapta `Geolocator.openAppSettings()` sem nova dependência e sem abertura automática.
- `lib/main.dart`
  - injeta `OperationalAppSettings` somente no controlador operacional E1.
- `lib/operation/operation_state.dart`
  - representa o alvo de readiness ativo;
  - separa `canRetryCameraReadiness`, `canRetryLocationReadiness`, `canOpenCameraSettings` e `canOpenLocationSettings`;
  - mantém captura desabilitada até câmera, preview, localização válida, lifecycle e single-flight estarem prontos.
- `lib/operation/operation_controller.dart`
  - substitui o retry global por `retryCameraReadiness()` e `retryLocationReadiness()`;
  - retry de câmera não publica nem readquire GPS; retry de GPS não publica nem readquire câmera;
  - usa um único gate de readiness para deduplicar toques repetidos e impedir solicitações concorrentes;
  - mantém classificação distinta de negação temporária e permanente;
  - oferece abertura serializada das configurações somente por ação explícita;
  - preserva captura desabilitada e não cria imagem/UUID/ocorrência durante indisponibilidade.
- `lib/operation/operation_screen.dart`
  - apresenta orientação acionável para negação solicitável;
  - apresenta “Abrir configurações da câmera/GPS” para negação permanente;
  - usa slots `IndexedStack` dimensionados pelo maior conteúdo para manter a geometria dos cards estável durante mudanças de estado;
  - mantém os botões de captura e recuperação coerentes com o single-flight.

### Testes

- `test/operation/operation_permission_denial_test.dart`
  - câmera negada: retry exclusivo, múltiplos toques deduplicados, GPS estável, captura bloqueada e ausência de loop;
  - GPS negado: retry exclusivo, múltiplos toques deduplicados, câmera estável, captura bloqueada e ausência de loop;
  - ambas negadas: recuperação serial, sem solicitações concorrentes e sem retry cruzado;
  - widgets: orientação temporária, ação permanente de configurações, captura desabilitada e estabilidade geométrica relativa dos cards durante e após retry;
  - configurações: duas ações visíveis, mas uma única abertura em andamento.
- `test/infrastructure/operational_adapters_test.dart`
  - verifica que as configurações Android só são abertas após ação explícita.

Os testes usam fakes Dart simples. A tarefa 34.6 não é uma tarefa PBT e nenhuma propriedade nova foi adicionada ao design.

## Resultados automatizados finais

| Verificação | Comando/escopo | Resultado final |
|---|---|---|
| Testes direcionados | denial + controller + screen + adapters | **36 aprovados, 0 falhas**, exit 0 |
| Suíte Flutter completa | `flutter test` | **90 aprovados, 0 falhas**, exit 0 |
| Regressão E0 | incluída na suíte completa | **3 testes E0 aprovados** |
| Análise estática | `flutter analyze` | **No issues found**, exit 0, 26,9 s |
| Formatação | `dart format --output=none --set-exit-if-changed` em 8 arquivos | **8 arquivos, 0 alterados**, exit 0 |
| Build Android final | `flutter build apk --debug` | **Aprovado**, exit 0, `assembleDebug` em 9,1 s |

Durante os testes novos houve uma fixture `const` inválida e uma comparação de posição absoluta após `ensureVisible`; ambos eram defeitos exclusivos dos testes e foram corrigidos. Uma primeira invocação do build terminou inconclusiva com exit `-1` sem erro conclusivo; a repetição final acima concluiu com sucesso.

O build preservou o aviso não bloqueante já conhecido: o projeto declara NDK `23.1.7779620` e plugins solicitam `26.1.10909125`. Nenhuma toolchain ou configuração Android foi alterada nesta execução.

## APK corrigido

| Campo | Valor |
|---|---|
| Caminho | `build/app/outputs/flutter-apk/app-debug.apk` |
| Tamanho | `109.727.375` bytes |
| SHA-256 | `2A9073E4F853264DAE90C973EA727F9092606F84D66228AC1CEA4770882F04F6` |
| Pacote | `com.vitor.pavimenta_ai_mobile` |

## Instalação, abertura e observação física pós-correção

O Galaxy S25+ foi detectado pelo Flutter como Samsung `SM-S936B`, Android 17/API 37. O APK de hash acima foi instalado com sucesso por:

```powershell
flutter install -d <SERIAL_OMITIDO> --use-application-binary build\app\outputs\flutter-apk\app-debug.apk
```

A instalação removeu a versão anterior e instalou o APK final em 5,4 s. A `MainActivity` foi iniciada via ADB. Antes da interação, o Android exibiu a tela nativa de permissão e registrava câmera/localização como não concedidas.

O usuário então executou no aparelho o roteiro dirigido e reportou:

1. câmera e GPS negados: **passou**; ambos exibiram orientação e “Registrar buraco” permaneceu desabilitado;
2. múltiplos toques no retry de câmera: **passou**; somente a câmera mudou, sem piscar/deslocar o GPS;
3. múltiplos toques no retry de GPS: **passou**; somente o GPS mudou, sem loop de solicitações;
4. negação permanente e “Abrir configurações”: **passou**; as configurações Android abriram;
5. permissões restauradas e retorno ao app: **passou**; preview/GPS/readiness foram recuperados.

Declaração adicional do usuário: **“não houve oscilação bug, nem nada”**.

Após o roteiro, a inspeção técnica complementar registrou a `MainActivity` do aplicativo em foco e câmera/localização precisa concedidas. Essa inspeção apenas corrobora o estado técnico; a evidência física é a observação explícita do usuário acima.

## Consolidação das evidências anteriores do Gate E1

| Área | Evidência consolidada | Estado |
|---|---|---|
| 34.1 — análise, testes, build, identidade, instalação e abertura | evidência técnica anterior + novo ciclo completo e APK final | **Aprovado no artefato final** |
| 34.2 — preview, banner, GPS/velocidade, captura única, contador e responsividade | observação física anterior; blockers de câmera/GPS agora observados no APK final | **Cobertura física/automatizada consolidada** |
| Campos internos de 34.2 (`detectedAt`, UUID, classe/confiança) | não exibidos na UI; cobertos pela suíte automatizada | **Limitação histórica mantida, sem alegar observação física** |
| 34.3 — cooldown | rejeição e ramo temporal observados; ramo de distância antes de 5 s automatizado | **Composição histórica mantida; ramo físico de distância não inventado** |
| 34.4 — JPEG/ownership/limpeza | evidência física e automatizada específica | **Aprovado** |
| 34.5 — lifecycle, wake lock, navegação, exclusão e regressão E0 | subtarefa registrada como concluída em `tasks.md`; regressão E0 automatizada novamente aprovada | **Registro anterior preservado; sem criar evidência física nova nesta correção** |
| Defeito que reprovou 34.6 | três cenários, múltiplos retries, permanente/configurações e nominal repetidos no Galaxy | **Aprovado fisicamente pós-correção** |

As limitações históricas já documentadas em 34.2 e 34.3 continuam explicitamente classificadas; nenhum teste automatizado foi renomeado como observação física.

## Preservação E0 e escopo negativo

- Nenhum arquivo de `lib/e0/`, `android/`, `pubspec.yaml` ou `pubspec.lock` foi alterado por esta correção.
- O adaptador de configurações reutiliza apenas `geolocator`, dependência já aprovada; nenhuma dependência foi adicionada.
- Os 3 testes de regressão E0 passaram dentro da suíte de 90 testes.
- Não foram adicionados fila, banco, persistência, API/cliente de ocorrências, multipart, credencial, envio, backoff, YOLO, TFLite, detector, inferência ou FPS.
- O único texto “YOLO” continua sendo o banner obrigatório informando que YOLO **não** está configurado.
- As evidências históricas E0 não foram alteradas.

## Decisão final e regra de parada

**Decisão explícita registrada: APROVAR.** O usuário aprovou o Validation Gate E1 após receber os resultados técnicos, o hash do APK, a instalação/abertura, a repetição física dos cenários corrigidos e as limitações históricas ainda documentadas.

A E1 está encerrada no gate. Nenhuma atividade E2 foi executada nesta tarefa; o trabalho para aqui, conforme a regra sequencial.
