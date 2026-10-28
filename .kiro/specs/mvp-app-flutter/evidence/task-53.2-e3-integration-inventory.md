# Evidência da tarefa 53.2 — Inventário de composição e pontos mínimos de integração E3

## Escopo e fontes

- Tarefa executada: **53.2 — Inventariar a composição atual de `main.dart`, `CooldownPolicy`, `OperationController`, rotas, permissões, manifestos e regras de backup para definir os pontos mínimos de integração E3.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Documentos revisados: `requirements.md`, `design.md` (seções E3.1–E3.9) e `tasks.md` do spec `mvp-app-flutter`.
- O diretório do spec não contém `.config` nem `.config.kiro`; a evidência da tarefa 53.1 já o registra como spec regular, não bugfix.
- Esta tarefa somente inventaria a baseline e define seams para E3. Não altera código, dependências, manifestos, regras de backup, comportamento E0–E2, rotas existentes ou evidências históricas.

## Inventário atual

| Área | Estado atual confirmado | Ponto mínimo de integração E3 |
|---|---|---|
| Composition root | `lib/main.dart` cria `PrivateImageStore`, runtime de fila E2, câmera, localização, relógio, UUID, Haversine, wake lock, JPEG preparer, `CooldownPolicy`, `E1PostCandidateProcessor` e `OperationController`. A fila indisponível é degradada de forma controlada. | Compor stores E3 somente após a tarefa 54: configuração não secreta, status de credencial e sua fonte observável. Não criar cliente de ocorrências nem injetar o segredo no controller operacional. Manter a criação/restauração da fila e a composição E0 intactas. |
| `CooldownPolicy` | `lib/domain/cooldown_policy.dart` recebe limites imutáveis no construtor (defaults de 5 s e 15 m), mantém referência privada do último aceite e a restaura pela maior `queueSequence` da fila E2. `evaluate` não altera referência; somente `commit` o faz após aceite válido. | Introduzir uma atualização de regra que preserve `_lastCreated`/referência recuperada; não reinstanciar a política sem preservar essa referência. Aplicar cooldown e distância atualizados apenas à próxima avaliação. |
| `OperationController` | `lib/operation/operation_controller.dart` coordena bootstrap da fila, restauração do cooldown, recursos de câmera/GPS/wake lock, lifecycle, single-flight, permissões e processamento. `suspendForDiagnostic()` marca a rota não corrente de modo síncrono e aguarda a liberação antes de navegar. | Generalizar o protocolo já existente para Configurações (por exemplo, suspensão por rota sem semântica de Diagnóstico), retornando por `updateOperationalContext`/reconciliação. Receber configuração sanitizada para atualizar cooldown/distância e publicar somente status de configuração de envio; não reter API key, executar rede ou alterar fila. |
| Estado e interface de Operação | `OperationState` contém somente dados de operação e agregados sanitizados da fila; `OperationScreen` observa lifecycle, chama ações de permissões e expõe a rota Diagnóstico. Não existe indicador de configuração nem tela Configurações. | Acrescentar projeção sanitizada de configuração (`pendente`/`pronta`) sem valor de URL ou chave. Adicionar entrada acessível para Configurações e testes de retorno; manter registro manual e fila habilitados quando URL/chave estiverem ausentes. |
| Rotas | `PavimentaAiMobileApp` usa `OperationScreen` como `home`. A única rota adicional é `MaterialPageRoute` nomeada `/diagnostic`; `_openDiagnostic` serializa a sessão E0 por `DiagnosticSessionDisposal` e reconcilia Operação ao retorno. | Adicionar uma rota de Configurações separada, sem mudar `/diagnostic` nem o ciclo de vida próprio da E0. Aplicar antes/depois dela o mesmo protocolo de suspensão/reconciliação, evitando câmera, GPS e wake lock simultâneos entre telas. |
| Permissões | O manifesto declara somente `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` e `INTERNET`; remove permissões de áudio e armazenamento inseridas por plugins. A câmera é recurso não obrigatório. `OperationController` e `OperationScreen` já distinguem negação temporária, permanente, serviço desativado, precisão reduzida e abrem detalhes Android por `OperationalAppSettings`/`Geolocator.openAppSettings`. | Reutilizar a porta `AppSettingsPort` e os estados existentes no painel de permissões das Configurações. Não adicionar permissões, solicitação concorrente, localização em segundo plano, serviço foreground ou wake lock adicional. |
| Manifesto principal/release | `android/app/src/main/AndroidManifest.xml` referencia `@xml/backup_rules` e `@xml/data_extraction_rules` e mantém `android:usesCleartextTraffic="false"`. O manifesto debug atual apenas declara `INTERNET`; não abre HTTP. | Manter o manifesto principal/release bloqueando cleartext. Criar somente em debug uma `network-security-config` que bloqueie cleartext no `base-config` e permita exclusivamente `http://localhost:3000`; não permitir IP, host/porta alternativos ou abertura global. |
| Backup e transferência | `backup_rules.xml` exclui banco E2, `-journal`, `-wal`, `-shm` e `e2_queue_images_v1/`. `data_extraction_rules.xml` replica exatamente essas exclusões em `cloud-backup` e `device-transfer`. | Após confirmar os artefatos reais de `flutter_secure_storage`, excluir o suporte da credencial em backup e transferência sem remover, renomear ou enfraquecer nenhuma exclusão E2. A configuração não secreta pode seguir a política Android aplicável. |
| Dependências e fronteira negativa | `pubspec.yaml` contém apenas dependências E0–E2; não há `shared_preferences` nem `flutter_secure_storage`. A composição não contém cliente de ocorrências, endpoint, `POST`, multipart, `Authorization`, worker, backoff, YOLO/TFLite ou inferência. | As únicas novas dependências diretas permitidas pelo plano E3 são `shared_preferences` e `flutter_secure_storage`, com pins exatos após verificação de compatibilidade. A tarefa 53.3 deverá automatizar a fronteira negativa restante. |

## Ordem mínima de integração futura

1. Na tarefa 54, adicionar e verificar os adaptadores E3 e as políticas Android, preservando a fila E2 e suas exclusões.
2. Nas tarefas 55–56, construir configuração tipada/validada, stores separados e status de credencial sem expor a chave completa.
3. Na tarefa 57, introduzir a tela de Configurações e reutilizar a abertura de detalhes Android para permissões permanentes.
4. Na tarefa 58, conectar a nova rota ao protocolo de suspensão/reconciliação existente e atualizar os limites do cooldown sem perder a referência restaurada da fila.

## Limites confirmados

- Não há configuração, `BASE_URL`, credencial, armazenamento seguro, tela Configurações ou indicador de envio implementados neste baseline.
- A ausência futura de `BASE_URL` ou API key não poderá bloquear captura manual, recuperação/persistência E2 ou a rota Diagnóstico.
- Transporte de ocorrências e autenticação (`POST`, endpoint, multipart, `Authorization: ApiKey`), retry/backoff e worker continuam exclusivamente em E4; YOLO/TFLite/inferência continuam exclusivamente em E5.
- Não foram registrados valores de URL, API key, UUID, coordenadas, caminhos privados ou conteúdo de armazenamento.

## Resultado

**Inventário 53.2 concluído.** Os pontos mínimos para E3 são: composição adicional isolada para stores, atualização preservadora de referência no cooldown, navegação de Configurações com o protocolo de recursos existente, projeções de estado sanitizadas, reutilização da porta de detalhes Android, exceção HTTP exclusiva de debug e extensão aditiva das exclusões de backup/transferência.
