# Task 73.8 - Redução da contagem, remoção do JPEG, force-stop e responsividade

## Classificação no ambiente real
| Cenário | Real (aparelho + Analytics) | Observação |
|---|---|---|
| Contagem reduz e JPEG removido só após decisão definitiva | **Não executado** | O agente não acessa o aparelho S25+ nem o Analytics. |
| Force-stop/reabertura sem perda | **Não executado** | Exige `adb shell am force-stop` e inspeção do aparelho. |
| Responsividade durante upload | **Não executado** | Exige observação humana (captura, navegação, rolagem). |

Nenhum cenário é tratado como aprovado por presunção. A task permanece pendente de execução manual.

## Cobertura simulada (rodada única, 69 testes, todos passaram)
`dart format` (0 alterações), `flutter analyze` sem problemas.
Arquivos: `e4_delivery_integration_test`, `e4_delivery_crash_consistency_test`, `e4_delivery_restart_test`.
- Contagem de pendências e `jpegCount` chegam a 0 após decisão definitiva; falha recuperável mantém JPEG e item.
- Crash antes/depois da decisão, dentro do protocolo de remoção (move do JPEG, transação SQLite): nada perdido, nada reenviado após decisão durável, sem JPEG/marcador órfão.
- Reabertura restaura JPEG de linha retida e conclui a limpeza sem HTTP.
- Responsividade real não é coberta por testes simulados.

## Roteiro para o operador
1. Registrar 2-3 ocorrências manuais com Analytics ativo. Esperado: a contagem cai uma a uma só após aceite; JPEG de cada item some somente depois (não verificável sem `run-as`; no debug APK usar `adb shell run-as <pacote> ls files`).
2. Com Analytics parado, registrar uma ocorrência, dar `adb shell am force-stop <pacote>`, reabrir. Esperado: item e JPEG preservados; religar Analytics e confirmar envio e remoção.
3. Durante um upload, capturar, navegar entre Operação/Configurações/Diagnóstico e rolar. Esperado: sem travamento nem ANR.
4. Anotar apenas passou/falhou/não executado e contagens. Sem UUID, chave, coordenada, imagem, URL completa ou body.

## Sanitização
Sem segredos, UUID, coordenadas, imagens, URL ou body. Nenhum código alterado; status da task não alterado.
