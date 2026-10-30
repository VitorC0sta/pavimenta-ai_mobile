# Task 73.7 - Falha temporária/backoff, pausa e retomada

Data: 2026-10-29

## Classificação no ambiente real
| Cenário | Real (aparelho + Analytics) | Observação |
|---|---|---|
| Falha temporária / backoff | **Não executado** | O agente não tem acesso ao aparelho nem ao Analytics. |
| Pausa por autenticação/acesso (401/403) | **Não executado** | Exige chave inválida/revogada no aparelho; não provocável pelo agente. |
| Resposta inesperada | **Não executado** | Exige o back-end devolver resposta fora do contrato; não provocável pelo agente. |
| Retomada (após backoff/pausa) | **Não executado** | Depende dos três anteriores. |

Nenhum cenário é tratado como aprovado por presunção. A cobertura simulada abaixo não substitui o real.

## Cobertura simulada (rodada única, 168 testes, todos passaram)
Arquivos: `delivery_backoff_policy_test`, `http_delivery_decision_policy_test`, `occurrence_transport_failure_classifier_test`, `occurrence_delivery_coordinator_test`, `e4_delivery_integration_test`, `operation_delivery_composition_test`.
- Backoff: política de atraso, estado `waitingBackoff` e retomada via ciclo de vida.
- Pausa: `pausedAuthentication`, `pausedAccess`, `pausedUnexpected`, com nova tentativa manual e mesma chave.
- Classificação de falhas de transporte e decisões HTTP.

## Roteiro para o operador
1. Backoff: registrar uma ocorrência e parar o Analytics (ou desligar a rede do aparelho). Esperado: item permanece na fila, painel indica espera, captura continua. Religar e confirmar envio automático.
2. Autenticação/acesso: trocar a chave do aparelho por uma inválida (ou revogá-la no Analytics) e registrar. Esperado: pausa por autenticação/acesso, item preservado. Corrigir a chave, usar a nova tentativa manual e confirmar envio.
3. Resposta inesperada: se for possível fazer o Analytics devolver resposta fora do contrato, esperado: pausa por resposta inesperada com item preservado. Caso contrário, registrar "não executado".
4. Anotar apenas resultado (passou/falhou/não executado) e contagens. Não anotar UUID, chave, coordenada, imagem, URL completa ou body.

## Sanitização
Sem UUID, chave, coordenada, imagem, URL completa ou body. Nenhum código alterado; status da task não alterado.
