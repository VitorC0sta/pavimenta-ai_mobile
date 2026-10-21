Crie exclusivamente a especificação de requisitos `requirements.md` para o aplicativo mobile do meu TCC:

“Dispositivo Veicular para Geolocalização de Defeitos em Pavimento Viário”.

Nesta fase:

- Gere somente `requirements.md`.
- Não gere `design.md`.
- Não gere `tasks.md`.
- Não crie projeto Flutter, código, testes, configurações ou outros arquivos.
- Não inicie a implementação.
- Não altere o contrato da API fornecido.
- Se algo não essencial estiver indefinido, adote a alternativa mais simples e registre-a em “Suposições adotadas”.
- Se houver ambiguidade essencial que impeça a especificação, pergunte antes de gerar o arquivo.
- A implementação futura deverá ocorrer sequencialmente, uma etapa por vez.
- Ao final de cada etapa futura, deverá existir um Validation Gate, interrompendo a execução até minha aprovação explícita.

# 1. Produto

O produto é um aplicativo Android simples que funciona como uma dashcam inteligente.

O celular ficará fixado no para-brisa e apontado para a pista de rodovias. O MVP será validado em um Samsung Galaxy S25+.

O aplicativo deverá:

1. Capturar imagens da câmera traseira.
2. Detectar buracos em tempo real com YOLO executado localmente no aparelho.
3. Associar cada buraco detectado à localização GPS e ao horário.
4. Armazenar a ocorrência localmente.
5. Enviar a ocorrência para uma API REST.
6. Manter as ocorrências em uma fila persistente quando não houver conexão ou quando ocorrer uma falha recuperável.

O celular está sendo utilizado por razões de custo e facilidade de validação. Futuramente, o cliente de captura poderá ser substituído por um dispositivo embarcado. Portanto, a lógica de detecção, cooldown, criação de ocorrências, fila e envio deverá permanecer separada da interface Flutter e do plugin específico de detecção.

# 2. Plataforma e stack

- Framework: Flutter/Dart.
- Plataforma alvo: exclusivamente Android.
- Aparelho principal de validação: Samsung Galaxy S25+.
- Detecção: plugin `ultralytics_yolo`.
- Modelo: TFLite incluído nos assets do aplicativo.
- O nome definitivo do arquivo do modelo ainda será definido.
- Localização: `geolocator`.
- Persistência local: `sqflite` ou Hive.
- A decisão entre `sqflite` e Hive deverá ocorrer apenas na futura fase de design, escolhendo a opção mais simples que cumpra os requisitos e registrando a justificativa.
- HTTP: `dio` ou `http`, com escolha apenas na futura fase de design.
- Gerenciamento de estado: adotar posteriormente a opção mais simples que atenda ao MVP.
- Não haverá login de usuário.
- A autenticação com a API será feita exclusivamente por uma API key vinculada ao dispositivo.
- A API key deverá ser armazenada utilizando armazenamento seguro do Android.
- Nenhum segredo, API key real ou URL de produção poderá ser versionado.

# 3. Contrato fixo da API

O aplicativo deverá seguir exatamente o contrato abaixo, sem renomear campos, alterar tipos ou criar endpoints alternativos.

## Endpoint

`POST {BASE_URL}/api/v1/occurrences`

Content-Type:

`multipart/form-data`

## Autenticação

Header:

`X-API-Key: {DEVICE_API_KEY}`

## Campos

- `image`: arquivo JPEG obrigatório.
- `idempotencyKey`: UUID obrigatório, gerado no aplicativo uma única vez para cada ocorrência e reutilizado em todas as tentativas de envio.
- `latitude`: número obrigatório entre -90 e 90.
- `longitude`: número obrigatório entre -180 e 180.
- `confidence`: número obrigatório entre 0 e 1.
- `defectClass`: texto obrigatório com valor fixo `pothole`.
- `speedKmh`: número opcional entre 0 e 300.
- `detectedAt`: data e hora obrigatórias no formato ISO 8601, incluindo informação de fuso horário.
- `highway`: texto opcional, não preenchido pelo MVP.
- `km`: valor opcional, não preenchido pelo MVP.

## Regras da imagem

Antes de ser armazenada na ocorrência:

- A imagem deverá estar no formato JPEG.
- A resolução máxima deverá ser 1280x720.
- A proporção original deverá ser preservada durante o redimensionamento.
- A qualidade JPEG deverá ser 85.
- O arquivo final não poderá ultrapassar 2 MiB.
- Caso a primeira compressão não cumpra o limite de 2 MiB, o aplicativo deverá reduzir adicionalmente a imagem ou sua qualidade antes de aceitar a ocorrência.
- Uma ocorrência que não puder produzir uma imagem válida não deverá ser enviada.

## Tratamento de respostas

- `201`: ocorrência criada; considerar sucesso e remover da fila.
- `200`: ocorrência já existente devido à idempotência; considerar sucesso e remover da fila.
- `400`: contrato violado; descartar da fila e registrar erro técnico sem expor segredo.
- `401`: API key inválida; pausar os envios, manter a fila e avisar o usuário.
- `403`: dispositivo inativo ou acesso negado; pausar os envios, manter a fila e avisar o usuário.
- `409`: conflito da chave de idempotência; descartar da fila e registrar erro.
- `413`: imagem acima do limite aceito; descartar da fila e registrar erro.
- `415`: formato de imagem inválido; descartar da fila e registrar erro.
- Respostas `5xx`: manter na fila e tentar novamente com backoff exponencial limitado por um teto.
- Falha de rede ou timeout: manter na fila e tentar novamente com backoff exponencial limitado por um teto.
- Outros códigos HTTP não especificados deverão seguir uma suposição conservadora claramente registrada no documento, sem alterar as regras acima.

# 4. Funcionalidades do MVP

## 4.1 Tela principal

A tela principal deverá apresentar:

- Preview da câmera traseira.
- Botão “Iniciar”.
- Botão ou estado alternativo “Parar”.
- Indicador de modelo carregado.
- Indicador de disponibilidade e precisão do GPS.
- FPS atual ou recente da inferência.
- Quantidade de buracos detectados na sessão atual.
- Quantidade de ocorrências pendentes de envio.
- Estado dos envios, incluindo situação pausada por erro de autenticação.

## 4.2 Detecção contínua

- A detecção deverá ocorrer continuamente enquanto a captura estiver ativa.
- A inferência deverá ser executada localmente no aparelho.
- A taxa de inferência deverá possuir limite configurável.
- O valor padrão deverá ser 5 FPS.
- Frames recebidos acima do limite poderão ser ignorados.
- Frames sem detecção válida deverão ser descartados imediatamente.
- Frames sem detecção não deverão ser armazenados.

## 4.3 Criação de ocorrência

Uma ocorrência deverá ser criada quando:

- O modelo detectar a classe `pothole`.
- A confiança for maior ou igual ao limiar configurado.
- O cooldown local permitir uma nova ocorrência.
- Houver uma localização válida disponível.

O limiar padrão de confiança deverá ser `0.5`.

A ocorrência deverá utilizar:

- Frame associado à detecção.
- Latitude.
- Longitude.
- Velocidade, quando disponibilizada pelo GPS e estiver no intervalo válido.
- Confiança.
- Classe fixa `pothole`.
- Data e hora da detecção.
- UUID de idempotência gerado no aplicativo.

## 4.4 Cooldown e deduplicação local

O MVP deverá possuir apenas deduplicação local baseada em cooldown.

Após criar uma ocorrência, novas detecções deverão ser ignoradas até que pelo menos uma das seguintes condições seja satisfeita:

- Tenham transcorrido 5 segundos por padrão; ou
- O veículo tenha se deslocado pelo menos 15 metros por padrão desde a ocorrência anterior.

Tempo e distância deverão ser configuráveis.

O back-end não realiza deduplicação de buracos. A idempotência da API evita somente a duplicação causada pelo reenvio da mesma ocorrência.

## 4.5 Fila persistente

- Toda ocorrência deverá ser gravada localmente antes da primeira tentativa de envio.
- A fila deverá sobreviver ao fechamento e à reabertura do aplicativo.
- A ocorrência deverá permanecer na fila durante falta de internet e falhas recuperáveis.
- Uma ocorrência somente deverá ser removida após resposta `200` ou `201`, exceto nos códigos explicitamente definidos como descarte.
- Todas as tentativas de uma ocorrência deverão reutilizar a mesma `idempotencyKey`.
- A fila deverá preservar os dados necessários para reconstruir exatamente o mesmo envio.
- O indicador de pendências deverá refletir a quantidade persistida.

## 4.6 Reenvio e backoff

- O aplicativo deverá tentar enviar ocorrências pendentes automaticamente.
- Falhas de rede, timeouts e respostas `5xx` deverão usar backoff exponencial com teto.
- O mecanismo deverá impedir ciclos de tentativas contínuas sem intervalo.
- Os envios pausados por `401` ou `403` somente deverão ser retomados após uma ação adequada, como correção da API key, correção da URL ou solicitação manual de nova tentativa.
- A interpretação de “segundo plano” no MVP deverá usar a solução Android mais simples compatível com as limitações da plataforma e deverá ser detalhada na futura fase de design.
- O requisito mínimo é que a fila seja persistente e que os envios sejam retomados quando o aplicativo puder executá-los novamente.

## 4.7 Configurações

Deverá existir uma tela simples para configurar:

- URL base da API.
- API key do dispositivo.
- Limiar de confiança.
- FPS máximo de inferência.
- Tempo de cooldown.
- Distância mínima.

Regras:

- A API key deverá ficar em armazenamento seguro.
- A API key nunca deverá aparecer em logs.
- A interface não deverá exibir a API key integralmente após salvá-la.
- Valores numéricos deverão ser validados antes de serem salvos.
- Valores de exemplo poderão ser fornecidos, mas não poderão representar segredos ou ambientes reais de produção.

## 4.8 Permissões e operação

- O aplicativo deverá solicitar acesso à câmera.
- O aplicativo deverá solicitar localização precisa.
- Recusas temporárias e permanentes deverão apresentar mensagens claras.
- O aplicativo não deverá iniciar a captura sem permissão de câmera.
- O aplicativo não deverá criar ocorrência sem localização válida.
- Quando a permissão estiver permanentemente negada, o aplicativo deverá orientar o usuário a abrir as configurações do Android.
- A tela deverá permanecer ligada enquanto a captura estiver ativa.
- A captura deverá ser encerrada de forma controlada quando o usuário tocar em “Parar”.

# 5. Fora do escopo do MVP

Não incluir requisitos de implementação para:

- Login de usuário.
- Cadastro de usuário.
- Mapa.
- Histórico de ocorrências.
- Tela de revisão manual.
- Suporte a iOS.
- Detecção de outros tipos de defeito.
- Preenchimento automático de rodovia ou quilômetro.
- Upload direto para storage.
- Atualização do modelo pela rede.
- Telemetria.
- Painel web.
- Deduplicação avançada entre diferentes passagens pelo mesmo buraco.

# 6. Etapas futuras e Validation Gates

Os requisitos deverão indicar claramente a qual etapa cada item pertence. Utilize identificadores ou uma matriz de rastreabilidade que permita reconhecer os requisitos das etapas E1 a E5.

## E1 — Spike de detecção

Entregáveis futuros:

- Projeto Flutter Android.
- Dependências mínimas.
- Modelo TFLite em assets.
- Carregamento do modelo.
- Preview da câmera traseira.
- Inferência contínua.
- Exibição de FPS e detecções.

Não incluir nesta etapa:

- GPS.
- Cooldown.
- Fila.
- Rede.
- Envio para API.

Objetivo: provar que a detecção funciona no Samsung Galaxy S25+.

## E2 — Captura da ocorrência

Adicionar:

- GPS.
- Cooldown.
- Compressão da imagem.
- UUID de idempotência.
- Criação da ocorrência em memória conforme o contrato.

Não adicionar fila persistente ou rede nesta etapa.

## E3 — Fila local

Adicionar:

- Persistência local da fila.
- Recuperação após reinício.
- Indicador de ocorrências pendentes.

Não adicionar integração real com a API nesta etapa.

## E4 — Integração com API

Adicionar:

- Envio multipart.
- Header `X-API-Key`.
- Idempotência.
- Tratamento individual dos códigos de resposta.
- Backoff exponencial.
- Pausa dos envios em `401` e `403`.
- Retomada dos envios pendentes.

## E5 — Finalização do MVP

Adicionar:

- Tela de configurações.
- Armazenamento seguro da API key.
- Tratamento completo de permissões.
- Manutenção da tela ligada durante a captura.
- README com instalação do Flutter, build Android, execução no aparelho, configuração da URL e API key e exemplo do contrato.

## Regra obrigatória de sequência

- As etapas deverão ser executadas estritamente na ordem E1, E2, E3, E4 e E5.
- Não deverá ser iniciada uma etapa enquanto a anterior não estiver validada.
- Ao final de cada etapa, a execução deverá parar.
- Cada etapa deverá apresentar o resultado, os testes executados e o roteiro manual de validação no Galaxy S25+.
- A próxima etapa somente poderá começar após minha aprovação explícita.
- Uma reprovação no Validation Gate deverá resultar apenas na correção da etapa atual.

# 7. Requisitos não funcionais

## Arquitetura

- Separar interface, domínio e infraestrutura.
- Isolar o plugin `ultralytics_yolo` atrás de uma interface.
- Isolar câmera, localização, persistência e rede atrás de interfaces.
- Permitir a futura troca do celular por outro cliente de captura sem reescrever as regras de cooldown, fila e envio.
- Evitar que widgets Flutter contenham regras de negócio.
- Manter o MVP simples, sem abstrações que não atendam a uma necessidade concreta.

## Segurança

- Não versionar API keys, URLs de produção ou outros segredos.
- Não registrar a API key em logs.
- Não incluir a API key em mensagens de erro.
- Utilizar somente valores fictícios em documentação e exemplos.
- Armazenar a API key em mecanismo seguro fornecido pelo Android.

## Testabilidade

A implementação futura deverá possuir testes automatizados executáveis com `flutter test` para:

- Cooldown por tempo.
- Cooldown por distância.
- Geração e validação do payload.
- Preservação da `idempotencyKey`.
- Classificação de respostas HTTP em sucesso, descarte, pausa ou reenvio.
- Política de backoff.
- Persistência e recuperação da fila.
- Remoção correta de itens da fila.

Os testes deverão utilizar fakes ou substitutos para:

- Câmera.
- Detector.
- GPS.
- Banco local.
- Rede.
- Relógio, quando necessário.

## Desempenho e validação manual

- O limite padrão de inferência deverá ser 5 FPS.
- A inferência não deverá bloquear a interface.
- A solução deverá controlar uso excessivo de CPU, GPU, bateria e temperatura.
- A detecção e o desempenho real deverão ser validados manualmente no Galaxy S25+.
- Cada etapa deverá possuir um roteiro de verificação manual.
- Os roteiros deverão indicar o que observar, incluindo modelo carregado, FPS, detecções, temperatura, GPS e fila, quando aplicáveis.
- Os requisitos não deverão inventar metas numéricas de precisão, temperatura ou autonomia que não foram fornecidas.

# 8. Formato obrigatório do requirements.md

O documento deverá ser escrito em português e conter:

1. Introdução.
2. Objetivo.
3. Escopo do MVP.
4. Fora do escopo.
5. Glossário.
6. Suposições adotadas.
7. Requisitos numerados.
8. História de usuário para cada requisito ou grupo coeso.
9. Critérios de aceitação no formato EARS:
   - `WHEN ... THE mobile application SHALL ...`
   - `IF ... THE mobile application SHALL ...`
   - `WHILE ... THE mobile application SHALL ...`
   - `WHERE ... THE mobile application SHALL ...`
10. Identificação da etapa E1, E2, E3, E4 ou E5 de cada requisito.
11. Matriz de rastreabilidade entre requisitos e etapas.
12. Requisito específico para sequência de entrega e Validation Gates.
13. Requisitos não funcionais.
14. Limitações e decisões adiadas para a fase de design.
15. Limite da fase atual.

Os critérios poderão manter as palavras-chave `WHEN`, `IF`, `WHILE`, `WHERE`, `THE` e `SHALL` em inglês, mas o restante da frase deverá ser escrito em português.

Cada critério deverá ser:

- Objetivo.
- Testável.
- Não ambíguo.
- Rastreável.
- Compatível com o contrato fixo da API.
- Livre de detalhes desnecessários de implementação.

# 9. Limite obrigatório da fase atual

Finalize o documento declarando explicitamente que:

- Esta fase produz apenas a especificação de requisitos.
- Nenhuma decisão detalhada de arquitetura será tomada agora.
- Nenhuma biblioteca opcional será escolhida agora quando houver alternativas permitidas.
- Nenhum código será criado.
- Nenhum teste será implementado.
- `design.md` e `tasks.md` dependerão de solicitação e aprovação futuras.
- A execução das etapas E1 a E5 dependerá de aprovação explícita e será interrompida em cada Validation Gate.

Antes de finalizar, revise o documento para confirmar que todos os campos, limites, códigos de resposta e regras de idempotência do contrato da API foram representados exatamente.
