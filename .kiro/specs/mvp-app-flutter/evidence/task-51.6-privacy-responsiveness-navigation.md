# Evidência da tarefa 51.6 — Privacidade, responsividade, Diagnóstico e exclusão de recursos E2

## Escopo executado

- Subtarefa: **51.6 — Confirmar JPEG privado fora da galeria, responsividade durante persistência, navegação ao Diagnóstico sem alteração da fila e exclusão mútua de câmera/GPS.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- O diretório da spec não contém `.config`; trata-se de uma spec regular, não de bugfix.
- Nenhum código, dependência, manifesto, banco, JPEG, configuração Android ou evidência histórica E0/E1 foi alterado.

## Cobertura automatizada dirigida

Foi executado em modo único:

```powershell
flutter test test/operation/operation_diagnostic_navigation_test.dart test/operation/operation_queue_screen_test.dart test/infrastructure/durable_image_store_test.dart test/infrastructure/e2_queue_integration_test.dart
```

Resultado: **25 testes aprovados**, término da suíte com `All tests passed!`.

A cobertura aprovada confirma:

- `operation_queue_screen_test.dart`: preview, GPS, acesso ao Diagnóstico e botão de registro permanecem responsivos durante `isPersisting`; a ação de registro fica bloqueada durante a persistência e a tela apresenta o estado local apropriado.
- `operation_diagnostic_navigation_test.dart`: a Operação libera stream GPS, localização e câmera antes da sessão Diagnóstico; cada retorno cria uma sessão operacional nova; não há permissão ou stream duplicado; os máximos simultâneos de dono de câmera, localização e stream são exatamente um.
- `durable_image_store_test.dart`: JPEGs E2 são promovidos com nomes opacos para o namespace privado, sem uso de galeria; o armazenamento preserva ownership, integridade, limpeza e sanitização de falhas.
- `e2_queue_integration_test.dart`: a fila SQLite e a associação imagem persistida são exercitadas com filesystem real em sandbox descartável.

Essa cobertura é automatizada e não é apresentada como substituta para a confirmação física pendente abaixo.

## Tentativa de revalidação no Galaxy S25+

O ADB aprovado reconheceu o Galaxy S25+ físico com estado `device` (`RQGL701ZV7Z`). A tentativa controlada pretendia:

1. abrir o aplicativo E2;
2. obter da árvore de acessibilidade a contagem agregada de pendências, sem ler dados da fila;
3. abrir Diagnóstico, confirmar o título E0 e retornar;
4. comparar somente a mesma contagem agregada antes/depois da navegação;
5. contar apenas arquivos no namespace interno `files/e2_queue_images_v1` e consultar de forma agregada entradas de imagem do MediaStore pertencentes ao pacote, sem listar imagens, paths, UUIDs, coordenadas, horários, bytes ou conteúdo.

A aplicação foi iniciada e a árvore de acessibilidade foi solicitada após espera controlada. A automação não encontrou o nó textual ou semântico `Pendências:` e encerrou antes de tocar no botão de Diagnóstico, contar arquivos privados ou consultar o MediaStore. A falha exata retornada foi:

```text
UI node not found: Pendências:
```

Portanto, não houve afirmação sobre navegação física, igualdade de pendências antes/depois, localização do JPEG no dispositivo ou ausência física de cópia na galeria nesta execução. Não foram criadas novas ocorrências, removidas pendências, despejados banco/logs, lidos bytes JPEG, copiados arquivos privados ou alteradas permissões.

## Resultado

| Critério 51.6 | Resultado atual | Evidência |
|---|---|---|
| JPEG privado fora da galeria | Não executado fisicamente | Cobertura automatizada aprovada; inspeção física agregada não foi alcançada. |
| Responsividade durante persistência | Aprovado por teste dirigido | Widget mantém preview, GPS e Diagnóstico visíveis e bloqueia somente o registro durante persistência. |
| Diagnóstico sem alteração da fila | Não executado fisicamente | Cobertura automatizada de navegação aprovada; comparação física agregada não foi alcançada. |
| Exclusão mútua de câmera/GPS | Aprovado por teste dirigido | Teste de ownership comprova máximo de um dono/stream em cada transição. |

**A tarefa 51.6 não está aprovada.** A confirmação física exigida ficou bloqueada pela ausência do indicador de pendências na árvore de acessibilidade, apesar de o dispositivo estar conectado e de toda a cobertura dirigida selecionada ter passado. Uma nova execução deverá primeiro identificar a tela/estado exibido pelo aplicativo e então repetir somente os passos físicos pendentes, preservando a sanitização e sem tratar testes como observação física.

## Reexecução posterior — correção da automação e estado físico atual

A falha anterior foi investigada no Samsung Galaxy S25+ conectado por ADB (`RQGL701ZV7Z`, estado `device`). Nenhuma alteração de código, dependência, manifesto ou configuração Android foi necessária.

### Correção da automação

O problema não era ausência do indicador de fila. Em orientação paisagem, o indicador e a ação de Diagnóstico ficam fora da região inicialmente visível do `ScrollView`; além disso, o Flutter expõe ambos por `content-desc`, e não por um nó de texto simples.

A árvore atual da tela Operação expôs os rótulos sem dados sensíveis:

- `Pendências: 10. Pronta. Fila local pronta.`;
- `Abrir Diagnóstico` como botão acessível;
- preview traseiro disponível e GPS pronto.

A automação corrigida rolou até o controle, tocou o botão a partir de seus limites acessíveis e, ao retornar, rolou até o cartão da fila e leu novamente o agregado por `content-desc`.

### Navegação, fila e recursos no aparelho

1. Antes de abrir Diagnóstico, a árvore acessível registrou `Pendências: 10`.
2. Diagnóstico abriu fisicamente e exibiu `E0 — Diagnóstico Android`, com os painéis de câmera e localização da E0 disponíveis.
3. A inspeção do serviço de câmera no handoff registrou `DISCONNECT` seguido de `CONNECT` para o cliente do pacote; havia exatamente um cliente de câmera ativo do aplicativo durante a sessão Diagnóstico. A inspeção de localização mostrou uma única solicitação de alta precisão atribuída ao pacote.
4. Após voltar à Operação, câmera e GPS foram readquiridos e permaneceram com um único cliente/solicitação ativos. A árvore da fila voltou a expor `Pendências: 10`.

Assim, a comparação física de fila antes/depois da navegação foi aprovada, e o handoff físico é compatível com a exclusão mútua de câmera/GPS. A sequência não criou nem removeu pendências.

### Persistência real e privacidade

- O namespace privado do aplicativo foi consultado somente de forma agregada por `run-as`; continha JPEGs em `files/e2_queue_images_v1`. Nenhum arquivo, nome, conteúdo, UUID, coordenada ou byte foi lido ou copiado.
- Uma nova confirmação manual, separada da comparação acima, foi aceita após o cooldown e a interface chegou a `Pendências: 11` e `Buraco salvo na fila local.`. Portanto, a persistência real no aparelho ocorreu; essa pendência adicional não pertence à verificação de igualdade antes/depois do Diagnóstico.
- Uma consulta agregada ao MediaStore, inclusive executada no contexto `run-as` do aplicativo e sem projetar paths ou conteúdo, falhou no dispositivo com `Error while accessing provider:media`. Logo, esta execução não comprova fisicamente a ausência de entrada na galeria.
- Após o toque de registro, foram realizados 30 dumps acessíveis a cada 120 ms para capturar `Salvando na fila local`/`Persistindo a ocorrência e a imagem na fila local.`. A operação terminou antes da primeira amostra; o estado transitório de persistência não foi observado fisicamente. Não foi introduzido atraso artificial nem UI de debug apenas para prolongá-lo.

### Validação automatizada complementar

Foi executado em modo único:

```powershell
flutter test test/operation/operation_diagnostic_navigation_test.dart test/operation/operation_queue_screen_test.dart test/infrastructure/durable_image_store_test.dart test/infrastructure/e2_queue_integration_test.dart
```

Resultado: **25 testes aprovados**. Eles continuam a ser evidência complementar de persistência responsiva, JPEG privado e exclusão de recursos, e não substituem as observações físicas pendentes.

### Resultado após a reexecução

| Critério 51.6 | Resultado | Evidência física atual |
|---|---|---|
| JPEG privado fora da galeria | Parcial / não aprovado | JPEGs confirmados no namespace privado interno; a consulta agregada ao MediaStore foi bloqueada pelo provedor, portanto não há confirmação física da ausência na galeria. |
| Responsividade durante persistência | Não aprovado | Persistência real concluiu, mas o estado transitório não foi capturado pelos 30 dumps de 120 ms; testes não a substituem. |
| Diagnóstico sem alteração da fila | Aprovado | Agregado acessível `10` antes e `10` depois do ciclo Operação → Diagnóstico E0 → Operação. |
| Exclusão mútua de câmera/GPS | Aprovado | Handoff de câmera `DISCONNECT → CONNECT`, um único cliente ativo, e uma solicitação GPS ativa por vez durante as sessões observadas. |

**A tarefa 51.6 permanece não concluída.** Bloqueios exatos: (1) o MediaStore não está acessível para a consulta agregada pelo ADB/app neste Galaxy, impedindo a confirmação física de que não houve cópia na galeria; e (2) a persistência termina antes da primeira amostra de acessibilidade, sem evidência física do estado responsivo durante a própria persistência. Nenhuma correção de implementação foi justificada ou aplicada.
