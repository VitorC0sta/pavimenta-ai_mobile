# Task 73.9 - Regressão de navegação Operação ↔ Configurações / Diagnóstico

## Contexto
O usuário informou que configurou o link do projeto público (deploy) no app e o envio funcionou. Isso é relato do usuário; não há evidência coletada pelo agente (sem acesso ao aparelho ou ao Analytics).

## Automatizado (rodada única)
`dart format` (0 alterações), `flutter analyze` sem problemas. Testes: `test/operation/operation_diagnostic_navigation_test.dart` e `test/architecture/e4_delivery_boundaries_test.dart`: todos passaram (24).

Novo teste: `Operation→Settings→Operation→Diagnostic→Operation keeps one resource set, one delivery and the E0–E3 surface`.
- Após cada retorno à Operação, painéis de câmera, GPS, sessão, fila e envio, botão de registro manual, rótulo de confirmação manual e botões de Configurações/Diagnóstico estão presentes (um de cada) e `canRegister` é verdadeiro (E0–E3).
- No máximo 1 dono de câmera, 1 de GPS e 1 stream; zero violações. Aquisições da Operação: 3, liberações: 2; sessão de Diagnóstico construída e descartada 1 vez.
- Tela mantida acesa: `[true, false, true, false, true]`.
- Entrega única: nenhuma chamada a `start`, `queue` ou `retry` pelas rotas (sem coordenador duplicado).

Cobertura já existente: toques repetidos abrem uma só sessão de Diagnóstico, salvar em Configurações restaura um só conjunto de recursos, rotas repetidas não duplicam permissão/stream, ciclo de vida global encaminhado uma vez, dispose.

## Aparelho físico (S25+)
| Cenário | Status |
|---|---|
| Operação → Configurações → Operação no aparelho | **Não executado** |
| Operação → Diagnóstico → Operação no aparelho | **Não executado** |
| E0–E3 preservados no aparelho | **Não executado** |

Roteiro: (1) Abrir Operação; confirmar preview, GPS, contagem de pendências e painel de envio. (2) Abrir Configurações, voltar; repetir 3 vezes; preview e GPS devem retornar sem congelar. (3) Abrir Diagnóstico (toque duplo rápido deve abrir uma só tela), voltar; repetir 3 vezes. (4) Registrar uma ocorrência manual e confirmar cooldown, contagem e envio. (5) Anotar apenas passou/falhou, sem UUID, chave, coordenada, imagem, URL ou body.

Nada é aprovado por presunção. Status da task não alterado.
