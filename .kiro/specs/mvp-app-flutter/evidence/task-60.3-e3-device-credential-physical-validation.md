# Evidência da tarefa 60.3 — Credencial do dispositivo no Galaxy S25+

## Escopo executado

- Tarefa: **60.3 — Colar chave de teste do dispositivo somente quando fornecida fora do repositório, salvar, reabrir e confirmar apenas o status “configurada”; validar troca, remoção com confirmação e orientação de rotação sem registrar o segredo.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- A pasta da spec não contém `.config` nem `.config.kiro`; trata-se de spec regular, não bugfix.
- Ambiente físico: Samsung `SM-S936B` (Galaxy S25+), conectado ao ADB Windows com estado `device`. O serial não é repetido nesta evidência.
- APK: a atualização preservadora E3 já registrada em `task-60.1-e3-preserving-update.md`.

## Proteção operacional do segredo

As duas chaves de teste foram obtidas e inseridas **diretamente pelo operador no aparelho**, fora deste repositório e fora da conversa. Nenhuma chave, prefixo, comprimento, valor mascarado, captura de tela, conteúdo de armazenamento seguro, URL, comando de automação, log ou texto copiado do campo foi coletado ou persistido.

A interação que manipula a chave foi manual. Esta evidência registra exclusivamente estados de interface sanitizados e a confirmação do operador.

## Roteiro físico e resultado observado

O operador confirmou no Galaxy S25+ que todos os passos abaixo foram aprovados:

| Cenário | Resultado sanitizado |
|---|---|
| Salvar a primeira chave de teste externa | A ação de salvar foi concluída no aplicativo. |
| Reabrir Configurações após o primeiro salvamento | A interface indicou somente **“Chave configurada”**; o campo permaneceu vazio e não republicou o valor. |
| Trocar por uma segunda chave de teste externa | A substituição por novo valor completo foi aceita. |
| Reabrir Configurações após a troca | A interface novamente indicou somente **“Chave configurada”**; o campo permaneceu vazio. |
| Solicitar remoção e cancelar | A chave permaneceu configurada. |
| Solicitar remoção e confirmar | A interface passou para **“Chave não configurada”**. |
| Orientação após remoção | A tela orientou rotação na Administração Next.js e informou que o aplicativo não recupera chaves já exibidas. |

## Critérios validados

- O provisionamento é manual e independente da Administração Next.js.
- Uma credencial salva é representada apenas por status sanitizado, sem preenchimento posterior do campo.
- A troca requer um novo valor completo, obtido externamente.
- A remoção exige confirmação e o cancelamento não remove a credencial.
- Após remoção, a orientação de rotação fica disponível sem tentativa de recuperar o segredo.
- Nenhum segredo foi registrado nesta evidência.

## Resultado

**SUCESSO no escopo da tarefa 60.3.** A validação física do fluxo de credencial foi concluída no Galaxy S25+ com confirmação do operador. Esta tarefa não alterou código, configurações, dados da fila E2, parâmetros operacionais, status de outras tarefas nem aprovou o Validation Gate E3. As tarefas 60.4–60.7 e o Gate 61 permanecem fora deste escopo.
