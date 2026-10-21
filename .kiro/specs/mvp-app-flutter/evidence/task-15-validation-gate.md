# Evidência — Tarefa 15: Validation Gate da E0 no Samsung Galaxy S25+

## Resultado consolidado do gate

**Estado final: APROVADO.** As evidências técnicas já aprovadas, os relatos de validação física fornecidos pelo usuário e sua decisão humana explícita de **Aprovar** sustentam todos os itens aplicáveis de 15.1 a 15.22 e a parada procedimental de 15.23. Não resta lacuna real de build, instalação, abertura, câmera, permissões, localização, HTTPS, indisponibilidade, ciclo de vida, responsividade, segurança operacional ou limite de escopo.

O item 15.22 está **Aprovado** pela decisão humana explícita do usuário em resposta à pergunta “Qual é sua decisão explícita para o Validation Gate da E0?”. O item 15.23 está aprovado procedimentalmente: a execução parou no gate e não iniciou E1 nem qualquer etapa posterior.

A tarefa 15 está pronta para conclusão pelo orquestrador. Este documento não altera `tasks.md` e a aprovação do gate não autoriza o início da E1 ou de qualquer etapa posterior sem nova solicitação do usuário.

## Critério das fontes

- **Relato físico do usuário:** observação direta informada pelo usuário sobre a execução no Samsung Galaxy S25+. O relato é registrado como declaração factual, sem atribuir a ele captura, gravação, log ou valor não fornecido.
- **Evidência automática/operacional:** build, hash, inspeção do APK, ADB, pacote instalado e configuração sanitizada já registrados na tarefa 14.
- **Inspeção de código/configuração:** comprova estrutura, salvaguardas determinísticas e limite de escopo; não é usada isoladamente para substituir observações físicas.
- **Não aplicável:** condição alternativa que não ocorreu no cenário executado.
- **Aprovação por decisão humana:** estado atribuído somente quando a escolha explícita do usuário foi registrada, sem inferência automática do agente.

O diretório da especificação não contém arquivo `.config`. `requirements.md`, `design.md` e `tasks.md` identificam esta entrega como E0, não como bugfix.

## Evidências físicas adicionais fornecidas pelo usuário

Os registros abaixo reproduzem apenas o conteúdo factual informado nesta sessão; nenhuma captura, gravação, saída de log ou valor de localização foi alegado ou inventado.

### Teste A — primeira abertura, ordem e preview

**Resultado informado: todos passaram.** Em instalação limpa, os três painéis apareceram imediatamente, sem crash. A câmera foi o primeiro diálogo. A localização apareceu somente após a decisão/concessão da câmera. O preview era da câmera traseira e permaneceu responsivo durante a rolagem.

**Itens sustentados:** 15.3, 15.4, 15.5 e 15.6.

### Teste B — localização, precisão e velocidade

**Resultado informado: passou.** Com localização aproximada, apareceu a distinção/mensagem esperada. Após habilitar a precisão, latitude, longitude e precisão foram exibidas. Os valores não foram fornecidos e não são registrados. O campo de velocidade apareceu em `m/s`.

Como a velocidade foi fornecida e exibida, **15.10 está aprovado**. A condição alternativa de velocidade ausente não ocorreu; portanto, **15.11 é não aplicável**, sem inferir ou exigir “Não fornecida” nesse cenário.

**Itens sustentados:** 15.7, 15.8, 15.9 e 15.10; condição de 15.11 classificada como não aplicável.

### Teste C — recusas independentes

**Resultado informado: as duas recusas passaram.** Ao negar câmera, o aplicativo apresentou mensagem clara e localização/HTTPS continuaram sem crash. Em execução limpa separada, ao conceder câmera e negar localização, o aplicativo apresentou mensagem clara e câmera/HTTPS continuaram. A ordem das permissões foi preservada.

**Itens sustentados:** 15.6 e 15.16.

### Teste D — indisponibilidade e recuperação da rede

**Resultado informado: passou.** Em modo avião, houve mensagem clara de rede/destino inacessível sem crash. Câmera e localização permaneceram utilizáveis. Após desativar o modo avião, o diagnóstico se recuperou com HTTP `204`.

**Itens sustentados:** 15.15 e, como confirmação adicional de recuperação, 15.12–15.13.

### Teste E — ciclo de vida e interface

**Resultado informado: passaram.** Após duas pausas e retornos, não houve diálogo ou stream aparentemente duplicado, controlador inválido, congelamento ou crash; o preview foi restaurado. Rolagem, textos, preview e botões permaneceram acessíveis nos estados normal e de erro e nas variações aplicáveis de orientação e fonte.

**Itens sustentados:** 15.17 e 15.18.

## Matriz final 15.1–15.23

| Item | Estado | Tipo de evidência | Fundamentação objetiva |
|---|---|---|---|
| 15.1 Build Android concluído | **Aprovado** | Evidência automática | APK debug em `build/app/outputs/flutter-apk/app-debug.apk`; SHA-256 `E9FB2F248A46E713982C00C6A6A276293E1928C8B7485548E05EE5071548EA50`; build `assembleDebug` concluído conforme tarefa 14. |
| 15.2 Instalação e `applicationId` | **Aprovado** | Evidência automática | `adb install -r` retornou `Success`; APK e pacote instalado confirmaram `com.vitor.pavimenta_ai_mobile` no Galaxy S25+ (`SM-S936B`). |
| 15.3 Tela imediata e sem crash | **Aprovado** | Relato físico do usuário — Teste A | Em instalação limpa, os três painéis apareceram imediatamente, sem crash. |
| 15.4 Câmera solicitada primeiro e concedida | **Aprovado** | Relato físico do usuário — Teste A | A câmera foi o primeiro diálogo e foi concedida no cenário nominal. |
| 15.5 Preview traseiro responsivo | **Aprovado** | Relato físico do usuário — Teste A | O preview foi identificado visualmente como traseiro e permaneceu responsivo durante a rolagem. |
| 15.6 Localização somente após câmera resolvida | **Aprovado** | Relato físico do usuário — Testes A e C | A localização apareceu somente após a decisão da câmera; a ordem foi preservada tanto na concessão quanto nos cenários de recusa. |
| 15.7 Precisão aproximada versus precisa | **Aprovado** | Relato físico do usuário — Teste B | A localização aproximada produziu a distinção/mensagem esperada; depois de habilitar precisão, o diagnóstico prosseguiu com os campos de posição. |
| 15.8 Latitude e longitude | **Aprovado** | Relato físico do usuário — Teste B | Ambos os campos foram exibidos após habilitar localização precisa. Nenhum valor é registrado nesta evidência. |
| 15.9 Precisão reportada | **Aprovado** | Relato físico do usuário — Teste B | O campo de precisão foi exibido. Nenhum valor ou limiar numérico é registrado. |
| 15.10 Velocidade fornecida | **Aprovado** | Relato físico do usuário — Teste B | O campo de velocidade apareceu em metros por segundo (`m/s`). Nenhum valor é registrado. |
| 15.11 Velocidade ausente como “Não fornecida” | **Não aplicável** | Condição alternativa não ocorrida | O provedor forneceu velocidade e o aplicativo a exibiu em `m/s`, satisfazendo 15.10; portanto, a condição de ausência prevista em 15.11 não ocorreu. |
| 15.12 HTTPS manual com URL externa de teste | **Aprovado** | Relato físico + evidência automática/operacional | URL HTTPS pública exclusiva de teste, sem credenciais, fornecida externamente por `--dart-define`; diagnóstico acionado manualmente e resposta HTTP `204`, inclusive após recuperação do modo avião. A URL permanece sanitizada. |
| 15.13 Código/classificação; nenhum corpo | **Aprovado** | Relato físico + inspeção de código | A tela apresentou HTTP `204` e classificação sanitizada de destino acessível. O cliente propaga somente código/classificação e não propaga, renderiza ou registra corpo e headers. |
| 15.14 Redirect, URL inválida e caminho proibido | **Aprovado** | Inspeção de código/configuração | `followRedirects=false`; validação exige URI absoluta HTTPS e host, rejeita userinfo/fragmento e bloqueia `/api/v1/occurrences` antes da conexão. São salvaguardas determinísticas independentes do hardware. |
| 15.15 Falha de rede/destino clara e sem crash | **Aprovado** | Relato físico do usuário — Teste D | Em modo avião, houve mensagem clara de rede/destino inacessível sem crash; câmera e localização permaneceram utilizáveis; ao restaurar a rede, houve recuperação com HTTP `204`. |
| 15.16 Negar câmera e localização separadamente | **Aprovado** | Relato físico do usuário — Teste C | As recusas foram executadas separadamente em execuções limpas; cada uma apresentou mensagem clara, preservou os diagnósticos independentes e não causou crash. |
| 15.17 Segundo plano e retorno | **Aprovado** | Relato físico do usuário — Teste E | Após duas pausas/retornos, não houve diálogo ou stream aparentemente duplicado, controlador inválido, congelamento ou crash; o preview foi restaurado. |
| 15.18 Rolagem, legibilidade, botões e responsividade | **Aprovado** | Relato físico do usuário — Teste E | Rolagem, textos, preview e botões permaneceram acessíveis nos estados normal e de erro e nas variações aplicáveis de orientação e fonte. |
| 15.19 Ausência de funcionalidades posteriores | **Aprovado** | Inspeção de código/configuração | `lib/` contém somente `main.dart` e `e0/`; dependências diretas são apenas Flutter, `camera` e `geolocator`; não foram encontrados YOLO/TFLite, inferência/FPS, captura ou processamento de frames, detecção, ocorrência, cooldown, fila, API key, armazenamento seguro ou multipart. A referência a `/api/v1/occurrences` existe somente para bloquear o caminho. |
| 15.20 Sem produção; URL sanitizada | **Aprovado** | Evidência operacional + inspeção | A tarefa 14 confirma destino público exclusivo de teste, fornecido fora do repositório, sem credenciais e registrado de forma sanitizada. Nenhuma URL ou credencial de produção foi fornecida. |
| 15.21 Reunir todas as evidências | **Aprovado** | Consolidação documental | Evidências de build, instalação, abertura, câmera, permissões sequenciais, GPS, velocidade, HTTPS, indisponibilidades, ciclo de vida e responsividade estão reunidas neste documento e nas referências da tarefa 14. Os relatos físicos são registrados como relatos, sem alegar arquivos de captura ou logs inexistentes. |
| 15.22 Decisão explícita do usuário | **Aprovado** | Decisão humana obrigatória | O usuário respondeu explicitamente **Aprovar** à pergunta “Qual é sua decisão explícita para o Validation Gate da E0?”. A aprovação foi registrada sem inferência automática do agente. |
| 15.23 Parar após o gate | **Aprovado** | Procedimental | A execução parou neste gate. E1 ou qualquer etapa posterior não foi iniciada e permanece condicionada a uma nova solicitação do usuário. |

**Contagem final:** 22 Aprovados, 0 Reprovados, 0 Pendentes e 1 Não aplicável.

## Verificação de pendências obrigatórias

- **Lacunas reais de evidência obrigatória:** nenhuma.
- **Item técnico, físico ou decisório ainda por executar:** nenhum.
- **Pendência processual obrigatória:** nenhuma; 15.22 foi aprovado por decisão humana explícita e 15.23 foi aprovado procedimentalmente.
- **Situação do gate:** **APROVADO**.
- **Situação da tarefa 15:** pronta para conclusão pelo orquestrador, sem alteração de `tasks.md` por este documento.
- **Etapas posteriores:** E1 e qualquer etapa posterior não foram iniciadas e não estão autorizadas sem nova solicitação do usuário.

## Evidências consultadas

1. `.kiro/specs/mvp-app-flutter/evidence/task-14-build-and-installation.md` — build, toolchain, APK, hash, instalação, pacote e URL sanitizada.
2. `.kiro/specs/mvp-app-flutter/evidence/task-14-physical-validation-checklist.md` — roteiro preparado e limites de aprovação física.
3. Relatos físicos do usuário nesta sessão — Testes A a E, conforme registrados acima.
4. `lib/e0/camera_diagnostic.dart` — seleção da primeira câmera traseira, preview sem áudio e sem stream de frames.
5. `lib/e0/location_diagnostic.dart` — permissão em primeiro plano, precisão reduzida, posição, velocidade opcional e assinatura cancelável.
6. `lib/e0/e0_controller.dart` e `lib/e0/e0_state.dart` — sequência de permissões, mensagens, geração e liberação de recursos.
7. `lib/e0/e0_screen.dart` — três painéis, campos diagnósticos, representação de velocidade ausente, rolagem e layout adaptável.
8. `lib/e0/diagnostic_http_client.dart` — GET HTTPS, validações, redirects desabilitados, descarte limitado do corpo e resultados sanitizados.
9. `pubspec.yaml`, `AndroidManifest.xml` e árvore de `lib/` — dependências, permissões e limite de escopo.

## Decisão humana registrada

O usuário decidiu explicitamente **Aprovar** o Validation Gate da E0. Com essa decisão, o gate está **APROVADO** e a tarefa 15 está documentalmente pronta para conclusão pelo orquestrador.

A execução permanece obrigatoriamente parada no gate. Esta aprovação não inicia nem autoriza E1 ou qualquer etapa posterior sem nova solicitação do usuário.