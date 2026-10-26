# Evidência — Tarefa 34.3: cooldown E1 no Galaxy S25+

## Resultado

**Status da subtarefa 34.3: PARCIALMENTE APROVADA / BLOQUEADA PARA CONCLUSÃO FÍSICA INTEGRAL.**

No Samsung Galaxy S25+ foram observados e aprovados: rejeição quando tempo e distância permanecem simultaneamente abaixo dos mínimos, feedback explícito, contador inalterado, ausência de nova captura definitiva e criação permitida pelo ramo temporal da regra OR após 5 segundos com deslocamento observado abaixo de 15 metros.

O ramo físico complementar `distância >= 15 m` com `tempo < 5 s` não foi executado: o aparelho permaneceu estacionário e conectado por USB, e o roteiro proíbe condução, estimativa visual ou simulação de GPS no APK do gate. Os testes automatizados consolidados já comprovam deterministicamente esse ramo, mas não substituem a observação física exigida pelo Validation Gate. Por isso, a tarefa 34.3 não deve ser marcada como integralmente concluída sem aceitação explícita da composição de evidências ou uma caminhada segura supervisionada.

Esta evidência cobre somente 34.3. Não executa 34.4–34.6, não aprova o gate pai, não altera `tasks.md` e não inicia E2.

## Ambiente

- Data/hora local da coleta: `2026-10-22T12:45:11-03:00`.
- Dispositivo físico: Samsung Galaxy S25+ (`SM-S936B`), reconhecido como `device` pelo ADB Windows aprovado; serial omitido.
- Pacote observado: `com.vitor.pavimenta_ai_mobile`.
- Rota usada: somente **Operação**.
- Câmera e GPS estavam prontos; aparelho mantido estacionário.
- O spec não possui `.config` nem `.config.kiro`; foram usados `requirements.md`, `design.md` e `tasks.md` como documentos normativos.
- Nenhuma instalação, atualização, reconfiguração, alteração de código ou execução de E2 ocorreu.

## Cenário A — ambos abaixo: rejeição

Após reinício limpo da sessão, uma primeira ocorrência foi criada. O segundo toque foi enviado **3264 ms (3,264 s)** depois do primeiro, portanto abaixo do cooldown de 5 segundos. O aparelho permaneceu estacionário e a própria UI classificou a tentativa como estando abaixo de ambos os mínimos.

### Observação física

- status: **“Ignorado por cooldown”**;
- descrição: **“Nenhuma imagem, UUID ou ocorrência foi criada.”**;
- feedback: **“Cooldown: Registro ignorado: tempo e distância ainda abaixo dos mínimos.”**;
- contador permaneceu em **1 registro criado**;
- não houve crash, navegação ou bloqueio da interface.

### Inspeção privada sanitizada antes/depois do bloqueio

| Medida | Antes do segundo toque | Depois do segundo toque |
|---|---:|---:|
| JPEG `prepared` reconhecível | 1 | 1 |
| captura `source` reconhecível | — | 0 |
| SHA-256 do JPEG corrente | `336D1F902432D233909D3C3E36A041CDEBE8AE42919EE94E8DEF6957EE0B5C72` | mesmo valor |

A contagem e o hash inalterados comprovam que o bloqueio não criou nem substituiu imagem definitiva. A ausência de geração interna de UUID não é diretamente introspectável na interface; a UI declara explicitamente que nenhum UUID foi criado, e a evidência automatizada consolidada de `post_candidate_processor_test.dart` cobre a não invocação do gerador no bloqueio.

## Cenário B — ramo temporal da regra OR

Em nova sessão limpa, o segundo toque foi enviado **7799 ms (7,799 s)** depois do primeiro. Duas amostras consecutivas da posição exibida, coletadas antes dos acionamentos e sem registrar as coordenadas, resultaram em deslocamento Haversine sanitizado de **0,0 m**, abaixo de 15 metros.

### Observação física

- condição temporal: `>= 5 s`;
- condição de distância observada: `< 15 m`;
- resultado: segunda ocorrência permitida;
- status final: **“Concluído”**;
- feedback final: **“Sucesso: Buraco registrado em memória.”**;
- contador mudou de 1 para **2 registros criados**;
- inventário final: 1 JPEG `prepared`, 0 capturas `source`, consistente com substituição da ocorrência corrente em memória.

Esse cenário comprova fisicamente o ramo temporal da regra OR: o registro foi permitido por tempo mesmo com deslocamento abaixo de 15 metros.

## Cenário C — ramo por distância antes de 5 segundos

**Status: NÃO EXECUTADO / BLOQUEIO MANUAL DE SEGURANÇA E OBSERVABILIDADE.**

Para observar esse ramo sem adulterar o APK, seria necessário deslocar fisicamente o aparelho pelo menos 15 metros e realizar o segundo acionamento em menos de 5 segundos, com confirmação local dos snapshots. O agente não pode mover o aparelho; o cabo USB e o ambiente atual não permitem uma caminhada supervisionada durante a coleta. Simular localização, estimar distância visualmente ou conduzir para produzir o cenário violaria o roteiro aprovado.

A suíte consolidada registrada em `task-31-automated-test-suite.md` cobre deterministicamente distância no/acima de 15 m, tempo abaixo de 5 s, limites inclusivos, regra OR e ausência de captura/UUID/commit no bloqueio. Essa correlação técnica é válida, mas não foi rotulada como observação física direta.

## Artefatos locais e privacidade

As capturas brutas permaneceram fora do repositório em `%TEMP%`, pois exibem cena da câmera e coordenadas. Somente hashes sanitizados são versionados nesta evidência.

| Artefato local | Conteúdo | SHA-256 |
|---|---|---|
| `task-34.3-rejected.png` | rejeição, feedback explícito e contador 1 | `8E092D73E271D53A8D385EF50BEEF434A144D13B0AA283FF54FA82885705A367` |
| `task-34.3-rejected-proof.png` | repetição da rejeição usada com inventário antes/depois | `8ED908FD750061B2AB8B36AE023FC3642C86F9D63E7C477435BAED74E9D21B73` |
| `task-34.3-time-allowed-proof.png` | criação pelo ramo temporal e contador 2 | `ABBA431F8EBA1D5705003405DD617FACCE536AE51E06881D98677FDE7522A32D` |

Nenhuma coordenada integral, serial, path privado completo ou conteúdo de imagem foi incluído neste documento.

## Decisão para o orquestrador

Não marcar 34.3 como concluída integralmente. Os critérios visíveis de rejeição, feedback, contador, ausência de novo artefato e permissão por tempo foram aprovados no Galaxy S25+. Permanece o bloqueio preciso da observação física do ramo por distância antes de 5 segundos. O gate E1 deve continuar pendente, e nenhuma etapa posterior foi iniciada.
