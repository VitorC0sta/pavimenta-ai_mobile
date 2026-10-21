# Design — E0: Smoke test da infraestrutura Android

## 1. Visão geral da E0

A E0 é um incremento diagnóstico mínimo, exclusivo para Android, destinado a reduzir riscos de compilação, instalação, permissões, câmera, localização e comunicação HTTPS no Samsung Galaxy S25+ antes de qualquer funcionalidade de detecção ou de ocorrência.

A entrega futura de E0 será uma única tela Flutter que:

- inicializa e exibe o preview da câmera traseira;
- solicita, de forma básica e serializada, primeiro a permissão de câmera e depois a permissão de localização precisa;
- apresenta o estado do serviço de localização e, quando houver posição, latitude, longitude, precisão e velocidade fornecida pelo provedor;
- executa, sob ação explícita do usuário, uma requisição HTTPS diagnóstica sem corpo e sem credenciais para um destino fictício ou exclusivo de teste;
- apresenta estados claros de inicialização, disponibilidade e indisponibilidade;
- permanece utilizável em diferentes dimensões, densidades e escalas de fonte do Galaxy S25+;
- libera câmera, assinatura de localização e cliente HTTP conforme o ciclo de vida.

A interface aparecerá imediatamente, sem aguardar permissões. A recusa de uma permissão não bloqueará os diagnósticos independentes, e nenhuma solicitação de permissão será apresentada simultaneamente a outra.

O resultado da E0 deverá ser interrompido em seu próprio Validation Gate para validação manual e aprovação explícita. Nenhuma etapa posterior poderá ser iniciada antes dessa aprovação.

## 2. Objetivos técnicos

1. Confirmar que o projeto Flutter Android pode ser compilado, instalado, aberto e executado de modo controlado no Samsung Galaxy S25+.
2. Confirmar que o Android reconhece as declarações de câmera, localização e internet exigidas pelo smoke test.
3. Selecionar a câmera traseira padrão disponível e manter um preview básico responsivo, sem captura de frames para processamento.
4. Solicitar e distinguir os estados básicos das permissões de câmera e localização precisa sem abrir diálogos Android concorrentes.
5. Obter uma posição de alta precisão em primeiro plano e atualizar seus valores diagnósticos sem associá-los a qualquer outro dado.
6. Confirmar comunicação HTTPS básica com um destino explicitamente fornecido para teste.
7. Produzir mensagens compreensíveis quando câmera, GPS, posição, rede ou destino de teste não estiverem disponíveis.
8. Verificar que a aplicação sobrevive a negações de permissão, indisponibilidades e transições de ciclo de vida sem encerramento inesperado.
9. Manter a solução pequena, com integrações de hardware e HTTP separadas dos widgets, mas sem camadas ou interfaces sem necessidade concreta na E0.

## 3. Limites de escopo

### Incluído na E0

- estrutura mínima de um aplicativo Flutter com suporte exclusivamente Android;
- execução no Samsung Galaxy S25+;
- preview da câmera traseira padrão, sem áudio;
- permissão básica de câmera;
- permissão de localização em primeiro plano com exigência de localização precisa;
- leitura diagnóstica de latitude, longitude, precisão em metros e velocidade em metros por segundo quando o provedor fornecer valor utilizável;
- estado básico do diagnóstico de comunicação;
- uma requisição `GET` HTTPS, sem corpo e sem autenticação, acionada manualmente contra URL fictícia ou exclusiva de teste;
- mensagens de indisponibilidade e ações simples de tentar novamente;
- interface adaptável e rolável;
- tratamento de ciclo de vida dos recursos;
- roteiro de validação manual, evidências esperadas e Validation Gate da E0.

### Expressamente excluído da E0

A E0 não conterá biblioteca YOLO, modelo TFLite, inferência, detector real, simulado ou falso, detecção de buracos, FPS de inferência, confiança, cooldown, criação ou representação de ocorrência, preparação definitiva de imagem, UUID de idempotência, fila persistente, API key, armazenamento seguro, multipart ou integração com a API de ocorrências. A requisição diagnóstica não conterá imagem, coordenadas ou qualquer dado de ocorrência e não utilizará o endpoint fixo de ocorrências.

Também ficam excluídos controles de início/parada de captura, processamento ou armazenamento de frames, execução em segundo plano, tela de configurações e experiência completa de recuperação de permissões. Esses itens não são necessários para comprovar a infraestrutura da E0.

## 4. Arquitetura mínima

A arquitetura será composta por uma camada de apresentação, um coordenador de estado e permissões e três componentes concretos de integração:

```text
E0Screen
   │ observa e envia ações
   ▼
E0Controller (ChangeNotifier)
   │ coordena a sequência de permissões
   ├── CameraDiagnostic
   ├── LocationDiagnostic
   └── DiagnosticHttpClient
```

- **Apresentação:** renderiza imediatamente o preview, os indicadores e botões de repetição do diagnóstico. Não acessa permissões, localização ou HTTP diretamente.
- **Coordenação:** mantém um único estado observável da tela, converte resultados técnicos em estados de interface e é a autoridade que autoriza cada etapa capaz de apresentar uma solicitação de permissão.
- **Integrações:** cada componente possui somente a responsabilidade concreta de câmera, localização ou HTTPS. Os componentes não iniciam por conta própria fluxos concorrentes de permissão.

O `E0Controller` manterá uma pequena máquina de estados para permissões: câmera pendente, câmera em resolução, câmera resolvida, localização pendente, localização em resolução e permissões resolvidas. Somente uma transição de solicitação poderá estar ativa. A câmera será resolvida primeiro; apenas após concessão ou recusa poderá começar a solicitação de localização. A recusa da câmera não interromperá a sequência. Concluídas as decisões de permissão, câmera e localização poderão atualizar seus estados independentemente.

Cada ciclo de inicialização terá um identificador de geração. Callbacks de operações assíncronas de gerações anteriores serão ignorados. Uma referência à solicitação de permissão em andamento impedirá que retomadas, reconstruções da tela ou toques repetidos abram diálogos duplicados.

`ChangeNotifier`, `ListenableBuilder`/`AnimatedBuilder` e `setState` são suficientes para a única tela. Não será adicionada biblioteca de gerenciamento de estado. Também não serão criados repositórios, casos de uso, injeção de dependências por framework ou interfaces espelho com uma única implementação. As dependências serão construídas explicitamente no ponto de composição da E0.

A separação proposta impede que regras de permissão, ciclo de vida e classificação de falhas fiquem nos widgets, sem transformar o smoke test em uma arquitetura definitiva para as etapas posteriores.

## 5. Estrutura proposta de diretórios

A estrutura abaixo representa somente os arquivos que seriam necessários durante a implementação futura da E0; este documento não os cria.

```text
lib/
├── main.dart
└── e0/
    ├── e0_screen.dart
    ├── e0_controller.dart
    ├── e0_state.dart
    ├── camera_diagnostic.dart
    ├── location_diagnostic.dart
    └── diagnostic_http_client.dart

android/app/src/main/
└── AndroidManifest.xml
```

Não haverá diretórios de detector, modelo, domínio de ocorrência, persistência, fila, envio, autenticação ou configurações.

### Identidade do projeto

- O repositório atual é exclusivo para o aplicativo mobile.
- O projeto Flutter será criado diretamente na raiz deste repositório; não será criado um subdiretório duplicado para o aplicativo.
- O nome do projeto Flutter será `pavimenta_ai_mobile`.
- O `applicationId` Android será `com.vitor.pavimenta_ai_mobile`.
- Esse identificador é gratuito e será usado para desenvolvimento, instalação local e apresentação do TCC. Não é necessário possuir nem registrar o domínio `vitor.com`; a notação reversa serve como identificador do pacote Android.
- A URL HTTPS funcional do diagnóstico será fornecida somente durante a validação por `--dart-define=E0_DIAGNOSTIC_URL=...`.
- Nenhuma URL funcional de produção será versionada.

O comando a considerar no planejamento futuro das tarefas será equivalente a:

`flutter create --platforms=android --project-name pavimenta_ai_mobile --org com.vitor .`

Esse comando não faz parte da revisão de design e não deverá ser executado nesta fase.

## 6. Componentes e responsabilidades

### `main.dart`

- inicializar os bindings Flutter;
- criar as dependências concretas da E0;
- iniciar um `MaterialApp` Android com `E0Screen` como única rota funcional;
- não carregar configurações, credenciais, modelos ou armazenamento.

### `E0Screen`

- observar `E0Controller`;
- renderizar imediatamente o painel da câmera, o painel de localização e o painel de rede, mesmo enquanto permissões estiverem pendentes;
- encaminhar ações de tentar novamente e executar diagnóstico;
- usar `SafeArea`, restrições de largura e conteúdo rolável para evitar cortes;
- observar o ciclo de vida por meio de `WidgetsBindingObserver` e encaminhar transições ao coordenador.

### `E0Controller`

- iniciar o fluxo serial de permissões sem bloquear a thread da interface;
- autorizar primeiro a operação de câmera que poderá solicitar permissão e aguardar sua conclusão, com concessão ou recusa, antes de autorizar a solicitação de localização;
- garantir que a recusa de câmera não impeça localização e que a recusa de localização não impeça câmera ou rede;
- depois de resolvidas as permissões, permitir que câmera e localização atualizem seus estados independentemente;
- manter um snapshot consolidado em `E0State`;
- serializar ações repetidas do mesmo diagnóstico para evitar inicializações concorrentes;
- impedir solicitações de permissão simultâneas ou duplicadas, inclusive em retomadas do ciclo de vida;
- invalidar e ignorar resultados assíncronos obsoletos após descarte, pausa ou início de uma nova geração;
- traduzir erros dos componentes em mensagens e estados definidos;
- coordenar pausa, retomada e descarte.

### `E0State`

Snapshot imutável e pequeno contendo:

- fase atual da sequência de permissões;
- estado e mensagem da câmera;
- referência somente leitura ao controlador de preview já inicializado, quando disponível;
- estado e mensagem da localização;
- latitude, longitude, precisão e velocidade opcionais;
- estado e mensagem do diagnóstico HTTPS;
- código HTTP opcional da última resposta;
- indicação de operação em andamento para impedir toques duplicados.

Não conterá entidade de ocorrência nem dados derivados para etapas posteriores.

### `CameraDiagnostic`

- consultar as câmeras expostas pelo dispositivo quando autorizado pelo `E0Controller`;
- escolher a primeira câmera com direção traseira;
- criar e possuir o `CameraController` com áudio desabilitado e resolução moderada adequada ao preview;
- inicializar, expor o controlador pronto para `CameraPreview` e classificar o resultado da permissão ou falhas conhecidas;
- nunca iniciar novamente uma solicitação enquanto a operação autorizada estiver em andamento;
- descartar o controlador de forma idempotente;
- não iniciar stream de imagens nem fornecer frames.

### `LocationDiagnostic`

- começar somente após autorização do `E0Controller`, quando a resolução da permissão de câmera já tiver terminado;
- verificar se o serviço de localização está habilitado;
- verificar e solicitar a permissão em primeiro plano;
- confirmar que a precisão concedida não foi reduzida pelo Android;
- obter uma posição inicial e manter uma assinatura de atualizações enquanto a tela estiver ativa;
- expor somente os valores diagnósticos da posição;
- cancelar a assinatura de forma idempotente;
- nunca abrir uma nova solicitação de permissão se já houver uma em andamento.

### `DiagnosticHttpClient`

- validar tecnicamente a configuração do destino antes de abrir conexão;
- aceitar somente URI absoluta, com esquema HTTPS, host presente, sem usuário ou senha embutidos e sem fragmento;
- rejeitar configuração ausente, URI inválida e o caminho `/api/v1/occurrences`;
- realizar uma única requisição `GET`, sem corpo, autenticação, API key, imagem, coordenadas, UUID ou outros dados de ocorrência;
- aplicar timeout finito, não seguir redirecionamentos e não repetir automaticamente;
- não armazenar, interpretar, renderizar nem registrar o corpo da resposta;
- limitar por tempo e volume qualquer leitura necessária para descartar o corpo e cancelar controladamente conexões que excedam esses limites ou não terminem;
- expor ao controlador somente o código HTTP e uma classificação sanitizada;
- classificar resposta recebida, timeout, falha TLS, configuração inválida e falha de conexão;
- encerrar o cliente e a requisição ativa na mudança de ciclo de vida ou no descarte.

O cliente não tentará inferir se um host pertence a produção. Essa garantia será um controle operacional humano do Validation Gate.

## 7. Fluxo de inicialização do aplicativo

1. O Flutter inicia e apresenta imediatamente a estrutura completa da tela com estados “Inicializando”; a renderização não aguarda permissões.
2. O `E0Controller` cria uma nova geração de inicialização e entra na fase de resolução da câmera.
3. Somente o fluxo de câmera recebe autorização para executar a operação que poderá abrir o diálogo Android. A localização permanece visível como “Aguardando conclusão da permissão de câmera”.
4. Quando a solicitação de câmera terminar, seja por concessão ou recusa, o controlador registra a câmera como resolvida e autoriza o fluxo de localização.
5. Somente então a localização verifica serviço e permissão e, se necessário, apresenta sua solicitação Android.
6. A recusa da câmera não impede o diagnóstico de localização. A recusa da localização não interrompe câmera nem rede.
7. Após ambas as permissões estarem resolvidas, câmera e localização atualizam seus próprios estados de forma independente. Uma falha posterior em um fluxo não bloqueia o outro.
8. O destino HTTPS é apenas validado tecnicamente na inicialização; nenhuma requisição é feita automaticamente.
9. O painel de rede permanece em “Não verificado” até o usuário tocar em “Executar diagnóstico HTTPS” e funciona independentemente das permissões.
10. Se uma transição de ciclo de vida ocorrer durante uma operação, a geração anterior é invalidada para publicação de estado. Uma solicitação de permissão Android ainda aberta permanece registrada como em andamento e não é repetida na retomada.
11. Ao retornar a `resumed`, o controlador reconcilia o resultado da solicitação pendente ou consulta o estado já resolvido antes de prosseguir. Nunca inicia duas solicitações simultâneas nem duplica um diálogo por reconstrução ou retomada.

## 8. Fluxo da câmera

1. Exibir “Inicializando câmera” assim que o `E0Controller` iniciar a primeira fase da sequência.
2. Consultar as câmeras disponíveis somente dentro da operação autorizada pelo controlador.
3. Selecionar a primeira cuja direção seja traseira. A seleção de uma lente física específica não faz parte da E0.
4. Criar o controlador com áudio desabilitado e resolução moderada; a E0 precisa validar preview, não qualidade de captura.
5. Durante a inicialização, o plugin poderá solicitar a permissão Android de câmera. Enquanto essa solicitação estiver ativa, o controlador não autorizará a solicitação de localização.
6. Assim que a permissão de câmera for concedida ou recusada, registrar a conclusão da fase para liberar a verificação de localização. A conclusão da inicialização do preview poderá continuar atualizando somente o estado da câmera.
7. Em caso de sucesso, marcar “Câmera traseira disponível” e exibir `CameraPreview` dentro de uma região com proporção preservada e recorte controlado.
8. Em caso de permissão negada, marcar “Permissão de câmera negada” e permitir que o fluxo de localização prossiga. Oferecer “Tentar novamente” sem executar a ação se outra solicitação de permissão estiver ativa.
9. Se a negação for permanente, orientar o usuário a habilitar a permissão nas configurações do Android, sem implementar o fluxo completo reservado a etapa posterior.
10. Se nenhuma câmera traseira existir, se ela estiver em uso por outro aplicativo ou se a inicialização falhar, manter localização e rede operacionais e apresentar uma mensagem específica quando o erro puder ser identificado.
11. Ao sair de `resumed`, descartar o controlador. Ao retomar, o `E0Controller` cria uma nova geração, verifica se já existe solicitação em andamento e somente então autoriza redescoberta e inicialização, sem reutilizar controlador descartado nem abrir diálogo duplicado.

O fluxo não inicia captura lógica, stream de imagens, análise, gravação, persistência ou inferência.

## 9. Fluxo de localização

1. A interface exibe o painel imediatamente como “Aguardando conclusão da permissão de câmera”.
2. Depois que a solicitação de câmera terminar por concessão ou recusa, o `E0Controller` autoriza a localização e o painel passa a “Verificando localização”.
3. Consultar o estado do serviço de localização do Android.
4. Se o serviço estiver desabilitado, apresentar “Serviço de localização desativado”, manter os valores como indisponíveis e oferecer nova verificação. Como nenhuma solicitação de permissão foi aberta, a fase é considerada resolvida sem bloquear câmera ou rede.
5. Se o serviço estiver habilitado, consultar a permissão atual.
6. Se ainda não houver permissão, solicitar localização em primeiro plano, desde que o controlador confirme não existir outra solicitação ativa. Não será solicitada localização em segundo plano.
7. Se negada, apresentar mensagem clara e permitir nova tentativa coordenada. A recusa não interrompe câmera nem rede. Se negada permanentemente, orientar habilitação nas configurações do Android.
8. Após concessão, consultar a precisão autorizada. Se o Android tiver concedido somente localização aproximada, apresentar “Localização precisa não autorizada” e não representar o requisito como atendido.
9. Com localização precisa autorizada, solicitar uma posição atual com alta precisão e iniciar atualizações em primeiro plano com frequência moderada, sem objetivo de rastreamento veicular.
10. A cada posição, exibir:
    - latitude e longitude em graus decimais;
    - precisão horizontal reportada, em metros;
    - velocidade reportada, em metros por segundo, somente se o valor for finito e não negativo; caso contrário, “Não fornecida”.
11. Se a posição ainda não estiver disponível, apresentar “Aguardando posição”. Se ocorrer timeout ou erro do provedor, apresentar “Posição indisponível” sem encerrar o aplicativo.
12. Ao sair de `resumed`, cancelar a assinatura e invalidar callbacks antigos. Ao retomar, o controlador verifica a sequência e qualquer solicitação ainda pendente antes de reavaliar serviço, permissão e precisão; nenhuma solicitação duplicada será aberta.

A E0 não define limiar aceitável de precisão, não usa posição para bloquear outra função e não aplica regras de validade pertencentes a ocorrências.

## 10. Fluxo de diagnóstico de rede

### Configuração

A URL será fornecida em tempo de compilação por uma chave exclusiva da E0, `E0_DIAGNOSTIC_URL`. O valor padrão será fictício e não resolvível, como `https://e0-diagnostic.example.invalid/health`. Para validar sucesso, o responsável deverá fornecer, fora do repositório, uma URL HTTPS pertencente a servidor simulado ou ambiente exclusivo de teste.

O aplicativo executará apenas as seguintes validações técnicas:

- configuração presente e URI sintaticamente válida;
- URI absoluta;
- esquema exatamente `https`;
- host presente;
- ausência de usuário e senha embutidos;
- ausência de fragmento;
- rejeição explícita do caminho `/api/v1/occurrences`;
- ausência de API key, imagem, coordenadas, UUID ou outros dados de ocorrência na requisição.

A aplicação não possui informação suficiente para determinar genericamente se outro endereço pertence a produção. Não haverá domínio funcional inventado, allowlist nem tentativa de classificar automaticamente o ambiente pelo host.

### Execução

1. O painel inicia em “Não verificado”. Isso evita afirmar que existe ou não conectividade sem uma tentativa real.
2. Ao tocar em “Executar diagnóstico HTTPS”, o botão é desabilitado e o estado muda para “Verificando”.
3. O cliente valida a configuração e envia uma única requisição `GET`, sem corpo, headers de autenticação, API key, coordenadas, imagem, UUID ou identificadores.
4. A validação TLS padrão da plataforma é mantida; certificados inválidos não são aceitos.
5. Redirecionamentos permanecem desabilitados. Uma resposta `3xx` é apenas classificada pelo código recebido, evitando seguir silenciosamente para outro destino.
6. O conteúdo da resposta nunca é armazenado, interpretado, renderizado ou registrado.
7. Qualquer leitura necessária para liberar a conexão e descartar o corpo terá timeout e limite finito de bytes. O valor numérico será definido na implementação, deverá ser pequeno e adequado a um diagnóstico que não utiliza conteúdo.
8. Se o corpo exceder o limite, não terminar dentro do prazo ou continuar indefinidamente, a requisição/conexão será cancelada de forma controlada. O estado receberá somente uma classificação sanitizada de resposta excessiva ou incompleta e, se já disponível, o código HTTP.
9. Somente o código HTTP e uma classificação sanitizada poderão chegar ao `E0State`; headers e corpo não serão propagados.
10. Qualquer resposta HTTP comprova que a pilha de rede e o destino responderam. Respostas `2xx` aparecem como “Destino de teste acessível”; outros códigos aparecem como “Destino respondeu com HTTP N”, sem semântica de envio.
11. Timeout de conexão/resposta, falha TLS e URI inválida recebem mensagens próprias.
12. Uma falha de socket ou resolução de nome aparece honestamente como “Rede indisponível ou destino de teste inacessível”, pois uma única requisição não permite distinguir todas as causas com segurança.
13. Ao final, o botão é reabilitado. Não há polling, retry automático ou execução em segundo plano.
14. Ao sair de `resumed` ou no descarte, o cliente e a requisição ativa são encerrados e callbacks antigos não atualizam a tela.

Não será usada biblioteca de conectividade: o resultado da própria requisição é o sinal diagnóstico de rede. Isso reduz dependências e evita declarar “online” sem comprovar acesso ao destino informado.

### Controles operacionais do Validation Gate

As condições que o aplicativo não pode inferir serão verificadas por uma pessoa no gate:

- confirmar que a URL funcional pertence a ambiente simulado ou exclusivo de teste;
- confirmar que nenhuma URL de produção foi fornecida;
- confirmar que a URL funcional foi fornecida fora do repositório por `--dart-define`;
- registrar evidência sanitizada, sem query string, credenciais ou exposição desnecessária do host.

## 11. Estados da interface

A tela será dividida em três cartões, sob o título “E0 — Diagnóstico Android”. Um banner no topo deixará explícito “Smoke test; nenhum dado de ocorrência é criado ou enviado”.

### Painel de câmera

- `inicial`: ainda não iniciado;
- `inicializando`: descoberta/permissão/inicialização em andamento;
- `disponível`: preview traseiro visível;
- `permissão negada`;
- `permissão negada permanentemente`;
- `sem câmera traseira`;
- `indisponível`: câmera ocupada ou falha de inicialização;
- `pausada`: aplicativo fora de primeiro plano.

### Painel de localização

- `aguardando câmera`: a sequência ainda está resolvendo a permissão de câmera;
- `verificando serviço/permissão`;
- `aguardando posição`;
- `disponível`: valores mais recentes visíveis;
- `serviço desativado`;
- `permissão negada`;
- `permissão negada permanentemente`;
- `precisão reduzida`;
- `posição indisponível`;
- `pausada`.

Valores ausentes serão mostrados como “Não disponível”, nunca como zero. A velocidade ausente será mostrada como “Não fornecida”.

### Painel de rede

- `não verificado`;
- `configuração inválida ou ausente`;
- `verificando`;
- `destino acessível` com código HTTP;
- `destino respondeu` com código HTTP não `2xx`;
- `resposta excessiva ou incompleta`;
- `timeout`;
- `falha TLS`;
- `rede ou destino indisponível`;
- `cancelado pelo ciclo de vida`.

### Responsividade visual

- o conteúdo ficará em `SafeArea` e será verticalmente rolável;
- o preview preservará proporção e terá altura limitada, evitando expulsar os diagnósticos da tela;
- textos poderão quebrar linha e não dependerão somente de cor;
- cartões e botões usarão largura disponível e alvos de toque do Material;
- operações assíncronas mostrarão progresso local, sem bloquear os demais cartões;
- no modo paisagem ou em largura ampla, o layout poderá distribuir cartões em colunas por `LayoutBuilder`; em largura reduzida, permanecerá em uma coluna.

## 12. Tratamento de permissões e indisponibilidades

| Situação | Comportamento da E0 |
|---|---|
| Câmera ainda não autorizada | Solicitar primeiro a câmera e manter localização em espera; nenhum outro diálogo de permissão será aberto simultaneamente. |
| Câmera negada | Não exibir preview; mostrar mensagem, liberar a etapa de localização e oferecer nova tentativa coordenada. |
| Câmera negada permanentemente | Informar que a habilitação deve ser feita nas configurações Android; localização e rede continuam disponíveis. |
| Nenhuma câmera traseira | Informar indisponibilidade e manter localização e rede funcionais. |
| Câmera ocupada/erro | Exibir falha controlada e permitir reinicialização. |
| Localização ainda não autorizada | Somente depois de resolvida a câmera, solicitar permissão em primeiro plano. |
| Serviço de localização desativado | Não solicitar posição; orientar ativação do serviço e permitir nova verificação. |
| Localização negada | Não iniciar stream; mostrar mensagem e ação coordenada de nova tentativa; câmera e rede continuam disponíveis. |
| Localização negada permanentemente | Orientar habilitação nas configurações Android. |
| Somente precisão aproximada | Informar que a E0 exige localização precisa e não marcar o diagnóstico como aprovado. |
| Sem posição/timeout | Manter valores indisponíveis e permitir nova tentativa. |
| URL ausente, inválida, não HTTPS, sem host, com credenciais/fragmento ou com caminho proibido | Não abrir conexão; mostrar erro de configuração. |
| Sem rede/destino inalcançável | Mostrar falha de conectividade sem atribuir causa mais específica do que a evidência permite. |
| Certificado TLS inválido | Recusar conexão e mostrar falha TLS; nunca desabilitar validação. |
| Corpo excessivo ou sem término | Cancelar conexão dentro dos limites finitos e mostrar classificação sanitizada. |

A E0 usará somente solicitações básicas e mensagens. Não implementará um fluxo completo de onboarding, abertura automática de configurações, rationale customizado ou política de permissão em segundo plano.

## 13. Ciclo de vida e liberação dos recursos

`E0Screen` observará `AppLifecycleState` e delegará as transições ao controlador:

- **`resumed`:** criar ou continuar uma geração controlada; reconciliar primeiro eventual solicitação de permissão já aberta; consultar os estados resolvidos; reavaliar câmera e localização somente quando não houver operação equivalente em andamento. A retomada nunca autoriza um segundo diálogo simultâneo ou duplicado.
- **`inactive`, `paused` ou `hidden`:** invalidar a publicação de resultados assíncronos da geração anterior, interromper atualizações de localização, descartar a câmera e encerrar a requisição ativa e o cliente HTTP. Uma solicitação de permissão do sistema que já esteja visível permanece registrada como pendente para reconciliação, não para repetição.
- **`detached` e `dispose`:** remover observer, cancelar `StreamSubscription`, descartar `CameraController`, abortar a requisição ativa, fechar `HttpClient`, invalidar callbacks pendentes e descartar `E0Controller`.

Cada operação de liberação será idempotente. Um identificador de geração impedirá que operações antigas de câmera, localização ou HTTP publiquem estado depois de pausa, descarte ou substituição. A referência separada ao fluxo de permissão em andamento impedirá duplicação, pois o diálogo do sistema pode sobreviver a uma transição em que outros recursos já tenham sido invalidados.

A retomada criará uma nova instância da câmera em vez de reutilizar controlador descartado. A assinatura de localização existirá somente em primeiro plano. A E0 não solicitará serviço de primeiro plano, localização em background, wake lock ou execução persistente.

## 14. Dependências Flutter estritamente necessárias

| Dependência | Uso na E0 | Justificativa |
|---|---|---|
| Flutter SDK (`material`) | Aplicativo, widgets, responsividade e estado nativo | Base obrigatória; fornece toda a apresentação e o `ChangeNotifier`, eliminando biblioteca exclusiva de estado. |
| `camera` | Descoberta da câmera traseira, permissão mediada pelo plugin, controlador e preview | É a integração Flutter oficial/convencional mínima para validar a câmera Android sem acessar APIs nativas diretamente. |
| `geolocator` | Estado do serviço, permissão, precisão autorizada, posição e stream | Já está previsto nos requisitos e concentra a integração Android necessária à localização diagnóstica. |
| Bibliotecas Dart `dart:io` e `dart:async` | `HttpClient`, timeout, limites e controle assíncrono | Fazem parte do SDK; são suficientes para uma única requisição diagnóstica simples e não adicionam pacote HTTP. |

As versões de `camera` e `geolocator` deverão ser fixadas no momento da implementação a versões mutuamente compatíveis com a versão Flutter adotada e com o Android do dispositivo-alvo. Não serão adicionados `http`, `dio`, biblioteca de conectividade, biblioteca de permissões, biblioteca de estado, persistência, armazenamento seguro ou qualquer dependência de visão computacional.

## 15. Configurações Android necessárias

### Verificação prévia do ambiente de desenvolvimento

Antes de criar o projeto Flutter, a futura implementação deverá verificar e registrar:

- a versão instalada do Flutter;
- o resultado de `flutter doctor -v`;
- a disponibilidade da toolchain Android;
- a disponibilidade do ADB no ambiente que executará os comandos Flutter;
- o reconhecimento do Samsung Galaxy S25+ pelo mesmo ambiente que executará o Flutter;
- a compatibilidade prática entre WSL, o ADB utilizado e o aparelho conectado ao Windows.

Não se presumirá que um aparelho reconhecido pelo ADB do Windows seja automaticamente reconhecido pelo ADB dentro do WSL. Se o Flutter for executado no WSL, o diagnóstico deverá confirmar que essa instância realmente lista e acessa o Galaxy S25+; se for executado no Windows, as verificações deverão ocorrer nesse mesmo ambiente.

A implementação não instalará, atualizará nem reconfigurará Flutter, Android SDK, drivers USB, WSL ou ADB sem autorização explícita do usuário. Toolchain ausente, incompatibilidade WSL/ADB ou dispositivo não reconhecido será relatado como bloqueio ou convertido em etapa manual, sem alteração autônoma do ambiente.

### Manifesto e plataforma Android

O `AndroidManifest.xml` da aplicação deverá declarar somente:

- `android.permission.CAMERA`;
- `android.permission.ACCESS_FINE_LOCATION`;
- `android.permission.ACCESS_COARSE_LOCATION`, necessário ao modelo moderno de escolha entre localização aproximada e precisa;
- `android.permission.INTERNET`.

A câmera deverá ser declarada como recurso não obrigatório no manifesto (`required=false`) para que a aplicação possa abrir e apresentar a mensagem controlada mesmo se o recurso não estiver exposto. Em execução, a ausência de câmera traseira reprova o respectivo item do smoke test, mas não deve causar encerramento inesperado.

Configurações adicionais:

- manter somente o módulo Android gerado pelo Flutter; não adicionar suporte iOS ao escopo de validação;
- usar o projeto `pavimenta_ai_mobile` e o `applicationId` `com.vitor.pavimenta_ai_mobile` definidos na identidade do projeto;
- usar `minSdk`, `compileSdk` e `targetSdk` compatíveis com as versões fixadas dos plugins e com a toolchain Flutter vigente na implementação, registrando os valores efetivamente usados como evidência do gate;
- manter tráfego em texto claro desabilitado; o diagnóstico aceita apenas HTTPS;
- não adicionar exceção de segurança de rede, certificado permissivo ou bypass TLS;
- não declarar microfone, armazenamento, localização em segundo plano, foreground service ou wake lock;
- manter o rótulo e ícone padrão suficientes para identificar a instalação E0, sem customização não funcional.

## 16. Estratégia para evitar exposição de URLs reais de produção

### Validações executadas pelo aplicativo

1. O código conterá apenas o valor fictício `https://e0-diagnostic.example.invalid/health`, cujo TLD `.invalid` é reservado para exemplos e não resolve publicamente.
2. O cliente exigirá configuração presente, URI válida e absoluta, esquema HTTPS, host, ausência de usuário/senha e ausência de fragmento.
3. O caminho `/api/v1/occurrences` será rejeitado explicitamente.
4. A requisição não conterá API key, cookies configurados pela aplicação, imagem, localização, UUID, identificador do aparelho ou qualquer dado de ocorrência.
5. O corpo de resposta não será armazenado, interpretado, renderizado ou registrado; somente código HTTP e classificação sanitizada serão expostos.
6. Logs e interface não exibirão query string ou credenciais acidentalmente presentes; mostrarão apenas classificação, código HTTP e, quando necessário, host sanitizado.

### Controles operacionais

1. Um destino funcional será fornecido fora do repositório por `--dart-define=E0_DIAGNOSTIC_URL=...` somente durante build/execução de validação.
2. O responsável pelo Validation Gate confirmará que o destino pertence a servidor simulado ou ambiente exclusivo de teste e que nenhuma URL de produção foi fornecida.
3. A URL não será cadastrada em tela, persistida nem tratada como configuração definitiva do aplicativo.
4. A evidência do gate será sanitizada e registrará a natureza de teste do destino sem expor query string, credenciais ou detalhes internos desnecessários.
5. Nenhuma URL funcional de produção ou credencial será versionada em documentação, exemplo ou código.

O aplicativo não detectará automaticamente se uma URL arbitrária pertence a produção e não usará domínio funcional inventado ou allowlist nesta fase.

## 17. Critérios técnicos de validação

A E0 estará tecnicamente pronta para apresentação no Validation Gate somente se todos os critérios abaixo forem demonstrados no Samsung Galaxy S25+:

| Área | Critério de aprovação |
|---|---|
| Ambiente | Versão Flutter, `flutter doctor -v`, toolchain Android, ADB e reconhecimento do Galaxy pelo ambiente executor foram verificados; qualquer bloqueio foi relatado sem reconfiguração não autorizada. |
| Build | Projeto criado na raiz com a identidade definida e build Android concluído sem incluir dependências ou ativos pertencentes às etapas posteriores. |
| Instalação e abertura | Aplicativo instalado, identificado e aberto sem encerramento inesperado; a tela aparece antes da resolução das permissões. |
| Serialização de permissões | Diálogo de câmera ocorre primeiro; localização somente pode ser solicitada após concessão ou recusa da câmera; retomadas não duplicam solicitações. |
| Câmera | Permissão solicitada quando necessária; preview da câmera traseira exibido após concessão. |
| Indisponibilidade da câmera | Negação ou indisponibilidade resulta em mensagem clara e não impede localização ou rede. |
| Localização | Permissão de localização precisa solicitada após a resolução da câmera e precisão concedida confirmada. |
| Dados de posição | Latitude, longitude e precisão reportada são exibidas quando há posição. |
| Velocidade | Valor é exibido quando o provedor o fornece; caso contrário, a ausência é explicitamente indicada e não reprova isoladamente a E0. |
| Indisponibilidade do GPS | Serviço desligado, permissão ausente/reduzida ou posição indisponível produz estado claro sem impedir câmera ou rede. |
| Validação técnica da URL | Configurações ausentes/inválidas, URI não absoluta, esquema não HTTPS, host ausente, credenciais, fragmento e caminho proibido são rejeitados antes da conexão. |
| HTTPS de teste | Uma requisição manual sem corpo, credenciais ou dados de ocorrência alcança um destino HTTPS confirmado humanamente como exclusivo de teste e apresenta o código recebido. |
| Resposta HTTP | Corpo nunca aparece em estado, tela, armazenamento ou logs; excesso ou ausência de término causa cancelamento controlado dentro de limites finitos. |
| Indisponibilidade de rede/destino | Falha é exibida sem travar a interface e sem ser representada como envio de ocorrência. |
| Segurança operacional | Gate confirma URL de teste fornecida fora do repositório, ausência de produção e evidência sanitizada. |
| Responsividade | Rolagem, botões, preview e atualização dos indicadores permanecem utilizáveis durante as operações. |
| Ciclo de vida | Alternar para segundo plano e retornar não mantém recursos inválidos, não duplica streams/diálogos e restaura os diagnósticos sem crash. |
| Limite de escopo | Ausência de detector, modelo, inferência, ocorrência, persistência, autenticação e integração com o contrato de ocorrências. |

Não há meta numérica de precisão, tempo de resposta, temperatura, bateria ou autonomia na E0. A precisão observada será registrada como evidência, não comparada com limite inventado. O limite de descarte do corpo HTTP será pequeno e finito, mas seu valor será escolhido na implementação porque não integra contrato de negócio.

## 18. Roteiro manual no Samsung Galaxy S25+

### Pré-condições de ambiente

1. Verificar a versão instalada do Flutter e registrar o resultado.
2. Executar `flutter doctor -v` e registrar a disponibilidade da toolchain Android.
3. Verificar a disponibilidade do ADB no ambiente que executará o Flutter.
4. Confirmar que o Samsung Galaxy S25+ com depuração USB autorizada é listado e acessível nesse mesmo ambiente.
5. Se o trabalho ocorrer via WSL, validar explicitamente a interoperabilidade entre WSL, ADB e o aparelho conectado ao Windows; não aceitar o reconhecimento apenas pelo ADB do Windows como prova automática de acesso pelo WSL.
6. Se qualquer item estiver ausente, relatar bloqueio ou orientar etapa manual. Não instalar, atualizar ou reconfigurar Flutter, Android SDK, drivers USB, WSL ou ADB sem autorização.

### Demais pré-condições

- Samsung Galaxy S25+ com bateria suficiente;
- aplicativo E0 ainda não instalado, ou dados/permissões removidos para validar a primeira execução;
- URL HTTPS de servidor simulado ou ambiente exclusivo de teste, sem autenticação e sem relação com ocorrências, fornecida fora do repositório;
- confirmação humana de que a URL não pertence a produção;
- mecanismo de captura de evidências definido: logs de comando, capturas de tela e, quando útil, gravação de tela.

### Execução nominal

1. Registrar versões de Flutter, Dart, Android SDK, plugins e identificação do dispositivo.
2. Criar futuramente o projeto diretamente na raiz com nome `pavimenta_ai_mobile`, organização `com.vitor` e somente Android, sem subdiretório duplicado; esta revisão de design não executa essa ação.
3. Executar a análise estática aplicável ao projeto E0 e guardar o resultado como evidência técnica, sem criar testes automatizados para esta etapa.
4. Gerar um build Android de depuração com a URL HTTPS de teste injetada por `--dart-define=E0_DIAGNOSTIC_URL=...` e guardar a saída completa do build.
5. Instalar o artefato no Galaxy S25+ e registrar o sucesso da instalação e o `applicationId` `com.vitor.pavimenta_ai_mobile`.
6. Abrir o aplicativo e confirmar que os três painéis aparecem imediatamente, antes da conclusão das permissões, sem travamento ou encerramento inesperado.
7. Confirmar que a câmera é a primeira solicitação apresentada e que nenhum diálogo de localização aparece simultaneamente.
8. Na solicitação de câmera, conceder acesso. Somente após sua conclusão, confirmar que a solicitação de localização pode aparecer.
9. Confirmar visualmente que o preview usa uma câmera traseira cobrindo a área delimitada.
10. Na solicitação de localização, selecionar uso durante o aplicativo e ativar a opção de localização precisa.
11. Em local com recepção adequada, aguardar a posição. Registrar latitude, longitude e precisão mostradas.
12. Observar a velocidade. Se o provedor não a fornecer, registrar corretamente “Não fornecida”; se houver valor, registrar sua exibição em metros por segundo.
13. Tocar em “Executar diagnóstico HTTPS”. Confirmar progresso, resposta do destino de teste e código HTTP, mantendo a interface utilizável.
14. Confirmar que nenhum conteúdo de resposta aparece na tela ou nos registros e que a evidência mostra apenas código/classificação sanitizados.
15. Aumentar temporariamente a escala de fonte e alternar orientação conforme permitido pelo aplicativo. Confirmar que informações e ações continuam acessíveis por rolagem, sem overflow relevante.
16. Enviar o aplicativo ao segundo plano durante inicialização e após os diagnósticos, depois retornar. Confirmar que não há diálogo duplicado, stream duplicado, tela congelada ou crash e que recursos são restaurados de modo controlado.

### Cenários de indisponibilidade

17. Em instalação limpa, negar a câmera e confirmar que somente depois da recusa a localização pode ser solicitada. Confirmar que GPS e rede continuam funcionais.
18. Negar a localização e confirmar mensagem clara, mantendo câmera e rede funcionais.
19. Revogar a câmera, reabrir/repetir o diagnóstico e confirmar mensagem clara sem impedir GPS e rede. Restaurar a permissão depois do registro.
20. Conceder somente localização aproximada e confirmar que a tela informa a ausência de localização precisa. Em seguida, conceder precisão para continuar.
21. Desativar o serviço de localização e confirmar a mensagem correspondente. Reativar e confirmar recuperação por nova tentativa.
22. Em uma condição sem posição disponível, confirmar “Aguardando posição” ou “Posição indisponível”, sem valores zero artificiais.
23. Ativar modo avião, executar novamente o diagnóstico HTTPS e confirmar a mensagem de rede ou destino indisponível. Desativar modo avião ao final.
24. Repetir o build com o host fictício `.invalid` e confirmar que a falha do destino é controlada. Não usar domínio de produção para esse cenário.
25. Se houver ambiente controlado com certificado inválido, confirmar a recusa TLS. Se não houver, marcar esse cenário como não executado, sem desabilitar TLS para forçar sucesso.
26. Configurar temporariamente cada classe inválida — valor ausente, URI relativa, não HTTPS, sem host, com usuário/senha, com fragmento e com caminho `/api/v1/occurrences` — e confirmar bloqueio antes da conexão.
27. Em servidor exclusivo de teste controlado, produzir corpo maior que o limite ou resposta que não termina e confirmar cancelamento controlado, sem conteúdo na interface ou nos logs. Se o ambiente não permitir o cenário, registrá-lo como não executado; não inventar endpoint funcional.

### Evidências e encerramento

28. Reunir: diagnóstico do ambiente, saída do build, instalação, captura da abertura imediata, ordem das permissões, preview traseiro, decisões de permissão, valores de GPS, resultado HTTPS, mensagens de indisponibilidade e observação do ciclo de vida/responsividade.
29. Registrar de modo sanitizado que a URL pertence a teste, foi fornecida fora do repositório e não é produção, sem expor query string, credencial ou detalhes internos desnecessários.
30. Preencher cada critério da seção 17 como aprovado, reprovado ou não executado, com referência à evidência.
31. Confirmar por inspeção de dependências, assets e interface que nenhum item excluído da E0 foi introduzido.
32. Apresentar o pacote de evidências no Validation Gate E0 e interromper o avanço. Qualquer reprovação autoriza apenas correções dentro da E0; E1 depende de aprovação explícita.

## 19. Riscos e limitações da E0

| Risco ou limitação | Mitigação na E0 |
|---|---|
| Diálogos de câmera e localização podem competir na primeira execução | `E0Controller` serializa a sequência: câmera primeiro, localização somente após concessão ou recusa. |
| Retomadas podem disparar inicializações e diálogos duplicados | Registrar solicitação em andamento, usar geração para invalidar callbacks antigos e reconciliar antes de reiniciar. |
| O Android pode conceder localização aproximada apesar da solicitação de precisão | Consultar a precisão autorizada e manter estado explícito de “precisão reduzida”. |
| GPS pode demorar ou falhar em ambiente interno | Diferenciar “aguardando” de erro e executar a validação nominal em área com recepção adequada. |
| Velocidade pode não ser fornecida ou permanecer zero em repouso | Exibir somente o valor válido reportado e aceitar “Não fornecida” como resultado legítimo. |
| A câmera pode estar ocupada, suspensa ou mudar após retorno do background | Descartar na pausa e redescobrir/reinicializar na retomada. |
| Uma requisição isolada não distingue perfeitamente falta de internet, DNS e host fora do ar | Usar mensagem combinada e não adicionar biblioteca de conectividade que também não comprovaria acesso ao destino. |
| O aplicativo não consegue determinar genericamente se a URL é de produção | Exigir confirmação humana e evidência sanitizada no Validation Gate; não criar allowlist ou domínio funcional. |
| O destino de teste pode estar indisponível durante o gate | Preparar previamente um ambiente exclusivo de teste e manter cenário fictício separado para validar falhas. |
| URL injetada em build pode ser extraída do APK | Usar somente destino de teste não secreto; nunca injetar produção ou credencial. |
| Resposta HTTP pode ser grande, infinita ou conter conteúdo não confiável | Nunca utilizar o conteúdo; aplicar limites finitos de tempo/volume e cancelar a conexão ao excedê-los. |
| Diferentes lentes traseiras podem ser expostas pelo aparelho | Selecionar a primeira câmera marcada como traseira; seleção avançada de lente não é objetivo da E0. |
| ADB do Windows e ADB do WSL podem enxergar dispositivos diferentes | Verificar o aparelho no mesmo ambiente que executará Flutter e relatar incompatibilidade sem reconfiguração não autorizada. |
| Não há metas numéricas de responsividade, precisão ou consumo | Registrar observações qualitativas sem inventar limiares de aprovação. |
| O smoke test não prova comportamento das etapas posteriores | Tratar o gate somente como redução de risco da infraestrutura Android básica. |

## 20. Decisões adiadas para E1 a E5

As etapas E1 a E5 são apenas fronteiras arquiteturais neste design:

- **E1:** integração do limite de detecção local; nenhum componente dessa integração existe na E0.
- **E2:** introdução do limite de criação em memória e dados associados; a E0 não cria nem prepara esses dados.
- **E3:** introdução do limite de persistência; a E0 não possui armazenamento ou fila.
- **E4:** introdução do limite de comunicação com o contrato de ocorrências e proteção de credenciais; o cliente diagnóstico da E0 não será tratado como essa integração.
- **E5:** introdução do limite de configuração e experiência operacional completa; a E0 mantém apenas controles diagnósticos básicos.

Interfaces, bibliotecas, formatos, fluxos e regras dessas etapas não são escolhidos neste documento. O código diagnóstico da E0 poderá ser substituído ou evoluído posteriormente, mas não deverá antecipar contratos futuros.

## 21. Correspondência com RF-00 e requisitos relacionados à E0

| Requisito | Cobertura no design E0 | Evidência prevista |
|---|---|---|
| RF-00.1–2 | Arquitetura e estrutura mínimas, identidade fixa, criação na raiz, Android exclusivo e verificação prévia do ambiente | Diagnóstico da toolchain; saídas de build e instalação; captura da aplicação aberta |
| RF-00.3–4 | Fluxo serial inicia pela câmera traseira, solicitação básica e mensagens de erro | Ordem dos diálogos, preview e cenários de permissão/indisponibilidade |
| RF-00.5–6 | Localização solicitada após a câmera e apresentação dos quatro dados diagnósticos | Captura dos valores e dos estados de permissão/serviço/posição |
| RF-00.7–8 | Requisição HTTPS exclusiva de teste, validações técnicas, controles humanos e estados de falha | Resultado HTTP sanitizado, confirmação do ambiente e cenários sem rede/destino |
| RF-00.9–10 | Limites explícitos e estrutura sem módulos posteriores | Inspeção de dependências, assets, diretórios e interface |
| RF-00.11 | Seções 17 e 18 definem critérios, roteiro e evidências no Galaxy S25+ | Checklist preenchido e evidências associadas |
| RF-00.12 | Interrupção obrigatória no Validation Gate | Registro de aprovação ou reprovação explícita |
| RF-01 | Suporte Android, execução no Galaxy S25+ e falhas controladas | Instalação, abertura e cenários de indisponibilidade sem crash |
| RF-03, parcela E0 | Preview básico traseiro sem inferência e permissão básica | Preview e negação/restauração da câmera |
| RF-05, parcela E0 | Uma tela com somente indicadores diagnósticos pertinentes à E0 | Captura integral da tela |
| RF-06, parcela E0 | Diagnóstico de localização sem criação de ocorrência | Valores de posição e mensagens de indisponibilidade |
| RF-23, parcela E0 | Ordem, escopo fechado, roteiro, evidências e bloqueio no gate | Checklist do gate e decisão explícita antes de E1 |
| RNF-04, parcela E0 | Preview, indicadores e ações assíncronas responsivos | Observação manual durante permissões, câmera, GPS, HTTP e rolagem |
| RNF-07, parcela E0 | Validação integral no Samsung Galaxy S25+ | Pacote de evidências produzido no dispositivo físico |

### Validation Gate da E0

O gate será considerado **aprovável** quando todos os critérios obrigatórios da seção 17 estiverem demonstrados no Samsung Galaxy S25+, as eventuais limitações estiverem registradas e a inspeção confirmar os limites de escopo. A velocidade poderá constar como “Não fornecida” quando esse for o resultado real do provedor; o comportamento deve estar visível e registrado.

A aprovação também exige confirmação humana de que a URL funcional pertence exclusivamente a teste, nenhuma URL de produção foi fornecida, o valor funcional permaneceu fora do repositório e a evidência foi sanitizada. O aplicativo valida apenas propriedades técnicas da URI e rejeita o caminho de ocorrências; ele não classifica ambientes automaticamente.

O gate será **reprovado** se houver falha de build, instalação ou abertura; solicitações simultâneas ou duplicadas; ausência do preview traseiro após autorização; impossibilidade não explicada de solicitar localização precisa ou apresentar posição disponível; ausência do diagnóstico HTTPS; corpo de resposta exposto; recurso não liberado; crash; interface impraticável; exposição de destino de produção/credencial; ou inclusão de qualquer funcionalidade posterior.

Após a apresentação, o trabalho deverá parar. Somente a aprovação explícita do responsável autoriza iniciar E1; em caso de reprovação, serão permitidas apenas correções pertencentes à E0.
