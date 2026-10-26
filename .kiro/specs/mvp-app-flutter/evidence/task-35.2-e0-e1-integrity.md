# Evidência — Tarefa 35.2: acesso E0, fluxo E1 e integridade histórica

## Escopo

Esta evidência executa exclusivamente a subtarefa **35.2**: confirmar, antes de qualquer alteração funcional E2 nesta execução, o acesso ao Diagnóstico E0, o fluxo Operação E1, a aprovação explícita do Validation Gate E1 e a integridade dos artefatos históricos relevantes.

Foram inspecionados `requirements.md`, `design.md`, `tasks.md`, o código de composição/navegação e as evidências indicadas abaixo. O diretório `.kiro/specs/mvp-app-flutter/` não contém `.config`; portanto, a especificação foi tratada como feature comum, e não bugfix.

Nenhum código funcional, dependência, configuração Android, status de tarefa ou evidência histórica foi alterado. Nenhuma tarefa irmã da E2 foi executada e nenhuma fila, persistência ou outra funcionalidade E2 foi iniciada.

## Estado inicial preservado

O `git status --short --branch` foi registrado antes desta documentação. O workspace já continha alterações e arquivos não rastreados provenientes do trabalho aprovado de E1 e da evolução documental da especificação. Nenhuma alteração preexistente foi descartada, revertida ou sobrescrita nesta tarefa.

Os documentos normativos confirmam a sequência e o baseline:

- `tasks.md` registra as tarefas 1–15 da E0 e 16–34 da E1 como histórico concluído, incluindo o Gate E1 na tarefa 34;
- `requirements.md`, especialmente RF-00.2–5, RF-03.11 e RF-23.1–9, exige preservar o Diagnóstico E0, mantê-lo acessível pela navegação e iniciar E2 somente após aprovação explícita da E1;
- `design.md`, em E1.2, E1.19, E1.29 e E2.1, define Operação como rota inicial, uma sessão E0 própria por navegação, exclusão mútua de recursos e a E1 como baseline aprovado da E2.

## Confirmação do acesso ao Diagnóstico E0

A inspeção de `lib/main.dart` e `lib/operation/operation_screen.dart` confirmou:

1. `PavimentaAiMobileApp` usa `OperationScreen` como `home`;
2. a Operação expõe a ação claramente rotulada **“Abrir Diagnóstico”** (`open-diagnostic-button`);
3. `_openDiagnostic` chama `OperationController.suspendForDiagnostic()` antes do `Navigator.push`;
4. a rota recebe o nome `/diagnostic`;
5. cada entrada cria uma nova `_E0Session`, com `E0Controller`, `CameraDiagnostic`, `LocationDiagnostic` e `DiagnosticHttpClient` próprios;
6. após o `pop`, a retomada da Operação aguarda `DiagnosticSessionDisposal.completed`, preservando o dispose da sessão E0 antes da readquisição operacional.

A evidência histórica `task-15-validation-gate.md` registra o Gate E0 como **APROVADO**, com acesso físico no Galaxy S25+, câmera traseira, permissões seriais, GPS, HTTPS diagnóstico, lifecycle e decisão humana explícita.

## Confirmação do fluxo Operação E1

A composição atual em `lib/main.dart` mantém os componentes E1 aprovados: fonte manual, pós-candidato, cooldown, preparação de imagem, UUID, câmera, localização, relógio, wake lock e `OperationController`. A apresentação em `OperationScreen` mantém:

- título **“Operação”** e Operação como tela inicial;
- banner permanente **“Modo manual — YOLO ainda não configurado”**;
- preview e estados independentes de câmera/GPS;
- ação manual de registro, readiness, single-flight e lifecycle delegados ao controlador;
- acesso ao Diagnóstico sem compartilhar simultaneamente a sessão de câmera/GPS.

A evidência `task-34.2-physical-observation.md` registra no Galaxy S25+ o fluxo nominal visível de Operação, preview traseiro, banner, GPS/velocidade, botão pronto, processamento single-flight, criação em memória, contador e responsividade. As limitações históricas ali registradas permanecem explícitas e não foram reclassificadas por esta tarefa.

## Aprovação explícita do Validation Gate E1

A evidência consolidada `task-34.6-validation-gate.md` declara inequivocamente:

- **“APROVADO EXPLICITAMENTE PELO USUÁRIO”**;
- a resposta final do usuário foi exatamente **“APROVAR”**;
- o APK corrigido foi instalado e os cenários físicos afetados foram repetidos no Galaxy S25+;
- a suíte final registrou 90 testes aprovados, análise estática sem issues e build Android aprovado;
- a aprovação encerrou E1 e não iniciou E2 automaticamente.

Assim, o pré-requisito decisório para iniciar a etapa E2 está documentalmente satisfeito, sem inferência automática nesta tarefa.

## Validação automatizada direcionada

Comando executado, sem modo watch:

```powershell
flutter test test/e0/e0_regression_test.dart test/operation/operation_diagnostic_navigation_test.dart test/operation/operation_screen_test.dart
```

Resultado:

```text
00:06 +13: All tests passed!
Exit Code: 0
```

Os 13 testes confirmaram no baseline atual:

- regressão E0 de preview, permissões seriais, GPS, HTTPS, mensagens e limpeza de lifecycle;
- Operação como tela inicial e ação rotulada de Diagnóstico;
- liberação completa dos recursos da Operação antes da sessão diagnóstica;
- uma única sessão diante de toques repetidos;
- sessões diagnósticas novas em entradas repetidas, sem duplicação de permissões ou streams;
- dispose do Diagnóstico antes da readquisição da Operação;
- retomada condicionada ao lifecycle `resumed`;
- estados, readiness, feedback e apresentação essencial da Operação.

Esta validação automatizada confirma o estado atual do código, sem substituir nem reexecutar a validação física histórica.

## Integridade das evidências históricas

### Evidências E0 rastreadas

A comparação Git dos artefatos históricos E0 das tarefas 1, 14 e 15 não retornou arquivo modificado. Em especial, `task-15-validation-gate.md` permanece rastreado e sem diff no baseline inspecionado.

### Evidências E1 e fingerprints do baseline

Algumas evidências E1 já estavam não rastreadas no estado inicial do workspace. Portanto, não seria correto alegar integridade histórica delas com base no índice Git. Para produzir uma referência verificável sem modificá-las, foram calculados os seguintes SHA-256 antes da criação deste documento:

| Evidência | SHA-256 |
|---|---|
| `task-15-validation-gate.md` | `50CCD0430A32F72158291BAFD1AF373AF7F71517513E844C963B4B4256D46F58` |
| `task-30-static-analysis.md` | `BBEBBACD188C86367116BD7216CBFDAF03E24BFEBF0A3F13365B0D236BB9AA14` |
| `task-31-automated-test-suite.md` | `F8B55A7D47D98113C89ED3BA6400FF70A187FA30349793623E9AF893D4F82945` |
| `task-34.1-technical-validation-and-device-opening.md` | `2A400373339F67E8D7EE34F98D73329751DC88F912DCD4222EE53AC1C1417E0B` |
| `task-34.2-physical-observation.md` | `976B5A0D9875B5E544A6185157E26F101D051DB6C8F81C2D08BF816850E419C1` |
| `task-34.3-cooldown-physical-observation.md` | `BB2A661EB9B6CE219979496C3AF8329533FAA88CFCC54502D83516A928FEE02E` |
| `task-34.4-jpeg-physical-validation.md` | `3B04B439FCECAA169A8273F9ADB043F6B32A758B010825BA3B5DA834132FCAB5` |
| `task-34.6-validation-gate.md` | `D8D76563B38E5854B794DA6660EBACB570285B3ECF9E9F8AEBAAD8C5FAFFA30B` |

A leitura cruzada confirmou que as evidências mantêm suas classificações e limitações originais: registros parciais não foram promovidos retroativamente a observação física, e a decisão final de aprovação está concentrada na consolidação 34.6 após a repetição dirigida no aparelho.

## Resultado

**Tarefa 35.2 confirmada documental e tecnicamente.** O Diagnóstico E0 permanece acessível a partir da Operação E1; a Operação continua sendo o fluxo inicial aprovado; o Validation Gate E1 possui aprovação explícita registrada; e os artefatos históricos consultados foram preservados, com integridade rastreada por Git quando aplicável e fingerprints SHA-256 para o baseline documental restante.

A única alteração desta execução é este novo arquivo de evidência. A atualização do status da tarefa cabe exclusivamente ao orquestrador.