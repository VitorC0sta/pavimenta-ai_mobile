# Task 73.5 - Registro manual e envio autenticado real

Data: 2026-10-29

## Cenário
- Aparelho SM-S936B (Galaxy S25+), APK debug E4 da 73.2, `adb reverse tcp:3000 tcp:3000` ativo, Analytics real (`next dev`) no WSL.
- URL e API key de teste digitadas pelo operador no aparelho, fora do repositório e da conversa. Nenhum valor foi lido, copiado ou registrado.
- Antes da configuração a fila local tinha 4 JPEGs (73.4).

## Resultados
| Verificação | Resultado |
|---|---|
| Registro manual com o app configurado | O operador registrou uma ocorrência pelo botão manual; a sessão exibe "Buracos registrados: 1" |
| Estado da fila após o envio (inspeção via adb) | Painel: "Pendências: 0. Pronta. Fila local pronta."; `files/e2_queue_images_v1` com 0 arquivos; painel Envio "Ocioso" |
| Recebimento pelo back-end | O operador confirmou no painel Ocorrências do Analytics local que a ocorrência apareceu com localização e foto |
| Autenticação real | O Analytics exige credencial (HTTP 401 sem chave, 73.3); o recebimento ocorreu com a chave configurada no aparelho |

## Limites desta evidência
- A ordem "aceite/persistência local antes da rede" não foi cronometrada nesta execução. Ela está sustentada pela observação física da 73.4 (ocorrência salva na fila local sem rede) e pelos testes automatizados de 72.x.
- A confirmação de recebimento vem do operador observando o painel do Analytics. Não foram guardados UUID, chave, coordenada, imagem, URL completa, body nem capturas de tela.
- As 4 ocorrências que estavam na fila antes da configuração foram drenadas (fila vazia); o operador não distinguiu cada uma no painel.

## Resultado
Evidência real de recebimento obtida. `Validation Gate E4 não executado` não se aplica. As tasks 73.6 em diante seguem pendentes.
