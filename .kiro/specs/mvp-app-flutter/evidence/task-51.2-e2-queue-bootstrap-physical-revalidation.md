# Evidência da tarefa 51.2 — Revalidação física da inicialização E2

## Escopo

- Subtarefa reexecutada: **51.2 — Confirmar criação/inicialização da fila, zero pendências em instalação sem fila E2, preview/GPS/banner/permissões E1 preservados e botão bloqueado até fila pronta.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Especificação: `mvp-app-flutter`; o diretório não possui `.config`, portanto não é uma spec de bugfix.
- Dispositivo físico: Samsung Galaxy S25+ (`SM-S936B`), serial ADB `RQGL701ZV7Z`, Android 17 / API 37.
- Nenhum arquivo de código, dependência, configuração Android ou toolchain foi alterado. Somente os dados locais do pacote foram limpos, como necessário para reproduzir a condição solicitada de instalação sem fila E2.

## Verificação automatizada complementar

Foi executado:

```powershell
flutter test test/operation/operation_queue_bootstrap_test.dart test/operation/operation_queue_screen_test.dart
```

Resultado: **9 testes aprovados**.

A cobertura confirmou especificamente que, enquanto o bootstrap está pendente, câmera, GPS e navegação ao Diagnóstico permanecem independentes; `canRegister` é `false` até a fila retornar `ready`; com snapshot confirmado `ready` e `pendingCount: 0`, o registro é habilitado; e estados indisponível/degradado mantêm o bloqueio.

## Fluxo físico reexecutado

1. ADB e Flutter reconheceram o Galaxy físico. `flutter devices --machine` listou `SM S936B`, `RQGL701ZV7Z`, `android-arm64`.
2. Foi executado `adb shell pm clear com.vitor.pavimenta_ai_mobile`, com retorno `Success`, removendo banco/fila e dados locais do app sem desinstalar o APK nem alterar o projeto.
3. A abertura por `adb shell am start -W -n com.vitor.pavimenta_ai_mobile/.MainActivity` retornou `Status: ok`, `Activity: com.vitor.pavimenta_ai_mobile/.MainActivity` e `TotalTime: 435 ms`.
4. No primeiro uso, o Android exibiu fisicamente o diálogo de câmera: “Permitir que o app pavimenta_ai_mobile tire fotos e grave vídeos?”, demonstrando a preservação do fluxo de permissão E1. A permissão foi concedida via ADB após o diálogo, pois a injeção de toque ADB não foi aceita pelo controlador de permissões.
5. Após a concessão, a árvore de acessibilidade da tela física confirmou: banner “Modo de registro manual. Detecção automática indisponível.”, câmera traseira `Pronta` com preview disponível e GPS `pronto` com localização, precisão e velocidade apresentadas.
6. Após rolagem, a árvore de acessibilidade confirmou o estado E2 final: “Fila local / Status: Pronta / Pendências: 0. Pronta. Fila local pronta.”; o contador E1 estava em `0 registros criados`; e o controle de registro estava `enabled=true` com o rótulo “Registrar buraco por confirmação manual”.
7. A inspeção técnica do sandbox após a abertura encontrou o banco `e2_occurrence_queue_v1.db`, seu journal e o namespace privado `files/e2_queue_images_v1`; não havia pendências visíveis nem imagens de pendência no cenário limpo.

## Resultado por critério

| Critério | Resultado | Evidência |
|---|---|---|
| Fila criada/inicializada em cenário sem fila E2 | Aprovado | Após `pm clear` e abertura, banco E2 e namespace privado foram criados; UI chegou a `Fila local pronta`. |
| Zero pendências em instalação sem fila | Aprovado | UI física: `Pendências: 0`; contador da sessão separado: `0 registros criados`. |
| Preview, GPS e banner E1 preservados | Aprovado | UI física apresentou preview traseiro disponível, GPS pronto com valores e banner de modo manual. |
| Permissões E1 preservadas | Aprovado com limitação registrada | Diálogo físico de câmera foi exibido no primeiro uso. Localização já permanecia concedida pelo Android depois do `pm clear`, e a UI confirmou GPS pronto; por isso não houve novo diálogo físico de localização nesta reexecução. |
| Registro bloqueado até fila pronta | Aprovado por teste direcionado; estado final confirmado fisicamente | O bootstrap físico completou rápido demais para capturar o frame transitório `Recuperando fila local` antes da primeira árvore disponível. Os testes direcionados aprovados cobrem explicitamente `canRegister == false` durante inicialização e só habilitam após `QueueHealth.ready`; no aparelho, o botão só foi observado habilitado no estado final `Pronta`. |

## Conclusão

**A tarefa 51.2 está revalidada com sucesso.** O cenário limpo no Galaxy alcançou a fila local pronta com zero pendências, preservando os elementos operacionais E1. A transição temporal de bloqueio do botão foi comprovada pelos testes direcionados e correlacionada com o estado físico final; a captura física do estado transitório não foi possível porque a inicialização SQLite concluiu antes do primeiro dump observável, sem alterar a implementação apenas para retardá-la.
