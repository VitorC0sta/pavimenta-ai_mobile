# Evidência da tarefa 31.3 — Presença, execução e aprovação da suíte E1

## Escopo verificado

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`
- Subtarefa exclusiva: **31.3 — Confirmar que todos os testes planejados e criados nas tarefas 19–28 estão presentes, executados e aprovados**.
- Documentos usados como fonte normativa: `requirements.md`, `design.md` (E1.27–E1.30) e `tasks.md` (tarefas 19–28 e 31.3).
- Requisitos de fechamento: RF-23.7, RNF-03.1–10 e RNF-07.2.
- Limite preservado: somente E0/E1; nenhuma fila, banco, API de ocorrências, multipart, credencial, envio, modelo, inferência ou FPS foi adicionado.

O diretório do spec não contém arquivo `.config`; estão presentes `requirements.md`, `design.md`, `tasks.md` e `tasks.meta.json`. A execução foi tratada como spec comum, não bugfix, conforme o conteúdo aprovado.

## Auditoria inicial

A evidência anterior registrava 66 testes aprovados, mas também duas lacunas:

1. testes diretos dos adaptadores operacionais e estados de GPS da tarefa 24;
2. testes de navegação e regressão E0 da tarefa 28.

A inspeção do estado atual mostrou que `test/operation/operation_diagnostic_navigation_test.dart` e os cenários de push/pop, repetição de rotas, espera pelo dispose e exclusão mútua já estavam presentes, embora a evidência anterior ainda os declarasse ausentes. Permaneciam efetivamente ausentes:

- testes diretos de `OperationalCamera` e `OperationalLocation` sem hardware;
- classificação operacional distinta de serviço desligado, permissão negada, negação permanente, precisão reduzida e posição indisponível;
- regressão automatizada direta do fluxo E0 para preview, ordem de permissões, GPS, HTTPS, mensagens e lifecycle.

## Alterações necessárias para fechar as lacunas

### Testes adicionados

- `test/infrastructure/operational_adapters_test.dart`
  - seleção da câmera traseira;
  - preview com resolução moderada e áudio desabilitado;
  - captura única pelo mesmo controlador;
  - adoção da captura no namespace privado E1 e remoção do arquivo de origem;
  - câmera traseira ausente sem construção de controlador;
  - solicitação de localização somente após a câmera terminar;
  - snapshot preciso imutável, atualização por stream e invalidação no release;
  - serviço desativado, permissão negada, negação permanente, precisão reduzida e posição indisponível;
  - continuidade do GPS quando a câmera falha;
  - mapeamento dos erros controlados para os estados de apresentação corretos.

- `test/e0/e0_regression_test.dart`
  - ordem câmera → localização e resolução serial das permissões;
  - preview traseiro disponível;
  - latitude, longitude, precisão e velocidade preservadas;
  - execução e classificação HTTPS sanitizada;
  - rejeição local de URLs ausentes, relativas, HTTP, sem host, com credencial, fragmento ou endpoint proibido;
  - mensagens controladas para indisponibilidades de GPS e TLS;
  - pausa e limpeza de câmera/localização/HTTPS pelo lifecycle.

### Código mínimo corrigido para testabilidade e comportamento

- `lib/application/e1_ports.dart`: adicionadas categorias neutras e controladas de falha de localização, sem dependência do plugin ou da UI.
- `lib/infrastructure/operational_camera.dart`: adicionados callbacks opcionais de infraestrutura para fakes Dart; os defaults continuam usando `camera`, `ResolutionPreset.medium`, áudio desabilitado e o mesmo fluxo de produção.
- `lib/infrastructure/operational_location.dart`: adicionados callbacks opcionais para fakes Dart e classificação explícita das precondições/falhas; os defaults continuam usando `geolocator` em primeiro plano e alta precisão.
- `lib/operation/operation_controller.dart`: erros controlados de localização passaram a alimentar os estados já existentes (`serviceDisabled`, `permissionDenied`, `permissionDeniedPermanently`, `reducedAccuracy`, `unavailable`) em vez de colapsarem todos em “Posição indisponível”.

Nenhuma dependência foi adicionada e nenhum arquivo aprovado de requisitos/design/tarefas foi alterado por esta execução.

## Arquivos de teste presentes e executados

A execução completa descobriu e executou estes 11 arquivos:

1. `test/application/post_candidate_processor_test.dart`
2. `test/architecture/e1_contracts_test.dart`
3. `test/candidate/manual_candidate_source_test.dart`
4. `test/domain/cooldown_policy_test.dart`
5. `test/domain/in_memory_occurrence_test.dart`
6. `test/e0/e0_regression_test.dart`
7. `test/infrastructure/operational_adapters_test.dart`
8. `test/infrastructure/private_image_pipeline_test.dart`
9. `test/operation/operation_controller_test.dart`
10. `test/operation/operation_diagnostic_navigation_test.dart`
11. `test/operation/operation_screen_test.dart`

## Matriz de cobertura confirmada — tarefas 19–28

| Tarefa | Contratos e cenários obrigatórios encontrados e executados | Resultado |
|---|---|---|
| 19 — ocorrência, horário, UUID, localização e velocidade | modelos imutáveis; limites de coordenadas; FakeClock/instante único; UUID v4; `confidence = 1.0`; `defectClass = pothole`; campos excluídos; conversão `m/s * 3.6`; zero/300 incluídos; demais velocidades omitidas | Presente e aprovada |
| 20 — cooldown por tempo OU distância | Haversine; primeira ocorrência; defaults 5 s/15 m; limites inclusivos; regra OR; rejeição apenas com ambos abaixo; relógio regressivo; ausência de avanço sem commit; commit somente no sucesso | Presente e aprovada |
| 21 — JPEG privado, ownership e limpeza | EXIF/orientação; proporção; máximo 1280x720; JPEG 85 em todas as tentativas; máximo 2 MiB; redução somente de dimensões; monotonicidade/terminação; rejeição; leases; substituição/dispose; órfãos; logs sanitizados; ausência de galeria | Presente e aprovada |
| 22 — fonte manual substituível | instante/localização preservados; `pothole`; `1.0`; aquisição diferida não invocada na emissão; ausência de `source`, API e persistência | Presente e aprovada |
| 23 — pós-candidato genérico | ordem validar → cooldown → capturar → preparar → UUID → fábrica → commit; aquisição única; bloqueio sem efeitos; limpeza em falhas; commit só no sucesso; independência da origem | Presente e aprovada |
| 24 — câmera e GPS operacionais | câmera traseira/preview/captura pelo mesmo controlador; câmera indisponível; captura privada; GPS sem serviço/permissão/precisão/posição; snapshot e stream válidos; câmera antes de localização; falhas independentes; regressão automatizada E0 | Presente e aprovada |
| 25 — estado, controlador e single-flight | readiness; botão bloqueado/habilitado; toques concorrentes; instante/snapshot antes do primeiro `await`; contador só no sucesso; geração e callback obsoleto sem efeitos | Presente e aprovada |
| 26 — tela, tema e feedbacks | banner/labels; paleta e contraste; estado não comunicado só por cor; botão enabled/disabled/busy; cooldown; status e erros; semântica; escala de texto e dimensões responsivas | Presente e aprovada |
| 27 — lifecycle e tela ligada | condição `visible && foreground && resumed && currentRoute`; bloqueios fora de resumed; callback tardio; limpeza; retomada após cleanup; wake lock idempotente/balanceado e falhas controladas | Presente e aprovada |
| 28 — navegação e exclusão mútua | Operação inicial; ação Diagnóstico; suspensão/liberação antes do push; dispose E0 antes da readquisição; lifecycle após pop; toques e rotas repetidos; no máximo um owner/stream; permissões sem duplicação; regressão funcional E0 de preview/GPS/HTTPS/mensagens/lifecycle | Presente e aprovada |

## Comandos e resultados

### Formatação e primeira execução completa

```powershell
dart format "lib/application/e1_ports.dart" "lib/infrastructure/operational_camera.dart" "lib/infrastructure/operational_location.dart" "lib/operation/operation_controller.dart" "test/infrastructure/operational_adapters_test.dart" "test/e0/e0_regression_test.dart"
flutter test --reporter expanded
```

A primeira execução do runner encontrou um erro de compilação exclusivamente no novo fake: uso de `const` sobre a factory não constante `ImmutableGeoPoint`. Até a detecção, os testes carregados não apresentaram falha comportamental. O teste foi corrigido sem alterar cenário ou produção.

### Execução consolidada final

```powershell
dart format "test/infrastructure/operational_adapters_test.dart"
flutter test --reporter expanded
```

Resultado verificável:

```text
Formatted 1 file (0 changed) in 0.22 seconds.
...
00:04 +82: All tests passed!

Exit Code: 0
```

**Resultado final: 82 testes aprovados, zero falhas, exit code 0.**

## Conclusão da tarefa 31.3

**CONCLUÍDA.** Todos os testes planejados e exigidos nas tarefas 19–28 estão presentes, foram descobertos pela suíte completa, executados e aprovados. A cobertura fecha explicitamente RF-23.7, RNF-03.1–10 e fornece a parte automatizável do roteiro exigido por RNF-07.2.

## Limitações

- Os adaptadores de plugins foram validados com fakes Dart e filesystem temporário real; disponibilidade física de câmera, GPS, permissões Android e comportamento no Samsung Galaxy S25+ continuam pertencendo ao roteiro/gate físico E1, não são substituídos por estes testes.
- A tarefa 31.3 confirma cobertura automatizada e não aprova o Validation Gate físico.
- Nenhuma funcionalidade E2–E5 foi criada ou simulada.
