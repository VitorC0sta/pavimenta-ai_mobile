# Evidência da tarefa 60.5 — Cooldown/distância, E2 e recuperação após force-stop

## Escopo executado

- Tarefa: **60.5 — Confirmar que alteração de cooldown/distância é observável sem perder a pendência/estado E2; force-stop/reabrir e confirmar recuperação de configuração e fila.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- A pasta da spec não contém `.config` nem `.config.kiro`; trata-se de spec regular, não bugfix.
- Dispositivo físico: Samsung `SM-S936B` (Galaxy S25+), conectado pelo ADB Windows no estado `device`, Android API 37.
- APK: a atualização E3 preservadora registrada em `task-60.1-e3-preserving-update.md`.
- Limite: não foram alteradas URL, credencial, permissões, dados de fila, imagens ou registros. Não houve tráfego de ocorrência e as tarefas 60.6–60.7 e o Gate 61 não foram executados.

## Condição inicial

A tela Operação informou fila local **Pronta** com **5 pendências**. A tela Configurações apresentou os defaults ainda efetivos: cooldown de 5 s e distância mínima de 15 m.

## Alteração observável e preservação em runtime

Foram informados e salvos valores positivos, não secretos e distintos dos defaults:

| Campo | Valor salvo |
|---|---:|
| Cooldown | 13 s |
| Distância mínima | 37 m |

A interface confirmou **“Parâmetros salvos.”** e, ao retornar à tela Operação, a fila continuou **Pronta**, com as mesmas **5 pendências**. Não houve reset da fila, descarte de registros, alteração da saúde E2 nem criação de nova ocorrência durante a mudança de parâmetros.

## Force-stop e reabertura

A aplicação foi encerrada com `adb shell am force-stop com.vitor.pavimenta_ai_mobile` e aberta novamente pela atividade principal. Após a recuperação:

| Verificação | Resultado observado |
|---|---|
| Recuperação da fila E2 | A tela Operação mostrou fila **Pronta** e **5 pendências**, igual à condição anterior ao force-stop. |
| Estado de processamento | **Pronto**, sem registro em processamento. |
| Recuperação da configuração | A tela Configurações mostrou novamente cooldown **13 s** e distância mínima **37 m**. |
| Estado dos recursos | Preview da câmera traseira disponível; o aplicativo reabriu sem crash. |

A inspeção foi limitada a rótulos semânticos e campos de parâmetros não secretos. Esta evidência não registra API key, URL, coordenadas, imagem, UUID, caminhos internos nem conteúdo de armazenamento.

## Resultado

**SUCESSO no escopo da tarefa 60.5.** A alteração de cooldown e distância mínima foi observável e persistiu em reabertura. O force-stop não removeu nem degradou a fila E2: as cinco pendências permaneceram prontas para uso futuro. Esta tarefa não aprova o Validation Gate E3 nem executa as tarefas 60.6–60.7.
