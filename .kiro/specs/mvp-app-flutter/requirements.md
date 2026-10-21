# Especificação de Requisitos — Aplicativo Mobile para Geolocalização de Defeitos em Pavimento Viário

## 1. Introdução

Este documento especifica os requisitos do MVP do aplicativo mobile do Trabalho de Conclusão de Curso **“Dispositivo Veicular para Geolocalização de Defeitos em Pavimento Viário”**. O aplicativo funcionará como uma dashcam inteligente: um celular fixado no para-brisa, com a câmera traseira apontada para a pista, realizará detecção local de buracos, associará cada ocorrência válida à posição geográfica e ao horário e enviará os dados a uma API REST.

O MVP tem como plataforma-alvo exclusivamente Android e será validado principalmente em um Samsung Galaxy S25+. A implementação futura utilizará Flutter/Dart, o plugin `ultralytics_yolo`, um modelo TFLite empacotado nos assets e o plugin `geolocator` para localização. Antes dessas integrações, a etapa E0 validará somente a infraestrutura Android básica, sem modelo, inferência ou ocorrência.

Esta especificação organiza a entrega nas etapas sequenciais E0 a E5. Cada etapa deverá terminar em um Validation Gate e dependerá de aprovação explícita antes do início da etapa seguinte.

## 2. Objetivo

Definir, de forma objetiva, testável e rastreável, o comportamento esperado do aplicativo para:

- validar inicialmente, em E0, a infraestrutura Flutter Android, câmera traseira, localização e conectividade sem antecipar detecção ou integração de ocorrências;
- capturar imagens da câmera traseira;
- detectar localmente a classe `pothole` em tempo real;
- criar ocorrências com imagem, localização, horário e dados da detecção;
- aplicar deduplicação local por cooldown;
- persistir ocorrências antes do envio;
- enviar ocorrências conforme o contrato fixo da API;
- preservar e reenviar ocorrências após falhas recuperáveis;
- oferecer informações operacionais e configurações mínimas;
- proteger a API key e evitar o versionamento ou a exposição de segredos;
- permitir que regras de negócio sejam reaproveitadas por um futuro cliente de captura embarcado.

## 3. Escopo do MVP

O MVP compreende:

1. Etapa E0 restrita a estrutura inicial Flutter Android, build, instalação, abertura e smoke test de câmera traseira, localização e conectividade no Samsung Galaxy S25+, sem funcionalidades de detecção ou ocorrência.
2. Aplicativo Android em Flutter/Dart.
3. Preview da câmera traseira e controle explícito de início e parada da captura.
4. Inferência local e contínua com YOLO por meio de `ultralytics_yolo` e modelo TFLite incluído nos assets, a partir de E1.
5. Detecção exclusiva de buracos representados pela classe `pothole`.
6. Associação da detecção válida à localização GPS, velocidade válida quando disponível, confiança, horário e UUID de idempotência.
7. Preparação de imagem JPEG dentro dos limites do contrato, sempre com qualidade `85` e redução adicional somente de dimensões.
8. Deduplicação local baseada somente em cooldown por tempo ou distância.
9. Fila local persistente, recuperação após reabertura e indicador de pendências.
10. Envio automático em `multipart/form-data` para o endpoint especificado, com API key do dispositivo.
11. Mecanismo mínimo de armazenamento seguro da API key em E4 e interface completa de configuração em E5.
12. Tratamento dos códigos HTTP, falhas de rede, timeouts, backoff e pausa de autenticação.
13. Tela principal com indicadores operacionais e tela simples de configurações.
14. Tratamento de permissões de câmera e localização precisa.
15. Manutenção da tela ligada durante a captura.
16. Testes automatizados das regras de domínio, persistência e classificação de envio definidos nesta especificação.
17. README final de instalação, build, execução e configuração.

## 4. Fora do escopo

Não fazem parte do MVP:

- login ou cadastro de usuário;
- mapa;
- histórico de ocorrências para consulta do usuário;
- revisão manual de detecções;
- suporte a iOS;
- detecção de classes diferentes de `pothole`;
- preenchimento de `highway` ou `km`;
- upload direto para serviço de armazenamento;
- atualização do modelo pela rede;
- telemetria;
- painel web;
- deduplicação avançada entre passagens distintas pelo mesmo buraco;
- definição ou alteração de endpoints do back-end;
- metas numéricas não fornecidas para precisão do modelo, temperatura, consumo de bateria ou autonomia.

## 5. Glossário

| Termo | Definição |
|---|---|
| Aplicativo | Aplicativo mobile Android especificado neste documento. |
| Smoke test E0 | Validação restrita da infraestrutura Flutter Android, câmera traseira, localização e conectividade, sem detecção, ocorrência ou integração com o contrato de ocorrências. |
| Captura | Período entre o acionamento de “Iniciar” e o encerramento controlado por “Parar” ou por impedimento operacional. |
| Detecção válida | Detecção da classe `pothole` cuja confiança é maior ou igual ao limiar configurado. |
| Ocorrência | Registro de um buraco aceito pelo cooldown e associado a uma imagem válida, localização válida, horário, confiança e chave de idempotência. |
| Fila persistente | Armazenamento local das ocorrências que aguardam envio ou decisão de tratamento. |
| Cooldown | Regra local que impede a criação de ocorrências muito próximas no tempo e no espaço. |
| `idempotencyKey` | UUID gerado uma única vez no aplicativo para uma ocorrência e reutilizado sem alteração em todas as suas tentativas de envio. |
| Validation Gate | Ponto obrigatório de interrupção ao final de cada etapa, no qual resultados e validações são apresentados para aprovação explícita. |
| Backoff exponencial | Aumento progressivo do intervalo entre novas tentativas, limitado por um teto. |
| Falha recuperável | Falha de rede, timeout ou resposta HTTP `5xx`, para a qual a ocorrência deve permanecer na fila e ser tentada novamente. |
| GPS disponível | Existência de uma posição fornecida pelo serviço de localização enquanto o aplicativo tem permissão de localização precisa. |
| Localização válida | Posição disponível para a detecção, com latitude entre -90 e 90 e longitude entre -180 e 180. |
| FPS de inferência | Quantidade de frames efetivamente submetidos à inferência por segundo, distinta da taxa de frames do preview. |
| Segredo | API key, URL real de produção ou outro dado sensível que não pode ser versionado ou exposto. |

## 6. Suposições adotadas

1. O arquivo será denominado `requirements.md` e pertence à especificação `mvp-app-flutter`.
2. O nome definitivo do arquivo TFLite será decidido posteriormente; o modelo será empacotado nos assets, sem download em tempo de execução.
3. A câmera traseira padrão disponível no aparelho será utilizada. A seleção de lente e os detalhes de resolução do fluxo serão decididos no design.
4. Uma localização é considerada válida quando há permissão de localização precisa, uma posição está disponível para a detecção e suas coordenadas respeitam os intervalos do contrato. Não se adota nesta fase um limite numérico de precisão ou idade da posição que não tenha sido fornecido.
5. A precisão reportada pelo provedor de localização será exibida para avaliação do operador, mas não bloqueará por si só a ocorrência, pois não foi definido um limite máximo aceitável.
6. A velocidade será omitida quando ausente, negativa, superior a 300 km/h ou não puder ser validada.
7. A primeira ocorrência válida de uma captura não será bloqueada por cooldown por não existir ocorrência anterior de referência.
8. O deslocamento do cooldown será avaliado entre a localização da detecção atual e a localização da última ocorrência criada. O método matemático exato será definido no design.
9. Frames excedentes ao limite de inferência poderão ser descartados sem enfileiramento para processamento posterior.
10. Todas as tentativas de preparação da imagem usarão JPEG com qualidade `85`. Quando necessário para cumprir `2 MiB`, somente as dimensões serão reduzidas progressivamente, preservando proporção e o máximo de `1280x720`; a qualidade nunca será reduzida. Uma ocorrência cuja imagem não possa atender a todas essas regras não será aceita, enfileirada nem enviada, e a falha será registrada tecnicamente sem API key, imagem ou outro segredo.
11. Em códigos HTTP não especificados no contrato, será aplicada uma política conservadora: a ocorrência permanecerá na fila, o envio automático será pausado para evitar descarte ou repetição indefinida, um erro técnico sem segredo será registrado e o usuário será avisado para corrigir a configuração ou solicitar nova tentativa manual. Essa suposição não altera o tratamento específico dos códigos definidos.
12. Após `401` ou `403`, a retomada poderá ocorrer quando a configuração relevante for salva novamente ou quando o usuário solicitar nova tentativa; a escolha exata de interação será detalhada no design.
13. O envio em segundo plano significa, no mínimo, persistir a fila e retomar as tentativas quando o Android permitir que o aplicativo volte a executá-las. A estratégia Android exata será escolhida no design.
14. O contador de buracos da sessão representa ocorrências efetivamente criadas após confiança, localização, imagem e cooldown serem aceitos, e será reiniciado em uma nova execução do aplicativo. O indicador de detecções brutas poderá existir na etapa E1 para apoiar o spike.
15. Os valores padrão — confiança `0.5`, limite de `5 FPS`, cooldown de `5 segundos` e distância mínima de `15 metros` — serão usados antes de haver configuração salva.
16. `BASE_URL` será configurável e não conterá por padrão uma URL real de produção.
17. O HTTP diagnóstico de E0 será dirigido exclusivamente a servidor simulado ou ambiente de teste, não representará ocorrência, não usará o endpoint de ocorrências e não usará API key real nem credencial de produção.
18. Em E4, a credencial de teste será fornecida e salva por mecanismo mínimo definido no design, sempre com proteção Android e sem código, arquivo versionado, armazenamento em texto simples, logs ou exposição integral em erros. E5 reutilizará esse armazenamento seguro em sua interface completa sem reduzir a proteção.

## 7. Requisitos funcionais

### RF-00 — Smoke test da infraestrutura Android

**Etapa:** E0.

**História de usuário:** Como pesquisador, quero validar a infraestrutura Android básica no Samsung Galaxy S25+, para reduzir riscos de build, permissões, hardware e conectividade antes de iniciar a detecção de buracos.

**Critérios de aceitação:**

1. WHEN a etapa E0 for executada, THE mobile application SHALL conter somente a estrutura inicial de um projeto Flutter com suporte Android necessária ao smoke test.
2. WHEN o projeto E0 for preparado, THE mobile application SHALL permitir build, instalação, abertura e execução controlada no Samsung Galaxy S25+.
3. WHEN a permissão básica de câmera for concedida, THE mobile application SHALL exibir um preview básico da câmera traseira.
4. WHEN o acesso básico à câmera for necessário e ainda não estiver concedido, THE mobile application SHALL solicitar a permissão de câmera e apresentar mensagem clara se a câmera permanecer indisponível.
5. WHEN a localização for necessária ao diagnóstico e ainda não estiver concedida, THE mobile application SHALL solicitar localização precisa e apresentar mensagem clara se o serviço, a permissão ou a posição permanecer indisponível.
6. WHEN uma posição estiver disponível no smoke test, THE mobile application SHALL exibir latitude, longitude, precisão reportada e velocidade quando fornecida pelo provedor.
7. WHEN a conectividade for diagnosticada, THE mobile application SHALL indicar seu estado e permitir uma requisição HTTP diagnóstica exclusivamente para servidor simulado ou ambiente exclusivo de teste.
8. WHERE o HTTP diagnóstico de E0 for executado, THE mobile application SHALL não representá-lo como ocorrência, SHALL não usar `POST {BASE_URL}/api/v1/occurrences`, SHALL não usar ambiente de produção e SHALL apresentar mensagens claras para indisponibilidade de rede ou do destino de teste.
9. WHERE E0 estiver em execução, THE mobile application SHALL não incluir `ultralytics_yolo`, modelo TFLite, inferência, FPS de inferência, detecção de buraco real, simulado ou fake, limiar de confiança, cooldown, ocorrência, UUID, compressão definitiva de imagem, fila, multipart, endpoint real de ocorrências, API key real ou credencial de produção.
10. WHERE uma funcionalidade pertencer a E1, E2, E3, E4 ou E5 e não for expressamente necessária ao smoke test E0, THE mobile application SHALL não antecipá-la em E0.
11. WHEN E0 for concluída, THE mobile application SHALL ser acompanhada de roteiro manual e evidências para build, instalação, abertura, preview da câmera traseira, permissões básicas, GPS, precisão, velocidade quando disponível, conectividade, HTTP diagnóstico e mensagens de indisponibilidade no Samsung Galaxy S25+.
12. WHEN o Validation Gate de E0 for apresentado, THE mobile application SHALL interromper o avanço até aprovação explícita.

### RF-01 — Plataforma e execução Android

**Etapa:** E0, mantido de E1 a E5.

**História de usuário:** Como pesquisador, quero executar o aplicativo em um aparelho Android, principalmente no Samsung Galaxy S25+, para validar o uso do celular como cliente veicular de captura.

**Critérios de aceitação:**

1. WHERE o aplicativo for distribuído como MVP, THE mobile application SHALL oferecer suporte exclusivamente à plataforma Android.
2. WHEN o aplicativo for instalado em um Samsung Galaxy S25+ compatível, THE mobile application SHALL permitir a execução das funcionalidades entregues na etapa corrente.
3. WHERE uma funcionalidade depender de recurso específico do dispositivo, THE mobile application SHALL apresentar falha controlada em vez de encerrar inesperadamente.

### RF-02 — Carregamento local do modelo

**Etapa:** E1.

**História de usuário:** Como operador, quero saber se o modelo de detecção foi carregado, para iniciar a captura somente quando a inferência estiver disponível.

**Critérios de aceitação:**

1. WHEN o aplicativo preparar a detecção, THE mobile application SHALL carregar localmente o modelo TFLite incluído nos assets.
2. WHILE o carregamento estiver em andamento, THE mobile application SHALL indicar que o modelo ainda não está disponível.
3. WHEN o carregamento terminar com sucesso, THE mobile application SHALL indicar o estado “modelo carregado”.
4. IF o modelo não puder ser carregado, THE mobile application SHALL impedir o início da inferência e apresentar uma mensagem de erro sem encerrar inesperadamente.
5. WHERE a detecção for executada, THE mobile application SHALL utilizar o plugin `ultralytics_yolo` isolado atrás de uma interface da aplicação.

### RF-03 — Preview, permissões básicas e controle da câmera traseira

**Etapa:** E0 para preview e permissão básica; E1 para câmera integrada à inferência e controles; E5 para experiência completa de permissões.

**História de usuário:** Como operador, quero visualizar a pista e controlar a captura, para confirmar o enquadramento e decidir quando detectar buracos.

**Critérios de aceitação:**

1. WHEN a câmera estiver autorizada e disponível em E0, THE mobile application SHALL exibir o preview básico da câmera traseira sem iniciar inferência.
2. IF a permissão de câmera não estiver concedida em E0, THE mobile application SHALL solicitá-la de forma básica e apresentar mensagem clara se o preview não puder ser exibido.
3. WHEN a câmera estiver disponível e a captura puder ser iniciada a partir de E1, THE mobile application SHALL exibir o preview da câmera traseira integrado ao fluxo de captura.
4. WHEN o operador tocar em “Iniciar” com modelo e câmera disponíveis a partir de E1, THE mobile application SHALL iniciar a captura e a inferência contínua.
5. WHILE a captura estiver ativa, THE mobile application SHALL apresentar “Parar” ou um estado de controle equivalente no lugar de “Iniciar”.
6. WHEN o operador tocar em “Parar”, THE mobile application SHALL encerrar de forma controlada a captura e a submissão de novos frames à inferência.
7. IF a permissão de câmera não estiver concedida, THE mobile application SHALL impedir o início da captura.
8. WHERE E5 estiver entregue, THE mobile application SHALL oferecer a experiência completa de tratamento de permissões definida em RF-20 sem reduzir os comportamentos anteriores.

### RF-04 — Inferência contínua e limitada

**Etapa:** E1; configuração pelo usuário em E5.

**História de usuário:** Como pesquisador, quero realizar inferência contínua com taxa limitada, para detectar buracos em tempo real sem processar desnecessariamente todos os frames.

**Critérios de aceitação:**

1. WHILE a captura estiver ativa e o modelo estiver carregado, THE mobile application SHALL executar localmente inferências contínuas sobre frames da câmera.
2. WHERE não existir configuração salva, THE mobile application SHALL limitar a inferência ao valor padrão de `5 FPS`.
3. WHEN frames forem recebidos acima do limite de inferência vigente, THE mobile application SHALL poder descartá-los sem atrasar a fila de processamento.
4. WHEN um frame não contiver detecção válida, THE mobile application SHALL descartá-lo imediatamente sem armazená-lo.
5. WHILE a inferência estiver ativa, THE mobile application SHALL atualizar o FPS atual ou recente da inferência na tela principal.
6. WHERE o detector produzir classes, THE mobile application SHALL considerar para criação de ocorrência somente a classe `pothole`.

### RF-05 — Indicadores da tela principal

**Etapa:** E0 para diagnóstico de câmera, GPS, precisão, velocidade e rede; E1 para modelo, FPS e detecções; E2 para ocorrências da sessão; E3 para pendências; E4 para estado dos envios.

**História de usuário:** Como operador, quero observar o estado do sistema em uma única tela, para verificar se captura, detecção, GPS e envio estão funcionando.

**Critérios de aceitação:**

1. WHILE a tela de E0 estiver visível, THE mobile application SHALL apresentar somente os indicadores diagnósticos pertinentes de câmera, disponibilidade de GPS, latitude, longitude, precisão, velocidade quando disponível, conectividade e resultado do HTTP diagnóstico.
2. WHILE a tela principal estiver visível a partir de E1, THE mobile application SHALL apresentar o preview, o controle “Iniciar” ou “Parar” e o indicador de carregamento do modelo.
3. WHILE a inferência estiver ativa, THE mobile application SHALL apresentar o FPS atual ou recente e informações de detecção disponíveis na etapa.
4. WHERE a funcionalidade de GPS estiver entregue para associação de ocorrências, THE mobile application SHALL apresentar a disponibilidade e a precisão reportada da localização.
5. WHERE a criação de ocorrências estiver entregue, THE mobile application SHALL apresentar a quantidade de buracos registrados na sessão atual.
6. WHERE a fila persistente estiver entregue, THE mobile application SHALL apresentar a quantidade persistida de ocorrências pendentes.
7. WHERE a integração com a API estiver entregue, THE mobile application SHALL apresentar o estado dos envios, inclusive quando estiver pausado por `401`, `403` ou código não especificado.

### RF-06 — Diagnóstico, obtenção e validação da localização

**Etapa:** E0 para diagnóstico sem ocorrência; E2 para associação à ocorrência; E5 para tratamento completo de permissões.

**História de usuário:** Como pesquisador, quero validar o GPS e associar coordenadas válidas à detecção quando essa funcionalidade estiver entregue, para geolocalizar o defeito viário.

**Critérios de aceitação:**

1. WHILE o diagnóstico E0 estiver ativo e a permissão de localização precisa estiver concedida, THE mobile application SHALL exibir disponibilidade, latitude, longitude, precisão reportada e velocidade quando disponível, sem criar ocorrência.
2. IF localização, permissão precisa ou serviço de GPS não estiver disponível em E0, THE mobile application SHALL apresentar mensagem clara de indisponibilidade sem antecipar regras de ocorrência.
3. WHILE a captura estiver ativa a partir de E2 e a permissão de localização precisa estiver concedida, THE mobile application SHALL obter atualizações de localização utilizáveis pelas detecções.
4. WHEN uma detecção elegível ocorrer, THE mobile application SHALL associar a ela uma posição disponível com latitude entre -90 e 90 e longitude entre -180 e 180.
5. IF nenhuma localização válida estiver disponível, THE mobile application SHALL deixar de criar a ocorrência e SHALL informar na tela a indisponibilidade do GPS.
6. WHEN o provedor disponibilizar a precisão da localização, THE mobile application SHALL exibi-la na tela principal.
7. IF o GPS fornecer velocidade entre 0 e 300 km/h, inclusive, THE mobile application SHALL associá-la à ocorrência.
8. IF a velocidade estiver ausente ou fora do intervalo de 0 a 300 km/h, THE mobile application SHALL omitir `speedKmh` da ocorrência.
9. WHERE E5 estiver entregue, THE mobile application SHALL aplicar o tratamento completo de permissões de localização definido em RF-20.

### RF-07 — Elegibilidade da detecção e criação da ocorrência

**Etapa:** E2.

**História de usuário:** Como pesquisador, quero transformar somente detecções elegíveis em ocorrências completas, para preservar dados válidos para armazenamento e envio.

**Critérios de aceitação:**

1. WHEN o modelo detectar `pothole` com confiança maior ou igual ao limiar vigente, houver localização válida e o cooldown permitir, THE mobile application SHALL iniciar a criação de uma ocorrência usando o frame associado à detecção.
2. WHERE não existir configuração salva, THE mobile application SHALL usar o limiar padrão de confiança `0.5`.
3. IF a confiança for menor que o limiar vigente, THE mobile application SHALL descartar a detecção sem criar ocorrência.
4. WHEN uma ocorrência for criada, THE mobile application SHALL incluir latitude, longitude, confiança entre 0 e 1, classe fixa `pothole`, horário da detecção e um UUID de idempotência.
5. WHEN houver velocidade GPS válida, THE mobile application SHALL incluir `speedKmh` na ocorrência.
6. WHERE o MVP criar uma ocorrência, THE mobile application SHALL deixar `highway` e `km` sem preenchimento.
7. WHEN uma ocorrência for aceita, THE mobile application SHALL incrementar a quantidade de buracos registrados na sessão atual.

### RF-08 — Data, hora e idempotência da ocorrência

**Etapa:** E2; preservação em E3 e E4.

**História de usuário:** Como integrador, quero que cada ocorrência tenha horário inequívoco e chave estável, para processar reenvios sem duplicar o mesmo registro.

**Critérios de aceitação:**

1. WHEN uma ocorrência for criada, THE mobile application SHALL registrar `detectedAt` em ISO 8601 com informação de fuso horário.
2. WHEN uma ocorrência for criada, THE mobile application SHALL gerar uma única `idempotencyKey` no formato UUID.
3. WHILE a ocorrência existir em memória, na fila ou em processo de reenvio, THE mobile application SHALL preservar sem alteração a mesma `idempotencyKey`.
4. IF uma tentativa de envio falhar, THE mobile application SHALL reutilizar a `idempotencyKey` original na tentativa seguinte.
5. WHEN o horário for associado à ocorrência, THE mobile application SHALL representar o instante da detecção que originou a ocorrência, e não o instante de envio.

### RF-09 — Cooldown e deduplicação local

**Etapa:** E2; configuração pelo usuário em E5.

**História de usuário:** Como pesquisador, quero limitar ocorrências próximas por tempo e distância, para reduzir duplicações locais durante a mesma passagem.

**Critérios de aceitação:**

1. WHEN a primeira detecção elegível não possuir ocorrência anterior de referência, THE mobile application SHALL permitir a criação da ocorrência.
2. WHEN já existir uma ocorrência anterior, THE mobile application SHALL permitir uma nova ocorrência se tiver transcorrido pelo menos o tempo de cooldown vigente desde a ocorrência anterior.
3. WHEN já existir uma ocorrência anterior, THE mobile application SHALL permitir uma nova ocorrência se o deslocamento desde a localização da ocorrência anterior for pelo menos a distância mínima vigente.
4. WHILE o tempo transcorrido for menor que o cooldown vigente e o deslocamento for menor que a distância mínima vigente, THE mobile application SHALL ignorar novas detecções elegíveis.
5. WHERE não existir configuração salva, THE mobile application SHALL usar `5 segundos` como cooldown e `15 metros` como distância mínima.
6. WHERE o MVP aplicar deduplicação, THE mobile application SHALL utilizar apenas essa regra local de cooldown, sem presumir deduplicação de buracos no back-end.

### RF-10 — Preparação e validação da imagem

**Etapa:** E2.

**História de usuário:** Como integrador, quero que a imagem da ocorrência respeite os limites do contrato antes de ser aceita, para evitar registros impossíveis de enviar.

**Critérios de aceitação:**

1. WHEN uma detecção passar pelos critérios de confiança, localização e cooldown, THE mobile application SHALL converter o frame associado em arquivo JPEG com qualidade `85` antes de aceitar a ocorrência.
2. WHEN a imagem exceder 1280 pixels de largura ou 720 pixels de altura, THE mobile application SHALL redimensioná-la para caber em `1280x720`, preservando a proporção original.
3. WHEN qualquer tentativa de compressão JPEG for executada, THE mobile application SHALL utilizar obrigatoriamente qualidade `85`.
4. IF o JPEG resultante exceder `2 MiB`, THE mobile application SHALL reduzir progressivamente apenas as dimensões e gerar novas tentativas em JPEG com qualidade `85`, preservando a proporção original e o limite máximo de `1280x720`.
5. WHERE a imagem for preparada, THE mobile application SHALL proibir qualquer redução ou outra alteração da qualidade JPEG para valor diferente do obrigatório `85` como estratégia para cumprir o limite de tamanho.
6. WHEN a ocorrência for aceita, THE mobile application SHALL garantir que o arquivo final seja JPEG com qualidade `85`, tenha no máximo `1280x720`, preserve a proporção original e não ultrapasse `2 MiB`.
7. IF não for possível produzir uma imagem de até `2 MiB` por redução exclusiva de dimensões mantendo JPEG, qualidade `85`, proporção original e máximo `1280x720`, THE mobile application SHALL rejeitar a ocorrência, não enfileirá-la, não enviá-la e registrar erro técnico sem API key, conteúdo da imagem ou outro segredo.

### RF-11 — Criação em memória antes da persistência

**Etapa:** E2.

**História de usuário:** Como desenvolvedor, quero validar a criação completa de uma ocorrência em memória antes de introduzir persistência e rede, para comprovar isoladamente as regras do domínio.

**Critérios de aceitação:**

1. WHEN todos os dados obrigatórios e a imagem forem válidos, THE mobile application SHALL criar em memória uma ocorrência compatível com o contrato fixo.
2. WHERE a etapa E2 estiver em execução, THE mobile application SHALL não depender de fila persistente ou integração real com a API.
3. IF qualquer dado obrigatório estiver ausente ou inválido, THE mobile application SHALL não considerar a ocorrência pronta para persistência ou envio futuro.

### RF-12 — Persistência local da fila

**Etapa:** E3.

**História de usuário:** Como operador, quero que ocorrências sejam preservadas localmente antes do envio, para não perder dados quando não houver conexão ou o aplicativo for fechado.

**Critérios de aceitação:**

1. WHEN uma ocorrência válida for produzida, THE mobile application SHALL gravá-la integralmente na fila local antes de qualquer primeira tentativa de envio.
2. WHEN o aplicativo for fechado e posteriormente reaberto, THE mobile application SHALL recuperar as ocorrências que permaneciam na fila.
3. WHILE uma ocorrência aguardar envio ou estiver sujeita a falha recuperável, THE mobile application SHALL preservar os dados necessários para reconstruir exatamente o mesmo envio.
4. WHEN a fila for alterada ou recuperada, THE mobile application SHALL atualizar o indicador de pendências para refletir a quantidade persistida.
5. WHERE a etapa E3 estiver em execução, THE mobile application SHALL não realizar integração real com a API.
6. IF a persistência de uma nova ocorrência falhar, THE mobile application SHALL não iniciar seu envio e SHALL registrar erro técnico sem expor segredo.

### RF-13 — Configuração do destino, autenticação e armazenamento seguro da API

**Etapa:** E4 para consumo e mecanismo mínimo de armazenamento seguro; E5 para tela completa de configuração.

**História de usuário:** Como operador autorizado, quero configurar o destino e proteger a credencial do dispositivo, para enviar ocorrências à API correta com autenticação sem expor segredos.

**Critérios de aceitação:**

1. WHERE a integração com a API estiver ativa, THE mobile application SHALL usar uma URL base configurada, sem embutir URL real de produção no código versionado.
2. WHEN enviar uma ocorrência, THE mobile application SHALL usar exatamente o endpoint `POST {BASE_URL}/api/v1/occurrences`.
3. WHEN enviar uma ocorrência, THE mobile application SHALL incluir exatamente o header `X-API-Key: {DEVICE_API_KEY}`.
4. IF a URL base ou a API key necessária não estiver configurada, THE mobile application SHALL manter a ocorrência na fila, não realizar a requisição e informar que a configuração é necessária.
5. WHERE houver logs ou mensagens de erro, THE mobile application SHALL não registrar nem exibir a API key integralmente.
6. WHEN E4 consumir uma API key de teste, THE mobile application SHALL obtê-la de mecanismo mínimo de armazenamento seguro com proteção fornecida pelo Android.
7. WHERE a credencial de teste de E4 for fornecida ou salva, THE mobile application SHALL não mantê-la em código, arquivo versionado, armazenamento em texto simples, logs ou integralmente em erros, e SHALL nunca usar credencial de produção para essa finalidade.
8. WHERE E4 estiver em execução, THE mobile application SHALL permitir que o mecanismo de fornecimento ou salvamento da credencial de teste seja o mínimo definido no design, sem antecipar a tela completa de configurações de E5.
9. WHEN E5 for entregue, THE mobile application SHALL reutilizar o armazenamento seguro introduzido em E4 e permitir cadastrar, alterar, indicar a existência da configuração e mascarar a API key sem reduzir sua proteção.

### RF-14 — Montagem do envio multipart

**Etapa:** E4.

**História de usuário:** Como integrador, quero enviar cada ocorrência exatamente no contrato definido, para garantir compatibilidade com a API.

**Critérios de aceitação:**

1. WHEN uma ocorrência pendente for enviada, THE mobile application SHALL usar `multipart/form-data`.
2. WHEN montar o multipart, THE mobile application SHALL incluir `image` como arquivo JPEG obrigatório.
3. WHEN montar o multipart, THE mobile application SHALL incluir `idempotencyKey` como UUID obrigatório e igual ao valor persistido da ocorrência.
4. WHEN montar o multipart, THE mobile application SHALL incluir `latitude` como número obrigatório entre -90 e 90.
5. WHEN montar o multipart, THE mobile application SHALL incluir `longitude` como número obrigatório entre -180 e 180.
6. WHEN montar o multipart, THE mobile application SHALL incluir `confidence` como número obrigatório entre 0 e 1.
7. WHEN montar o multipart, THE mobile application SHALL incluir `defectClass` como texto obrigatório com o valor exato `pothole`.
8. IF houver velocidade válida, THE mobile application SHALL incluir `speedKmh` como número entre 0 e 300; caso contrário, SHALL omitir o campo.
9. WHEN montar o multipart, THE mobile application SHALL incluir `detectedAt` como data e hora ISO 8601 com informação de fuso horário.
10. WHERE o envio pertencer ao MVP, THE mobile application SHALL não preencher os campos opcionais `highway` e `km`.
11. WHEN reconstruir qualquer tentativa da mesma ocorrência, THE mobile application SHALL usar os mesmos dados persistidos, inclusive imagem e `idempotencyKey`.

### RF-15 — Processamento de sucesso e descarte

**Etapa:** E4.

**História de usuário:** Como operador, quero remover da fila ocorrências concluídas ou rejeitadas de forma definitiva conforme o contrato, para manter a fila consistente.

**Critérios de aceitação:**

1. WHEN a API responder `201`, THE mobile application SHALL considerar a ocorrência criada com sucesso e removê-la da fila.
2. WHEN a API responder `200`, THE mobile application SHALL considerar a ocorrência já existente devido à idempotência e removê-la da fila.
3. WHEN a API responder `400`, THE mobile application SHALL descartar a ocorrência da fila e registrar erro técnico de violação de contrato sem expor segredo.
4. WHEN a API responder `409`, THE mobile application SHALL descartar a ocorrência da fila e registrar erro de conflito da chave de idempotência.
5. WHEN a API responder `413`, THE mobile application SHALL descartar a ocorrência da fila e registrar erro de imagem acima do limite aceito.
6. WHEN a API responder `415`, THE mobile application SHALL descartar a ocorrência da fila e registrar erro de formato de imagem inválido.
7. WHEN uma ocorrência for removida ou descartada, THE mobile application SHALL atualizar o indicador persistente de pendências.
8. WHERE uma mensagem técnica for registrada, THE mobile application SHALL não incluir API key nem outro segredo.

### RF-16 — Pausa por autenticação ou acesso

**Etapa:** E4.

**História de usuário:** Como operador, quero ser avisado e evitar tentativas repetidas quando a autenticação ou o acesso falhar, para corrigir a configuração sem perder ocorrências.

**Critérios de aceitação:**

1. WHEN a API responder `401`, THE mobile application SHALL manter a ocorrência na fila, pausar os envios e avisar que a API key é inválida.
2. WHEN a API responder `403`, THE mobile application SHALL manter a ocorrência na fila, pausar os envios e avisar que o dispositivo está inativo ou que o acesso foi negado.
3. WHILE os envios estiverem pausados por `401` ou `403`, THE mobile application SHALL impedir novas tentativas automáticas.
4. WHEN a configuração relevante for corrigida ou uma nova tentativa manual for solicitada, THE mobile application SHALL permitir a retomada dos envios pendentes.
5. WHILE a pausa estiver ativa, THE mobile application SHALL indicar esse estado na tela principal sem expor a API key.

### RF-17 — Falhas recuperáveis, reenvio e backoff

**Etapa:** E4.

**História de usuário:** Como operador, quero que falhas temporárias sejam tratadas automaticamente e com intervalos crescentes, para preservar ocorrências sem sobrecarregar a rede ou a API.

**Critérios de aceitação:**

1. WHEN ocorrer falha de rede, timeout ou resposta HTTP `5xx`, THE mobile application SHALL manter a ocorrência na fila.
2. WHEN ocorrer falha de rede, timeout ou resposta HTTP `5xx`, THE mobile application SHALL programar nova tentativa com backoff exponencial limitado por um teto.
3. WHILE uma ocorrência estiver aguardando o instante permitido pelo backoff, THE mobile application SHALL não tentar enviá-la continuamente.
4. WHEN o aplicativo voltar a ter oportunidade de execução, THE mobile application SHALL retomar automaticamente o processamento das ocorrências elegíveis da fila.
5. WHERE a estratégia de execução em segundo plano for limitada pelo Android, THE mobile application SHALL no mínimo preservar a fila e retomar os envios quando puder executá-los novamente.
6. WHEN uma tentativa for repetida, THE mobile application SHALL reutilizar a imagem, os dados e a `idempotencyKey` originais.

### RF-18 — Códigos HTTP não especificados

**Etapa:** E4.

**História de usuário:** Como operador, quero um comportamento conservador para respostas inesperadas, para evitar perda de dados e ciclos de requisições.

**Critérios de aceitação:**

1. WHEN a API responder com código HTTP não tratado explicitamente em RF-15, RF-16 ou RF-17, THE mobile application SHALL manter a ocorrência na fila.
2. WHEN ocorrer um código HTTP não especificado, THE mobile application SHALL pausar o envio automático, registrar erro técnico sem segredo e avisar o usuário.
3. WHILE a pausa por código não especificado estiver ativa, THE mobile application SHALL impedir ciclos automáticos de tentativas sem intervalo.
4. WHEN o usuário corrigir a configuração aplicável ou solicitar nova tentativa manual, THE mobile application SHALL permitir a retomada do envio pendente.

### RF-19 — Tela de configurações

**Etapa:** E5.

**História de usuário:** Como operador, quero ajustar os parâmetros do MVP, para apontar o aplicativo à API e adequar detecção e cooldown à validação.

**Critérios de aceitação:**

1. WHEN o operador abrir as configurações, THE mobile application SHALL permitir configurar URL base da API, cadastrar ou alterar a API key do dispositivo, limiar de confiança, FPS máximo de inferência, tempo de cooldown e distância mínima.
2. WHEN não houver valor previamente salvo, THE mobile application SHALL apresentar ou aplicar confiança `0.5`, máximo de `5 FPS`, cooldown de `5 segundos` e distância mínima de `15 metros`.
3. IF um valor numérico estiver vazio, não for numérico ou estiver fora do domínio aceito, THE mobile application SHALL impedir seu salvamento e indicar o campo inválido.
4. WHERE o limiar de confiança for configurado, THE mobile application SHALL aceitar somente valor entre 0 e 1.
5. WHERE FPS máximo, tempo de cooldown ou distância mínima forem configurados, THE mobile application SHALL aceitar somente valores positivos.
6. WHEN a API key for salva ou alterada, THE mobile application SHALL reutilizar o armazenamento seguro com proteção Android introduzido em E4, sem reduzir sua proteção.
7. WHEN a configuração for reaberta após o salvamento, THE mobile application SHALL indicar que a API key está configurada sem exibi-la integralmente.
8. WHERE exemplos de configuração forem exibidos, THE mobile application SHALL usar somente valores fictícios que não representem segredo ou ambiente real de produção.

### RF-20 — Permissões de câmera e localização

**Etapa:** E5.

**História de usuário:** Como operador, quero receber solicitações e orientações claras sobre permissões, para habilitar os recursos necessários de forma consciente.

**Critérios de aceitação:**

1. WHEN o aplicativo necessitar usar a câmera sem permissão concedida, THE mobile application SHALL solicitar acesso à câmera.
2. WHEN o aplicativo necessitar geolocalizar ocorrências sem permissão concedida, THE mobile application SHALL solicitar localização precisa.
3. IF a permissão de câmera for recusada temporariamente, THE mobile application SHALL explicar que a captura não pode iniciar e permitir nova solicitação quando apropriado.
4. IF a permissão de localização precisa for recusada temporariamente, THE mobile application SHALL explicar que ocorrências não podem ser criadas sem localização válida.
5. IF uma permissão necessária estiver permanentemente negada, THE mobile application SHALL orientar o usuário a abrir as configurações do Android.
6. IF a câmera não estiver autorizada, THE mobile application SHALL não iniciar a captura.
7. IF a localização válida não estiver disponível, THE mobile application SHALL não criar ocorrência.

### RF-21 — Tela ligada e ciclo controlado de captura

**Etapa:** E5.

**História de usuário:** Como operador, quero que a tela permaneça ativa durante a captura e seja liberada ao final, para acompanhar a operação veicular sem manter esse comportamento desnecessariamente.

**Critérios de aceitação:**

1. WHILE a captura estiver ativa, THE mobile application SHALL manter a tela do aparelho ligada.
2. WHEN a captura for encerrada, THE mobile application SHALL liberar a manutenção de tela ligada solicitada para a captura.
3. WHEN o operador tocar em “Parar”, THE mobile application SHALL interromper novos frames, concluir de forma controlada o processamento em andamento e preservar ocorrências já aceitas.

### RF-22 — Documentação operacional final

**Etapa:** E5.

**História de usuário:** Como avaliador, quero instruções de preparação e execução, para reproduzir o MVP no aparelho de validação.

**Critérios de aceitação:**

1. WHEN a etapa E5 for apresentada para validação, THE mobile application SHALL estar acompanhada de README com instalação do Flutter, build Android e execução no aparelho.
2. WHERE o README descrever configuração, THE mobile application SHALL estar documentada com instruções para URL base e API key usando somente exemplos fictícios.
3. WHERE o README descrever integração, THE mobile application SHALL estar documentada com um exemplo compatível com o contrato fixo de ocorrências.
4. WHERE o README mencionar credenciais, THE mobile application SHALL não incluir API key real, URL real de produção ou outro segredo.

### RF-23 — Sequência de entrega e Validation Gates

**Etapa:** E0, E1, E2, E3, E4 e E5.

**História de usuário:** Como responsável pelo TCC, quero aprovar cada incremento antes do próximo, para controlar o escopo e validar progressivamente o MVP no Galaxy S25+.

**Critérios de aceitação:**

1. WHEN a implementação futura for iniciada, THE mobile application SHALL ser entregue estritamente na ordem E0, E1, E2, E3, E4 e E5.
2. WHEN E0 for concluída, THE mobile application SHALL interromper a execução em seu próprio Validation Gate antes de qualquer início de E1.
3. IF E0 ainda não tiver sido concluída e aprovada explicitamente, THE mobile application SHALL não iniciar E1.
4. IF a etapa anterior não tiver aprovação explícita, THE mobile application SHALL não receber implementação pertencente à etapa seguinte.
5. WHEN uma etapa for concluída, THE mobile application SHALL ter sua execução interrompida no Validation Gate correspondente.
6. WHEN um Validation Gate for apresentado, THE mobile application SHALL ser acompanhada do resultado da etapa, dos testes ou verificações aplicáveis, das evidências e de um roteiro manual de validação no Samsung Galaxy S25+.
7. WHERE o roteiro manual for aplicável, THE mobile application SHALL orientar a observação dos elementos pertencentes à etapa, sem antecipar funcionalidades posteriores.
8. IF uma etapa for reprovada no Validation Gate, THE mobile application SHALL receber apenas correções pertencentes à etapa atual; em particular, uma reprovação de E0 SHALL receber somente correções de E0.
9. WHEN o responsável aprovar explicitamente o Validation Gate, THE mobile application SHALL poder avançar para a etapa imediatamente seguinte.
10. WHERE a etapa for E0, THE mobile application SHALL limitar a entrega a estrutura inicial Flutter Android, build, instalação e execução no Samsung Galaxy S25+, preview básico traseiro, solicitações básicas de câmera e localização precisa, exibição diagnóstica de latitude, longitude, precisão e velocidade quando disponível, conectividade, HTTP diagnóstico exclusivo de teste, mensagens de indisponibilidade, roteiro, evidências e Validation Gate, respeitando todas as proibições de RF-00.
11. WHERE o Validation Gate for E0, THE mobile application SHALL demonstrar resultado da compilação, instalação, abertura e execução no Samsung Galaxy S25+, resultado da câmera traseira, resultado do GPS, precisão, velocidade quando disponível, resultado da rede, HTTP diagnóstico de teste, mensagens observadas em indisponibilidades, roteiro e evidências da validação manual, sem modelo, inferência ou ocorrência.
12. WHERE a etapa for E1, THE mobile application SHALL limitar a entrega a projeto Flutter Android, dependências mínimas, modelo em assets, carregamento, preview, inferência, FPS e detecções, sem GPS associado a ocorrência, cooldown, fila ou rede de ocorrências.
13. WHERE a etapa for E2, THE mobile application SHALL adicionar GPS associado a ocorrência, cooldown, preparação de imagem, UUID e criação em memória, sem fila persistente ou rede de ocorrências.
14. WHERE a etapa for E3, THE mobile application SHALL adicionar fila persistente, recuperação após reinício e indicador de pendências, sem integração real com a API de ocorrências.
15. WHERE a etapa for E4, THE mobile application SHALL adicionar multipart, autenticação, idempotência, tratamento de respostas, backoff, pausa e retomada de envios e mecanismo mínimo de armazenamento seguro da API key com proteção Android, sem antecipar a tela completa de configurações.
16. WHERE a etapa for E5, THE mobile application SHALL adicionar a interface completa de configurações, reutilizar e ampliar sem redução de proteção o armazenamento seguro introduzido em E4, completar o tratamento de permissões, manter a tela ligada durante a captura e fornecer README.

## 8. Requisitos não funcionais

### RNF-01 — Separação arquitetural

**Etapa:** E1, preservado e ampliado de E2 a E5.

**História de usuário:** Como desenvolvedor, quero separar interface, domínio e infraestrutura, para trocar integrações sem reescrever regras de negócio.

**Critérios de aceitação:**

1. WHERE o aplicativo contiver regras de negócio, THE mobile application SHALL mantê-las fora dos widgets Flutter.
2. WHERE o aplicativo integrar o detector, THE mobile application SHALL isolar `ultralytics_yolo` atrás de uma interface.
3. WHERE câmera, localização, persistência ou rede forem adicionadas, THE mobile application SHALL isolá-las atrás de interfaces apropriadas.
4. WHEN um futuro cliente de captura substituir o celular, THE mobile application SHALL permitir o reaproveitamento das regras de detecção elegível, cooldown, ocorrência, fila e envio sem dependência de widgets ou do plugin específico.
5. WHERE uma abstração não atender a uma necessidade concreta do MVP, THE mobile application SHALL privilegiar a solução mais simples.

### RNF-02 — Segurança de configurações e registros

**Etapa:** E4 para comunicação, logs e armazenamento seguro mínimo; E5 para interface completa de configuração.

**História de usuário:** Como responsável pelo sistema, quero proteger credenciais e ambientes, para evitar exposição acidental de segredos.

**Critérios de aceitação:**

1. WHERE código, configuração, documentação ou exemplo forem versionados, THE mobile application SHALL não conter API key real, URL real de produção ou outro segredo.
2. WHERE logs, erros ou diagnósticos forem produzidos, THE mobile application SHALL não incluir a API key, o conteúdo de imagens rejeitadas nem outro segredo.
3. WHEN a API key de teste for fornecida ou persistida em E4, THE mobile application SHALL usar mecanismo mínimo de armazenamento seguro com proteção fornecida pelo Android.
4. WHERE E4 usar credencial de teste, THE mobile application SHALL não armazená-la em código, arquivo versionado ou texto simples, SHALL não expô-la integralmente em logs ou erros e SHALL não usar credencial de produção.
5. WHERE o mecanismo de fornecimento ou salvamento da credencial de teste de E4 for necessário, THE mobile application SHALL defini-lo no design sem exigir nem antecipar a tela completa de configurações.
6. WHEN E5 permitir cadastrar ou alterar a API key, THE mobile application SHALL reutilizar o armazenamento seguro de E4 sem reduzir sua proteção.
7. WHEN a API key já salva for representada em E5, THE mobile application SHALL mascará-la ou indicar somente que existe um valor configurado.
8. WHERE exemplos forem necessários, THE mobile application SHALL usar valores fictícios.

### RNF-03 — Testabilidade automatizada

**Etapa:** E2 para cooldown e payload; E3 para fila; E4 para HTTP e backoff.

**História de usuário:** Como desenvolvedor, quero testar regras críticas sem depender de hardware ou serviços reais, para detectar regressões de forma reproduzível.

**Critérios de aceitação:**

1. WHERE o cooldown estiver implementado, THE mobile application SHALL possuir testes executáveis com `flutter test` para cooldown por tempo e por distância.
2. WHERE a criação de ocorrências estiver implementada, THE mobile application SHALL possuir testes para geração e validação dos dados do payload e, conforme as regras testáveis fora do hardware, para garantir JPEG com qualidade `85` em todas as tentativas, proporção preservada, máximo de `1280x720`, redução progressiva somente de dimensões quando acima de `2 MiB`, proibição de reduzir qualidade e rejeição sem enfileiramento ou envio quando o limite não puder ser cumprido.
3. WHERE idempotência estiver implementada, THE mobile application SHALL possuir testes para preservação da `idempotencyKey` entre tentativas.
4. WHERE a integração HTTP estiver implementada, THE mobile application SHALL possuir testes para classificar respostas em sucesso, descarte, pausa ou reenvio.
5. WHERE o backoff estiver implementado, THE mobile application SHALL possuir testes para progressão exponencial e aplicação do teto.
6. WHERE a fila estiver implementada, THE mobile application SHALL possuir testes para persistência, recuperação e remoção correta dos itens.
7. WHERE dependências externas participarem dos testes, THE mobile application SHALL permitir fakes ou substitutos para câmera, detector, GPS, banco local, rede e relógio quando necessário.

### RNF-04 — Responsividade e desempenho operacional

**Etapa:** E0 para responsividade básica quando pertinente; E1, preservado de E2 a E5 para inferência e operação.

**História de usuário:** Como operador, quero uma interface responsiva durante diagnósticos e inferência, para controlar e observar o aplicativo de forma segura.

**Critérios de aceitação:**

1. WHILE o smoke test E0 estiver em execução, THE mobile application SHALL manter responsivos, quando pertinentes, o preview básico e os indicadores de câmera, GPS e rede.
2. WHILE a inferência estiver ativa, THE mobile application SHALL manter a interface responsiva a atualizações e ao comando “Parar”.
3. WHILE frames excederem o limite de inferência, THE mobile application SHALL poder descartá-los para controlar processamento acumulado.
4. WHERE não houver configuração salva, THE mobile application SHALL usar o limite de inferência de `5 FPS`.
5. WHILE a captura estiver ativa, THE mobile application SHALL evitar processamento acumulado desnecessário que agrave uso de CPU, GPU, bateria ou temperatura.
6. WHEN cada etapa aplicável for validada no Galaxy S25+, THE mobile application SHALL ser observada quanto à responsividade e, a partir de E1, FPS e temperatura, sem impor metas numéricas não fornecidas.

### RNF-05 — Confiabilidade e consistência da fila

**Etapa:** E3 e E4.

**História de usuário:** Como operador, quero consistência entre persistência e envio, para que nenhuma ocorrência seja enviada antes de estar protegida localmente ou removida indevidamente.

**Critérios de aceitação:**

1. WHEN uma ocorrência for elegível para envio, THE mobile application SHALL já tê-la persistido com todos os dados necessários.
2. WHILE uma tentativa estiver em andamento, THE mobile application SHALL preservar a ocorrência até receber resultado que determine sucesso ou descarte explícito.
3. IF o aplicativo for interrompido antes da confirmação de sucesso ou descarte, THE mobile application SHALL recuperar a ocorrência para processamento posterior com a mesma `idempotencyKey`.
4. WHEN a remoção da fila for confirmada, THE mobile application SHALL manter consistente a contagem de pendências.

### RNF-06 — Privacidade mínima das imagens

**Etapa:** E2 a E5.

**História de usuário:** Como responsável pelo MVP, quero limitar o armazenamento de imagens ao que gerou ocorrência válida, para evitar retenção desnecessária de frames da câmera.

**Critérios de aceitação:**

1. WHEN um frame não gerar ocorrência válida, THE mobile application SHALL descartá-lo sem armazenamento persistente.
2. WHEN uma ocorrência for removida da fila por sucesso ou descarte explícito, THE mobile application SHALL remover também a imagem local associada que não seja mais necessária ao envio.
3. WHERE uma imagem permanecer armazenada, THE mobile application SHALL estar associada a uma ocorrência persistente pendente ou pausada.
4. IF uma imagem não cumprir RF-10, THE mobile application SHALL não enfileirá-la, não enviá-la e não incluir seu conteúdo em logs ou erros.

### RNF-07 — Validação no dispositivo principal

**Etapa:** E0, E1, E2, E3, E4 e E5.

**História de usuário:** Como avaliador, quero validar cada incremento no Samsung Galaxy S25+, para confirmar o comportamento no dispositivo-alvo real.

**Critérios de aceitação:**

1. WHEN E0 chegar ao Validation Gate, THE mobile application SHALL possuir roteiro e evidências para verificar build, instalação, abertura e execução no Samsung Galaxy S25+, preview básico da câmera traseira, solicitações básicas de câmera e localização precisa, latitude, longitude, precisão, velocidade quando disponível, conectividade, HTTP diagnóstico exclusivo de teste e mensagens claras de indisponibilidade, sem antecipar E1 a E5.
2. WHEN E1 chegar ao Validation Gate, THE mobile application SHALL possuir roteiro para verificar carregamento do modelo, preview, inferência, FPS, detecções, responsividade e temperatura.
3. WHEN E2 chegar ao Validation Gate, THE mobile application SHALL acrescentar ao roteiro a verificação de GPS associado, confiança, cooldown, imagem, horário e UUID.
4. WHEN E3 chegar ao Validation Gate, THE mobile application SHALL acrescentar ao roteiro a verificação de persistência, recuperação após reabertura e contador de pendências.
5. WHEN E4 chegar ao Validation Gate, THE mobile application SHALL acrescentar ao roteiro a verificação de envio, idempotência, códigos de resposta, backoff, pausa, retomada e armazenamento seguro mínimo da API key de teste.
6. WHEN E5 chegar ao Validation Gate, THE mobile application SHALL acrescentar ao roteiro a verificação da interface completa de configurações, proteção e mascaramento da API key, permissões, tela ligada e documentação.
7. WHERE precisão, temperatura ou autonomia forem observadas, THE mobile application SHALL não ser avaliada contra metas numéricas que não tenham sido previamente aprovadas.

## 9. Matriz de rastreabilidade entre requisitos e etapas

A etapa indicada corresponde à primeira entrega ou ampliação do requisito. `X` identifica introdução ou ampliação naquela etapa; `M` identifica manutenção do comportamento já entregue e sua sujeição a regressão nas etapas seguintes.

| Requisito | Descrição resumida | E0 | E1 | E2 | E3 | E4 | E5 |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|
| RF-00 | Smoke test da infraestrutura Android | X |  |  |  |  |  |
| RF-01 | Plataforma e execução Android | X | M | M | M | M | M |
| RF-02 | Carregamento local do modelo |  | X | M | M | M | M |
| RF-03 | Preview, permissões e controle da câmera | X | X | M | M | M | X |
| RF-04 | Inferência contínua e limitada |  | X | M | M | M | X |
| RF-05 | Indicadores da tela principal | X | X | X | X | X | M |
| RF-06 | Diagnóstico e localização válida | X | M | X | M | M | X |
| RF-07 | Elegibilidade e ocorrência |  |  | X | M | M | M |
| RF-08 | Horário e idempotência |  |  | X | X | X | M |
| RF-09 | Cooldown local |  |  | X | M | M | X |
| RF-10 | Preparação da imagem |  |  | X | M | M | M |
| RF-11 | Ocorrência em memória |  |  | X | M | M | M |
| RF-12 | Fila persistente |  |  |  | X | M | M |
| RF-13 | Destino, autenticação e armazenamento seguro |  |  |  |  | X | X |
| RF-14 | Envio multipart |  |  |  |  | X | M |
| RF-15 | Sucesso e descarte HTTP |  |  |  |  | X | M |
| RF-16 | Pausa por `401`/`403` |  |  |  |  | X | M |
| RF-17 | Reenvio e backoff |  |  |  |  | X | M |
| RF-18 | Outros códigos HTTP |  |  |  |  | X | M |
| RF-19 | Tela de configurações |  |  |  |  |  | X |
| RF-20 | Tratamento completo de permissões |  |  |  |  |  | X |
| RF-21 | Tela ligada e encerramento |  |  |  |  |  | X |
| RF-22 | README operacional |  |  |  |  |  | X |
| RF-23 | Sequência e Validation Gates | X | X | X | X | X | X |
| RNF-01 | Separação arquitetural |  | X | M | M | M | M |
| RNF-02 | Segurança |  |  |  |  | X | X |
| RNF-03 | Testabilidade |  |  | X | X | X | M |
| RNF-04 | Responsividade e desempenho | X | X | M | M | M | M |
| RNF-05 | Confiabilidade da fila |  |  |  | X | X | M |
| RNF-06 | Privacidade mínima das imagens |  |  | X | X | X | M |
| RNF-07 | Validação no dispositivo | X | X | X | X | X | X |

**Legenda:** `X` = requisito introduzido ou ampliado na etapa; `M` = requisito mantido e sujeito a regressão na etapa.

## 10. Rastreabilidade do contrato fixo da API

O HTTP diagnóstico de E0 é separado deste contrato: não representa ocorrência, não usa o endpoint abaixo, não usa produção e não altera qualquer elemento do contrato de ocorrências.

| Elemento do contrato | Requisitos correspondentes |
|---|---|
| `POST {BASE_URL}/api/v1/occurrences` | RF-13 |
| `multipart/form-data` | RF-14 |
| Header `X-API-Key` | RF-13, RNF-02 |
| `image` JPEG obrigatório | RF-10, RF-14 |
| `idempotencyKey` UUID estável | RF-08, RF-12, RF-14, RF-17, RNF-03, RNF-05 |
| `latitude` [-90, 90] | RF-06, RF-07, RF-14 |
| `longitude` [-180, 180] | RF-06, RF-07, RF-14 |
| `confidence` [0, 1] | RF-07, RF-14, RF-19 |
| `defectClass = pothole` | RF-04, RF-07, RF-14 |
| `speedKmh` opcional [0, 300] | RF-06, RF-07, RF-14 |
| `detectedAt` ISO 8601 com fuso | RF-08, RF-14 |
| `highway` e `km` não preenchidos | RF-07, RF-14 |
| Máximo 1280x720 e proporção preservada | RF-10, RNF-03 |
| Qualidade JPEG `85` obrigatória em todas as tentativas | RF-10, RNF-03 |
| Limite de `2 MiB` com redução progressiva somente de dimensões | RF-10, RNF-03 |
| Proibição de reduzir qualidade e rejeição sem fila ou envio se o limite for impossível | RF-10, RNF-03, RNF-06 |
| `200` e `201` | RF-15 |
| `400`, `409`, `413` e `415` | RF-15 |
| `401` e `403` | RF-16 |
| `5xx`, rede e timeout | RF-17 |
| Outros códigos HTTP | RF-18 |

## 11. Limitações e decisões adiadas para a fase de design

As decisões abaixo não serão tomadas nesta fase:

1. Escolha entre `sqflite` e Hive para persistência local; deverá ser escolhida no design a opção mais simples que cumpra os requisitos, com justificativa.
2. Escolha entre `dio` e `http`; deverá ser feita no design conforme simplicidade e atendimento ao multipart, timeout e classificação de respostas.
3. Escolha da solução de gerenciamento de estado; deverá ser a alternativa mais simples adequada ao MVP.
4. Nome definitivo e detalhes de empacotamento do arquivo TFLite.
5. Estrutura detalhada de pastas, classes, entidades, casos de uso e interfaces.
6. Estratégia exata para câmera, seleção de lente, orientação, rotação, conversão e redimensionamento de frames.
7. Estratégia de concorrência para manter inferência e interface responsivas.
8. Método exato de cálculo da distância do cooldown.
9. Valores configuráveis da progressão e do teto do backoff, preservando obrigatoriamente a natureza exponencial e limitada.
10. Solução Android para retomada ou execução em segundo plano, respeitando no mínimo a persistência e a retomada quando o aplicativo puder executar.
11. Fluxo visual exato para retomada manual após `401`, `403` ou código não especificado.
12. Biblioteca e mecanismo concretos de armazenamento seguro da API key e o meio mínimo de fornecimento ou salvamento da credencial de teste em E4, desde que usem proteção fornecida pelo Android e atendam integralmente a RF-13 e RNF-02; a interface completa permanece para E5.
13. Forma exata dos logs técnicos, desde que nenhum segredo, API key ou conteúdo de imagem rejeitada seja exposto.
14. Limites superiores de configuração de FPS, cooldown e distância, além das validações mínimas especificadas.
15. Qualquer meta quantitativa de precisão, temperatura, bateria ou autonomia, que dependerá de medição e aprovação posterior.
16. Detalhes de implementação do servidor simulado ou ambiente exclusivo de teste e do HTTP diagnóstico de E0, preservando sua separação absoluta do endpoint, das credenciais e das ocorrências de produção.

Nenhuma decisão de design poderá alterar a exigência de JPEG com qualidade `85` em todas as tentativas, reduzir a qualidade para cumprir tamanho ou modificar o contrato fixo da API de ocorrências.

## 12. Limite da fase atual

Esta fase produz **apenas a especificação de requisitos** contida neste `requirements.md`.

- E0 está somente especificada e não foi implementada.
- Nenhuma decisão detalhada de arquitetura será tomada agora.
- Nenhuma biblioteca opcional será escolhida agora quando houver alternativas permitidas.
- Nenhum projeto Flutter ou código será criado.
- Nenhum teste será implementado ou executado.
- Nenhuma configuração, relatório auxiliar ou outro arquivo de implementação será criado.
- `design.md` e `tasks.md` dependerão de solicitação e aprovação futuras.
- A implementação não será iniciada nesta fase.
- A execução futura das etapas E0, E1, E2, E3, E4 e E5 dependerá de aprovação explícita.
- A execução será interrompida ao final de cada etapa no respectivo Validation Gate.
- Uma etapa seguinte não poderá começar antes da aprovação explícita da etapa anterior.
- Se uma etapa for reprovada, somente correções pertencentes à etapa corrente poderão ser feitas antes de nova apresentação do gate.

O contrato da API de ocorrências foi preservado sem renomear campos, alterar tipos ou criar endpoints alternativos: endpoint e método, `multipart/form-data`, header `X-API-Key`, campos obrigatórios e opcionais, intervalos, formato temporal, regras da imagem, idempotência e tratamentos de `200`, `201`, `400`, `401`, `403`, `409`, `413`, `415`, respostas `5xx`, falha de rede, timeout e demais códigos HTTP estão rastreados neste documento. O HTTP diagnóstico de E0 permanece separado, exclusivo para servidor simulado ou ambiente de teste, sem representar ocorrência, sem usar o endpoint de ocorrências e sem usar produção ou credencial de produção.
