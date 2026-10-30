# Tasks 74.7 e 74.8 - Decisão do Validation Gate E4

Data: 2026-10-30

## Decisão do usuário
Aprovação explícita do Validation Gate E4

## Base da decisão
- Evidências 74.1–74.6: [task-74.1-74.6-e4-gate-presentation.md](task-74.1-74.6-e4-gate-presentation.md), que consolida 72.1–72.5 e 73.2–73.9.
- Roteiro físico no Galaxy S25+ (SM-S936B) executado pelo operador: instalação preservadora, ausência de URL/chave, envio autenticado, idempotência, falha/backoff/pausa/retomada, contagem e remoção do JPEG, force-stop e regressão de navegação.

## Ressalvas declaradas (aceitas com a aprovação)
- Recebimento real, idempotência e as tasks 73.5–73.9 repousam em declaração do operador, sem contagens nem capturas.
- A deduplicação por idempotência depende do back-end e não tem teste automatizado.
- A divergência entre alvo local (`adb reverse`) e link público citado na 73.9 não foi esclarecida.
- Os testes automatizados usam fakes e servidor loopback, não o back-end real.

## 74.8 Parada obrigatória
E4 encerrado. Nenhum trabalho de E5 foi iniciado. Um novo ciclo E5 só começa por solicitação posterior do usuário e continua condicionado a um modelo treinado compatível. Nenhum código foi alterado.
