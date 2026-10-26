# Roteiro preparado — Tarefa 33.3: permissões, cooldown e imagem E1

## Uso, estado e limite

Este roteiro prepara exclusivamente a futura coleta de evidências no Samsung Galaxy S25+ para **permissões, blockers, concorrência, cooldown por tempo/distância/regra OR, JPEG 85, orientação, proporção, máximo `1280x720`, máximo 2 MiB, rejeição e limpeza temporária**. Todos os passos físicos abaixo permanecem **não executados**.

A preparação não executa o Validation Gate E1, não aprova comportamento físico, não altera o aplicativo e não inicia E2. Não cobre o fluxo nominal completo de 33.2 nem valida lifecycle, wake lock, responsividade, acessibilidade, navegação/exclusão mútua ou regressão E0 de 33.4, exceto quando uma transição for usada estritamente para observar a limpeza de uma imagem E1.

Para cada cenário, registrar `Aprovado`, `Reprovado`, `Inconclusivo` ou `Não executado`, os IDs das evidências e uma observação factual. `Inconclusivo` não equivale a aprovado. Não registrar coordenadas integrais, serial do aparelho, caminho privado completo, bytes da imagem ou mídia com pessoas/placas.

## 1. Pré-condições e instrumentos

- [ ] Usar o Samsung Galaxy S25+ (`SM-S936B`) e o pacote `com.vitor.pavimenta_ai_mobile` instalado na tarefa 33.1.
- [ ] Confirmar que o APK corresponde ao SHA-256 `6896EFDBFA40C80052B164B88B7DFFE9F201702C5CFDB9A4497A1F21D6D9B95B`.
- [ ] Usar somente a rota **Operação**, salvo a transição explicitamente indicada para verificar encerramento da ownership E1.
- [ ] Posicionar o aparelho de forma segura e estável, sem conduzir veículo, com um alvo assimétrico neutro (por exemplo, folha com seta “PARA CIMA”) diante da câmera traseira.
- [ ] Preparar gravação de tela para os cenários de blockers, concorrência e cooldown.
- [ ] Preparar Android Studio Device Explorer, ou ferramenta local equivalente já disponível, somente para o APK debug. Inspecionar o namespace privado relativo `cache/e1_images_v1` sem registrar o caminho privado completo.
- [ ] Antes de cada inventário, anotar apenas quantidade, tipo pelo nome (`source`/`prepared`), tamanho e um identificador sanitizado/hash; não copiar a imagem para o repositório.
- [ ] Se for necessário exportar um JPEG para inspeção, usar diretório local controlado fora do repositório, conferir propriedades, calcular hash e apagar a cópia ao concluir.
- [ ] Alterar permissões pelo painel Android **Informações do app > Permissões**. Não limpar dados do aplicativo nem executar `pm clear` sem autorização explícita do responsável.
- [ ] Entre cenários de permissão, restaurar câmera e localização precisa e aguardar a Operação voltar a `Pronta`/`GPS pronto` antes do cenário seguinte.

### Protocolo de inventário privado

Em cada ponto indicado, registrar somente:

| Campo | Valor permitido |
|---|---|
| Quantidade de `e1_source_*.capture` | número |
| Quantidade de `e1_prepared_*.jpg` | número |
| Tamanho do JPEG preparado | bytes |
| Identidade sanitizada | hash SHA-256 ou rótulo local; sem path |

A presença de arquivo `source` após a conclusão, a permanência de mais de um `prepared` após substituição ou artefato após o encerramento da responsabilidade E1 reprova o item correspondente. Arquivos não reconhecidos não devem ser removidos nem atribuídos à E1.

## 2. Permissões e blockers

### 33.3-P01 — câmera recusada

1. Com o app fora de foco, remover a permissão de câmera nas configurações Android.
2. Retornar à Operação e observar a solicitação/resultado da câmera antes da localização quando houver diálogo.
3. Recusar a câmera.
4. Confirmar:
   - [ ] o preview não fica disponível;
   - [ ] o painel mostra câmera indisponível e explica que o registro manual ficará indisponível;
   - [ ] **Registrar buraco** permanece desabilitado;
   - [ ] GPS/interface continuam responsivos;
   - [ ] nenhum contador é incrementado e o inventário privado não muda.
5. Repetir conforme permitido pelo Android para a negação permanente e confirmar orientação para abrir as configurações do Android. Se o sistema não oferecer uma segunda modalidade, configurar manualmente “Não permitir” e reabrir.
6. Evidência: `33.3-S01-permissao-camera.mp4`, `33.3-E01-camera-bloqueada.png` e inventário antes/depois.

**Critério estrito:** mensagem genérica sem orientação adequada deve ser registrada como reprovação para RF-20.3/RF-20.5, ainda que o botão permaneça corretamente bloqueado.

### 33.3-P02 — localização recusada, reduzida, serviço desligado e posição indisponível

Executar os subcenários separadamente, restaurando o estado nominal entre eles:

1. **Recusa temporária:** manter câmera autorizada, remover permissão de localização, retornar ao app e recusar. Confirmar botão desabilitado, ausência de ocorrência/arquivo novo e texto que explique que ocorrências não podem ser criadas.
2. **Recusa permanente:** bloquear a permissão nas configurações Android. Confirmar botão desabilitado e orientação para habilitar localização precisa nas configurações.
3. **Precisão reduzida:** conceder localização aproximada, mas não precisa. Confirmar estado de precisão reduzida/localização precisa necessária e botão desabilitado.
4. **Serviço desligado:** com permissão concedida, desligar o serviço de localização. Confirmar estado de serviço desativado, botão desabilitado e câmera/interface ainda utilizáveis.
5. **Posição indisponível:** em condição controlada sem fix válido, confirmar posição indisponível, valores não inventados e botão desabilitado.
6. Evidências: `33.3-S02-permissao-gps.mp4`, capturas `33.3-E02a` a `33.3-E02e` e inventários antes/depois.

**Critério estrito:** cada condição deve apresentar significado específico. Se a implementação reduzir negação, precisão reduzida ou serviço desligado apenas a “Posição indisponível”, registrar reprovação do subcenário, não aprovação parcial da mensagem.

### 33.3-P03 — blocker direto

1. Em cada estado bloqueado acima, tentar acionar o botão somente se a plataforma de acessibilidade permitir foco; não contornar programaticamente o estado desabilitado.
2. Confirmar contador inalterado, ausência de processamento e inventário privado inalterado.
3. Correlacionar com os testes de `OperationState`/`OperationController`, que exercitam a chamada direta bloqueada sem depender do widget.

A impossibilidade de tocar um botão Material desabilitado é comportamento esperado; a evidência visual comprova o blocker e a evidência automatizada comprova ausência de efeito numa invocação direta.

## 3. Concorrência e single-flight

### 33.3-C01 — toques simultâneos/repetidos

1. Restaurar câmera, localização precisa e readiness; registrar contador inicial `N` e inventário inicial.
2. Iniciar gravação de tela em alta taxa disponível.
3. Acionar **Registrar buraco** com dois toques quase simultâneos (duas pessoas/dedos) e repetir toques enquanto aparecer **Registrando…**.
4. Aguardar conclusão sem navegar ou pausar.
5. Confirmar:
   - [ ] o primeiro aceite desabilita imediatamente o botão;
   - [ ] existe no máximo uma sequência de processamento;
   - [ ] o contador termina em `N + 1`, nunca acima;
   - [ ] ao final não existe `source` e existe no máximo um novo `prepared` sob ownership da ocorrência corrente;
   - [ ] não há crash ou UI bloqueada.
6. Evidência: `33.3-S03-single-flight.mp4`, `33.3-E03-contador-unico.png`, inventários antes/depois e teste `accepts only one operation from concurrent taps`.

A gravação física demonstra a UI e o contador; a asserção de uma única chamada de captura é técnica e deve ser correlacionada ao teste automatizado, pois a UI não expõe contagem interna de `takePicture()`.

## 4. Cooldown de 5 segundos OU 15 metros

### 33.3-CD01 — rejeição quando tempo **e** distância estão abaixo

1. Criar uma ocorrência válida e registrar contador `N`, horário local sanitizado e inventário.
2. Sem mover o aparelho, tocar novamente bem antes de 5 segundos.
3. Conferir pelas coordenadas exibidas localmente que o deslocamento calculado permaneceu abaixo de 15 m. Não versionar as coordenadas; registrar apenas “`< 15 m`”.
4. Confirmar:
   - [ ] status **Ignorado por cooldown**;
   - [ ] feedback **“Registro ignorado: tempo e distância ainda abaixo dos mínimos.”**;
   - [ ] descrição **“Nenhuma imagem, UUID ou ocorrência foi criada.”**;
   - [ ] contador permanece `N`;
   - [ ] inventário e identidade do JPEG preparado permanecem inalterados; nenhum `source` aparece após o cenário.
5. Se jitter do GPS indicar 15 m ou mais, marcar a tentativa `Inconclusiva`, estabilizar a posição e repetir; não classificar uma nova ocorrência permitida por distância como falha da regra.
6. Evidência: `33.3-S04-cooldown-bloqueado.mp4`, `33.3-E04-cooldown.png` e inventários antes/depois.

### 33.3-CD02 — permissão por tempo (ramo OR)

1. Após uma ocorrência válida, manter deslocamento abaixo de 15 m e aguardar pelo menos 5 segundos, medidos por cronômetro visível na gravação.
2. Tocar **Registrar buraco**.
3. Confirmar processamento concluído e contador `N + 1`, mesmo com distância abaixo de 15 m.
4. Confirmar substituição controlada do JPEG: o anterior deixa de existir e apenas o novo `prepared` permanece.
5. Evidência: `33.3-S05-cooldown-tempo.mp4`, `33.3-E05-tempo-permite.png` e inventário/hash antes/depois.

### 33.3-CD03 — permissão por distância antes de 5 segundos (ramo OR)

A observação física é **opcional** e só pode ocorrer em percurso a pé, controlado e seguro, sem condução:

1. Obter uma ocorrência de referência.
2. Posicionar-se previamente para que o deslocamento entre snapshots possa atingir pelo menos 15 m e executar o segundo acionamento antes de 5 segundos.
3. Confirmar localmente, com coordenadas sanitizadas, `distância >= 15 m` e `tempo < 5 s`.
4. Confirmar criação e incremento do contador.
5. Se qualquer limiar não puder ser demonstrado, marcar `Inconclusivo` e usar a evidência automatizada determinística; nunca estimar distância visualmente nem simular GPS no APK do gate.

A evidência normativa dos limites exatos `4999 ms/15 m`, `5000 ms/14,999 m` e da tabela OR é o teste `test/domain/cooldown_policy_test.dart`. O aparelho não é instrumento adequado para produzir exatamente esses limites.

### 33.3-CD04 — primeira ocorrência, limites inclusivos e ausência de commit em falha

Correlacionar o fluxo físico com os testes automatizados:

- primeira ocorrência sem referência é permitida;
- tempo exatamente 5 s permite;
- distância exatamente 15 m permite;
- rejeição ocorre somente com ambos abaixo;
- relógio regressivo conta como tempo abaixo do limiar;
- rejeição/falha não avança referência;
- cooldown bloqueado não invoca captura, UUID nem commit.

Esses itens não devem receber o tipo “observação física direta” se o valor exato não for mensurável na UI.

## 5. JPEG, orientação, proporção, dimensões e tamanho

### 33.3-IMG01 — captura orientável e JPEG privado

1. Com o alvo assimétrico apontando para cima, registrar uma ocorrência em cada orientação aplicável do aparelho sem alterar artificialmente o arquivo.
2. Após cada sucesso, inventariar o namespace privado e exportar somente o `prepared` atual para área local controlada fora do repositório.
3. Confirmar:
   - [ ] assinatura/formato reconhecido como JPEG e nome final `.jpg`;
   - [ ] arquivo está somente no namespace privado, não na galeria;
   - [ ] não existe `source` após a conclusão;
   - [ ] a seta/texto fica visualmente na orientação correta ao abrir a cópia;
   - [ ] largura `<= 1280` e altura `<= 720`;
   - [ ] proporção visual é preservada, sem estiramento; registrar dimensões de origem e destino somente quando ambas forem observáveis;
   - [ ] tamanho `<= 2.097.152` bytes;
   - [ ] hash da cópia coincide com o hash do arquivo inspecionado antes da exclusão local.
4. Apagar a cópia exportada após a coleta e não adicionar imagem ao repositório.
5. Evidência: `33.3-E06-jpeg-metadata.txt` com apenas formato, dimensões, bytes, orientação observada e hash; `33.3-E07-orientacao-sanitizada.png` somente se a cena for neutra.

### 33.3-IMG02 — qualidade JPEG 85 e redução somente de dimensões

A qualidade solicitada `85` e as tentativas internas não são inferíveis com confiabilidade a partir de uma captura de tela, propriedades do JPEG ou tamanho final. Portanto:

- usar como evidência técnica `test/infrastructure/private_image_pipeline_test.dart`, que injeta codec rastreável e comprova `quality == 85` em todas as codificações;
- usar o mesmo teste para comprovar resize inicial em `1280x720`, proporção dentro do arredondamento, redução estritamente monotônica somente de dimensões e terminação finita;
- usar a inspeção física de IMG01 apenas para formato, orientação observada, dimensões e tamanho do artefato real;
- não declarar “JPEG 85 observado fisicamente” e não estimar qualidade visual.

### 33.3-IMG03 — limite de 2 MiB

1. Registrar o tamanho exato do JPEG real de IMG01.
2. Aprovar o artefato real somente se `bytes <= 2 * 1024 * 1024`.
3. Correlacionar o limite inclusivo exato de 2 MiB e o laço de redução ao teste automatizado.
4. Se a câmera real não produzir fonte capaz de exercitar múltiplas tentativas, registrar essa limitação; não inflar/corromper o arquivo privado do aplicativo.

## 6. Rejeição e limpeza temporária

### 33.3-CL01 — bloqueio sem novo artefato

Usar o cenário CD01. O inventário antes/depois deve ser idêntico e não deve haver `source`. Isso demonstra fisicamente que o bloqueio por cooldown não deixa captura definitiva; correlacionar ausência de UUID/commit com `post_candidate_processor_test.dart`.

### 33.3-CL02 — substituição da ocorrência corrente

1. Após um sucesso, registrar hash/identidade sanitizada do único `prepared` atual.
2. Permitir outra ocorrência por tempo (CD02).
3. Confirmar que o JPEG anterior foi removido e somente o novo permanece.
4. Confirmar contador incrementado uma vez.

### 33.3-CL03 — término da responsabilidade E1

1. Com uma ocorrência corrente, registrar inventário.
2. Encerrar a responsabilidade da Operação pelo fluxo aprovado (por exemplo, abrir Diagnóstico e aguardar a suspensão completa), sem avaliar aqui ordem de recursos/navegação.
3. Inventariar novamente e confirmar que não restam arquivos E1 reconhecíveis.
4. Registrar apenas a limpeza da imagem; a validação de navegação, câmera/GPS e lifecycle pertence a 33.4.

### 33.3-CL04 — rejeição/falha controlada

Não provocar corrupção, falta de espaço, permissão de filesystem ou falha de deleção no aparelho do gate. Esses cenários exigiriam adulteração do ambiente e não são garantidos pela captura normal. Usar evidência automatizada para:

- fonte indecodificável removida;
- tamanho máximo inalcançável rejeitado em `1x1` com laço finito;
- limpeza de fonte e derivados em cada estágio de falha do processor;
- transferência única de ownership e `dispose` idempotente;
- varredura restrita de órfãos reconhecíveis;
- log de falha sanitizado sem path nem bytes.

Na UI, se uma falha real não induzida ocorrer, registrar a mensagem literal **“Falha na imagem: não foi possível preparar o JPEG.”** ou a mensagem efetivamente exibida, contador inalterado e inventário final; não repetir destrutivamente para forçar o erro.

## 7. Matriz de evidência técnica automatizada

| Propriedade | Evidência existente |
|---|---|
| Blockers e chamada direta sem efeito | `test/operation/operation_controller_test.dart` |
| Toques concorrentes produzem no máximo uma operação | `test/operation/operation_controller_test.dart` e `test/operation/operation_screen_test.dart` |
| Cooldown 5 s/15 m, limites inclusivos e regra OR | `test/domain/cooldown_policy_test.dart` |
| Bloqueio sem captura, UUID, commit ou artefato | `test/application/post_candidate_processor_test.dart` |
| JPEG, EXIF, proporção, 1280x720, 2 MiB, qualidade 85, monotonicidade e terminação | `test/infrastructure/private_image_pipeline_test.dart` |
| Limpeza em falhas do processor | `test/application/post_candidate_processor_test.dart` |
| Ownership, substituição, dispose, órfãos, privacidade e log sanitizado | `test/infrastructure/private_image_pipeline_test.dart` |
| Feedback visual de cooldown/captura/imagem | `test/operation/operation_screen_test.dart` |

A saída consolidada anterior pode ser referenciada, mas suas ressalvas devem ser preservadas. Para 33.3, anexar também a saída da validação direcionada executada durante a preparação deste roteiro.

## 8. Encerramento e critérios de decisão

- [ ] Restaurar câmera e localização precisa ao estado autorizado.
- [ ] Apagar cópias locais exportadas dos JPEGs após produzir metadados/hash sanitizados.
- [ ] Não apagar arquivos privados manualmente: a limpeza deve ser efeito do ciclo de ownership da aplicação.
- [ ] Preencher `task-33.3-evidence-record.md` sem marcar o Gate E1 como aprovado.
- [ ] Classificar como bloqueio qualquer cenário que dependa de observabilidade inexistente; complementar com teste somente quando o design prevê evidência técnica, nunca inventar observação física.
- [ ] Parar após a preparação/coleta de 33.3; não iniciar 33.4, 33.5, 34 ou E2.

## Referências normativas

- Tarefa: `tasks.md`, item 33.3.
- Requisitos: RF-03.6–10 e 14–16; RF-05.10–11; RF-09.1–11; RF-10.1–15; RF-11.5–8; RF-20.1–7; RF-23.7, 19–20; RNF-03.1, 3–4 e 10; RNF-04.3; RNF-06.1–8, 11–12; RNF-07.2.
- Design: E1.13–E1.16, E1.21, E1.24, E1.27 e E1.28 passos 12–17 e 25–26.
- Instalação preparada: `task-33.1-apk-installation.md`.

## Limitações conhecidas para a execução futura

1. A UI não apresenta qualidade JPEG, dimensões, bytes, path ou ownership; esses itens exigem inspeção privada sanitizada e/ou testes automatizados.
2. Qualidade JPEG 85, tentativas internas, rejeição sintética e falha de limpeza não são observáveis de forma confiável no fluxo físico normal.
3. O ramo por distância antes de 5 s pode ser impraticável com segurança e precisão no aparelho; a evidência determinística é automatizada.
4. Pela implementação atualmente inspecionada, falhas técnicas de câmera/localização podem chegar ao controlador como estados genéricos. A futura execução deve reprovar mensagens específicas ausentes em vez de presumir que negação, negação permanente, precisão reduzida e serviço desligado foram distinguidos.
5. O arquivo de configuração esperado do spec (`.config`/`.config.kiro`) não está presente no diretório; o fluxo foi tratado como spec de feature com base em `requirements.md`, `design.md` e `tasks.md`, não como bugfix.

## Declaração obrigatória

Este roteiro é preparação de evidência. Testes, inspeção de código e metadados não substituem observação física dos itens visíveis no Galaxy S25+, e observação da UI não comprova detalhes internos não expostos. A aprovação da E1 pertence exclusivamente à tarefa 34 e exige decisão explícita do usuário.
