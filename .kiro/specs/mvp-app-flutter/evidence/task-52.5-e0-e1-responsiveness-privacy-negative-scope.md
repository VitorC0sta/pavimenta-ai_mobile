# Evidência da tarefa 52.5 — Regressão E0/E1, responsividade, privacidade e escopo negativo

## Escopo e limites

- Tarefa executada: **52.5 — Apresentar regressão E0/E1, responsividade, privacidade, logs sanitizados e inspeção negativa demonstrando ausência de configuração, credencial, envio, backoff, worker, YOLO, TFLite, inferência e FPS.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Documentos consultados: `requirements.md`, `design.md` e `tasks.md` da spec `mvp-app-flutter`.
- O diretório da spec não contém `.config`; esta é uma spec comum, não uma spec de bugfix.
- Nenhum código de produção, dependência, manifesto, configuração Android, banco, JPEG, dado do dispositivo ou evidência histórica E0/E1 foi alterado. Este arquivo novo é a única alteração desta tarefa.
- Esta apresentação **não aprova o Validation Gate E2**, não registra decisão do usuário e não executa as tarefas 52.6 ou 52.7.

A seção E2.1–E2.3 do design preserva E0/E1 e limita E2 à fila local. Ela proíbe explicitamente configuração de ocorrências, credencial, cliente/tráfego HTTP de ocorrências, envio, retry/backoff de transporte, worker/background, YOLO, TFLite, inferência e FPS. A seção E2.23 requer regressão E0/E1, evidência sanitizada e ausência comprovada dessas capacidades antes de o gate ser apresentável.

## Validação automatizada atual

### Análise estática

```powershell
flutter analyze
```

Resultado:

```text
Analyzing pavimenta-ai_mobile...
No issues found! (ran in 3.1s)
Exit Code: 0
```

### Regressão dirigida E0/E1, responsividade e privacidade

```powershell
flutter test test/e0/e0_regression_test.dart test/operation/operation_screen_test.dart test/operation/operation_queue_screen_test.dart test/operation/operation_diagnostic_navigation_test.dart test/infrastructure/durable_image_store_test.dart test/architecture/e2_dependency_policy_test.dart test/architecture/e2_contract_boundaries_test.dart
```

Resultado:

```text
00:07 +44: All tests passed!
Exit Code: 0
```

Os 44 testes aprovados cobrem, entre outros:

| Aspecto | Evidência automatizada atual |
| --- | --- |
| Diagnóstico E0 preservado | `e0_regression_test.dart` preserva preview traseiro, ordem serial de permissões, GPS, HTTPS diagnóstico restrito, mensagens controladas e limpeza no ciclo de vida. URLs sem HTTPS, com credencial/fragmento ou com `/api/v1/occurrences` são rejeitadas antes de conexão. |
| Operação E1 preservada | `operation_screen_test.dart` confirma modo manual inequívoco, preview, GPS, contador e entrada rotulada para o Diagnóstico; `operation_diagnostic_navigation_test.dart` confirma liberação de câmera/GPS antes da rota E0 e recuperação sem sessões, permissões ou streams duplicados. |
| Responsividade | O teste de layout reduz o viewport para `320x480` com escala de texto `2`, mantém mensagens de permissão/ciclo de vida e o controle de registro acessíveis por rolagem, sem exceção; em `1000x800`, confirma a distribuição em colunas. `operation_queue_screen_test.dart` mantém preview, GPS, Diagnóstico e indicadores utilizáveis durante a persistência local, bloqueando apenas o registro concorrente. |
| Privacidade da interface | `operation_queue_screen_test.dart` confirma mensagens agregadas e sanitizadas da fila e a ausência, no painel, de UUID, path privado, namespace de imagem, coordenada e digest. Também confirma ausência de controles de lista/remoção de pendências, configurações, envio e detecção automática ativa. |
| Limites arquiteturais | Os testes de política de dependências e de fronteiras E2 aprovados no mesmo comando protegem contra dependências e chamadores fora do escopo, incluindo remoção interna sem chamador funcional de produção. |

Esta execução é automatizada; não é apresentada como substituta de observação física.

## Regressão física E0/E1 já aplicável

A evidência física não destrutiva mais recente é [task-51.8-e0-e1-regression-and-negative-scope.md](task-51.8-e0-e1-regression-and-negative-scope.md). Ela registra, no Samsung Galaxy S25+ (`SM-S936B`), a rota:

```text
Operação E1/E2 → Diagnóstico E0 → HTTPS diagnóstico manual → Operação E1/E2
```

Os resultados físicos já registrados e preservados são:

- preview traseiro e GPS operacionais na Operação antes da navegação;
- banner de modo manual, sem alegação de detecção automática;
- Diagnóstico E0 aberto com preview, localização e aviso explícito de que nenhum dado de ocorrência é criado ou enviado;
- diagnóstico HTTPS manual com o destino fictício padrão, produzindo a falha controlada esperada e sem servidor/URL funcional de produção;
- retorno à Operação com câmera e GPS readquiridos sem duplicação e com a contagem agregada de pendências inalterada;
- ausência de ANR/falha fatal no processo durante a rota;
- ausência de incremento automático de tráfego após o retorno à Operação; o único tráfego observado ocorreu após o toque explícito no diagnóstico HTTPS E0.

A evidência física complementar [task-51.6-privacy-responsiveness-navigation.md](task-51.6-privacy-responsiveness-navigation.md) mantém as limitações honestas: a comprovação física de ausência no MediaStore e a captura visual do estado transitório de persistência ficaram pendentes. A cobertura de widget acima permanece complementar e não reclassifica tais limites físicos.

## Privacidade e logs sanitizados

### Dados e interface

A cobertura dirigida não permite que o painel da fila renderize UUID, paths privados, namespace de imagem, coordenadas ou digest. A interface expõe somente estados e contagens agregadas necessários à operação local.

### Logs técnicos

A busca recursiva em `lib/**/*.dart` por APIs diretas de emissão (`debugPrint`, `print(` e `log(`) retornou **nenhuma ocorrência**.

As integrações de armazenamento E1/E2 recebem por padrão o sumidouro `_discardLog`, que não emite o texto recebido. Quando um logger técnico é injetado para diagnóstico controlado, as mensagens preservam apenas o nome da operação/categoria e `error.runtimeType`:

```text
E1_IMAGE_CLEANUP_FAILED operation=<categoria> kind=<categoria> error=<tipo>
E2_IMAGE_OPERATION_FAILED operation=<categoria> error=<tipo>
E2_QUEUE_OPERATION_FAILED operation=<categoria> error=<tipo>
```

Elas não incluem bytes JPEG, UUID, path absoluto, nome de arquivo canônico, coordenadas, horário, digest, URL, API key ou corpo/header HTTP.

O único fluxo HTTP permitido é o `DiagnosticHttpClient` preservado da E0. Ele usa somente `E0_DIAGNOSTIC_URL` fornecida em tempo de compilação com default fictício; valida HTTPS, host, credenciais embutidas, fragmento e caminho proibido antes de conectar. Ele descarta o corpo sob limites e retorna apenas classificação sanitizada e código HTTP opcional. Essa configuração diagnóstica E0 não é `BASE_URL`, não é configuração E3 e não habilita envio de ocorrência.

## Inspeção negativa recursiva atual

A busca recursiva atual em `lib/**/*.dart` e `android/**` pelo conjunto abaixo retornou **nenhuma ocorrência**:

```text
BASE_URL|DEVICE_API_KEY|flutter_secure_storage|OccurrenceApiClient|
sendOccurrence|uploadOccurrence|MultipartRequest|multipart/form-data|
Authorization: ApiKey|nextAttemptAt|backoff|workmanager|WorkManager|
ultralytics_yolo|tflite_flutter|tensorflow|inferenceFps|maxInferenceFps
```

Também não foram encontrados assets `.tflite` ou `.onnx` no workspace pesquisável. Em conjunto com os pins de produção atuais — `camera`, `geolocator`, `image`, `uuid`, `wakelock_plus`, `path_provider`, `sqflite` e `crypto` — a inspeção confirma:

| Capacidade | Resultado |
| --- | --- |
| Configuração de envio / `BASE_URL` | Ausente |
| Credencial / API key / secure storage | Ausente |
| Cliente, endpoint, multipart, autenticação ou envio de ocorrência | Ausente |
| `nextAttemptAt`, backoff ou política de reenvio | Ausente |
| WorkManager, worker, serviço/execução de envio em background | Ausente |
| YOLO, TFLite/TensorFlow, asset de modelo, inferência ou FPS de inferência | Ausente |

A palavra `YOLO` pode aparecer somente como texto negativo do banner manual aprovado (por exemplo, “YOLO ainda não configurado”), que comunica indisponibilidade; não representa pacote, modelo, detector, stream de frames ou inferência.

## Conclusão

**Evidência apresentada para a tarefa 52.5.** A análise estática não encontrou issues e a regressão dirigida atual passou com 44 testes. As evidências físicas E0/E1 previamente aprovadas permanecem preservadas e referenciadas, enquanto limitações físicas ainda pendentes permanecem explícitas. Interface e logs são sanitizados, e a inspeção recursiva atual confirma ausência de configuração, credencial, envio, backoff, worker, YOLO, TFLite, inferência e FPS das etapas E3–E5.

Este resultado satisfaz somente a apresentação/evidência da tarefa 52.5; o Validation Gate E2 continua pendente de decisão explícita do usuário e nenhuma etapa posterior foi iniciada.
