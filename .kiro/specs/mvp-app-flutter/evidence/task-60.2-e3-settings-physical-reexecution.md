# Evidência da tarefa 60.2 — Nova execução física de parâmetros E3

## Escopo e proteção de dados

- Tarefa: **60.2 — Verificar defaults, editar/salvar/reabrir cooldown, distância, confiança, FPS e URL válida de teste fictícia/sanitizada; confirmar erros de URL/números inválidos e que o sufixo de ocorrências é recusado.**
- Dispositivo acessível: Samsung Galaxy S25+ conectado por ADB no ambiente Windows.
- A pasta da spec não contém `.config` nem `.config.kiro`; a spec é regular, não bugfix.
- Não foram capturados screenshots, dumps de interface, coordenadas, identificadores do dispositivo, URL real, API key, localização, imagem, UUID, paths privados nem conteúdo do armazenamento seguro.
- A única URL usada como entrada durante a tentativa foi uma origem HTTPS fictícia e não resolvível sob `.invalid`. O seu texto não é reproduzido nesta evidência.
- Não houve limpeza de dados, desinstalação, `pm clear`, alteração de pendências E2, alteração de credencial, envio de ocorrência ou tráfego de ocorrência.

## Pré-condição observada

O aplicativo abriu no aparelho e a tela Configurações continuou acessível. Antes da tentativa, a reabertura mostrou os parâmetros anteriormente preservados pela tarefa 60.5 para cooldown e distância. Confiança e FPS mostraram os defaults previstos, e não havia destino salvo.

A evidência anterior `task-60.5-cooldown-distance-force-stop-recovery.md` já registra a observação física dos defaults de cooldown (5 s) e distância (15 m) antes de sua alteração naquela tarefa. Esta nova execução não apagou a configuração nem a fila para tentar recriar esse estado, pois isso extrapolaria a tarefa e comprometeria os dados E2 preservados.

## Resultado por cenário

| Cenário de 60.2 | Classificação | Evidência sanitizada e limite |
|---|---|---|
| Defaults de cooldown e distância | **Aprovado por evidência física complementar** | A observação física anterior, preservada em `task-60.5-cooldown-distance-force-stop-recovery.md`, registra 5 s e 15 m antes da edição. Não foi repetida por limpeza de estado nesta tentativa. |
| Defaults de confiança futura e FPS futuro | **Aprovado** | Na reabertura física desta execução, a interface exibiu os defaults aprovados: 0,5 e 5 FPS. |
| Edição, salvamento e reabertura de cooldown e distância | **Aprovado por evidência física complementar** | `task-60.5-cooldown-distance-force-stop-recovery.md` registra a edição, salvamento, force-stop e reabertura no mesmo aparelho sem perda da fila. |
| Edição, salvamento e reabertura de confiança futura | **Não executado** | A edição direta do campo foi observada, mas não foi possível obter salvamento e reabertura verificáveis sem ambiguidade. |
| Edição, salvamento e reabertura de FPS futuro | **Não executado** | A tentativa não alcançou evidência sanitizada suficiente de salvamento e reabertura. |
| Salvar e reabrir URL HTTPS fictícia válida | **Não executado** | A origem fictícia foi usada somente durante a interação. Não houve confirmação sanitizada de persistência após reabertura. |
| Erro de números inválidos | **Não executado** | A tentativa de inserir valores inválidos não gerou uma evidência de erro por campo que pudesse ser distinguida de mensagens auxiliares estáticas da tela. |
| Erro de URL inválida | **Não executado** | A tentativa não produziu uma classificação de erro de URL inequivocamente observável e sanitizada. |
| Recusa do sufixo `/api/v1/occurrences` | **Não executado** | O sufixo proibido foi inserido em tentativa controlada, porém a observação resultante não permitiu separar de forma confiável a mensagem de erro da mensagem auxiliar estática que já menciona o sufixo. |

## Bloqueio

A tentativa anterior havia sido bloqueada pelo bloqueio da tela do Galaxy S25+. Nesta nova tentativa, o aparelho permaneceu conectado e acessível, mas o controle físico por ADB apresentou uma limitação distinta: a tecla Voltar encerra a rota Configurações em vez de fornecer uma etapa confiável de fechamento do teclado, e o teclado/rolagem altera quais campos aparecem na hierarquia de acessibilidade. Como resultado, o roteiro automatizado não conseguiu demonstrar, sem ambiguidade, que confiança, FPS e URL foram simultaneamente salvos e recuperados.

Não foi aplicada limpeza de dados nem modificação fora de escopo para contornar essa limitação. Isso preserva a fila E2 e a credencial do dispositivo, mas impede classificar os cenários restantes como aprovados.

## Resultado

**Tarefa 60.2 parcialmente executada, sem reprovação funcional registrada.** Há confirmação física complementar dos defaults e do round-trip de cooldown/distância, e confirmação nesta execução dos defaults de confiança/FPS. Os cenários restantes continuam **não executados**, não aprovados por inferência de testes ou código. O bloqueio deve ser resolvido por uma interação manual observável no Galaxy S25+ ou por automação de interface que mantenha a rota e forneça checkpoints sanitizados por campo.
