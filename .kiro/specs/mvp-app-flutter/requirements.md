# Requirements Document

**Aplicativo Mobile para Geolocalização de Defeitos em Pavimento Viário**

## Introduction

Este documento especifica o MVP do aplicativo mobile do Trabalho de Conclusão de Curso **“Dispositivo Veicular para Geolocalização de Defeitos em Pavimento Viário”**. O aplicativo Android utiliza um celular fixado no para-brisa, com a câmera traseira apontada para a pista, para registrar ocorrências geolocalizadas de buracos e enviá-las posteriormente a uma API REST.

A etapa E0 já foi **implementada, validada fisicamente no Samsung Galaxy S25+ e aprovada**. O comportamento validado do Diagnóstico de câmera traseira, GPS e HTTPS deverá permanecer disponível pela opção **“Diagnóstico”** nas etapas posteriores, e as evidências históricas existentes não poderão ser alteradas retroativamente. A integração do Diagnóstico à navegação do novo aplicativo poderá mover ou refatorar minimamente arquivos da E0, desde que preserve as responsabilidades e o comportamento aprovados.

Como o modelo YOLO ainda não foi treinado, E1 a E4 utilizarão um **Modo manual temporário**. Nesse modo, o operador confirma um buraco observado pelo botão **“Registrar buraco”**. A ação manual é uma fonte de candidato de ocorrência, não uma detecção automática e não representa confiança de modelo. A arquitetura deverá permitir que, em E5, a fonte manual seja substituída pela fonte YOLO sem reescrever criação de ocorrência, fila, idempotência ou envio.

As entregas permanecem sequenciais e sujeitas a Validation Gates: **E0 aprovada → E1 → E2 → E3 → E4 → E5**. Esta revisão altera somente a especificação de requisitos; não inicia E1 nem modifica a implementação ou as evidências de E0.

## 2. Objetivo

Definir de forma objetiva, testável e rastreável o comportamento esperado para:

- preservar a E0 aprovada e manter seu diagnóstico acessível;
- registrar manualmente, de forma temporária e inequívoca, um buraco observado;
- capturar a imagem e associar localização, velocidade válida, horário, classe, confirmação manual e UUID;
- aplicar cooldown local por tempo ou distância;
- preparar JPEG segundo os limites fixos do contrato;
- criar a ocorrência completa em memória antes da persistência;
- persistir ocorrências e imagens antes de qualquer envio;
- configurar destino, credencial e parâmetros sem versionar segredos;
- enviar ocorrências em `multipart/form-data` com autenticação `Authorization: ApiKey`;
- classificar sucessos, descartes, pausas e falhas recuperáveis;
- substituir futuramente a fonte manual pelo YOLO sem alterar o pós-candidato compartilhado;
- validar cada incremento no Samsung Galaxy S25+ antes de iniciar a etapa seguinte.

## 3. Escopo do MVP

O MVP compreende:

1. Preservação integral da E0 já implementada, validada e aprovada, incluindo diagnóstico de câmera, GPS e HTTPS, evidências existentes e acesso pela opção “Diagnóstico”.
2. Aplicativo Android em Flutter/Dart, validado principalmente no Samsung Galaxy S25+.
3. Em E1, nova tela operacional com preview traseiro, identidade visual definida, banner do modo manual e botão “Registrar buraco”.
4. Fonte manual temporária de candidato de ocorrência, claramente distinta de detecção automática.
5. Em E1, captura da imagem no acionamento, localização válida, velocidade opcional em km/h, horário, `confidence = 1.0`, `defectClass = pothole`, UUID, cooldown, JPEG e ocorrência completa em memória.
6. Em E2, fila local persistente, recuperação após reabertura, imagem associada e indicador de pendências, sem integração real com a API.
7. Em E3, tela de configurações, armazenamento seguro Android da API key, validações e parâmetros presentes e futuros.
8. Em E4, envio automático ao contrato fixo da API, idempotência, classificação de respostas, backoff, pausa, retomada, indicadores e README.
9. Em E5, integração futura do `ultralytics_yolo` com modelo TFLite treinado e compatível, inferência local, FPS e confiança configuráveis e substituição ou desativação da fonte manual.
10. Regras de domínio e infraestrutura isoladas da interface e da fonte de candidato.
11. Testes automatizados das regras aplicáveis em E1, E2, E3 e E4.
12. Validation Gate obrigatório ao fim de cada etapa, com uma única etapa em execução por vez.

## 4. Fora do escopo

Não fazem parte do MVP:

- login ou cadastro de usuário final;
- mapa ou histórico de ocorrências para consulta do operador;
- revisão manual posterior de ocorrências;
- suporte a iOS;
- classes diferentes de `pothole`;
- preenchimento de `highway` ou `km`;
- campo `source` no contrato da ocorrência;
- upload direto para serviço de armazenamento;
- atualização do modelo pela rede;
- telemetria ou painel web;
- deduplicação avançada entre passagens distintas pelo mesmo buraco;
- alteração de endpoints ou campos do back-end;
- alegação de detecção automática antes da integração do modelo treinado;
- TFLite, `ultralytics_yolo`, inferência, FPS de inferência ou limiar efetivo de modelo em E1, E2, E3 ou E4;
- metas numéricas não aprovadas para precisão do modelo, temperatura, consumo de bateria ou autonomia;
- URL real de produção ou API key real versionada.

## Glossary

| Termo | Definição |
|---|---|
| Aplicativo | Aplicativo mobile Android especificado neste documento. |
| E0 | Smoke test Android já implementado, validado fisicamente no Samsung Galaxy S25+ e aprovado. |
| Diagnóstico | Funcionalidade preservada da E0 para verificar câmera traseira, GPS e HTTPS, integrada à navegação das etapas posteriores pela opção “Diagnóstico” e com ciclo de vida próprio. |
| Modo operacional ativo | Estado no qual a tela operacional está visível, o Aplicativo está em primeiro plano e o `AppLifecycleState` é `resumed`. |
| Captura manual | Operação iniciada por um acionamento aceito do botão “Registrar buraco”; o instante aceito define `detectedAt`, e a imagem associada é produzida pela operação de captura iniciada imediatamente como consequência do acionamento. |
| Fonte de candidato de ocorrência | Componente que informa ao fluxo que existe um possível buraco; atualmente recebe a ação manual e futuramente receberá a detecção YOLO. |
| Modo manual temporário | Modo no qual o usuário pressiona um botão para registrar um buraco observado; a interface identifica o modo claramente e nunca o apresenta como detecção automática. |
| Candidato de ocorrência | Entrada produzida por uma fonte e entregue ao pós-candidato compartilhado para validação e possível criação de ocorrência. |
| Pós-candidato compartilhado | Fluxo independente da fonte que coordena imagem, GPS, horário, cooldown, UUID, validação, persistência e envio conforme a etapa disponível. |
| Ocorrência | Registro completo de um buraco aceito, associado a imagem válida, localização válida, horário, classe, confiança ou confirmação correspondente e chave de idempotência. |
| Confirmação manual | Decisão explícita do operador representada no contrato por `confidence = 1.0`; não significa confiança produzida por modelo. |
| Detecção YOLO | Candidato produzido futuramente em E5 pelo modelo treinado, com classe e confiança inferidas. |
| Fila persistente | Armazenamento local das ocorrências e imagens que aguardam envio ou decisão de tratamento. |
| Cooldown | Regra local que permite nova ocorrência quando o tempo mínimo **ou** a distância mínima tiver sido atingida. |
| `idempotencyKey` | UUID gerado uma única vez para uma ocorrência e reutilizado sem alteração em todas as tentativas. |
| `BASE_URL` | Origem configurável do servidor Next.js acessível pelo aparelho, sem o sufixo `/api/v1/occurrences`. |
| Administração Next.js | Interface administrativa externa na qual um administrador cria ou rotaciona a chave de um dispositivo e recebe a chave completa em exibição única. |
| `DEVICE_API_KEY` | Chave completa de dispositivo no formato `prefixo.segredo`, exibida uma única vez pelo Next.js ao administrador durante a criação ou rotação, copiada manualmente e colada nas configurações Flutter. |
| Validation Gate | Interrupção obrigatória ao final de cada etapa para apresentação dos resultados e aprovação explícita. |
| Backoff exponencial | Aumento progressivo do intervalo entre tentativas, limitado por um teto. |
| Falha recuperável | Falha de rede, timeout ou resposta HTTP `5xx`, para a qual a ocorrência permanece na fila. |
| Localização válida | Posição disponível com permissão de localização precisa, latitude entre -90 e 90 e longitude entre -180 e 180. |
| FPS de inferência | Quantidade de frames submetidos ao modelo por segundo em E5, distinta da taxa de frames do preview. |
| Segredo | API key, URL real de produção ou outro dado sensível que não pode ser versionado ou exposto. |

## 6. Decisões aprovadas e suposições

1. A identidade visual usa fundo principal `#111827`, cartões ou painéis `#1F2937`, destaque e ação principal `#F59E0B`, sucesso `#22C55E`, erro `#EF4444` e texto principal `#F9FAFB` sobre fundos escuros; botões com fundo `#F59E0B` usam texto e ícones `#111827`, e toda combinação de foreground e background exige contraste legível.
2. A fonte manual usa o botão “Registrar buraco”, `defectClass` exatamente `pothole` e `confidence` exatamente `1.0`.
3. `confidence = 1.0` no modo manual representa confirmação humana temporária e não precisão ou confiança de modelo.
4. O contrato não receberá o campo `source`.
5. O comportamento e as responsabilidades aprovados da E0, assim como a disponibilidade do Diagnóstico, permanecem preservados; as evidências históricas existentes não podem ser alteradas retroativamente.
6. Não existe atualmente `BASE_URL` funcional nem API key confirmada. Os campos podem permanecer vazios; a ausência não bloqueia E1 ou E2.
7. Sem `BASE_URL` ou API key, as ocorrências permanecem na fila e nenhuma chamada ao endpoint é realizada.
8. A integração real de E4 depende de URL de teste acessível e de chave válida criada pelo back-end para um dispositivo de teste.
9. O administrador cria ou rotaciona a chave de um dispositivo na administração Next.js, copia a chave completa exibida uma única vez e, em momento posterior, abre as configurações Flutter para colar e salvar o valor, preferencialmente para um dispositivo do tipo `mobile`.
10. O provisionamento da chave é manual e assíncrono entre as interfaces: o Aplicativo não precisa estar aberto durante a exibição no Next.js, não detecta o fechamento do diálogo do Next.js e não recupera a chave do back-end. Antes de salvar, o Aplicativo valida minimamente `prefixo.segredo` e usa armazenamento seguro Android; ao reabrir, apenas indica configuração, a substituição exige novo valor completo, a remoção exige confirmação e uma chave perdida exige rotação no Next.js.
11. A câmera traseira padrão disponível será utilizada. Seleção de lente, resolução e rotação serão definidas no design.
12. Uma localização é válida conforme a definição do Glossário; não se adota limite numérico de precisão ou idade que não tenha sido aprovado.
13. A precisão reportada será exibida, mas não bloqueará isoladamente uma ocorrência.
14. A velocidade será convertida para km/h e omitida quando ausente, negativa, superior a 300 km/h ou não validável.
15. A primeira ocorrência não será bloqueada por cooldown. As seguintes usarão a última ocorrência criada como referência.
16. O cooldown permitirá nova ocorrência quando o tempo mínimo **ou** a distância mínima tiver sido atingida.
17. Todas as tentativas de preparação usarão JPEG com qualidade `85`; somente dimensões poderão ser reduzidas para cumprir `2 MiB`.
18. Antes de configuração salva, serão usados cooldown de `5 segundos` e distância mínima de `15 metros`.
19. Os valores padrão de E5 serão limiar de confiança `0.35` e limite de inferência de `5 FPS`. *(Emenda E5: o valor original `0.5` foi substituído por `0.35`, próximo do melhor F1 medido para o modelo `buraco.tflite`; valores já salvos pelo operador não são reescritos.)*
20. O contador da sessão representa ocorrências efetivamente criadas e reinicia em uma nova execução do aplicativo.
21. `BASE_URL` não conterá URL real de produção por padrão e não incluirá o caminho `/api/v1/occurrences`.
22. Em produção, `BASE_URL` usará HTTPS.
23. Em desenvolvimento por USB, `adb reverse tcp:3000 tcp:3000` poderá permitir `http://localhost:3000`.
24. HTTP sem TLS será permitido somente no manifesto Android de debug; o manifesto principal e a variante release continuarão bloqueando HTTP.
25. O HTTP diagnóstico de E0 permanece separado do contrato de ocorrências e não utiliza credencial real nem endpoint de ocorrências.
26. E5 somente poderá iniciar quando existir modelo TFLite treinado, disponível e compatível.
27. *(Emenda E5.)* Em E5, a detecção YOLO é automática enquanto o modelo estiver carregado e o Modo operacional ativo vigorar; o botão “Registrar buraco” permanece como confirmação manual complementar; se o modelo não puder ser carregado, o Modo manual temporário E1–E4 continua disponível.
28. *(Emenda E5.)* Um candidato YOLO exige confirmação temporal: uma detecção compatível em pelo menos 2 dos últimos 3 frames processados. Duas caixas são compatíveis quando a distância entre seus centros é menor que o maior lado entre as duas caixas. A região de interesse da pista, inclusive a linha de horizonte, fica adiada.
29. *(Emenda E5.)* O FPS máximo de inferência aceita somente inteiros de `1` a `15`.
30. *(Emenda E5.)* Admitir a confiança do modelo exige generalizar a validação de `confidence` para o intervalo [0, 1] no pós-candidato e migrar o schema local de forma não destrutiva. Esse ajuste não constitui reescrita do pós-candidato, da fila, do payload ou do envio.
31. *(Emenda E5.)* O pré-processamento, a decodificação, o NMS e a conversão das caixas para o frame original ficam a cargo do `ultralytics_yolo`, com IoU de NMS `0.7`, igual ao padrão do Ultralytics usado na validação do modelo. O Aplicativo não acrescenta desfoque nem outro pré-processamento aos frames.
32. *(Emenda E5.)* Após o NMS, caixas com área maior que `20%` da área do frame são descartadas.
33. *(Emenda E5.)* A janela da confirmação temporal (N de M) e a área máxima da caixa ficam em `OperationalConfiguration` como valores padrão definidos no código, sem persistência e sem campo na tela de Configurações.

## Requirements

### Requisitos funcionais

### RF-00 — Smoke test Android preservado

**Etapa:** E0 concluída e aprovada; preservado de E1 a E5.

**História de usuário:** Como pesquisador, quero preservar o diagnóstico Android já validado, para consultar câmera, GPS e HTTPS sem perder a evidência aprovada da infraestrutura.

#### Critérios de aceitação

1. THE Aplicativo SHALL registrar a E0 como implementada, validada fisicamente no Samsung Galaxy S25+ e aprovada.
2. THE Aplicativo SHALL preservar o comportamento e as responsabilidades aprovados do Diagnóstico da E0.
3. THE Aplicativo SHALL preservar as evidências históricas existentes da E0 sem alteração retroativa.
4. WHEN uma etapa posterior estiver disponível, THE Aplicativo SHALL integrar o acesso ao Diagnóstico pela navegação do novo aplicativo.
5. WHEN o projeto com o Diagnóstico integrado for verificado, THE Aplicativo SHALL permitir build, instalação, abertura e execução controlada no Samsung Galaxy S25+.
6. WHEN o Diagnóstico for aberto com permissão de câmera, THE Aplicativo SHALL exibir o preview básico da câmera traseira conforme o comportamento aprovado.
7. WHEN a câmera for necessária sem permissão concedida, THE Aplicativo SHALL solicitar a permissão e apresentar mensagem clara se a câmera permanecer indisponível.
8. WHEN a localização for necessária sem permissão concedida, THE Aplicativo SHALL solicitar localização precisa e apresentar mensagem clara se serviço, permissão ou posição permanecer indisponível.
9. WHEN uma posição estiver disponível no Diagnóstico, THE Aplicativo SHALL exibir latitude, longitude, precisão reportada e velocidade quando fornecida pelo provedor.
10. WHEN a conectividade for diagnosticada, THE Aplicativo SHALL indicar o estado da rede e permitir a requisição HTTPS diagnóstica aprovada.
11. WHERE o HTTP diagnóstico for executado, THE Aplicativo SHALL manter a operação separada de uma ocorrência.
12. WHERE o HTTP diagnóstico for executado, THE Aplicativo SHALL usar somente servidor simulado ou ambiente exclusivo de teste.
13. WHERE o HTTP diagnóstico for executado, THE Aplicativo SHALL omitir o endpoint `/api/v1/occurrences`.
14. WHERE o HTTP diagnóstico for executado, THE Aplicativo SHALL omitir API key real e credencial de produção.
15. IF câmera, localização, rede ou destino de diagnóstico estiver indisponível, THEN THE Aplicativo SHALL apresentar a mensagem controlada prevista pela E0.
16. WHERE o fluxo da tela Diagnóstico for executado, THE Aplicativo SHALL permanecer sem modelo, inferência, criação de ocorrência, UUID, cooldown, fila, multipart ou integração real com a API de ocorrências.
17. WHEN os resultados da E0 forem consultados, THE Aplicativo SHALL manter disponíveis o roteiro e as evidências aprovadas de build, instalação, abertura, câmera, permissões, GPS, precisão, velocidade quando disponível, rede, HTTPS diagnóstico e indisponibilidades.
18. WHERE a E0 estiver preservada, THE Aplicativo SHALL manter registrada a aprovação histórica existente.
19. WHERE a integração à nova navegação exigir reorganização interna, THE Aplicativo SHALL permitir movimentação de arquivos e refatoração mínima sem exigir preservação literal da estrutura de arquivos ou do código da E0.
20. WHEN arquivos da E0 forem movidos ou refatorados para integração, THE Aplicativo SHALL preservar câmera, GPS, HTTPS diagnóstico, mensagens, permissões e ciclo de vida aprovados.
21. WHERE o cliente HTTP diagnóstico estiver disponível, THE Aplicativo SHALL mantê-lo separado do cliente HTTP de ocorrências.
22. IF a integração introduzir regressão no Diagnóstico, THEN THE Aplicativo SHALL corrigir a regressão na etapa que a introduziu.

### RF-01 — Plataforma e execução Android

**Etapa:** E0, mantido de E1 a E5.

**História de usuário:** Como pesquisador, quero executar o aplicativo no Android, principalmente no Samsung Galaxy S25+, para utilizar o celular como cliente veicular de captura.

#### Critérios de aceitação

1. WHERE o MVP for distribuído, THE Aplicativo SHALL oferecer suporte exclusivamente à plataforma Android.
2. WHEN o Aplicativo for instalado em um Samsung Galaxy S25+ compatível, THE Aplicativo SHALL permitir as funcionalidades aprovadas até a etapa corrente.
3. IF um recurso específico do dispositivo estiver indisponível, THEN THE Aplicativo SHALL apresentar falha controlada.

### RF-02 — Carregamento futuro do modelo

**Etapa:** E5.

**História de usuário:** Como operador, quero carregar o modelo treinado somente quando estiver disponível, para habilitar a detecção automática sem bloquear as etapas manuais.

#### Critérios de aceitação

1. WHERE E1, E2, E3 ou E4 estiver em execução, THE Aplicativo SHALL operar sem TFLite e sem `ultralytics_yolo`.
2. WHEN E5 for iniciada com modelo treinado e compatível disponível, THE Aplicativo SHALL carregar localmente o TFLite incluído nos assets.
3. WHILE o carregamento estiver em andamento, THE Aplicativo SHALL indicar que o modelo ainda não está disponível.
4. WHEN o carregamento terminar com sucesso, THE Aplicativo SHALL indicar o estado “modelo carregado”.
5. IF o modelo não puder ser carregado, THEN THE Aplicativo SHALL impedir o início da inferência e apresentar mensagem controlada.
6. WHERE a detecção YOLO for executada, THE Aplicativo SHALL isolar `ultralytics_yolo` atrás da abstração de Fonte de candidato de ocorrência.
7. WHERE o modelo for carregado, THE Aplicativo SHALL usar somente o arquivo incluído nos assets, sem download ou atualização pela rede.
8. IF o modelo não puder ser carregado, THEN THE Aplicativo SHALL manter disponível o Modo manual temporário.

### RF-03 — Tela operacional, preview e captura manual

**Etapa:** E1; mantido e ampliado de E2 a E5.

**História de usuário:** Como operador, quero visualizar a pista e registrar um buraco observado, para criar uma ocorrência antes da disponibilidade do YOLO.

#### Critérios de aceitação

1. WHEN a câmera traseira estiver autorizada e disponível em E1, THE Aplicativo SHALL exibir o preview na nova tela operacional.
2. WHILE o Modo manual temporário estiver ativo, THE Aplicativo SHALL exibir permanentemente o banner “Modo manual — YOLO ainda não configurado” ou texto inequívoco equivalente.
3. WHILE o Modo manual temporário estiver ativo, THE Aplicativo SHALL apresentar o botão principal “Registrar buraco”.
4. WHEN o operador tocar em “Registrar buraco”, THE Aplicativo SHALL interpretar o toque como confirmação manual de um buraco observado.
5. WHEN o toque em “Registrar buraco” for aceito, THE Aplicativo SHALL iniciar imediatamente a operação de captura da imagem como consequência do acionamento.
6. WHILE a câmera estiver indisponível, THE Aplicativo SHALL manter o botão “Registrar buraco” desabilitado.
7. WHILE a localização estiver inválida, THE Aplicativo SHALL manter o botão “Registrar buraco” desabilitado.
8. WHILE outra captura manual estiver em processamento, THE Aplicativo SHALL manter o botão “Registrar buraco” desabilitado.
9. WHILE o ciclo de vida impedir captura segura, THE Aplicativo SHALL manter o botão “Registrar buraco” desabilitado.
10. WHEN toques simultâneos ou repetidos ocorrerem durante uma captura manual, THE Aplicativo SHALL processar no máximo uma operação de registro.
11. WHEN o operador selecionar “Diagnóstico”, THE Aplicativo SHALL abrir a funcionalidade preservada da E0.
12. WHERE E5 substituir ou desativar a fonte manual, THE Aplicativo SHALL manter inalterado o pós-candidato compartilhado.
13. WHEN o toque em “Registrar buraco” for aceito, THE Aplicativo SHALL registrar imediatamente o instante do acionamento como origem de `detectedAt`.
14. WHEN o cooldown rejeitar um acionamento manual, THE Aplicativo SHALL informar brevemente que o registro foi ignorado porque tempo e distância permanecem abaixo dos mínimos vigentes.
15. WHEN o cooldown rejeitar um acionamento manual, THE Aplicativo SHALL impedir a criação de imagem definitiva, UUID e ocorrência.
16. WHERE a interação de cooldown for definida no design, THE Aplicativo SHALL preservar o feedback do bloqueio tanto com botão desabilitado quanto com toque destinado somente ao feedback.
17. WHERE E5 estiver entregue com modelo carregado, THE Aplicativo SHALL manter o botão “Registrar buraco” como confirmação manual complementar, com `confidence = 1.0`.

### RF-04 — Inferência YOLO contínua e limitada

**Etapa:** E5.

**História de usuário:** Como pesquisador, quero realizar inferência local com taxa limitada quando o modelo estiver disponível, para emitir candidatos automáticos sem acumular frames.

#### Critérios de aceitação

1. WHILE a captura automática estiver ativa e o modelo estiver carregado, THE Aplicativo SHALL executar inferências locais sobre frames da câmera.
2. WHERE não existir configuração salva de FPS, THE Aplicativo SHALL limitar a inferência a `5 FPS`.
3. WHEN frames forem recebidos acima do limite vigente, THE Aplicativo SHALL descartar frames excedentes sem enfileirá-los para inferência posterior.
4. WHEN um frame não contiver candidato elegível, THE Aplicativo SHALL descartá-lo sem armazenamento persistente.
5. WHILE a inferência estiver ativa, THE Aplicativo SHALL atualizar o FPS atual ou recente na tela principal.
6. WHERE o detector produzir classes, THE Aplicativo SHALL emitir candidatos somente para a classe `pothole`.
7. WHEN o YOLO emitir um candidato, THE Aplicativo SHALL entregá-lo ao mesmo pós-candidato utilizado pela fonte manual.
8. WHEN uma detecção acima do limiar vigente for observada, THE Aplicativo SHALL emitir candidato somente após detecção compatível em pelo menos 2 dos últimos 3 frames processados.
9. WHEN um candidato YOLO for emitido, THE Aplicativo SHALL usar a confiança produzida pelo modelo e `defectClass` exatamente `pothole`, nunca `confidence = 1.0` por convenção.
10. WHILE outro candidato estiver em processamento, THE Aplicativo SHALL descartar novas detecções sem enfileirá-las.
11. WHEN uma detecção já tiver gerado candidato, THE Aplicativo SHALL suprimir novos candidatos da mesma detecção persistente até que ela deixe de ser observada.
12. WHEN uma caixa detectada ocupar mais que a área máxima vigente do frame (padrão `20%`), THE Aplicativo SHALL descartá-la antes da confirmação temporal.
13. WHERE a detecção YOLO for executada, THE Aplicativo SHALL configurar o NMS do detector com IoU `0.7` e SHALL NOT aplicar desfoque ou outro pré-processamento adicional aos frames.
14. WHEN o checkpoint de compatibilidade do modelo for executado, THE Aplicativo SHALL produzir, para as mesmas imagens de referência e na resolução do stream da câmera, caixas e confianças praticamente iguais às obtidas na validação do modelo fora do Aplicativo, ou a divergência SHALL ser registrada e tratada antes da implementação.

### RF-05 — Indicadores da tela principal

**Etapa:** E1, ampliado em E2, E3, E4 e E5.

**História de usuário:** Como operador, quero observar o estado do sistema em uma única tela, para entender captura, localização, fila e envio.

#### Critérios de aceitação

1. WHILE a tela operacional de E1 estiver visível, THE Aplicativo SHALL apresentar preview, banner do modo manual, botão “Registrar buraco”, disponibilidade de câmera e estado de GPS.
2. WHILE a tela operacional de E1 estiver visível, THE Aplicativo SHALL apresentar latitude, longitude, precisão reportada e velocidade quando disponíveis.
3. WHEN uma captura manual estiver em processamento, THE Aplicativo SHALL indicar o estado de processamento.
4. WHEN uma ocorrência manual for criada, THE Aplicativo SHALL atualizar a quantidade de buracos registrados na sessão.
5. WHERE E2 estiver entregue, THE Aplicativo SHALL apresentar a quantidade persistida de ocorrências pendentes.
6. WHERE E3 estiver entregue, THE Aplicativo SHALL indicar se a configuração necessária para envio está presente sem expor a API key.
7. WHERE E4 estiver entregue, THE Aplicativo SHALL apresentar o estado dos envios e eventuais pausas.
8. WHERE E5 estiver entregue, THE Aplicativo SHALL apresentar estado do modelo, FPS de inferência e modo operacional vigente.
9. WHILE o Modo manual temporário estiver ativo, THE Aplicativo SHALL evitar qualquer indicação de detecção automática.
10. WHEN o cooldown rejeitar um registro manual, THE Aplicativo SHALL apresentar feedback breve e explícito sobre a proximidade simultânea de tempo e distância.
11. WHERE um indicador de cooldown for adotado, THE Aplicativo SHALL indicar o cooldown ativo sem substituir o feedback de um registro rejeitado.

### RF-06 — Obtenção e validação da localização

**Etapa:** E1; tratamento ampliado em E3.

**História de usuário:** Como pesquisador, quero associar coordenadas e velocidade válidas ao acionamento manual, para geolocalizar o buraco observado.

#### Critérios de aceitação

1. WHILE a tela operacional estiver ativa e a permissão precisa estiver concedida, THE Aplicativo SHALL obter atualizações de localização utilizáveis pela captura manual.
2. WHEN um candidato for recebido, THE Aplicativo SHALL associar latitude entre -90 e 90 e longitude entre -180 e 180.
3. IF nenhuma localização válida estiver disponível, THEN THE Aplicativo SHALL impedir a criação da ocorrência.
4. IF nenhuma localização válida estiver disponível, THEN THE Aplicativo SHALL informar a indisponibilidade do GPS.
5. WHEN o provedor disponibilizar precisão, THE Aplicativo SHALL exibir a precisão reportada.
6. WHEN o provedor disponibilizar velocidade válida, THE Aplicativo SHALL convertê-la para km/h.
7. IF a velocidade convertida estiver entre 0 e 300 km/h, inclusive, THEN THE Aplicativo SHALL incluir `speedKmh` na ocorrência.
8. IF a velocidade estiver ausente, negativa, superior a 300 km/h ou não validável, THEN THE Aplicativo SHALL omitir `speedKmh`.

### RF-07 — Candidato manual e criação da ocorrência

**Etapa:** E1; fonte automática futura em E5.

**História de usuário:** Como pesquisador, quero transformar uma confirmação manual válida em ocorrência completa, para desenvolver o domínio antes do modelo treinado.

#### Critérios de aceitação

1. WHEN o operador acionar “Registrar buraco” em condições habilitadas, THE Fonte de candidato de ocorrência SHALL emitir um candidato manual ao pós-candidato compartilhado.
2. WHEN um candidato manual for processado, THE Aplicativo SHALL usar `defectClass` exatamente `pothole`.
3. WHEN um candidato manual for processado, THE Aplicativo SHALL usar `confidence` exatamente `1.0` como confirmação manual.
4. WHERE o modo manual produzir uma ocorrência, THE Aplicativo SHALL omitir o campo `source`.
5. WHEN um candidato tiver imagem, localização, horário e cooldown válidos, THE Aplicativo SHALL criar uma ocorrência completa.
6. IF qualquer dado obrigatório estiver ausente ou inválido, THEN THE Aplicativo SHALL rejeitar a criação da ocorrência.
7. WHEN uma ocorrência for criada, THE Aplicativo SHALL incluir latitude, longitude, confiança, classe, horário da captura e UUID de idempotência.
8. WHEN houver velocidade válida, THE Aplicativo SHALL incluir `speedKmh`.
9. WHERE o MVP criar uma ocorrência, THE Aplicativo SHALL omitir `highway` e `km`.
10. WHEN uma ocorrência for aceita, THE Aplicativo SHALL incrementar a quantidade de buracos registrados na sessão.
11. WHEN um candidato YOLO for habilitado em E5, THE Aplicativo SHALL encaminhá-lo ao mesmo pós-candidato compartilhado.
12. WHEN a Fonte de candidato de ocorrência emitir um candidato manual, THE Fonte de candidato de ocorrência SHALL incluir o instante registrado no aceite do toque como origem de `detectedAt`.
13. WHEN um candidato manual incluir uma imagem, THE Aplicativo SHALL associar a imagem produzida pela operação de captura iniciada em consequência do mesmo acionamento aceito.

### RF-08 — Data, hora e idempotência

**Etapa:** E1; preservado de E2 a E5.

**História de usuário:** Como integrador, quero horário inequívoco e chave estável, para preservar a identidade da ocorrência em persistência e reenvios.

#### Critérios de aceitação

1. WHEN uma ocorrência for criada, THE Aplicativo SHALL registrar `detectedAt` em ISO 8601 com informação de fuso horário.
2. WHEN uma ocorrência manual for criada, THE Aplicativo SHALL usar como `detectedAt` o instante em que o toque “Registrar buraco” foi aceito.
3. WHEN uma ocorrência for criada, THE Aplicativo SHALL gerar uma única `idempotencyKey` no formato UUID.
4. WHILE a ocorrência existir em memória, fila ou reenvio, THE Aplicativo SHALL preservar a mesma `idempotencyKey`.
5. IF uma tentativa de envio falhar, THEN THE Aplicativo SHALL reutilizar a `idempotencyKey` original.
6. WHEN o toque “Registrar buraco” for aceito, THE Aplicativo SHALL registrar o instante antes de operações assíncronas de captura, GPS, compressão ou geração de UUID.
7. WHEN GPS, compressão, geração de UUID ou preparação da ocorrência terminar, THE Aplicativo SHALL preservar em `detectedAt` o instante original do acionamento aceito.
8. WHEN uma ocorrência for enviada ou reenviada, THE Aplicativo SHALL preservar `detectedAt` sem substituí-lo pelo horário do envio.
9. WHERE a captura manual associar imagem e `detectedAt`, THE Aplicativo SHALL associar ambos pela mesma operação iniciada no acionamento sem exigir coincidência de milissegundo com o sensor da câmera.

### RF-09 — Cooldown e deduplicação local

**Etapa:** E1; configurável em E3.

**História de usuário:** Como pesquisador, quero limitar registros próximos por tempo e distância, para reduzir duplicações durante a mesma passagem.

#### Critérios de aceitação

1. WHEN o primeiro candidato elegível não possuir ocorrência anterior, THE Aplicativo SHALL permitir a criação da ocorrência.
2. WHEN existir ocorrência anterior e tiver transcorrido pelo menos o cooldown vigente, THE Aplicativo SHALL permitir a nova ocorrência.
3. WHEN existir ocorrência anterior e o deslocamento atingir pelo menos a distância mínima vigente, THE Aplicativo SHALL permitir a nova ocorrência.
4. WHILE o tempo transcorrido for menor que o cooldown vigente e o deslocamento for menor que a distância mínima vigente, THE Aplicativo SHALL rejeitar o novo candidato.
5. WHERE não existir configuração salva, THE Aplicativo SHALL usar cooldown de `5 segundos`.
6. WHERE não existir configuração salva, THE Aplicativo SHALL usar distância mínima de `15 metros`.
7. WHEN um acionamento manual ocorrer, THE Aplicativo SHALL aplicar o cooldown antes de criar a ocorrência.
8. WHERE o MVP aplicar deduplicação, THE Aplicativo SHALL usar somente a regra local de tempo ou distância.
9. WHEN o tempo transcorrido e o deslocamento permanecerem simultaneamente abaixo dos mínimos vigentes, THE Aplicativo SHALL informar brevemente que o registro foi ignorado por cooldown.
10. WHEN um candidato for bloqueado por cooldown, THE Aplicativo SHALL impedir a criação de imagem definitiva, UUID e ocorrência para o candidato bloqueado.
11. WHILE uma captura manual estiver em processamento ou o cooldown bloquear um candidato, THE Aplicativo SHALL impedir concorrência e duplicidade de registro.

### RF-10 — Preparação e validação da imagem

**Etapa:** E1; preservado de E2 a E5.

**História de usuário:** Como integrador, quero preparar a imagem no contrato fixo, para impedir ocorrências impossíveis de persistir ou enviar.

#### Critérios de aceitação

1. WHEN um candidato passar pelas validações anteriores, THE Aplicativo SHALL converter em JPEG com qualidade `85` a imagem produzida pela operação de captura iniciada no acionamento aceito.
2. WHEN a imagem exceder 1280 pixels de largura ou 720 pixels de altura, THE Aplicativo SHALL redimensioná-la para caber em `1280x720` preservando a proporção.
3. WHEN qualquer tentativa de compressão JPEG ocorrer, THE Aplicativo SHALL usar qualidade `85`.
4. IF o JPEG exceder `2 MiB`, THEN THE Aplicativo SHALL reduzir progressivamente somente as dimensões.
5. WHEN novas tentativas por tamanho ocorrerem, THE Aplicativo SHALL preservar a proporção original e a qualidade `85`.
6. WHERE a imagem for preparada, THE Aplicativo SHALL manter o limite máximo de `1280x720`.
7. WHEN uma ocorrência for aceita, THE Aplicativo SHALL garantir arquivo JPEG de até `2 MiB`.
8. IF não for possível cumprir `2 MiB` reduzindo somente dimensões, THEN THE Aplicativo SHALL rejeitar a ocorrência.
9. IF a imagem for rejeitada, THEN THE Aplicativo SHALL impedir seu enfileiramento e envio.
10. IF a imagem for rejeitada, THEN THE Aplicativo SHALL registrar erro técnico sem API key, conteúdo da imagem ou outro segredo.
11. WHERE uma imagem manual temporária for armazenada, THE Aplicativo SHALL mantê-la somente no armazenamento privado do Aplicativo.
12. WHERE uma captura manual produzir imagem temporária, THE Aplicativo SHALL omitir gravação automática na galeria do dispositivo.
13. IF uma imagem for rejeitada durante validação ou preparação, THEN THE Aplicativo SHALL remover o arquivo temporário correspondente.
14. IF uma falha ocorrer antes da criação de uma ocorrência válida, THEN THE Aplicativo SHALL remover arquivos temporários sem responsabilidade atribuída.
15. IF a limpeza de uma imagem temporária falhar, THEN THE Aplicativo SHALL registrar erro técnico sem conteúdo da imagem, API key ou outro segredo.

### RF-11 — Ocorrência completa em memória

**Etapa:** E1.

**História de usuário:** Como desenvolvedor, quero validar a ocorrência manual completa em memória, para comprovar as regras antes da fila e da rede.

#### Critérios de aceitação

1. WHEN todos os dados obrigatórios e a imagem forem válidos, THE Aplicativo SHALL criar em memória uma ocorrência compatível com o contrato fixo.
2. WHERE E1 estiver em execução, THE Aplicativo SHALL operar sem fila persistente.
3. WHERE E1 estiver em execução, THE Aplicativo SHALL operar sem integração real com a API.
4. WHERE E1 estiver em execução, THE Aplicativo SHALL operar sem API key.
5. IF qualquer dado obrigatório estiver ausente ou inválido, THEN THE Aplicativo SHALL manter a ocorrência fora do estado de pronta.
6. WHILE uma ocorrência permanecer válida somente em memória durante E1, THE Aplicativo SHALL reter a imagem temporária apenas pelo período necessário para validar ou apresentar a ocorrência.
7. WHEN a ocorrência em memória e sua imagem deixarem de ser necessárias, a sessão terminar ou a ocorrência for descartada em E1, THE Aplicativo SHALL remover o arquivo temporário sem uso.
8. WHEN uma ocorrência válida for aceita em E2, THE Aplicativo SHALL transferir formalmente à fila persistente a responsabilidade pelos dados e pela imagem associados.

### RF-12 — Persistência local da fila

**Etapa:** E2.

**História de usuário:** Como operador, quero preservar ocorrências e imagens antes do envio, para evitar perda quando o aplicativo for fechado.

#### Critérios de aceitação

1. WHEN uma ocorrência válida for produzida em E2, THE Aplicativo SHALL gravá-la integralmente na fila local antes de qualquer envio futuro.
2. WHEN uma ocorrência for persistida, THE Aplicativo SHALL preservar a imagem associada necessária para reconstruir o envio.
3. WHEN o Aplicativo for fechado e reaberto, THE Aplicativo SHALL recuperar as ocorrências pendentes.
4. WHILE uma ocorrência aguardar envio ou permanecer pausada, THE Aplicativo SHALL preservar os dados necessários para reconstruir exatamente o mesmo envio.
5. WHEN a fila for alterada ou recuperada, THE Aplicativo SHALL atualizar o indicador de pendências.
6. WHERE E2 estiver em execução, THE Aplicativo SHALL operar sem integração real com a API.
7. IF a persistência de uma nova ocorrência falhar, THEN THE Aplicativo SHALL impedir qualquer envio dessa ocorrência.
8. IF a persistência falhar, THEN THE Aplicativo SHALL registrar erro técnico sem segredo.
9. WHEN uma remoção for confirmada, THE Aplicativo SHALL remover consistentemente os dados e a imagem associados.
10. WHEN a ocorrência e a imagem forem persistidas com sucesso em E2, THE Fila persistente SHALL assumir formalmente a responsabilidade pelos arquivos necessários à ocorrência.
11. WHILE a Fila persistente mantiver responsabilidade por uma imagem, THE Aplicativo SHALL preservar a imagem até sucesso ou descarte explícito da ocorrência.

### RF-13 — Configuração, destino e credencial segura

**Etapa:** E3; consumido em E4.

**História de usuário:** Como operador autorizado, quero configurar destino e credencial com proteção Android, para habilitar o envio sem expor segredos.

#### Critérios de aceitação

1. WHEN E3 estiver entregue, THE Aplicativo SHALL permitir configurar uma `BASE_URL` sem o sufixo `/api/v1/occurrences`.
2. WHERE uma `BASE_URL` de produção for configurada, THE Aplicativo SHALL exigir origem HTTPS.
3. WHERE desenvolvimento USB usar `adb reverse tcp:3000 tcp:3000`, THE Aplicativo SHALL aceitar `http://localhost:3000` somente na variante debug.
4. WHERE HTTP de desenvolvimento for permitido, THE Aplicativo SHALL limitar a permissão ao manifesto Android de debug.
5. WHERE a variante principal ou release for construída, THE Aplicativo SHALL manter HTTP sem TLS bloqueado.
6. WHEN a API key for salva, THE Aplicativo SHALL armazenar a chave completa em armazenamento seguro com proteção Android.
7. WHEN uma API key já salva for representada, THE Aplicativo SHALL indicar somente que a chave está configurada sem preencher a interface com o valor completo.
8. WHERE código, arquivos versionados, logs ou mensagens forem produzidos, THE Aplicativo SHALL omitir a chave completa.
9. WHEN E4 enviar uma ocorrência, THE Aplicativo SHALL usar o endpoint `POST {BASE_URL}/api/v1/occurrences`.
10. WHEN E4 enviar uma ocorrência, THE Aplicativo SHALL incluir `Authorization: ApiKey {DEVICE_API_KEY}`.
11. WHEN o header de autenticação for montado, THE Aplicativo SHALL usar o esquema exatamente `ApiKey` seguido de exatamente um espaço e da chave completa.
12. WHERE a autenticação da ocorrência for montada, THE Aplicativo SHALL omitir o esquema `Bearer`.
13. WHERE a autenticação da ocorrência for montada, THE Aplicativo SHALL não enviar `X-API-Key` nem qualquer header alternativo de API key.
14. IF `BASE_URL` ou API key estiver ausente, THEN THE Aplicativo SHALL manter a ocorrência na fila.
15. IF `BASE_URL` ou API key estiver ausente, THEN THE Aplicativo SHALL impedir a chamada ao endpoint.
16. IF `BASE_URL` ou API key estiver ausente, THEN THE Aplicativo SHALL informar que a configuração é necessária.
17. WHEN uma API key completa for informada para salvamento, THE Aplicativo SHALL validar minimamente a presença de um prefixo, um ponto separador e um segredo não vazio no formato `prefixo.segredo`.
18. WHEN um administrador criar ou rotacionar a chave de um dispositivo, THE Administração Next.js SHALL exibir a chave completa uma única vez para cópia manual.
19. WHEN o administrador abrir posteriormente as configurações Flutter, THE Aplicativo SHALL oferecer campo para colar e salvar a chave completa copiada da Administração Next.js.
20. WHERE o provisionamento manual da chave for realizado, THE Aplicativo SHALL tratar a exibição no Next.js e o salvamento no Flutter como ações independentes, sem exigir que o Aplicativo esteja aberto durante a exibição e sem detectar o fechamento do diálogo externo.
21. WHERE um dispositivo de teste for criado para Flutter, THE Aplicativo SHALL permitir o uso preferencial do tipo `mobile`.
22. WHEN as configurações forem reabertas após o salvamento, THE Aplicativo SHALL indicar que a API key está configurada sem preencher o campo com a chave completa.
23. WHEN o operador substituir a API key, THE Aplicativo SHALL exigir um novo valor completo com formato válido.
24. WHEN o operador solicitar a remoção da API key, THE Aplicativo SHALL exigir confirmação antes de remover o valor do armazenamento seguro.
25. IF a API key completa for perdida ou não tiver sido copiada, THEN THE Aplicativo SHALL orientar o administrador a rotacionar a chave na Administração Next.js.
26. WHERE a configuração de API key for usada, THE Aplicativo SHALL depender somente do valor fornecido manualmente e omitir qualquer alegação de recuperação da chave pelo back-end.

### RF-14 — Montagem do envio multipart

**Etapa:** E4.

**História de usuário:** Como integrador, quero enviar cada ocorrência no contrato definido, para garantir compatibilidade com a API.

#### Critérios de aceitação

1. WHEN uma ocorrência pendente for enviada, THE Aplicativo SHALL usar `multipart/form-data`.
2. WHEN o multipart for montado, THE Aplicativo SHALL incluir `image` como arquivo JPEG obrigatório.
3. WHEN o multipart for montado, THE Aplicativo SHALL incluir `idempotencyKey` como UUID igual ao valor persistido.
4. WHEN o multipart for montado, THE Aplicativo SHALL incluir `latitude` entre -90 e 90.
5. WHEN o multipart for montado, THE Aplicativo SHALL incluir `longitude` entre -180 e 180.
6. WHEN o multipart for montado, THE Aplicativo SHALL incluir `confidence` entre 0 e 1.
7. WHEN uma ocorrência manual for montada, THE Aplicativo SHALL enviar `confidence` exatamente `1.0`.
8. WHEN o multipart for montado, THE Aplicativo SHALL incluir `defectClass` exatamente `pothole`.
9. IF houver velocidade válida, THEN THE Aplicativo SHALL incluir `speedKmh` entre 0 e 300.
10. IF não houver velocidade válida, THEN THE Aplicativo SHALL omitir `speedKmh`.
11. WHEN o multipart for montado, THE Aplicativo SHALL incluir `detectedAt` em ISO 8601 com informação de fuso.
12. WHERE o envio pertencer ao MVP, THE Aplicativo SHALL omitir `highway`, `km` e `source`.
13. WHEN uma tentativa da mesma ocorrência for reconstruída, THE Aplicativo SHALL usar os mesmos dados persistidos, a mesma imagem e a mesma `idempotencyKey`.
14. WHERE a tela operacional estiver ativa, THE Aplicativo SHALL delegar a montagem do multipart à camada de integração.

### RF-15 — Sucesso e descarte de respostas definitivas

**Etapa:** E4.

**História de usuário:** Como operador, quero remover ocorrências concluídas ou rejeitadas definitivamente, para manter a fila consistente.

#### Critérios de aceitação

1. WHEN a API responder `201`, THE Aplicativo SHALL considerar a ocorrência criada com sucesso e removê-la da fila.
2. WHEN a API responder `200`, THE Aplicativo SHALL considerar a ocorrência já existente por idempotência e removê-la da fila.
3. WHEN a API responder `400`, THE Aplicativo SHALL descartar a ocorrência e registrar erro técnico de multipart, campo ou contrato inválido.
4. WHEN a API atual responder `400` por MIME diferente de `image/jpeg`, THE Aplicativo SHALL descartar a ocorrência e registrar erro de formato sem expor a imagem.
5. WHEN a API responder `409`, THE Aplicativo SHALL descartar a ocorrência e registrar conflito protegido de idempotência.
6. WHERE uma tentativa repetir a mesma `idempotencyKey`, THE Aplicativo SHALL tratar `200` como resposta normal de idempotência em vez de presumir `409`.
7. WHEN a API responder `413`, THE Aplicativo SHALL descartar a ocorrência e registrar imagem acima de `2 MiB`.
8. WHEN a API responder `415`, THE Aplicativo SHALL descartar a ocorrência e registrar formato não suportado como proteção futura.
9. WHERE o back-end atual rejeitar MIME inválido, THE Aplicativo SHALL esperar `400` em vez de depender de `415`.
10. WHEN uma ocorrência for removida ou descartada, THE Aplicativo SHALL atualizar o indicador persistente de pendências.
11. WHEN uma ocorrência for removida ou descartada, THE Aplicativo SHALL remover a imagem local que não seja mais necessária.
12. WHERE uma mensagem técnica for registrada, THE Aplicativo SHALL omitir API key e outros segredos.

### RF-16 — Pausa por autenticação ou acesso

**Etapa:** E4.

**História de usuário:** Como operador, quero pausar tentativas quando autenticação ou acesso falhar, para corrigir a configuração sem perder ocorrências.

#### Critérios de aceitação

1. WHEN a API responder `401`, THE Aplicativo SHALL manter a ocorrência na fila e pausar os envios.
2. WHEN a API responder `401`, THE Aplicativo SHALL informar que a chave está ausente, malformada ou inválida sem exibir a chave.
3. WHEN a API responder `403`, THE Aplicativo SHALL manter a ocorrência na fila e pausar os envios.
4. WHEN a API responder `403`, THE Aplicativo SHALL informar que o dispositivo está inativo.
5. WHILE os envios estiverem pausados por `401` ou `403`, THE Aplicativo SHALL impedir novas tentativas automáticas.
6. WHEN a configuração relevante for corrigida, THE Aplicativo SHALL permitir a retomada dos envios pendentes.
7. WHEN uma nova tentativa manual for solicitada, THE Aplicativo SHALL permitir a retomada dos envios pendentes.
8. WHILE a pausa estiver ativa, THE Aplicativo SHALL indicar o estado sem expor a API key.

### RF-17 — Falhas recuperáveis, reenvio e backoff

**Etapa:** E4.

**História de usuário:** Como operador, quero tratar falhas temporárias automaticamente, para preservar ocorrências sem sobrecarregar a rede ou a API.

#### Critérios de aceitação

1. WHEN ocorrer falha de rede, timeout ou resposta HTTP `5xx`, THE Aplicativo SHALL manter a ocorrência na fila.
2. WHEN ocorrer falha de rede, timeout ou resposta HTTP `5xx`, THE Aplicativo SHALL programar nova tentativa com backoff exponencial limitado por um teto.
3. WHILE uma ocorrência aguardar o instante permitido pelo backoff, THE Aplicativo SHALL impedir tentativa contínua.
4. WHEN o Aplicativo voltar a ter oportunidade de execução, THE Aplicativo SHALL retomar o processamento das ocorrências elegíveis.
5. WHERE o Android limitar execução em segundo plano, THE Aplicativo SHALL preservar a fila para retomada posterior.
6. WHEN uma tentativa for repetida, THE Aplicativo SHALL reutilizar imagem, dados e `idempotencyKey` originais.

### RF-18 — Códigos HTTP não especificados

**Etapa:** E4.

**História de usuário:** Como operador, quero comportamento conservador para respostas inesperadas, para evitar perda de dados e ciclos de requisição.

#### Critérios de aceitação

1. WHEN a API responder código não tratado em RF-15, RF-16 ou RF-17, THE Aplicativo SHALL manter a ocorrência na fila.
2. WHEN ocorrer código não especificado, THE Aplicativo SHALL pausar o envio automático.
3. WHEN ocorrer código não especificado, THE Aplicativo SHALL registrar erro técnico sem segredo e avisar o usuário.
4. WHILE a pausa por código não especificado estiver ativa, THE Aplicativo SHALL impedir ciclos automáticos de tentativas.
5. WHEN a configuração aplicável for corrigida, THE Aplicativo SHALL permitir a retomada.
6. WHEN uma nova tentativa manual for solicitada, THE Aplicativo SHALL permitir a retomada.

### RF-19 — Tela de configurações

**Etapa:** E3.

**História de usuário:** Como operador, quero ajustar parâmetros atuais e futuros, para preparar o aplicativo para fila, API e YOLO.

#### Critérios de aceitação

1. WHEN o operador abrir as configurações, THE Aplicativo SHALL permitir configurar `BASE_URL` e API key do dispositivo.
2. WHEN o operador abrir as configurações, THE Aplicativo SHALL permitir configurar cooldown e distância mínima.
3. WHEN o operador abrir as configurações, THE Aplicativo SHALL permitir configurar limiar de confiança e FPS máximo para uso futuro em E5.
4. WHEN não houver valor salvo, THE Aplicativo SHALL aplicar cooldown de `5 segundos` e distância mínima de `15 metros`.
5. WHEN não houver valor salvo, THE Aplicativo SHALL aplicar confiança `0.35` e máximo de `5 FPS` em E5. *(Emenda E5: substitui `0.5`.)*
6. IF um valor numérico estiver vazio, não numérico ou fora do domínio, THEN THE Aplicativo SHALL impedir seu salvamento e indicar o campo inválido.
7. WHERE o limiar de confiança for configurado, THE Aplicativo SHALL aceitar somente valor entre 0 e 1.
8. WHERE FPS máximo, cooldown ou distância mínima forem configurados, THE Aplicativo SHALL aceitar somente valores positivos.
9. WHEN a API key for salva ou alterada, THE Aplicativo SHALL usar armazenamento seguro com proteção Android.
10. WHEN a configuração for reaberta, THE Aplicativo SHALL indicar somente que a API key está configurada sem preencher o campo com o valor completo.
11. WHERE exemplos forem exibidos, THE Aplicativo SHALL usar somente valores fictícios.
12. IF `BASE_URL` ou API key permanecer vazio, THEN THE Aplicativo SHALL permitir o funcionamento de E1 e E2.
13. WHEN o operador configurar a API key, THE Aplicativo SHALL oferecer campo para colar o valor completo copiado manualmente da Administração Next.js.
14. IF a API key informada não contiver prefixo, ponto separador e segredo não vazio, THEN THE Aplicativo SHALL impedir o salvamento e indicar formato inválido.
15. WHEN a tela de configurações for reaberta com API key salva, THE Aplicativo SHALL manter o campo da chave sem o valor completo e indicar o estado “configurada”.
16. WHEN o operador substituir a API key, THE Aplicativo SHALL solicitar um novo valor completo no formato `prefixo.segredo`.
17. WHEN o operador remover a API key, THE Aplicativo SHALL solicitar confirmação antes da remoção.
18. IF o operador perder a API key completa, THEN THE Aplicativo SHALL orientar a rotação na Administração Next.js em vez de tentar recuperar o valor do back-end.
19. WHERE E5 estiver entregue e o FPS máximo for configurado, THE Aplicativo SHALL aceitar somente inteiros de `1` a `15`. *(Emenda E5.)*
20. IF um FPS salvo antes da E5 estiver fora do domínio E5, THEN THE Aplicativo SHALL aplicar `5 FPS` e indicar o campo para correção. *(Emenda E5.)*

### RF-20 — Permissões de câmera e localização

**Etapa:** E1 para operação; ampliado em E3.

**História de usuário:** Como operador, quero orientações claras sobre permissões, para habilitar a captura manual de forma consciente.

#### Critérios de aceitação

1. WHEN a tela operacional necessitar da câmera sem permissão, THE Aplicativo SHALL solicitar acesso à câmera.
2. WHEN a tela operacional necessitar de geolocalização sem permissão, THE Aplicativo SHALL solicitar localização precisa.
3. IF a permissão de câmera for recusada temporariamente, THEN THE Aplicativo SHALL explicar que o registro manual ficará indisponível.
4. IF a localização precisa for recusada temporariamente, THEN THE Aplicativo SHALL explicar que ocorrências não podem ser criadas.
5. IF uma permissão necessária estiver permanentemente negada, THEN THE Aplicativo SHALL orientar a abertura das configurações do Android.
6. WHILE a câmera estiver sem autorização, THE Aplicativo SHALL manter o registro manual desabilitado.
7. WHILE a localização estiver inválida, THE Aplicativo SHALL manter o registro manual desabilitado.
8. WHERE E3 estiver entregue, THE Aplicativo SHALL oferecer o tratamento completo de reabertura e orientação de permissões sem alterar o Diagnóstico aprovado.

### RF-21 — Tela ligada e ciclo controlado

**Etapa:** E1; preservado de E2 a E5.

**História de usuário:** Como operador, quero manter a tela ativa durante a operação e controlar capturas concorrentes, para acompanhar o aplicativo com estado previsível.

#### Critérios de aceitação

1. WHILE o Modo operacional ativo estiver vigente, THE Aplicativo SHALL manter a tela do aparelho ligada.
2. WHEN o operador navegar para outra tela, o Aplicativo entrar em segundo plano ou a tela operacional for encerrada, THE Aplicativo SHALL liberar a manutenção de tela ligada.
3. WHILE o `AppLifecycleState` for diferente de `resumed`, THE Aplicativo SHALL bloquear novos registros manuais.
4. WHEN uma captura manual estiver em andamento e o Aplicativo sair de `resumed`, THE Aplicativo SHALL concluir ou cancelar controladamente o processamento conforme o ciclo de vida.
5. WHEN uma ocorrência já tiver sido aceita, THE Aplicativo SHALL preservar os dados conforme a etapa disponível.
6. WHERE o Diagnóstico for aberto, THE Aplicativo SHALL preservar o ciclo de vida próprio aprovado da tela Diagnóstico.
7. WHERE o Modo manual temporário estiver disponível, THE Aplicativo SHALL usar a visibilidade da tela operacional, o primeiro plano e o estado `resumed` como controle de ativação, sem exigir botão “Iniciar” ou “Parar” salvo decisão futura aprovada.

### RF-22 — Documentação operacional

**Etapa:** E4.

**História de usuário:** Como avaliador, quero instruções de preparação e integração, para reproduzir o MVP no aparelho de validação.

#### Critérios de aceitação

1. WHEN E4 for apresentada para validação, THE Aplicativo SHALL estar acompanhado de README com instalação do Flutter, build Android e execução no aparelho.
2. WHERE o README descrever configuração, THE Aplicativo SHALL documentar `BASE_URL` e API key somente com exemplos fictícios.
3. WHERE o README descrever autenticação, THE Aplicativo SHALL documentar `Authorization: ApiKey {DEVICE_API_KEY}`.
4. WHERE o README descrever desenvolvimento USB, THE Aplicativo SHALL documentar `adb reverse tcp:3000 tcp:3000` e `http://localhost:3000` somente para debug.
5. WHERE o README descrever integração, THE Aplicativo SHALL incluir exemplo compatível com o contrato fixo.
6. WHERE o README mencionar credenciais ou ambientes, THE Aplicativo SHALL omitir API key real e URL real de produção.

### RF-23 — Sequência de entrega e Validation Gates

**Etapa:** E0 a E5.

**História de usuário:** Como responsável pelo TCC, quero aprovar cada incremento antes do próximo, para controlar escopo e riscos no Samsung Galaxy S25+.

#### Critérios de aceitação

1. THE Aplicativo SHALL seguir estritamente a sequência `E0 aprovada → E1 → E2 → E3 → E4 → E5`.
2. THE Aplicativo SHALL manter a E0 registrada como concluída e aprovada.
3. WHEN uma etapa de E1 a E5 for concluída, THE Aplicativo SHALL interromper o avanço no Validation Gate correspondente.
4. IF a etapa corrente não tiver aprovação explícita, THEN THE Aplicativo SHALL permanecer na etapa corrente.
5. IF uma etapa for reprovada, THEN THE Aplicativo SHALL receber somente correções pertencentes à etapa corrente.
6. WHEN o responsável aprovar explicitamente o Validation Gate, THE Aplicativo SHALL permitir o início da etapa imediatamente seguinte.
7. WHERE a etapa for E1, THE Aplicativo SHALL limitar a entrega à tela operacional, paleta, banner manual, preview, registro manual, abstração da fonte, imagem, GPS, velocidade, horário, `confidence = 1.0`, `defectClass = pothole`, UUID, cooldown, JPEG, ocorrência em memória, testes das regras e acesso ao Diagnóstico.
8. WHERE a etapa for E1, THE Aplicativo SHALL operar sem fila persistente, API real, API key, YOLO ou TFLite.
9. WHERE a etapa for E2, THE Aplicativo SHALL adicionar fila persistente, imagem, recuperação, indicador, remoção consistente e testes sem integração real.
10. WHERE a etapa for E3, THE Aplicativo SHALL adicionar configurações, `BASE_URL`, API key, parâmetros, armazenamento seguro, indicação de chave configurada e validações.
11. WHERE a etapa for E4, THE Aplicativo SHALL adicionar envio multipart, autenticação `ApiKey`, idempotência, respostas, backoff, pausa, retomada, indicadores, testes e README.
12. WHERE o desenvolvimento de E4 anteceder a disponibilidade da API real, THE Aplicativo SHALL permitir fakes ou servidor simulado sem declarar o gate real aprovado.
13. WHEN E4 chegar ao Validation Gate real, THE Aplicativo SHALL usar URL de teste acessível e API key válida de dispositivo de teste.
14. WHEN E4 chegar ao Validation Gate real, THE Aplicativo SHALL apresentar evidência de recebimento pelo back-end.
15. WHERE a etapa for E5, THE Aplicativo SHALL adicionar TFLite treinado, `ultralytics_yolo`, carga, inferência, FPS, confiança configurável e candidatos YOLO.
16. WHERE a etapa for E5, THE Aplicativo SHALL substituir ou desativar a fonte manual sem reescrever fila, payload ou envio.
17. IF um TFLite treinado, disponível e compatível não existir, THEN THE Aplicativo SHALL adiar o início de E5.
18. WHEN E5 chegar ao Validation Gate, THE Aplicativo SHALL apresentar observações de desempenho, FPS e temperatura no Samsung Galaxy S25+.
19. WHEN um Validation Gate for apresentado, THE Aplicativo SHALL incluir resultados, testes aplicáveis, evidências e roteiro manual da etapa corrente.
20. WHERE um roteiro manual for apresentado, THE Aplicativo SHALL limitar as verificações às funcionalidades entregues até a etapa corrente.

## 8. Requisitos não funcionais

### RNF-01 — Separação arquitetural e fonte substituível

**Etapa:** E1, preservado e ampliado de E2 a E5.

**História de usuário:** Como desenvolvedor, quero separar fonte, domínio, interface e infraestrutura, para substituir o registro manual pelo YOLO sem reescrever regras compartilhadas.

#### Critérios de aceitação

1. WHERE o Aplicativo contiver regras de negócio, THE Aplicativo SHALL mantê-las fora dos widgets Flutter.
2. WHERE o modo manual estiver implementado, THE Aplicativo SHALL isolá-lo atrás de uma abstração substituível de Fonte de candidato de ocorrência.
3. WHERE E5 integrar YOLO, THE Aplicativo SHALL implementar YOLO como outra Fonte de candidato de ocorrência.
4. WHEN a fonte manual emitir um candidato, THE Aplicativo SHALL encaminhar imagem, GPS e horário ao pós-candidato compartilhado.
5. WHEN a fonte YOLO emitir um candidato, THE Aplicativo SHALL encaminhar seus dados ao mesmo pós-candidato compartilhado.
6. WHERE o pós-candidato for executado, THE Aplicativo SHALL compartilhar regras de cooldown, UUID, validação, persistência e envio conforme a etapa disponível.
7. WHERE widgets Flutter receberem ações do usuário, THE Aplicativo SHALL delegar a criação da ocorrência à camada de aplicação ou domínio.
8. WHERE widgets Flutter exibirem uma ocorrência, THE Aplicativo SHALL delegar a montagem do payload HTTP à camada de integração.
9. WHERE a ação manual for executada, THE Aplicativo SHALL mantê-la independente do cliente da API.
10. WHEN a fonte YOLO substituir a fonte manual, THE Aplicativo SHALL preservar o contrato da ocorrência.
11. WHERE fila, idempotência, HTTP ou segurança forem implementados, THE Aplicativo SHALL mantê-los independentes da fonte de candidato.
12. WHERE câmera, localização, persistência ou rede forem adicionadas, THE Aplicativo SHALL isolá-las atrás de interfaces adequadas.
13. WHERE uma abstração não atender a necessidade concreta, THE Aplicativo SHALL privilegiar a solução mais simples compatível com a substituição exigida.
14. WHERE E5 admitir confiança de modelo, THE Aplicativo SHALL limitar a alteração do pós-candidato e da fila à validação de `confidence` no intervalo [0, 1] e à migração não destrutiva do schema, preservando cooldown, preparação de imagem, UUID, payload e envio. *(Emenda E5.)*

### RNF-02 — Segurança de configurações e registros

**Etapa:** E3 e E4.

**História de usuário:** Como responsável pelo sistema, quero proteger credenciais e ambientes, para evitar exposição acidental de segredos.

#### Critérios de aceitação

1. WHERE código, configuração, documentação ou exemplo forem versionados, THE Aplicativo SHALL omitir API key real e URL real de produção.
2. WHERE logs, erros ou diagnósticos forem produzidos, THE Aplicativo SHALL omitir a API key completa.
3. WHERE logs, erros ou diagnósticos forem produzidos, THE Aplicativo SHALL omitir conteúdo de imagens rejeitadas e outros segredos.
4. WHEN uma API key for persistida, THE Aplicativo SHALL usar armazenamento seguro com proteção Android.
5. WHERE a API key for armazenada, THE Aplicativo SHALL impedir persistência em texto simples.
6. WHEN uma API key já salva for representada, THE Aplicativo SHALL indicar somente que a chave está configurada sem preencher a interface com o valor completo.
7. WHERE uma chave de teste for usada, THE Aplicativo SHALL usar credencial de dispositivo de teste em vez de credencial de produção.
8. WHERE exemplos forem necessários, THE Aplicativo SHALL usar valores fictícios.
9. WHERE HTTP local for necessário, THE Aplicativo SHALL restringi-lo à configuração de debug.
10. WHERE a variante release for produzida, THE Aplicativo SHALL exigir transporte HTTPS.
11. WHEN a configuração com API key salva for reaberta, THE Aplicativo SHALL preservar o segredo no armazenamento seguro sem preencher a interface com a chave completa.
12. WHEN uma API key for substituída, THE Aplicativo SHALL aceitar somente um novo valor completo validado no formato `prefixo.segredo`.
13. WHEN a remoção da API key for solicitada, THE Aplicativo SHALL exigir confirmação antes de apagar o segredo.
14. WHERE a API key for provisionada, THE Aplicativo SHALL receber o valor por colagem manual e omitir mecanismo de recuperação da chave completa no back-end.

### RNF-03 — Testabilidade automatizada

**Etapa:** E1 a E4.

**História de usuário:** Como desenvolvedor, quero testar regras críticas sem hardware ou serviços reais, para detectar regressões de forma reproduzível.

#### Critérios de aceitação

1. WHERE E1 estiver implementada, THE Aplicativo SHALL possuir testes executáveis com `flutter test` para cooldown por tempo ou distância.
2. WHERE E1 estiver implementada, THE Aplicativo SHALL possuir testes para `confidence = 1.0`, `defectClass = pothole`, UUID, horário e velocidade opcional.
3. WHERE E1 estiver implementada, THE Aplicativo SHALL possuir testes para qualidade JPEG `85`, proporção, máximo `1280x720`, limite `2 MiB` e redução somente de dimensões.
4. WHERE E1 estiver implementada, THE Aplicativo SHALL possuir testes para rejeição de dados obrigatórios inválidos e prevenção de capturas manuais concorrentes.
5. WHERE E2 estiver implementada, THE Aplicativo SHALL possuir testes para persistência, recuperação, reconstrução e remoção consistente de ocorrência e imagem.
6. WHERE E3 estiver implementada, THE Aplicativo SHALL possuir testes para validação de configurações, ausência de configuração e indicação de chave configurada sem preenchimento do valor completo.
7. WHERE E4 estiver implementada, THE Aplicativo SHALL possuir testes para montagem do multipart e autenticação `Authorization: ApiKey`.
8. WHERE E4 estiver implementada, THE Aplicativo SHALL possuir testes para classificar `200`, `201`, `400`, `401`, `403`, `409`, `413`, `415`, `5xx`, timeout, rede e códigos não especificados.
9. WHERE E4 estiver implementada, THE Aplicativo SHALL possuir testes para preservação da `idempotencyKey` e progressão do backoff até o teto.
10. WHERE dependências externas participarem dos testes, THE Aplicativo SHALL permitir fakes para câmera, fonte de candidato, GPS, armazenamento, rede e relógio.

### RNF-04 — Responsividade e desempenho operacional

**Etapa:** E0 preservada; E1 a E4 para modo manual; E5 para inferência.

**História de usuário:** Como operador, quero uma interface responsiva, para controlar e observar o aplicativo sem operações acumuladas.

#### Critérios de aceitação

1. WHILE o Diagnóstico E0 estiver em execução segundo o próprio ciclo de vida aprovado, THE Aplicativo SHALL preservar a responsividade validada de preview e indicadores.
2. WHILE o Modo operacional ativo estiver vigente, THE Aplicativo SHALL manter responsivos o preview, os indicadores e a navegação.
3. WHILE uma captura manual estiver em processamento, THE Aplicativo SHALL bloquear novos registros sem bloquear a atualização da interface.
4. WHILE a inferência E5 estiver ativa, THE Aplicativo SHALL manter a interface responsiva.
5. WHEN frames excederem o limite de inferência E5, THE Aplicativo SHALL descartá-los sem acúmulo desnecessário.
6. WHEN cada etapa for validada no Samsung Galaxy S25+, THE Aplicativo SHALL ser observado quanto à responsividade.
7. WHEN E5 for validada no Samsung Galaxy S25+, THE Aplicativo SHALL ser observado quanto a FPS e temperatura sem meta numérica não aprovada.

### RNF-05 — Confiabilidade e consistência da fila

**Etapa:** E2 e E4.

**História de usuário:** Como operador, quero consistência entre persistência e envio, para impedir perda ou remoção indevida de ocorrências.

#### Critérios de aceitação

1. WHEN uma ocorrência for elegível para envio, THE Aplicativo SHALL já tê-la persistido com todos os dados e imagem necessários.
2. WHILE uma tentativa estiver em andamento, THE Aplicativo SHALL preservar a ocorrência até resultado de sucesso ou descarte explícito.
3. IF o Aplicativo for interrompido antes da confirmação, THEN THE Aplicativo SHALL recuperar a ocorrência com a mesma `idempotencyKey`.
4. WHEN a remoção da fila for confirmada, THE Aplicativo SHALL manter consistente a contagem de pendências.
5. IF configuração de envio estiver ausente, THEN THE Aplicativo SHALL preservar a ocorrência sem chamar o endpoint.

### RNF-06 — Privacidade mínima das imagens

**Etapa:** E1 a E5.

**História de usuário:** Como responsável pelo MVP, quero limitar a retenção de imagens ao necessário, para evitar armazenamento de frames sem ocorrência válida.

#### Critérios de aceitação

1. WHEN um frame não gerar ocorrência válida, THE Aplicativo SHALL descartá-lo sem armazenamento persistente.
2. WHEN uma ocorrência sob responsabilidade da fila for removida por sucesso ou descarte explícito, THE Aplicativo SHALL remover a imagem local sem uso restante.
3. WHERE uma imagem permanecer armazenada após a transferência para E2, THE Aplicativo SHALL associá-la a uma ocorrência pendente ou pausada.
4. IF uma imagem não cumprir RF-10, THEN THE Aplicativo SHALL impedir seu enfileiramento e envio.
5. IF uma imagem for rejeitada, THEN THE Aplicativo SHALL omitir seu conteúdo de logs e erros.
6. WHERE E1 produzir uma imagem temporária, THE Aplicativo SHALL usar somente o armazenamento privado do Aplicativo pelo período necessário à validação ou apresentação da ocorrência em memória.
7. IF a preparação for rejeitada ou falhar antes de produzir ocorrência válida, THEN THE Aplicativo SHALL remover o arquivo temporário sem deixar imagem órfã.
8. WHEN a ocorrência em memória deixar de ser necessária, a sessão terminar ou ocorrer descarte em E1, THE Aplicativo SHALL remover a imagem temporária sem uso.
9. WHEN E2 persistir com sucesso uma ocorrência aceita e sua imagem, THE Fila persistente SHALL assumir formalmente a responsabilidade pelos arquivos associados.
10. WHILE a Fila persistente for responsável por uma imagem, THE Aplicativo SHALL removê-la somente após sucesso ou descarte explícito.
11. IF a limpeza de qualquer imagem falhar, THEN THE Aplicativo SHALL registrar erro técnico sem conteúdo da imagem, API key ou outro segredo.
12. WHERE uma captura produzir arquivo de imagem, THE Aplicativo SHALL omitir gravação automática na galeria do dispositivo.

### RNF-07 — Validação no dispositivo principal

**Etapa:** E0 a E5.

**História de usuário:** Como avaliador, quero validar cada incremento no Samsung Galaxy S25+, para confirmar o comportamento no dispositivo-alvo.

#### Critérios de aceitação

1. THE Aplicativo SHALL preservar o roteiro e as evidências históricas existentes da E0 aprovada sem alteração retroativa.
2. WHEN E1 chegar ao Validation Gate, THE Aplicativo SHALL possuir roteiro para preview, banner manual, botão, bloqueios, imagem, GPS, velocidade, horário, cooldown, UUID, JPEG e ocorrência em memória.
3. WHEN E2 chegar ao Validation Gate, THE Aplicativo SHALL acrescentar persistência, recuperação após reabertura, imagem e pendências ao roteiro.
4. WHEN E3 chegar ao Validation Gate, THE Aplicativo SHALL acrescentar configurações, armazenamento seguro, indicação de chave configurada sem preenchimento do valor completo, permissões e ausência de configuração ao roteiro.
5. WHEN E4 chegar ao Validation Gate de desenvolvimento, THE Aplicativo SHALL permitir validação automatizada com fakes ou servidor simulado.
6. WHEN E4 chegar ao Validation Gate real, THE Aplicativo SHALL possuir URL de teste acessível, API key válida de dispositivo de teste e evidência de recebimento no back-end.
7. WHEN E5 chegar ao Validation Gate, THE Aplicativo SHALL acrescentar modelo treinado, carga, inferência, FPS, confiança, substituição da fonte e observações de temperatura.
8. WHEN E5 chegar ao Validation Gate, THE Aplicativo SHALL demonstrar que fila, multipart e envio não foram reescritos para a nova fonte.
9. WHERE precisão, temperatura ou autonomia forem observadas, THE Aplicativo SHALL omitir avaliação contra metas numéricas não aprovadas.
10. IF a integração de uma etapa posterior causar regressão no comportamento validado do Diagnóstico, THEN THE Aplicativo SHALL incluir a correção e a verificação da regressão no Validation Gate da etapa responsável.

### RNF-08 — Identidade visual e clareza do modo operacional

**Etapa:** E1, preservado de E2 a E5.

**História de usuário:** Como operador, quero identidade visual legível e indicação inequívoca do modo, para distinguir registro manual de detecção automática.

#### Critérios de aceitação

1. WHERE a tela operacional for exibida, THE Aplicativo SHALL usar `#111827` como fundo principal.
2. WHERE cartões ou painéis forem exibidos, THE Aplicativo SHALL usar `#1F2937` como fundo desses elementos.
3. WHERE ação principal ou destaque for exibido, THE Aplicativo SHALL usar `#F59E0B`.
4. WHERE sucesso for comunicado, THE Aplicativo SHALL usar `#22C55E` em ícone, borda ou detalhe acompanhado de texto significativo.
5. WHERE erro for comunicado, THE Aplicativo SHALL usar `#EF4444` em ícone, borda ou detalhe acompanhado de texto significativo.
6. WHERE texto principal for exibido sobre fundo escuro, THE Aplicativo SHALL usar `#F9FAFB` com contraste legível.
7. WHILE o YOLO não estiver configurado, THE Aplicativo SHALL exibir permanentemente o banner “Modo manual — YOLO ainda não configurado” ou texto inequívoco equivalente.
8. WHEN o botão “Registrar buraco” for exibido, THE Aplicativo SHALL comunicar que o acionamento representa confirmação manual.
9. WHILE não existir modelo treinado em operação, THE Aplicativo SHALL omitir alegações de detecção automática.
10. WHEN estados de sucesso ou erro forem apresentados, THE Aplicativo SHALL comunicar o significado por texto ou ícone além da cor.
11. WHERE um botão usar `#F59E0B` como fundo, THE Aplicativo SHALL usar `#111827` no texto e nos ícones do botão.
12. WHERE `#22C55E` ou `#EF4444` for usado como fundo, THE Aplicativo SHALL selecionar a cor do texto ou ícone após verificação de contraste em vez de presumir texto branco.
13. WHERE qualquer combinação de foreground e background for exibida, THE Aplicativo SHALL manter contraste legível entre os elementos.
14. WHERE informação de estado for apresentada, THE Aplicativo SHALL combinar qualquer uso de cor com texto ou ícone significativo.

## 9. Matriz de rastreabilidade entre requisitos e etapas

`X` identifica introdução ou ampliação; `M` identifica manutenção; `A` identifica etapa concluída e aprovada.

| Requisito | Descrição resumida | E0 | E1 | E2 | E3 | E4 | E5 |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|
| RF-00 | E0 e Diagnóstico preservados | A | M | M | M | M | M |
| RF-01 | Plataforma Android | A | M | M | M | M | M |
| RF-02 | Carregamento futuro do modelo |  |  |  |  |  | X |
| RF-03 | Tela operacional e captura manual |  | X | M | M | M | X |
| RF-04 | Inferência e FPS |  |  |  |  |  | X |
| RF-05 | Indicadores operacionais |  | X | X | X | X | X |
| RF-06 | Localização e velocidade | A | X | M | X | M | M |
| RF-07 | Candidato e ocorrência |  | X | M | M | M | X |
| RF-08 | Horário e idempotência |  | X | M | M | M | M |
| RF-09 | Cooldown local |  | X | M | X | M | M |
| RF-10 | Preparação da imagem |  | X | M | M | M | M |
| RF-11 | Ocorrência em memória |  | X | M | M | M | M |
| RF-12 | Fila persistente |  |  | X | M | M | M |
| RF-13 | Configuração e credencial |  |  |  | X | X | M |
| RF-14 | Envio multipart |  |  |  |  | X | M |
| RF-15 | Sucesso e descarte HTTP |  |  |  |  | X | M |
| RF-16 | Pausa por `401`/`403` |  |  |  |  | X | M |
| RF-17 | Reenvio e backoff |  |  |  |  | X | M |
| RF-18 | Outros códigos HTTP |  |  |  |  | X | M |
| RF-19 | Tela de configurações |  |  |  | X | M | M |
| RF-20 | Permissões | A | X | M | X | M | M |
| RF-21 | Tela ligada e ciclo controlado |  | X | M | M | M | M |
| RF-22 | README operacional |  |  |  |  | X | M |
| RF-23 | Sequência e Validation Gates | A | X | X | X | X | X |
| RNF-01 | Fonte substituível e separação |  | X | M | M | M | X |
| RNF-02 | Segurança |  |  |  | X | X | M |
| RNF-03 | Testabilidade |  | X | X | X | X | M |
| RNF-04 | Responsividade | A | X | M | M | M | X |
| RNF-05 | Confiabilidade da fila |  |  | X | M | X | M |
| RNF-06 | Privacidade de imagens |  | X | X | M | M | M |
| RNF-07 | Validação no dispositivo | A | X | X | X | X | X |
| RNF-08 | Identidade e clareza operacional |  | X | M | M | M | X |

## 10. Rastreabilidade do contrato fixo da API

O diagnóstico HTTPS da E0 permanece separado deste contrato. O modo manual altera apenas a semântica de `confidence = 1.0` como confirmação humana e não adiciona campos.

| Elemento do contrato | Requisitos correspondentes |
|---|---|
| `BASE_URL` como origem sem caminho da ocorrência | RF-13, RF-19, RF-22 |
| `POST {BASE_URL}/api/v1/occurrences` | RF-13 |
| `multipart/form-data` | RF-14 |
| `Authorization: ApiKey {DEVICE_API_KEY}` | RF-13, RF-22, RNF-02, RNF-03 |
| Esquema `ApiKey`, um espaço e chave `prefixo.segredo` | RF-13 |
| Proibição de `Bearer`, `X-API-Key` e qualquer header alternativo de API key | RF-13 |
| Chave criada ou rotacionada na Administração Next.js, copiada manualmente e preferencialmente associada a dispositivo `mobile` | RF-13, RF-19 |
| Chave completa exibida uma única vez ao administrador, sem recuperação pelo Flutter ou pelo back-end | RF-13, RF-19 |
| Campo Flutter para colar e salvar `prefixo.segredo`, com validação mínima antes do salvamento | RF-13, RF-19 |
| Reabertura sem preenchimento da chave; substituição por valor completo e remoção confirmada | RF-13, RF-19, RNF-02 |
| Armazenamento seguro Android e segredo fora de código/logs | RF-13, RF-19, RNF-02 |
| `image` JPEG obrigatório | RF-10, RF-14 |
| `idempotencyKey` UUID estável | RF-08, RF-12, RF-14, RF-17, RNF-03, RNF-05 |
| `latitude` [-90, 90] e `longitude` [-180, 180] | RF-06, RF-07, RF-14 |
| `confidence` [0, 1], manual exatamente `1.0` | RF-07, RF-14, RF-19 |
| `defectClass = pothole` | RF-07, RF-14 |
| `speedKmh` opcional [0, 300] | RF-06, RF-07, RF-14 |
| `detectedAt` ISO 8601 com fuso | RF-08, RF-14 |
| `highway`, `km` e `source` omitidos | RF-07, RF-14 |
| Máximo `1280x720`, proporção preservada e qualidade JPEG `85` | RF-10, RNF-03 |
| Máximo `2 MiB` com redução somente de dimensões | RF-10, RNF-03 |
| `200` existente e `201` criada como sucesso | RF-15 |
| `400` para multipart, campos ou MIME inválidos no back-end atual | RF-15 |
| `401` para chave ausente, malformada ou inválida | RF-16 |
| `403` para dispositivo inativo | RF-16 |
| `409` protegido, mas não esperado na repetição idempotente normal | RF-15 |
| `413` acima de `2 MiB` | RF-15 |
| `415` protegido para compatibilidade futura | RF-15 |
| `5xx`, timeout e rede recuperáveis | RF-17 |
| Outros códigos com retenção e pausa | RF-18 |
| HTTPS em produção | RF-13, RNF-02 |
| HTTP local somente com `adb reverse` e manifesto debug | RF-13, RF-22, RNF-02 |

## 11. Decisões adiadas para a fase de design

1. Escolha justificada em E2 entre `sqflite` e Hive para persistência local.
2. Escolha justificada em E4 entre `dio` e `http` para multipart, timeout e classificação de respostas.
3. Solução de gerenciamento de estado mais simples adequada ao MVP.
4. Estrutura detalhada de pastas, classes, entidades, casos de uso e interfaces, sem impor nomes de classes nesta fase.
5. Estratégia exata de câmera, seleção de lente, orientação, rotação e obtenção do frame no acionamento.
6. Método exato de cálculo de distância do cooldown.
7. Estratégia exata para serializar e reconstruir a ocorrência persistida.
8. Valores configuráveis da progressão e do teto do backoff, preservando natureza exponencial e limitada.
9. Solução Android para retomada em segundo plano, preservando no mínimo fila e retomada posterior.
10. Fluxo visual exato de retomada manual após `401`, `403` ou código não especificado.
11. Biblioteca concreta de armazenamento seguro Android, desde que cumpra RF-13 e RNF-02.
12. Limites superiores para FPS, cooldown e distância, além das validações mínimas especificadas.
13. Nome e empacotamento do TFLite futuro, após existir modelo treinado e compatível.
14. Estratégia de concorrência, seleção de frames e integração do `ultralytics_yolo` em E5.
15. Metas quantitativas de precisão, temperatura, bateria ou autonomia, que dependerão de aprovação posterior.
16. URL de teste e API key de dispositivo de teste para o Validation Gate real de E4; nenhum valor será inventado ou versionado.
17. Estratégia exata de transferência de responsabilidade dos arquivos temporários de E1 para a fila persistente de E2, com ponto de confirmação, rollback de falhas e limpeza sem arquivos órfãos.
18. Comportamento visual do cooldown, incluindo a escolha entre botão temporariamente desabilitado com indicador ou toque destinado somente ao feedback, preservando feedback explícito e bloqueio de concorrência.

Nenhuma decisão de design poderá alterar o contrato fixo, reduzir a qualidade JPEG abaixo de `85`, adicionar `source`, apresentar o modo manual como detecção automática, acoplar widgets à persistência ou HTTP, ou exigir YOLO antes de E5.

## 12. Limite da fase atual

Esta fase revisa **somente** o arquivo `requirements.md`.

- A E0 permanece historicamente implementada, validada fisicamente no Samsung Galaxy S25+, aprovada e disponível pelo Diagnóstico.
- O comportamento e as responsabilidades aprovados do Diagnóstico permanecem preservados; as evidências históricas existentes não podem ser alteradas retroativamente.
- A integração futura poderá mover ou refatorar minimamente arquivos da E0 para incorporá-los à navegação, sem exigir estrutura literal de arquivos ou código e sem alterar câmera, GPS, HTTPS diagnóstico, mensagens, permissões ou ciclo de vida aprovados.
- O cliente HTTP diagnóstico permanecerá separado do cliente de ocorrências, e eventual regressão de integração será corrigida na etapa que a introduzir.
- E1 não foi iniciada por esta revisão.
- Nenhum código, teste, evidência, configuração, dependência ou outro arquivo é criado ou alterado nesta fase.
- `design.md` e `tasks.md` não são criados nem alterados nesta fase.
- A próxima ação depende de revisão e aprovação explícita destes requisitos.
- A implementação futura deverá iniciar por E1 e parar em seu Validation Gate.
- E2, E3, E4 e E5 dependerão da aprovação explícita da etapa imediatamente anterior.
- E5 permanecerá adiada até existir TFLite treinado, disponível e compatível.

O contrato da API permanece fixo quanto a endpoint, multipart, campos, imagem, idempotência e políticas de fila. A autenticação normativa é `Authorization: ApiKey {DEVICE_API_KEY}`; o esquema `Bearer`, o header `X-API-Key` e qualquer header alternativo de API key não pertencem ao contrato. Nenhuma `BASE_URL` real ou API key foi definida nesta revisão.
