# Task 73.3 - Analytics real via servidor local com `adb reverse`

Data: 2026-10-29

## Ambiente
- Analytics real (Next.js `next dev`, v16.3.8) já em execução no WSL (Ubuntu-24.04), porta 3000.
- Acesso a partir do Windows ao endpoint de ocorrências sem credencial: HTTP 401 (autenticação exigida).
- Túnel: `adb reverse tcp:3000 tcp:3000` para o aparelho `RQGL701ZV7Z` (Galaxy S25+). `adb reverse --list` mostra a regra ativa.
- Conectividade do aparelho: conexão TCP a `127.0.0.1:3000` com sucesso (`nc` exit 0).

## Observações
- O destino é loopback HTTP, permitido apenas no build debug (conforme 72.4).
- URL completa e API key não são registradas aqui nem no repositório. A configuração no app fica para as tasks 73.4 e 73.5, com valores digitados no aparelho.
- A regra `adb reverse` se perde ao desconectar o cabo ou reiniciar o adb e precisa ser refeita.
- O banco e o armazenamento do Analytics são remotos (Supabase), conforme o `.env` do Analytics, que não foi lido nem copiado.
