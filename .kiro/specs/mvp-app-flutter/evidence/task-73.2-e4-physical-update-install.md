# Task 73.2 - Instalação do APK E4 como atualização no aparelho físico

Data: 2026-10-29

## Aparelho
- Modelo: SM-S936B (Samsung Galaxy S25+), Android 17.
- Pacote: `com.vitor.pavimenta_ai_mobile` (versionName 1.0.0, versionCode 1).

## APK
- Arquivo: `build/app/outputs/flutter-apk/app-debug.apk` (126325365 bytes).
- SHA-256: `434DB52C642F8324E12437C7CEFE6E5233E46193DAED435A4E5E4D21EA1CA669`.
- O hash coincide com o registrado na task 72.3.

## Instalação
- Comando: `adb install -r` (atualização, sem desinstalar).
- Resultado: `Success`.
- `firstInstallTime` permaneceu 2026-10-24 18:33:58, o que indica preservação de dados.
- `lastUpdateTime` passou para 2026-10-29 23:34:06.

## Verificação visual (somente observação, nenhuma ocorrência criada)
| Item | Resultado |
|---|---|
| Aviso "Modo manual — YOLO ainda não configurado" | Presente |
| Câmera traseira / preview | Pronta, preview ativo |
| GPS | "GPS pronto", fix disponível (valores omitidos) |
| Fila local | Pendências: 3, preservadas da instalação anterior |
| Envio | "Configuração necessária" (sem URL/chave, esperado) |
| Processamento | Pronto, nenhum registro em processamento |
| Botão "Registrar buraco" | Presente, habilitado, sem cooldown ativo |
| Configurações → Operação | Cooldown 5 s e distância mínima 15 m preservados |
| Diagnóstico E0 | Abre, mostra câmera disponível; retorno à Operação sem falha |

## Observações
- Coordenadas exibidas na tela e capturas de tela não foram guardadas na evidência.
- Nenhuma URL ou chave foi usada ou registrada.
- O cooldown em contagem ativa não foi exercitado aqui (exige registrar ocorrência, escopo da 73.5).
