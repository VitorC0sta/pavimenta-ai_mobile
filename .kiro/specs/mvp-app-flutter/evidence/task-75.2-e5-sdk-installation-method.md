# Evidência da tarefa 75.2 — Método de instalação do SDK novo

## Decisão do usuário

Perguntado se o SDK novo deveria atualizar a instalação existente ou ficar num SDK paralelo, o usuário respondeu que este é o único projeto Flutter da máquina. O método escolhido é **atualizar a instalação existente**.

## Estado da instalação existente

- Caminho: `C:\dev\flutter`, clone Git do repositório oficial `flutter/flutter`.
- Versão atual: tag `3.24.3` (framework `2663184aa7`), sem alterações locais em arquivos versionados. Os 26 commits "à frente" de `origin/stable` são os cherry-picks oficiais da release 3.24.3.
- Existe um diretório não versionado `C:\dev\flutter\flutter\`, alheio ao projeto; ele não é tocado.

## Reversão

A troca de versão é feita por tag Git. Para voltar à toolchain da baseline 75.1, basta fazer checkout da tag `3.24.3` em `C:\dev\flutter` e executar `flutter --version`.

## Resultado

Método confirmado. Nenhuma mudança global foi feita nesta tarefa; a atualização acontece na 75.4, depois do registro da matriz em 75.3.
