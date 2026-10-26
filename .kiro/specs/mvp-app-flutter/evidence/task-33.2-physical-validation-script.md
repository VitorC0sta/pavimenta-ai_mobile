# Roteiro preparado — Tarefa 33.2: validação física nominal E1

## Uso, estado e limite

Este roteiro prepara exclusivamente a futura observação de **abertura, preview, banner manual, botão/readiness, captura única, GPS, velocidade, `detectedAt`, UUID, classe, confiança e contador** no Samsung Galaxy S25+. Todos os passos observacionais abaixo permanecem **não executados**.

A preparação não abre o aplicativo, não executa o Validation Gate E1 e não aprova comportamento físico. Não cobre cooldown/JPEG/limpeza (33.3), lifecycle/wake lock/responsividade/acessibilidade/navegação/regressão E0 (33.4), nem inspeção negativa de E2–E5 (33.5).

Para cada passo, registrar `Aprovado`, `Reprovado` ou `Não executado`, identificador da evidência e uma observação factual. Não registrar coordenadas integrais, serial do aparelho, caminho privado de imagem ou outro dado desnecessário.

## 1. Pré-condições

- [ ] Usar o Samsung Galaxy S25+ (`SM-S936B`) e o pacote `com.vitor.pavimenta_ai_mobile` instalado pela tarefa 33.1.
- [ ] Confirmar que o APK sob validação corresponde ao SHA-256 `6896EFDBFA40C80052B164B88B7DFFE9F201702C5CFDB9A4497A1F21D6D9B95B` registrado na tarefa 33.1.
- [ ] Posicionar o aparelho com segurança, com a câmera traseira apontada para uma cena de teste sem pessoas, placas ou outros dados desnecessários.
- [ ] Manter serviço de localização ativo e permitir câmera e localização precisa quando solicitadas.
- [ ] Iniciar uma gravação de tela contínua para correlacionar abertura, readiness, toque aceito, processamento e contador. Nome sugerido: `33.2-S01-fluxo-nominal.mp4`.
- [ ] Não dirigir nem simular cenário em via pública para esta tarefa; o fluxo nominal pode ser verificado com o aparelho parado.

## 2. Abertura, identidade manual e estado inicial

1. Abrir o aplicativo pelo ícone, sem navegar para Diagnóstico.
2. Observar a primeira tela até a estabilização dos recursos.
3. Confirmar e registrar:
   - [ ] a rota inicial possui o título **“Operação”**;
   - [ ] a tela abre sem crash, congelamento ou fechamento inesperado;
   - [ ] o banner **“Modo manual — YOLO ainda não configurado”** está visível;
   - [ ] o texto **“Confirmação manual de um buraco observado. Não é detecção automática.”** está visível;
   - [ ] o painel **“Câmera traseira”** aparece;
   - [ ] o painel **“GPS e localização”** aparece;
   - [ ] o painel **“Sessão atual”** inicia em **“Buracos registrados: 0”**;
   - [ ] o painel **“Processamento”** aparece.
4. Evidência mínima: um frame/captura da tela inicial e o início da gravação `33.2-S01`.

## 3. Preview traseiro

1. Aguardar a câmera concluir a inicialização nominal.
2. Confirmar e registrar:
   - [ ] o status da câmera muda para **“Pronta”**;
   - [ ] a mensagem indica **“Câmera traseira pronta”**;
   - [ ] o preview mostra a cena posicionada diante da câmera traseira;
   - [ ] o preview atualiza visualmente e não é uma imagem congelada;
   - [ ] não há indicação de detecção automática no preview.
3. Para demonstrar que a lente é traseira sem registrar dados pessoais, mover brevemente um marcador neutro diante da traseira e confirmar sua aparição no preview.
4. Evidência mínima: trecho sanitizado da gravação mostrando o marcador neutro e captura com status **“Pronta”**. Nome sugerido: `33.2-E02-preview-traseiro.png`.

## 4. GPS, precisão e velocidade

1. Aguardar o painel de localização chegar ao estado nominal.
2. Confirmar e registrar:
   - [ ] o status mostra **“GPS pronto”**;
   - [ ] a mensagem mostra **“GPS disponível”**;
   - [ ] latitude e longitude deixam de mostrar **“Não disponível”**;
   - [ ] a precisão reportada é exibida em metros, sem aplicar limiar inventado;
   - [ ] se o provedor fornecer velocidade válida, a UI a mostra em `km/h`;
   - [ ] se o provedor não fornecer velocidade válida, a UI mostra **“Não fornecida”**, sem inventar zero.
3. Na captura de evidência, ocultar ou recortar os dígitos de latitude/longitude. Preservar apenas os rótulos e a prova de que os campos foram preenchidos.
4. Classificar velocidade conforme o resultado real:
   - `Fornecida`: registrar somente que um valor em `km/h` foi exibido; ou
   - `Não fornecida`: registrar a mensagem literal, sem reprovar isoladamente.
5. Evidência mínima: `33.2-E03-gps-sanitizado.png`, com coordenadas redigidas, e observação objetiva no registro de evidências.

## 5. Readiness do botão

1. Durante a inicialização, observar o botão **“Registrar buraco”** antes de câmera e GPS estarem prontos.
2. Após câmera e GPS ficarem prontos e o processamento estar ocioso, observar o mesmo botão.
3. Confirmar e registrar:
   - [ ] enquanto câmera ou GPS ainda não está pronto, o botão está desabilitado;
   - [ ] com câmera pronta, snapshot GPS válido, rota Operação corrente, aplicativo ativo e nenhum processamento em curso, o botão está habilitado;
   - [ ] a habilitação não depende de alegação de detecção automática;
   - [ ] o rótulo permanece **“Registrar buraco”** e a explicação identifica confirmação manual.
4. Evidência mínima: dois frames da gravação, um no estado indisponível e outro no estado pronto. Nomes sugeridos: `33.2-E04a-botao-bloqueado.png` e `33.2-E04b-botao-pronto.png`.

## 6. Captura única e contador

1. Confirmar antes da ação: botão habilitado, contador `0` e processamento **“Pronto”**.
2. Tocar uma única vez em **“Registrar buraco”** e não realizar novo toque até a conclusão.
3. Confirmar e registrar a sequência visível:
   - [ ] o botão é desabilitado durante o processamento;
   - [ ] o rótulo temporário muda para **“Registrando…”**;
   - [ ] o painel de processamento indica validação/processamento;
   - [ ] somente uma operação visual de registro ocorre para o toque aceito;
   - [ ] o resultado termina em **“Concluído”**;
   - [ ] a mensagem informa **“A ocorrência foi criada somente em memória.”**;
   - [ ] o feedback informa **“Sucesso: Buraco registrado em memória.”**;
   - [ ] o contador muda exatamente de `0` para `1`, sem salto ou segundo incremento;
   - [ ] após a conclusão, o botão volta ao estado habilitado se o readiness continuar válido.
4. Evidência mínima: gravação contínua desde antes do toque até contador `1`, mais captura final `33.2-E05-registro-concluido.png`.

> A execução futura deve produzir somente uma ocorrência neste cenário. Não realizar um segundo registro, pois cenários de repetição/cooldown pertencem à tarefa 33.3.

## 7. `detectedAt`, UUID v4, classe e confiança

Esses quatro valores pertencem à ocorrência em memória, mas **não são renderizados na tela Operação atual**. Portanto, a gravação física comprova o acionamento aceito, o processamento concluído e o incremento do contador, mas não comprova isoladamente o valor interno exato. Não atribuir a uma captura de tela evidência que ela não contém.

Usar a seguinte composição de evidências já existente, sem modificar o aplicativo durante 33.2:

- [ ] `detectedAt`: registrar o instante visível do toque aceito em `33.2-S01` e anexar a evidência automatizada de que o controlador lê o relógio uma vez antes do primeiro `await` e preserva esse valor na ocorrência (`test/operation/operation_controller_test.dart` e `test/domain/in_memory_occurrence_test.dart`).
- [ ] UUID: anexar a evidência automatizada de geração/validação UUID v4 (`test/domain/in_memory_occurrence_test.dart` e `test/application/post_candidate_processor_test.dart`). Registrar somente o padrão sanitizado `xxxxxxxx-xxxx-4xxx-[89ab]xxx-xxxxxxxxxxxx`, nunca inventar um valor da execução física.
- [ ] Classe: anexar a evidência automatizada de `defectClass = pothole` (`test/candidate/manual_candidate_source_test.dart`, `test/application/post_candidate_processor_test.dart` e `test/domain/in_memory_occurrence_test.dart`).
- [ ] Confiança: anexar a evidência automatizada de `confidence = 1.0` como confirmação humana (`test/candidate/manual_candidate_source_test.dart`, `test/application/post_candidate_processor_test.dart` e `test/domain/in_memory_occurrence_test.dart`).
- [ ] Referenciar a saída consolidada existente em `task-31-automated-test-suite.md` apenas pelo fato objetivo de que a execução reportou `66 testes aprovados, zero falhas`; preservar as lacunas de cobertura registradas naquele documento e não declarar a tarefa 31 concluída.

### Limitação de observabilidade a registrar

Sem instrumentação adicional aprovada, `detectedAt`, UUID, classe e confiança não podem receber o tipo de evidência **“observação física direta da UI”**. Eles podem receber **“evidência técnica automatizada correlacionada ao fluxo físico”**. Se o Validation Gate exigir visualização runtime desses valores no aparelho, isso é um bloqueio de observabilidade a ser decidido fora de 33.2; não adicionar UI, log, persistência ou rede nesta tarefa.

## 8. Encerramento desta execução nominal

- [ ] Parar a gravação após o contador chegar a `1` e o processamento concluir.
- [ ] Não abrir Diagnóstico, não enviar o app ao segundo plano e não executar cenários de cooldown, erro, JPEG ou limpeza nesta tarefa.
- [ ] Copiar somente as evidências sanitizadas necessárias para o pacote; manter mídia bruta com coordenadas sob controle local e fora do repositório.
- [ ] Preencher `task-33.2-evidence-record.md` sem marcar o Validation Gate E1 como aprovado ou reprovado.

## Referências normativas

- Tarefa: `tasks.md`, item 33.2.
- Requisitos: RF-03.1–10 e 13; RF-05.1–4; RF-06.1–8; RF-07.1–10 e 12–13; RF-08.1–3 e 6–9; RF-11.1–5; RF-23.7 e 19–20; RNF-03.2 e 4; RNF-04.2–3; RNF-07.2; RNF-08.7–10.
- Design: E1.8, E1.10–E1.12, E1.15, E1.17–E1.18 e E1.28, passos 5–11.
- Instalação preparada: `task-33.1-apk-installation.md`.

## Declaração obrigatória

Este roteiro apenas prepara coleta futura. Build, instalação, testes e inspeção de código não substituem a observação física dos itens visíveis no Galaxy S25+. Da mesma forma, uma gravação da UI não demonstra campos internos que a UI não apresenta. A aprovação da E1 pertence exclusivamente à tarefa 34 e exige decisão explícita do usuário.