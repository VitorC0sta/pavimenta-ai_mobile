# Evidência da tarefa 49.6 — Validação consolidada E2

## Escopo e preservação histórica

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Tarefa executada: **49.6 — Registrar saídas completas, quantidade de testes/propriedades e inspeção negativa em evidência E2 nova, sem alterar evidências históricas E0/E1**.
- Documentos normativos consultados antes da execução: `requirements.md`, `design.md` e `tasks.md` do spec `mvp-app-flutter`.
- O diretório do spec não contém `.config`; portanto, é uma spec comum, não uma spec de bugfix.
- Evidências históricas E0/E1 foram somente lidas; não foram modificadas. Este arquivo é o novo registro exclusivo da E2.
- Requisitos cobertos: RF-00.22, RF-12.6, RF-23.1–10, RNF-01.1–13, RNF-03.1–10, RNF-07.3 e RNF-07.10.

## Correção mínima decorrente da validação

A primeira análise encontrou exclusivamente duas importações não usadas em `lib/main.dart`:

```text
warning - Unused import: 'domain/in_memory_occurrence.dart' - lib\main.dart:13:8 - unused_import
warning - Unused import: 'domain/persistent_occurrence.dart' - lib\main.dart:14:8 - unused_import
2 issues found. (ran in 19.6s)
```

Foram removidas somente essas duas importações. Não houve alteração de comportamento, dependência, configuração Android ou documento normativo. A validação consolidada abaixo foi executada depois da correção.

## Saídas completas das validações finais

### Formatação

Comando:

```powershell
dart format --output=none --set-exit-if-changed lib test
```

Saída:

```text
Formatted 75 files (0 changed) in 0.93 seconds.
FORMAT_EXIT=0
```

Resultado: a formatação está estável; nenhum dos 75 arquivos Dart verificados precisou ser alterado.

### Análise estática

Comando:

```powershell
flutter analyze
```

Saída:

```text
Analyzing pavimenta-ai_mobile...
No issues found! (ran in 4.1s)
ANALYZE_EXIT=0
```

Resultado: zero issues.

### Suíte automatizada completa

Comando:

```powershell
flutter test
```

Saída consolidada do runner:

```text
TEST_EXIT=0
```

O comando foi executado após a análise e terminou com código `0`; o script somente avançou para o inventário e para a inspeção negativa depois desse resultado. A execução inclui os testes de SQLite/filesystem, política Android XML/manifesto, integração da fila, testes de UI/arquitetura e regressões E0/E1, além das propriedades E2 13–20.

Inventário estático dos testes descobertos:

```text
TEST_FILES=38
EXPLICIT_TEST_CASES=201
PBT_CASES=8
PBT_PROPERTY_MARKERS=8
PBT_120_RUN_CONFIGS=8
```

Assim, a suíte contém 201 casos de teste declarados, dos quais 8 são propriedades PBT E2. Cada propriedade possui um marcador de rastreabilidade e configuração de 120 execuções — acima do mínimo de 100 definido para E2:

1. Property 13 — Aceite somente após persistência íntegra;
2. Property 14 — Round-trip da fila;
3. Property 15 — Unicidade idempotente;
4. Property 16 — Contagem derivada da fila;
5. Property 17 — Ownership exclusivo após aceite;
6. Property 18 — Remoção consistente;
7. Property 19 — Recuperação idempotente;
8. Property 20 — Restauração da referência de cooldown.

## Inspeção negativa de escopo E0–E2

### Capacidades futuras vedadas

Foi pesquisado recursivamente em `lib/`, `android/`, `pubspec.yaml` e `pubspec.lock` o conjunto:

```text
BASE_URL|DEVICE_API_KEY|flutter_secure_storage|OccurrenceApiClient|
multipart/form-data|MultipartRequest|sendOccurrence|uploadOccurrence|
workmanager|ultralytics_yolo|tflite|tensorflow|inferenceFps|maxInferenceFps
```

Saídas:

```text
STRICT_PROHIBITED_MATCHES=0
FORBIDDEN_MATCHES_WITH_DEPENDENCIES=0
FUTURE_MODEL_ASSETS=0
BACKGROUND_COMPONENT_REFERENCES=0
```

Não há BASE_URL, chave de dispositivo, secure storage, cliente de ocorrências, multipart, envio/upload, worker/background, YOLO, TFLite, TensorFlow, inferência, FPS de inferência ou asset de modelo (`.tflite`, `.onnx`, `.pt`, `.pth`, `.weights`).

### Banco e dependências E2 permitidos

A inspeção encontrou somente a persistência local esperada da E2:

```text
E2_SQLITE_SCHEMA_REFERENCES=14
```

Dependências diretas efetivas observadas:

```text
camera: 0.11.0+2
geolocator: 13.0.2
image: 4.2.0
uuid: 4.6.0
wakelock_plus: 1.2.8
path_provider: 2.1.4
sqflite: 2.4.1
crypto: 3.0.7
glados: 1.1.7
sqflite_common_ffi: 2.3.4+4
```

`sqlite`/`sqflite`, `crypto`, `glados` e `sqflite_common_ffi` são capacidades de persistência, integridade e teste local da E2; não fornecem integração de envio.

### HTTP, retry e remoção interna: classificação

A busca por `HttpClient` retornou exatamente três referências, todas em `lib/e0/diagnostic_http_client.dart`:

```text
HTTP_CLIENT_REFERENCES=3
lib/e0/diagnostic_http_client.dart:44:HttpClient? _activeClient;
lib/e0/diagnostic_http_client.dart:66:final client = HttpClient()
lib/e0/diagnostic_http_client.dart:204:required HttpClient client,
```

Logo, o único cliente HTTP continua isolado no Diagnóstico preservado da E0. Não existe cliente HTTP de ocorrências E2.

A busca por backoff retornou zero e a busca por retry retornou 16 referências:

```text
BACKOFF_REFERENCES=0
RETRY_REFERENCES=16
```

As 16 referências são exclusivamente retry de bootstrap/recuperação da fila local E2 e botões de nova tentativa para a prontidão de câmera, GPS ou fila; não incluem rede, endpoint, autenticação, status HTTP de ocorrência ou reenvio. Elas não representam a política de retry/backoff de transporte, reservada à E4.

A remoção E2 permanece uma operação interna sem chamador funcional de produção:

```text
REMOVE_INTERNAL_DECLARATION_OR_REFERENCE_COUNT=3
lib/application/e2_persistence_ports.dart:102:Future<QueueRemovalResult> removeInternal(String idempotencyKey);
lib/infrastructure/persistent_occurrence_queue.dart:622:Future<QueueRemovalResult> removeInternal(String idempotencyKey) async =>
lib/infrastructure/persistent_occurrence_queue.dart:875:Future<QueueRemovalResult> removeInternal(String idempotencyKey) async {
```

As três ocorrências são a declaração de porta e duas implementações (indisponível e coordenada); não existe invocação em código de produção. A suíte completa também executou o teste arquitetural que confirma essa ausência de chamador funcional.

## Resultado

**APROVADO para a tarefa 49.6.** Depois da remoção de duas importações não usadas, a formatação ficou estável, `flutter analyze` terminou com zero issues e `flutter test` completo terminou com código 0. Há 38 arquivos de teste, 201 casos declarados e 8 propriedades E2, cada uma com 120 execuções configuradas. A inspeção negativa confirma que o projeto contém somente capacidades E0–E2: diagnóstico HTTP E0 isolado, captura/operação E1 e fila SQLite/JPEG local E2; não há capacidades de configuração, credenciais, rede de ocorrências, envio, retry/backoff de transporte, worker, modelo ou inferência das etapas E3–E5.

Esta evidência técnica não aprova o Validation Gate físico E2 nem inicia a tarefa 50 ou qualquer etapa posterior.
