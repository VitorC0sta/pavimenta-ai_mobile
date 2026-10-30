---
inclusion: always
---

# Execução de tasks da spec mvp-app-flutter

## IDs de tasks

As ferramentas `task_get`, `task_update` e `specTask` só reconhecem o **ID completo**: o número mais o texto inteiro da linha da task em tasks.md. Exemplo: `68.1 Implementar `OccurrenceDeliveryCoordinator` single-flight ...`. O ID curto (`68.1`) retorna "Task not found".

- Use o ID completo desde a primeira chamada. Se ele não estiver no prompt, copie-o de uma única chamada `task_list`.
- Não use `grep_search` nem leia o tasks.md inteiro só para descobrir o ID.
- O mesmo ID completo vai em `task_get`, `task_update` (em_progress e completed) e `specTask.taskId` do `invoke_sub_agent`.
- Verifique as dependências ("Depende de") lendo apenas as linhas necessárias do tasks.md, uma vez.

## Sub-agentes (spec-task-execution)

- O ID completo já vem em `specTask`. Não o procure de novo.
- Leia direto os arquivos citados na task e os existentes do mesmo módulo. Evite varreduras amplas.
- Rode `dart format`, `flutter analyze` e somente os testes relevantes, uma vez.
- Não altere o status da task. O orquestrador faz isso.

## Economia de contexto

- Respeite a linha "Ordem interna" do grupo: tasks que alteram o mesmo arquivo rodam em sequência, nunca em paralelo.
- Leia primeiro os arquivos das linhas "Arquivos (alterar)" e "Arquivos (consultar)" do grupo. Só busque outros se faltar algo concreto.
- Do design.md, leia só as seções da linha "Design" (ex.: E4.9), localizando o título com uma busca. Não leia o design inteiro.
- Rode só os testes dos arquivos alterados. A suíte completa fica para as tasks de gate (70 e 72).
- Ao terminar, informe em até 5 linhas os arquivos e APIs públicas que mudaram, para a próxima task não precisar redescobrir.
