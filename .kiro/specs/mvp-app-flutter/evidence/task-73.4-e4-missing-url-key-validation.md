# Task 73.4 - Ausência de URL/chave no aparelho físico

Data: 2026-10-29

## Cenário
- Aparelho SM-S936B (Galaxy S25+), APK debug da 73.2, sem URL e sem API key configuradas.
- `adb reverse tcp:3000 tcp:3000` ativo (73.3), de modo que qualquer request chegaria ao Analytics real.
- Estado inicial: 3 JPEGs na fila local (`files/e2_queue_images_v1`).

## Resultados
| Verificação | Resultado |
|---|---|
| Registro manual com "Registrar buraco" | Processamento "Concluído": "A ocorrência foi salva na fila local." |
| Ocorrência permanece na fila | JPEGs na fila passaram de 3 para 4; nenhuma remoção |
| Painel de envio orienta configuração | "Configuração necessária. Configure o destino e a chave para enviar pendências." |
| Captura continua | Preview da câmera e GPS seguem prontos após o registro; botão volta a ficar disponível |
| Nenhum request aberto | `/proc/net/tcp*` mostra apenas o listener do `adb reverse` (uid shell) na porta 3000; nenhuma conexão de cliente para ou desde a porta 3000 |

## Observações
- Nenhuma URL ou chave foi usada ou registrada. Coordenadas e capturas de tela não foram guardadas.
- Esta ocorrência manual extra permanece na fila e será enviada nas tasks seguintes, quando houver configuração.
- A verificação de rede é um instantâneo após a ação; a ausência de request também é coberta pelos testes automatizados de 72.2/72.4.
