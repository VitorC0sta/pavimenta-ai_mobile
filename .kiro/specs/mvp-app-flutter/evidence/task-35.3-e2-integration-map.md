# Evidência — Tarefa 35.3: mapa concreto de integração E2

## Escopo e método

Esta evidência executa exclusivamente a subtarefa **35.3**: mapear os pontos concretos em que a futura fila persistente E2 deverá integrar-se ao `PostCandidateProcessor`, `OperationController`, `OperationState`, ownership/lease de imagem, cooldown e composition root, sem alterar comportamento nesta tarefa.

Foram confrontados:

- `requirements.md`, com foco em RF-11.8, RF-12 e nos limites RF-23.9;
- `design.md`, especialmente E2.5–E2.14, E2.18 e E2.19;
- `tasks.md`, especialmente as futuras tarefas 37.4, 41, 42, 45, 46 e 47;
- implementação E1 atual em `lib/`;
- testes E1 que fixam ordem, lifecycle, ownership, cooldown, estado e composição.

O diretório `.kiro/specs/mvp-app-flutter/` não contém `.config`; essa ausência já estava registrada na evidência 35.2. A especificação continua tratada como feature comum, não como bugfix.

Nenhum código Dart, teste, dependência, manifesto, status de tarefa ou evidência histórica E0/E1 foi modificado. Nenhum contrato, banco, diretório durável, bootstrap, observer ou comportamento E2 foi criado.

## Fluxo E1 encontrado

O caminho concreto atual de um registro manual é:

```text
OperationScreen
  -> OperationController.registerManualPothole()
  -> OccurrenceCandidateSource.requestCandidate()
  -> PostCandidateProcessor.process()
     -> valida candidato/localização
     -> cooldown.evaluate()
     -> candidate.acquireImage()
     -> ImagePreparer.prepare()
     -> captura temporária.dispose()
     -> UUID
     -> InMemoryOccurrenceFactory.create()
     -> cooldown.commit()
     -> CandidateCreated(occurrence com OwnedPreparedImage)
  -> OperationController._applyResult()
     -> retém InMemoryOccurrence em _ownedOccurrence
     -> publica resumo e contador da sessão
     -> limpa o JPEG ao substituir, pausar, navegar ou encerrar
```

A inserção E2 aprovada é única e fica entre a criação completa em memória e o commit final:

```text
... -> InMemoryOccurrenceFactory.create()
    -> [futuro OccurrenceAcceptancePort: persistência íntegra + ownership]
    -> cooldown.commit() somente após novo aceite durável
    -> resultado/controlador/estado coerentes com persistida, equivalente ou falha
```

Este diagrama é somente um mapa. A inserção não foi implementada.

## Matriz dos pontos concretos

| Área | Ponto atual encontrado | Integração E2 já aprovada para tarefa futura | Invariantes que não podem regredir |
|---|---|---|---|
| Pós-candidato | `lib/application/post_candidate_processor.dart`: `E1PostCandidateProcessor.process`; fábrica em torno da linha 215; `cooldown.commit` em torno da linha 231 | Tarefa 45: injetar `OccurrenceAcceptancePort` e chamá-lo depois da fábrica e antes de cooldown, sucesso e contador | Ordem E1 até a fábrica; cooldown antes da captura; uma aquisição; UUID após JPEG; ausência de ramo por fonte; falha sem sucesso parcial |
| Controller | `lib/operation/operation_controller.dart`: `_ownedOccurrence` em torno da linha 43; `_applyResult` a partir da linha 872; `_retireStaleResult`, `_takeOwnedOccurrence`, `_deactivateResources` e `dispose` limpam a imagem | Tarefas 45.5 e 46: deixar de reter lease/path persistido, observar snapshot da fila, separar novo aceite de equivalência e preservar o JPEG pertencente à fila em lifecycle/navegação | Single-flight, geração/cancelamento, câmera/GPS independentes, contador da sessão somente em novo aceite e nenhum callback obsoleto na UI |
| Estado | `lib/operation/operation_state.dart`: `OperationState`; `canRegister` em torno da linha 163 considera apenas readiness E1 | Tarefas 46.3–46.4 e 47: acrescentar saúde/recuperação/persistência/`pendingCount`; exigir fila pronta em `canRegister`; apresentar estado textual e contadores separados | Snapshot imutável; estado sem bytes/path; lifecycle/câmera/GPS/busy continuam necessários; Diagnóstico continua acessível com fila indisponível |
| Lease/ownership | `OwnedPreparedImage` expõe somente `dispose`; `InMemoryOccurrence.image` guarda a lease opaca; `PrivatePreparedImage` contém arquivo/metadados e `transferOwnership()`; o controller é o dono final E1 | Tarefas 37.4, 42.5 e 45: evoluir a lease apenas com leitura/promoção/retirada mínimas, transferir à fila após commit íntegro e limpar o temporário nos demais resultados | Transferência única, dispose idempotente, sem galeria, sem path/bytes na UI ou logs, nenhuma remoção do JPEG durável por lifecycle da Operação |
| Cooldown | `lib/domain/cooldown_policy.dart`: `_lastCreated` privado; `evaluate` não muta; `commit` aceita ocorrência completa | Tarefas 45.2 e 46.2: manter commit depois da persistência; restaurar/limpar referência a partir da maior `queueSequence` antes de habilitar registro | Regra 5 s OU 15 m inalterada; falha/equivalência não cria segundo commit de novo aceite; recuperação não incrementa contador da sessão |
| Composition root | `lib/main.dart`: cria store E1, câmera/GPS, preparador, cooldown inline no processor e controller; `composeE1`/`E1Composition` representam o grafo E1 testável | Tarefas 41, 45 e 46: construir store/banco/fila/acceptance/observer, compartilhar uma instância restaurável de cooldown, iniciar bootstrap e injetar somente os novos limites necessários | DI explícita sem framework; nenhuma rede de ocorrência; E0 e `DiagnosticHttpClient` isolados; câmera/GPS não devem ser reinicializados por retry da fila |

## 1. `PostCandidateProcessor`

### Estado atual

`E1PostCandidateProcessor` recebe somente `CandidateCooldown`, `ImagePreparer`, `UuidGenerator` e `InMemoryOccurrenceCreator`. O método `process` preserva a sequência aprovada da E1 e, após criar uma `InMemoryOccurrence`, verifica novamente o guard de lifecycle, executa `_cooldown.commit(occurrence)` e retorna `CandidateCreated`.

O teste `test/application/post_candidate_processor_test.dart` fixa a ordem atual:

```text
cooldown.evaluate
image.acquire
image.prepare
capture.dispose
uuid.generate
occurrence.create
cooldown.commit
```

O mesmo teste confirma que bloqueio/falha não adquire ou não conserva artefatos indevidos e não faz commit.

### Corte futuro exato

A tarefa 45 deverá inserir o aceite persistente **depois** de `_occurrenceCreator.create(...)` e **antes** de `_cooldown.commit(occurrence)`. Esse é o único corte que satisfaz simultaneamente:

- a fila recebe uma ocorrência já completa e validada;
- sucesso E2 não é publicado antes da durabilidade;
- falha/conflito não avança cooldown;
- a ordem E1 anterior à fábrica permanece intacta.

Os resultados futuros de aceite (`persistida`, equivalente, conflito e falhas tipadas) pertencem às tarefas 37 e 45. Esta tarefa não altera `CandidateResult` nem antecipa seus tipos.

### Lifecycle no corte

Hoje qualquer invalidação depois da fábrica causa dispose do `occurrence.image` antes do commit. Na E2, a tarefa 45.4 deverá distinguir os dois lados do ponto de não retorno durável:

- antes da seção final: cancelamento e limpeza E1;
- depois de iniciada a seção final: conclusão ou rollback da persistência, sem publicação por callback obsoleto;
- depois do commit íntegro: o JPEG canônico pertence à fila e não pode ser descartado pelo caminho E1 de stale result.

## 2. `OperationController`

### Estado atual

O controller possui `InMemoryOccurrence? _ownedOccurrence`. Em `_applyResult(CandidateCreated)` ele:

1. substitui `_ownedOccurrence`;
2. descarta a imagem da ocorrência anterior;
3. publica `succeeded` e “Buraco registrado em memória.”;
4. cria `OperationOccurrenceSummary`;
5. incrementa `sessionOccurrenceCount`.

Em pausa, navegação e `dispose`, `_takeOwnedOccurrence` transfere a ocorrência para `_deactivateResources`, que descarta a imagem. `_retireStaleResult` também descarta a imagem de um `CandidateCreated` obsoleto. Esse comportamento é correto para a E1 e seria destrutivo para um JPEG já aceito pela fila.

### Cortes futuros exatos

- **Resultado do processor:** `_applyResult` deverá distinguir novo aceite persistido, confirmação equivalente e falha/conflito. Somente novo aceite incrementa a sessão e recebe feedback nominal E2.
- **Retenção:** `_ownedOccurrence` não poderá continuar representando ownership do JPEG após persistência. O controller deve guardar somente resumo sanitizado; lifecycle e navegação não removem conteúdo da fila.
- **Stale result:** `_retireStaleResult` só pode limpar lease ainda pertencente ao fluxo E1; não pode receber ou descartar o artefato canônico da fila.
- **Observação:** pendências devem vir de `QueueSnapshot` confirmado, nunca de incremento otimista no controller.
- **Readiness/retry:** fila inicializando, degradada ou indisponível bloqueia registro, mas não reinicializa câmera/GPS e não impede o Diagnóstico.

Os testes atuais `operation_controller_test.dart` protegem single-flight, captura de horário/snapshot antes do primeiro `await`, contador somente em criação, callback obsoleto e limpeza da ocorrência E1 na pausa. Na futura tarefa 45/46, o último teste deve continuar válido para leases E1 não aceitas e ganhar cobertura separada demonstrando retenção do JPEG persistido.

## 3. `OperationState`

### Estado atual

`OperationState` é imutável e contém somente estados E1. `canRegister` exige Operação ativa, câmera pronta com preview, localização pronta com snapshot e ausência de processamento. Não existe campo de fila, recuperação, persistência ou pendências.

`OperationScreen` consome diretamente `state.canRegister`, `feedback`, `processingStatus` e `sessionOccurrenceCount`. O painel atual comunica “registros criados” da sessão, não pendências persistidas.

### Ampliação futura delimitada

Conforme tarefas 46.3–46.4 e 47, o ponto concreto é ampliar `OperationState`/`copyWith` e os consumidores correspondentes com:

- saúde da fila: inicializando, pronta, degradada ou indisponível;
- estado de recuperação/persistência necessário à apresentação;
- `pendingCount` derivado de snapshot confirmado;
- readiness que adiciona “fila pronta” às condições E1;
- manutenção separada de `sessionOccurrenceCount`.

Não devem entrar no estado: lista de registros, path, UUID completo de pendência, coordenadas, horário, digest, bytes, API key, URL, resposta HTTP ou ação de remoção.

## 4. Ownership e lease de imagem

### Cadeia atual concreta

1. `OperationalCamera.takePicture` devolve `TemporaryCapture`.
2. `PrivateJpegImagePreparer.prepare` consome a captura e produz `PrivatePreparedImage` visto pela aplicação como `OwnedPreparedImage`.
3. `InMemoryOccurrenceFactory` coloca a mesma lease opaca em `InMemoryOccurrence.image`.
4. `OperationController` retém a ocorrência e descarta a imagem ao substituir, pausar, navegar ou encerrar.

`OwnedPreparedImage` expõe apenas `dispose()`. A implementação concreta `PrivatePreparedImage` possui `file`, `width`, `height`, `byteLength`, `quality`, `mimeType`, `isActive` e `transferOwnership()`. `_FileLease.transfer()` invalida o token anterior e permite uma única transferência; `dispose` é idempotente.

`InMemoryImageOwner` e `PrivatePreparedImage.transferOwnership()` são atualmente exercitados na suíte de infraestrutura, mas o fluxo de produção processor → ocorrência → controller transporta a mesma instância opaca e não chama esse owner auxiliar. Portanto, eles constituem uma referência de semântica E1, não uma fila E2 preexistente.

### Corte futuro exato

A tarefa 37.4 deverá evoluir o contrato opaco somente com as capacidades mínimas necessárias ao aceite durável, sem fazer widgets ou domínio conhecerem `File`. As tarefas 42.5/45 deverão efetivar a transição:

```text
lease E1 ativa
  -> fila copia/valida/publica JPEG E2 e confirma linha
  -> fila assume ownership canônico
  -> lease E1 é retirada/limpa idempotentemente
```

Se qualquer etapa falhar antes do aceite, o fluxo atual continua responsável pela lease E1. Confirmação equivalente limpa somente o temporário novo e preserva o canônico existente. Lifecycle posterior não toca o JPEG canônico.

Os testes `private_image_pipeline_test.dart` já protegem transferência única, dispose idempotente, limpeza por substituição/fim de sessão, namespace privado e log sanitizado; são o baseline de regressão para as futuras propriedades 13, 15 e 17.

## 5. Cooldown

### Estado atual

`CooldownPolicy` mantém `_lastCreated` apenas em memória. `evaluate` não altera a referência; `commit` extrai `detectedAt` e ponto de uma ocorrência completa. O processor é o único chamador funcional encontrado para `commit`.

Os testes `cooldown_policy_test.dart` fixam defaults, primeira ocorrência, limites inclusivos, regra tempo **OU** distância, relógio regressivo e ausência de alteração sem commit.

### Corte futuro exato

Dois pontos distintos deverão ser atendidos futuramente:

1. na tarefa 45, mover semanticamente o momento de commit para depois do resultado `persistida`;
2. na tarefa 46, restaurar ou limpar a referência durante bootstrap, usando a pendência de maior `queueSequence` e sem incrementar o contador da sessão.

A interface atual `CandidateCooldown` só oferece `evaluate` e `commit`, e `_lastCreated` é privado. Portanto, não existe ainda um ponto de restauração. A futura tarefa 46 precisará adicionar uma operação explícita mínima de restauração/limpeza ou uma inicialização equivalente, sem alterar a matemática de `evaluate`. Esta evidência apenas identifica essa lacuna concreta.

Confirmação equivalente não representa um segundo novo aceite da execução; ela deve reconciliar a referência existente sem duplicar sessão ou pendência. Falha e conflito não avançam a referência.

## 6. Composition root

### Estado atual

`main.dart`:

1. cria e varre o namespace temporário E1;
2. compõe câmera, localização, relógio, UUID, distância, wake lock e preparador;
3. instancia `CooldownPolicy` inline no construtor de `E1PostCandidateProcessor`;
4. injeta processor/fonte/portas em `OperationController`;
5. inicia `PavimentaAiMobileApp`, mantendo o Diagnóstico E0 em sessão própria.

O helper `composeE1` e `E1Composition` são exercitados pelo teste arquitetural `e1_contracts_test.dart`; a busca encontrou uso de `composeE1` somente nesse teste. A produção em `main()` monta os objetos diretamente.

### Cortes futuros exatos

- manter uma referência compartilhada e explícita ao `CooldownPolicy`, porque o bootstrap precisa restaurá-lo antes do readiness da fila;
- criar as implementações E2 somente após os contratos e dependências das tarefas anteriores: banco/store durável, fila/coordenador, acceptance port e observer/snapshot;
- injetar o acceptance port no processor e o limite de snapshot/retry necessário no controller;
- coordenar bootstrap sem acoplar SQLite/filesystem à apresentação;
- manter câmera, GPS, relógio, fonte manual, preparador E1, wake lock e sessão E0 preservados;
- não reutilizar nem generalizar `DiagnosticHttpClient` como cliente de ocorrências.

`composeE1`/`E1Composition` precisarão ser ampliados ou substituídos por uma composição E2 testável apenas quando as tarefas 45/46 forem executadas. Nenhuma mudança foi feita agora.

## Ordem futura de implementação já delimitada pelo plano

Este mapa não autoriza antecipação. Os pontos acima pertencem às tarefas posteriores já ordenadas:

1. **37.4:** capacidade mínima da lease;
2. **38–44:** modelos, armazenamento, fila, bootstrap/recuperação e remoção interna sem chamador funcional;
3. **45:** acceptance port no processor, ownership e resultado;
4. **46:** bootstrap, snapshot, cooldown restaurado, controller e estado;
5. **47:** apresentação de pendências/saúde sem gestão de fila;
6. **48:** propriedades 13–20 e integração consolidada.

## Invariantes de preservação para a integração futura

- `PostCandidateProcessor` continua independente da fonte manual e de widgets.
- Cooldown continua antes da aquisição de imagem; bloqueio continua sem captura, UUID ou ocorrência.
- O aceite persistente ocorre depois da ocorrência completa e antes de cooldown/sucesso.
- Somente `persistida` representa novo aceite e incremento da sessão.
- Pendências vêm da fila, não da UI.
- JPEG persistido nunca é descartado por pausa, navegação ao Diagnóstico ou encerramento da sessão operacional.
- A fila indisponível bloqueia novos registros, mas não impede preview, GPS, interface ou Diagnóstico.
- E0 e seu `DiagnosticHttpClient` permanecem isolados.
- Não há nesta etapa rede de ocorrências, configuração, credencial, multipart, retry, worker, YOLO, TFLite ou inferência.

## Resultado

**Mapeamento concreto concluído sem alteração de comportamento.** Foram identificados os símbolos atuais, o corte exato entre fábrica e cooldown, o ownership E1 que deverá deixar o controller, a ampliação futura do estado/readiness, a lacuna explícita de restauração do cooldown e os objetos que o composition root deverá compor somente nas tarefas E2 correspondentes.

A única alteração desta execução é este novo arquivo de evidência. O status da tarefa permanece sob responsabilidade exclusiva do orquestrador.
