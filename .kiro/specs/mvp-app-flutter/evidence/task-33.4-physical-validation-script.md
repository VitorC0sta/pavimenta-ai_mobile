# Roteiro preparado — Tarefa 33.4: lifecycle, wake lock, interface, navegação e regressão E0

## Uso, estado e limite

Este roteiro prepara exclusivamente a futura coleta de evidências no Samsung Galaxy S25+ para **lifecycle operacional, wake lock, responsividade, acessibilidade, navegação Operação–Diagnóstico, exclusão mútua de câmera/GPS e regressão do Diagnóstico E0**. Todos os passos físicos abaixo permanecem **não executados**.

A preparação não abre o aplicativo, não executa o Validation Gate E1, não aprova comportamento físico, não altera o APK e não modifica evidências históricas da E0. Não cobre o fluxo nominal e os dados da ocorrência de 33.2, permissões/cooldown/JPEG/limpeza de 33.3, nem a inspeção negativa de E2–E5 de 33.5. Uma captura poderá ser iniciada somente nos cenários de interrupção para observar cancelamento por lifecycle/navegação; seus dados não serão reavaliados aqui.

Para cada cenário, registrar `Aprovado`, `Reprovado`, `Inconclusivo` ou `Não executado`, IDs de evidência e observação factual. `Inconclusivo` não equivale a aprovado. Evidência automatizada deve ser identificada como técnica, nunca como observação física.

## 1. Pré-condições, privacidade e restauração do aparelho

- [ ] Usar o Samsung Galaxy S25+ (`SM-S936B`) e o pacote `com.vitor.pavimenta_ai_mobile` instalado pela tarefa 33.1.
- [ ] Confirmar que o APK corresponde ao SHA-256 `6896EFDBFA40C80052B164B88B7DFFE9F201702C5CFDB9A4497A1F21D6D9B95B`.
- [ ] Preservar os arquivos históricos E0, especialmente `task-15-validation-gate.md`; novas observações são evidências da integração E1, não reescrita do gate E0.
- [ ] Conceder câmera e localização precisa e aguardar Operação com câmera **Pronta**, **GPS pronto** e botão habilitado, salvo quando o cenário exigir outro estado.
- [ ] Apontar a câmera traseira para cena neutra sem pessoas, placas, documentos ou endereços identificáveis.
- [ ] Redigir coordenadas, serial do aparelho, notificações e demais dados pessoais antes de incluir qualquer imagem no pacote.
- [ ] Usar gravação de tela para transições curtas. Como a gravação pode impedir ou alterar o timeout da tela, **não usá-la como única evidência de wake lock**; para WL01/WL02, preferir observação por uma segunda câmera sem enquadrar dados pessoais, ou registro manual com cronômetro externo.
- [ ] Anotar o valor original de **Configurações > Visor > Tempo limite da tela** e selecionar temporariamente o menor valor disponível (esperado: 15 s).
- [ ] Desabilitar temporariamente qualquer opção global **Manter tela ligada durante carregamento**, rotina de economia/automação ou acessório que possa impedir o timeout; manter o aparelho desconectado do carregador durante WL01/WL02 quando seguro.
- [ ] Anotar os valores originais de tamanho da fonte, zoom/tamanho da tela, rotação automática, TalkBack e correção de cor.
- [ ] Ao final, restaurar exatamente timeout, opções de desenvolvedor, fonte, zoom, rotação, TalkBack e correção de cor.
- [ ] Não executar `pm clear`, reinstalar, rebuildar, alterar toolchain ou introduzir instrumentação no aplicativo durante 33.4.

### Observabilidade permitida

O APK não exibe um indicador textual de wake lock, owner da câmera, owner do GPS, quantidade de streams ou número de callbacks. Assim:

- tela permanecer acesa/apagar é evidência física do **efeito** do wake lock, não de seu estado interno;
- preview e GPS que deixam uma rota e reaparecem na outra sustentam a troca funcional de recursos, mas não provam sozinhos a ordem exata ou ausência de sobreposição de poucos milissegundos;
- ordem de `wake lock off -> GPS release -> camera release -> rota E0` e máximos de um owner/stream são comprovados pelos testes de controlador/navegação;
- cancelamento de callback obsoleto, limpeza e ausência de commit interno são comprovados por testes, correlacionados ao cenário físico interrompido;
- ausência de crash, congelamento, diálogo duplicado, preview inválido ou atualização aparentemente duplicada deve ser registrada fisicamente, sem alegar contagem interna não exposta.

## 2. Lifecycle operacional

### 33.4-LC01 — pausa e retomada nominal da Operação

1. Iniciar gravação `33.4-S01-lifecycle-operacao.mp4` com Operação pronta e contador anotado como `N`.
2. Pressionar Home para colocar o aplicativo em segundo plano; aguardar pelo menos 5 s sem encerrar o processo.
3. Abrir novamente o aplicativo pela tela de recentes.
4. Repetir o ciclo três vezes, incluindo uma alternância rápida e uma permanência superior ao timeout configurado.
5. Confirmar e registrar:
   - [ ] nenhuma ação de registro ocorre em segundo plano;
   - [ ] no retorno, câmera/GPS passam por estado de inicialização antes de voltar a **Pronta**/**GPS pronto**;
   - [ ] o preview traseiro volta a atualizar e o botão só reabilita após readiness;
   - [ ] não surge diálogo de permissão já resolvida;
   - [ ] não há preview congelado, controlador inválido, crash, congelamento ou mensagem repetida;
   - [ ] contador permanece `N` e nenhuma ocorrência é criada pelo lifecycle;
   - [ ] após estabilização, rolagem, botão e navegação continuam utilizáveis.
6. Evidência mínima: vídeo da saída/retorno e captura `33.4-E01-operacao-retomada.png` com câmera/GPS recuperados e coordenadas redigidas.

### 33.4-LC02 — interrupção durante registro em andamento

1. Com readiness válido, iniciar gravação e anotar contador `N`.
2. Tocar **Registrar buraco** e, enquanto **Registrando…** estiver visível, pressionar Home imediatamente.
3. Retornar ao aplicativo e aguardar estabilização.
4. Se a operação terminar antes da saída e o contador mudar para `N + 1`, classificar a tentativa como `Inconclusiva` para cancelamento e repetir no máximo duas vezes; não declarar falha de lifecycle por uma operação que concluiu antes da pausa.
5. Quando a pausa ocorrer durante busy, confirmar:
   - [ ] no retorno aparece estado/feedback de cancelamento controlado, quando ainda observável;
   - [ ] não aparece ocorrência tardia nem novo incremento depois da invalidação;
   - [ ] o botão permanece bloqueado até câmera/GPS serem readquiridos;
   - [ ] a UI volta ao estado utilizável sem crash;
   - [ ] eventual artefato temporário fica sujeito ao inventário/limpeza já definido em 33.3, sem reinspecionar JPEG aqui.
6. Evidência: `33.4-S02-cancelamento-lifecycle.mp4` e contador antes/depois. Correlacionar callback obsoleto, ownership e limpeza aos testes técnicos; não inferi-los somente pela UI.

### 33.4-LC03 — pausa na rota Diagnóstico E0

1. Abrir **Diagnóstico**, aguardar preview e localização estabilizarem e anotar o estado HTTPS sem expor URL.
2. Pressionar Home, aguardar 5 s e retornar pela tela de recentes; repetir duas vezes.
3. Confirmar:
   - [ ] E0 permanece na rota Diagnóstico após retorno;
   - [ ] câmera e localização E0 pausam/retomam sem diálogo duplicado;
   - [ ] preview e valores diagnósticos se recuperam sem stream aparentemente duplicado;
   - [ ] não há crash, congelamento ou controlador inválido;
   - [ ] o cliente HTTPS E0 continua separado e nenhum dado de ocorrência aparece.
4. Evidência: `33.4-S03-lifecycle-e0.mp4` e captura sanitizada `33.4-E02-e0-retomada.png`.

## 3. Wake lock restrito à Operação ativa

### 33.4-WL01 — Operação ativa mantém a tela ligada

1. Confirmar timeout mínimo, opção global “manter ligada” desabilitada, aparelho fora do carregador e Operação como rota corrente em `resumed`.
2. Deixar câmera/GPS estabilizarem, iniciar cronômetro externo e não tocar no aparelho por `timeout configurado + 15 s`.
3. Confirmar que a tela não escurece nem bloqueia automaticamente durante esse intervalo.
4. Repetir uma vez após uma retomada de LC01 para verificar readquisição.
5. Evidência mínima: `33.4-E03-wakelock-operacao.txt` com timeout configurado, duração observada, condições de energia e resultado; vídeo externo opcional sanitizado.

**Critério:** aprovar o efeito físico somente se a tela permanecer ativa além do timeout nas duas observações e não houver fator global concorrente conhecido. Se gravação de tela, carregamento ou configuração global puder manter o display aceso, marcar `Inconclusivo`.

### 33.4-WL02 — wake lock é liberado fora da Operação

Executar os ramos separadamente:

1. **Diagnóstico corrente:** a partir da Operação, tocar **Abrir Diagnóstico**, aguardar o título **Pavimenta AI — E0**, não interagir por `timeout + 15 s` e observar se a tela apaga/bloqueia.
2. **Segundo plano:** voltar à Operação, pressionar Home e aguardar `timeout + 15 s`; observar se a tela apaga/bloqueia normalmente.
3. Após cada ramo, desbloquear/retomar e confirmar que a rota correta se recupera sem crash.
4. Voltar do Diagnóstico à Operação, aguardar readiness e repetir WL01 uma vez para confirmar que a manutenção de tela é reativada somente na Operação corrente.
5. Evidência: `33.4-E04-wakelock-liberado.txt`, contendo timeout, duração e resultado de cada ramo, sem alegar estado interno do plugin.

**Critério:** o display deve poder seguir o timeout na rota Diagnóstico e em segundo plano. Resultado diferente deve ser repetido após excluir reprodução de mídia, carregamento, gravação de tela e políticas globais; persistindo, registrar `Reprovado` ou `Inconclusivo` com causa.

### 33.4-WL03 — balanceamento e falhas do plugin

Não provocar falha de `wakelock_plus` no aparelho nem alterar código. Usar evidência automatizada para:

- habilitação somente quando `visible && foreground && resumed && currentRoute`;
- chamadas idempotentes e balanceadas em pausa/retomada/navegação;
- compensação quando `enable` falha;
- estado bloqueado e ausência de repetição quando `disable` falha.

Esses itens recebem tipo **teste automatizado**, não observação física.

## 4. Responsividade e layout

### 33.4-RP01 — interação durante inicialização, processamento e retomada

1. Em abertura limpa da sessão, enquanto câmera/GPS inicializam, rolar até o botão e retornar ao topo.
2. Com readiness, iniciar um registro e, durante **Registrando…**, rolar entre preview, GPS, sessão e processamento sem repetir o toque.
3. Executar LC01 e, durante a readquisição, repetir a rolagem.
4. Confirmar em cada fase:
   - [ ] animações e preview continuam atualizando;
   - [ ] rolagem responde sem saltos impeditivos;
   - [ ] textos e botões recebem toque quando habilitados;
   - [ ] busy bloqueia apenas novo registro, não a atualização da interface;
   - [ ] não há acúmulo de comandos, ANR, congelamento ou crash.
5. Evidência: `33.4-S04-responsividade.mp4` com coordenadas redigidas.

### 33.4-RP02 — orientação, fonte e zoom representativos

Executar a tabela, restaurando o estado nominal entre combinações:

| Caso | Orientação | Fonte | Zoom/tamanho da tela |
|---|---|---|---|
| A | retrato | padrão | padrão |
| B | paisagem | padrão | padrão |
| C | retrato | maior disponível | maior disponível |
| D | paisagem | maior disponível | maior disponível |

Para cada caso:

1. Abrir Operação, percorrer toda a tela por rolagem e acessar **Abrir Diagnóstico**.
2. No Diagnóstico, percorrer os três painéis e voltar.
3. Confirmar:
   - [ ] nenhum overflow visual amarelo/preto, texto cortado de modo irrecuperável ou elemento sobreposto;
   - [ ] título, banner, status, valores, contador, processamento e botões permanecem alcançáveis;
   - [ ] textos quebram linha e não exigem largura fixa impossível;
   - [ ] preview mantém área delimitada e não expulsa os controles;
   - [ ] rotação não cria segunda rota, diálogo ou stream aparente;
   - [ ] o foco/estado atual continua compreensível após rotação.
4. Evidências: `33.4-E05a` a `33.4-E05d` (capturas sanitizadas) e observações por caso.

## 5. Acessibilidade e significado além da cor

### 33.4-A11Y01 — navegação e anúncios com TalkBack

1. Ativar TalkBack pelas configurações Android e retornar à Operação.
2. Percorrer a tela por gestos de próximo elemento, sem depender da posição visual.
3. Confirmar que são anunciados de forma compreensível:
   - [ ] título **Operação** e ação **Abrir Diagnóstico**;
   - [ ] banner como **Modo de registro manual. Detecção automática indisponível.**;
   - [ ] preview como disponível/indisponível;
   - [ ] títulos e badges com prefixo **Status**;
   - [ ] latitude, longitude, precisão e velocidade por seus rótulos, sem versionar valores;
   - [ ] contador e estado de processamento;
   - [ ] botão como **Registrar buraco por confirmação manual**, com estado habilitado/desabilitado e hint adequado.
4. Acionar o registro por duplo toque somente se readiness estiver válido e confirmar anúncio/alcance do feedback de sucesso, cooldown ou erro como região viva, sem exigir cor.
5. Acionar **Abrir Diagnóstico**, percorrer os painéis E0 e confirmar os rótulos semânticos de câmera, localização e rede HTTPS; voltar pelo comando padrão do Android.
6. Evidência: registro de observação `33.4-E06-talkback.txt`; gravação com áudio somente se não capturar notificações ou dados pessoais.

### 33.4-A11Y02 — contraste funcional e estados não dependentes só de cor

1. Com TalkBack desativado, observar os estados nominal, inicializando, bloqueado/cancelado e sucesso/erro que ocorrerem nos cenários deste roteiro.
2. Confirmar que cada estado possui texto e/ou ícone significativo além de verde, vermelho ou âmbar.
3. Ativar temporariamente correção de cor/tons de cinza e confirmar que banner, badges, feedback e botão continuam distinguíveis por rótulo, contorno, ícone ou estado habilitado.
4. Confirmar que o botão âmbar usa foreground escuro legível e que texto principal permanece legível nos painéis escuros, sem declarar medição numérica de contraste que não foi feita.
5. Evidência: `33.4-E07-estados-sem-cor.png` opcional e registro factual. Medição automatizada de contraste não deve ser alegada pela inspeção visual.

## 6. Navegação e exclusão mútua de recursos

### 33.4-NAV01 — Operação → Diagnóstico → Operação

1. Com Operação pronta, iniciar gravação e anotar câmera/GPS prontos e contador `N`.
2. Tocar uma única vez em **Abrir Diagnóstico**.
3. Confirmar que a rota de destino abre com título **Pavimenta AI — E0** e aviso **“Smoke test E0: nenhum dado de ocorrência é criado ou enviado.”**.
4. Aguardar câmera e GPS do Diagnóstico estabilizarem e confirmar preview/posição conforme E0REG01.
5. Voltar pelo gesto/botão Android.
6. Confirmar que Operação primeiro reinicializa e somente depois volta a câmera **Pronta**, **GPS pronto** e botão habilitado; contador continua `N`.
7. Confirmar ausência de `CameraException`, tela preta persistente, diálogo concorrente, crash ou congelamento.
8. Evidência: `33.4-S05-navegacao-recursos.mp4` e capturas de cada rota.

**Limite de inferência:** a gravação mostra handoff funcional, mas não prova a ordem interna completa. Correlacionar com os testes que exigem liberação E1 antes de construir E0 e dispose E0 antes de readquirir E1.

### 33.4-NAV02 — repetição e toque múltiplo na ação Diagnóstico

1. A partir de Operação pronta, tocar rapidamente **Abrir Diagnóstico** duas ou três vezes.
2. Confirmar que apenas uma rota/sessão Diagnóstico aparece.
3. Voltar e repetir o ciclo completo Operação–Diagnóstico–Operação três vezes.
4. Confirmar:
   - [ ] cada entrada mostra uma sessão E0 funcional, não uma tela antiga congelada;
   - [ ] nenhum empilhamento de rotas exige múltiplos retornos por um único ciclo;
   - [ ] não há solicitação duplicada de permissão já concedida;
   - [ ] não há dois previews, atualização GPS acelerada/aparentemente duplicada ou erro de câmera ocupada;
   - [ ] Operação recupera câmera/GPS uma vez por retorno observável e continua responsiva.
5. Evidência: `33.4-S06-navegacao-repetida.mp4`.

A unicidade exata de owners, streams e autoridades de permissão deve ser atribuída ao teste `operation_diagnostic_navigation_test.dart`, não à aparência da UI.

### 33.4-NAV03 — navegação solicitada durante busy

1. Com contador `N`, tocar **Registrar buraco** e imediatamente **Abrir Diagnóstico** enquanto **Registrando…** ainda estiver visível.
2. Se o registro concluir antes da ação de navegação, marcar a tentativa `Inconclusiva` para cancelamento e não interpretar `N + 1` como falha.
3. Quando a navegação invalidar uma operação ainda ativa, confirmar:
   - [ ] não abre Diagnóstico antes de a transição terminar de forma controlada;
   - [ ] nenhuma ocorrência tardia aparece após a troca;
   - [ ] Diagnóstico abre sem câmera ocupada;
   - [ ] ao voltar, Operação recupera readiness sem crash.
4. Correlacionar ordem, barreira de limpeza, callback obsoleto e contador ao teste automatizado.
5. Evidência: `33.4-S07-navegacao-durante-busy.mp4`.

## 7. Regressão do Diagnóstico E0 integrado

### 33.4-E0REG01 — conteúdo e fluxo nominal preservados

1. Abrir Diagnóstico pela Operação.
2. Confirmar fisicamente:
   - [ ] título **E0 — Diagnóstico Android** e aviso de que nenhum dado de ocorrência é criado/enviado;
   - [ ] painéis independentes de **Câmera traseira**, **Localização precisa** e **Rede e destino HTTPS**;
   - [ ] preview usa câmera traseira e permanece responsivo;
   - [ ] localização apresenta latitude, longitude, precisão e velocidade em `m/s` quando fornecida, ou **Não fornecida**;
   - [ ] botões de nova tentativa e **Executar diagnóstico HTTPS** continuam acessíveis;
   - [ ] nenhuma ocorrência, contador E1, UUID, cooldown, JPEG, credencial ou envio aparece dentro do Diagnóstico.
3. Sanitizar coordenadas e cena da câmera nas evidências.
4. Evidência: `33.4-S08-regressao-e0.mp4`, `33.4-E08-e0-paineis.png` e referência separada ao histórico aprovado `task-15-validation-gate.md`.

### 33.4-E0REG02 — mensagens e lifecycle E0

1. Executar LC03 para pausa/retomada.
2. Reutilizar somente resultados reais de indisponibilidade observados durante 33.4; não revogar permissões novamente, pois o roteiro específico pertence a 33.3.
3. Confirmar que qualquer indisponibilidade observada produz mensagem controlada e não bloqueia painéis independentes.
4. Correlacionar mensagens de serviço, permissão, precisão, posição, TLS e rede aos testes E0 existentes.
5. Não alterar nem reinterpretar os relatos históricos do gate E0; registrar tudo como nova regressão da integração E1.

### 33.4-E0REG03 — HTTPS no APK instalado e limitação conhecida

O APK de hash `6896...B95B` foi construído sem `--dart-define`; conforme tarefa 32.1, `E0_DIAGNOSTIC_URL` usa o destino fictício `.invalid`. Portanto:

1. Tocar **Executar diagnóstico HTTPS** uma vez.
2. Confirmar progresso local, botão temporariamente indisponível e resultado controlado de destino inacessível/configuração conforme o comportamento real, sem crash e sem corpo/headers na UI.
3. Não registrar o host, query string ou qualquer URL completa.
4. **Não declarar sucesso HTTPS físico** para este APK. O HTTP `204` pertence ao gate histórico E0 e não deve ser transplantado para esta execução.
5. Correlacionar preservação lógica de sucesso `204`, validações, mensagens e cleanup ao teste `test/e0/e0_regression_test.dart`.
6. Se o Gate E1 exigir nova comprovação física de sucesso HTTPS no artefato integrado, registrar bloqueio: será necessário, fora de 33.4 e mediante autorização, gerar/identificar outro APK com URL HTTPS exclusiva de teste fornecida externamente, registrar novo hash, reinstalar e repetir a evidência aplicável. Não substituir silenciosamente o APK atual.

## 8. Matriz de evidência técnica automatizada

| Propriedade | Evidência existente |
|---|---|
| Operação ativa exige visível + foreground + `resumed` + rota corrente | `test/operation/operation_controller_test.dart` |
| Bloqueio fora de `resumed`, geração obsoleta sem efeito e limpeza | `test/operation/operation_controller_test.dart` |
| Wake lock balanceado/idempotente e compensação de falhas | `test/operation/operation_controller_test.dart` |
| Layout estreito, escala de texto 2x, semântica e mensagens | `test/operation/operation_screen_test.dart` |
| Liberação completa antes do push e dispose E0 antes da retomada | `test/operation/operation_screen_test.dart` |
| Uma sessão por toques repetidos e máximo de um owner/stream | `test/operation/operation_diagnostic_navigation_test.dart` |
| Câmera antes de localização e snapshots invalidados no release | `test/infrastructure/operational_adapters_test.dart` |
| Preview, GPS, HTTPS, mensagens e lifecycle preservados na E0 | `test/e0/e0_regression_test.dart` |

A saída consolidada da tarefa 31 pode ser citada somente com suas ressalvas. Durante a preparação de 33.4, executar uma suíte direcionada com esses cinco arquivos e registrar o resultado em `task-33.4-evidence-record.md`.

## 9. Encerramento

- [ ] Restaurar todas as configurações Android anotadas na seção 1.
- [ ] Confirmar que câmera e localização precisa continuam concedidas conforme o estado anterior.
- [ ] Parar e revisar gravações; redigir coordenadas, notificações, rostos, placas e outros dados antes de eventual inclusão.
- [ ] Manter mídia bruta fora do repositório sob controle local.
- [ ] Preencher `task-33.4-evidence-record.md` sem marcar o Validation Gate E1 como aprovado.
- [ ] Registrar como `Inconclusivo` qualquer cenário dependente de timing que não tenha ocorrido enquanto busy; usar o teste correspondente sem inventar observação física.
- [ ] Parar após 33.4; não executar 33.5, 34 ou E2.

## Referências normativas

- Tarefa: `tasks.md`, item 33.4.
- Requisitos centrais: RF-00.2–5, RF-00.6–10, RF-00.15 e RF-00.17–22; RF-03.9 e RF-03.11; RF-05.1–4 e RF-05.9–11; RF-21.1–7; RF-23.7 e RF-23.19–20; RNF-04.1–3 e RNF-04.6; RNF-07.1–2 e RNF-07.10; RNF-08.1–14.
- Design E1: E1.2–E1.3, E1.18–E1.25, E1.27, E1.28 passos 18–24 e E1.29.
- Design E0 preservado: seções 7–13, 17–18 e Validation Gate E0.
- APK instalado: `task-33.1-apk-installation.md`.
- Build sem URL funcional: `task-32.1-android-debug-build.md`.
- Histórico E0 imutável: `task-15-validation-gate.md`.

## Limitações conhecidas para a execução futura

1. Wake lock interno, owners de câmera/GPS, quantidade de streams e ordem exata de liberação/aquisição não são exibidos; a evidência física observa efeitos, e os testes comprovam os contratos internos.
2. Interrupção durante busy pode ser difícil porque captura/preparação podem concluir rapidamente; tentativa concluída antes da pausa/navegação é inconclusiva, não reprovação.
3. TalkBack, correção de cor, escala máxima e rotação precisam ser restaurados após o roteiro.
4. O APK instalado não contém URL HTTPS funcional E0; ele permite apenas observar o tratamento controlado do destino fictício. Nova evidência física de sucesso HTTPS exigiria outro artefato autorizado e rastreado fora desta tarefa.
5. A regressão E0 desta tarefa produz evidência nova da integração; nunca modifica a decisão ou os relatos históricos de E0.
6. O diretório da spec não contém `.config` nem `.config.kiro`; a execução foi tratada como feature a partir dos três documentos normativos.

## Declaração obrigatória

Este roteiro é preparação de evidência. Testes e inspeção não substituem observação física dos efeitos visíveis no Galaxy S25+, e observação da UI não comprova estados internos não expostos. A aprovação da E1 pertence exclusivamente à tarefa 34 e exige decisão explícita do usuário.