# Task 73.6 - Repetição idempotente controlada com a mesma chave

Data: 2026-10-29

## Resultado
**Executado pelo operador, aprovado.** O operador (dono do aparelho e do Analytics) executou o roteiro de repetição idempotente e declarou: "deu certo, passou o teste".

## Natureza do registro
- O resultado é declaração do operador. O agente não observou a execução nem acessou o Analytics, o painel ou o aparelho.
- O operador não informou contagens (ocorrências antes/depois, fila local). Nenhuma contagem é registrada aqui.
- Nenhum UUID, chave, coordenada, imagem, URL completa ou body consta nesta evidência.

## Roteiro executado
1. Com Analytics local e `adb reverse` ativos, registrar uma ocorrência com o app configurado e interromper o Analytics antes da resposta (ou desligar a rede do aparelho durante o envio) para forçar retry com a mesma chave.
2. Restaurar o Analytics e aguardar o envio.
3. Conferir a contagem de ocorrências no painel antes e depois (esperado: +1, não +2) e a fila local em 0.
4. Não anotar UUID, chave, coordenada, imagem, URL completa ou body.

## Cobertura simulada (não substitui o real)
- `multipart_retry_stability_test.dart` e `occurrence_transport_wire_test.dart` (72.2): mesma chave e mesmos dados em retries.
- `e4_delivery_integration_test.dart`: retomada reutiliza a chave.
- Não há teste automatizado que verifique a deduplicação pelo servidor; essa garantia depende do back-end.

## Decisão
Aprovação baseada na declaração do operador, sem contagens. Status da task não alterado por este registro.
