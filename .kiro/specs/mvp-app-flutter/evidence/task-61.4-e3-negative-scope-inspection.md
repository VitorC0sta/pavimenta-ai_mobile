# Evidência da tarefa 61.4 — Inspeção negativa de transporte, execução e inferência E3

## Escopo

- Tarefa executada: **61.4 — Apresentar inspeção negativa comprovando ausência de HTTP de ocorrência, autenticação, multipart, worker, backoff, YOLO/TFLite/modelo/inferência.**
- Documentos normativos consultados: `requirements.md`, `design.md` e `tasks.md` da spec `mvp-app-flutter`.
- A pasta da spec não contém `.config` nem `.config.kiro`; esta é uma spec regular, não um bugfix.
- Limite E3 aplicado: conforme E3.1 e E3.7 do design, Configurações pode persistir parâmetros não secretos e o status/valor protegido da credencial, mas não pode introduzir cliente ou endpoint de ocorrências, `POST`, `Authorization`, multipart, envio, worker, retry/backoff ou implementação YOLO/TFLite/inferência.
- Esta tarefa somente inspecionou o estado existente, executou a verificação automatizada dirigida e criou esta evidência. Não alterou código de produção, dependências, Android, testes, credenciais, dados locais ou tarefas 61.5–61.6. E4 e E5 não foram iniciadas.

## Inspeção das fontes e da composição

A busca dirigida em `lib/**/*.dart` não encontrou, fora do Diagnóstico E0, endpoint ou transporte de ocorrência. Não há ocorrência de `POST`, `.post(`, `.send(`, `multipart/form-data`, `MultipartRequest`, `MultipartFile`, `Authorization`, `ApiKey`, `Bearer`, `X-API-Key` ou import de `package:http`/`package:dio`.

As duas referências ao caminho futuro são controles permitidos, sem chamada de rede de ocorrência:

| Local | Referência observada | Classificação |
|---|---|---|
| `lib/settings/settings_screen.dart` | Orienta o operador a não incluir `/api/v1/occurrences` em `BASE_URL`. | Texto de validação/configuração E3; não monta nem transmite endpoint. |
| `lib/e0/diagnostic_http_client.dart` | Rejeita explicitamente `/api/v1/occurrences` e `/api/v1/occurrences/`. | Proteção do GET HTTPS diagnóstico E0; não é cliente de ocorrências. |

`HttpClient` ocorre somente no Diagnóstico E0, composto em `lib/main.dart` como `DiagnosticHttpClient`. A implementação usa `client.getUrl(destination)` e mantém o destino de ocorrências rejeitado antes de abrir conexão. Não há `HttpClient` em fontes não diagnósticas, nem caminho de composição de transporte a partir de Operação, fila ou Configurações.

A busca por execução antecipada não encontrou `Workmanager`, `BackgroundFetch`, `BackgroundService`, `Worker`, `backoff`, `exponentialBackoff`, agendamento de envio ou temporizador de reenvio. As correspondências de `retry` observadas são apenas as ações explícitas e locais de recuperação de bootstrap E2, permissões, câmera, localização e carregamento de Configurações. Elas não chamam rede, não processam fila para entrega e não programam tentativa automática.

A busca por visão computacional não encontrou import, pacote, classe, asset ou operação de `ultralytics_yolo`, `tflite_flutter`, TensorFlow, YOLO, `startImageStream`, `CameraImage`, `ImageStream`, processador de frame, loader/runner de modelo ou inferência. As correspondências permitidas são exclusivamente:

- o banner E1 `Modo manual — YOLO ainda não configurado`;
- os campos E3 `confidenceThreshold` e `maximumInferenceFps`, que apenas representam, validam, persistem e exibem parâmetros reservados para E5.

Esses parâmetros não são consumidos por loop de frames, modelo ou detector. Portanto, não constituem inferência, ainda que conservem a configuração futura aprovada.

## Dependências, assets e Android

A inspeção de `pubspec.yaml` não encontrou dependências diretas de transporte de ocorrência, worker ou visão computacional: `http`, `dio`, `workmanager`, `flutter_background_service`, `background_fetch`, `ultralytics_yolo`, `tflite_flutter`, `tflite_flutter_helper` e TensorFlow estão ausentes. As dependências E3 presentes são `shared_preferences: 2.5.2` e `flutter_secure_storage: 9.2.4`, permitidas somente para configuração não secreta e credencial protegida.

Também não há seção `assets` nem referências a `.tflite`, `.onnx`, `.pt` ou TorchScript no manifesto Flutter. A busca em `android/**` não encontrou referência a endpoint, autenticação, multipart, worker/backoff, YOLO, TFLite ou TensorFlow. O APK debug, seus metadados, manifests mesclados e dependências foram gerados e inspecionados na evidência técnica imediatamente anterior [task-61.1-e3-technical-validation.md](task-61.1-e3-technical-validation.md); esta tarefa não o reconstruiu nem modificou.

## Verificação automatizada dirigida

Foi executado em modo único, com código de saída `0`:

```text
flutter test test/architecture/e3_configuration_boundaries_test.dart --reporter expanded
```

Resultado observado:

```text
+1: E3 contains no worker, backoff, or model inference implementation
+2: E3 keeps confidence and FPS as future parameters without frame loops
+3: All tests passed!
```

O teste inspeciona todos os arquivos Dart de produção. Ele falha se houver import proibido, transporte de ocorrência fora de `lib/e0/`, `HttpClient` não diagnóstico, `POST`/envio, header de autenticação, multipart, worker, backoff, pacote de modelo ou processamento de frames. O teste admite somente a orientação de UI sobre o endpoint futuro, o banner manual obrigatório e os dois parâmetros E5 persistidos na E3, sem permitir sua execução.

## Matriz de resultado

| Capacidade excluída da E3 | Resultado | Evidência |
|---|---|---|
| HTTP/cliente de ocorrência e `POST` | Ausente | Nenhuma implementação fora do GET diagnóstico E0; endpoint futuro apenas rejeitado/orientado. |
| Autenticação de ocorrência | Ausente | Sem `Authorization`, `ApiKey`, `Bearer`, `X-API-Key` ou composição de header. |
| Multipart | Ausente | Sem tipos, MIME, request ou montagem `multipart/form-data`. |
| Worker e envio em segundo plano | Ausente | Sem pacote, serviço, worker ou caminho de envio programado. |
| Retry/backoff de entrega | Ausente | Sem backoff/agendamento; retries existentes são ações locais e explícitas, sem rede. |
| YOLO/TFLite/modelo/inferência | Ausente | Sem pacote, asset, loader, stream de imagens, processador de frames ou executor; somente banner e parâmetros futuros permitidos. |

## Resultado

**Sucesso no escopo da tarefa 61.4.** A inspeção estática e o teste arquitetural dirigido comprovam que a E3 permanece limitada a configuração e armazenamento seguro, sem antecipar transporte/autenticação/multipart de ocorrências, worker/backoff ou YOLO/TFLite/modelo/inferência.

Esta conclusão não aprova o Validation Gate E3, não elimina as pendências físicas já declaradas e não registra a decisão explícita reservada às tarefas 61.5 e 61.6.
