# Evidência da tarefa 60.4 — Ausência de configuração de envio no Galaxy S25+

## Escopo executado

- Tarefa: **60.4 — Verificar ausência de URL/chave: Operação e fila continuam funcionando, indicador informa configuração pendente e não há tráfego/tentativa de ocorrência.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- A pasta da spec não contém `.config` nem `.config.kiro`; trata-se de spec regular, não bugfix.
- Dispositivo físico: Samsung `SM-S936B` (Galaxy S25+), conectado ao ADB Windows no estado `device`.
- APK: a atualização preservadora E3 registrada em `task-60.1-e3-preserving-update.md`.
- Limite: esta validação não configurou URL ou credencial, não tentou integração HTTP, não abriu Diagnóstico, não alterou permissões, não limpou dados e não executou as tarefas 60.5–60.7 ou o Gate 61.

## Condição inicial confirmada

Na tela **Configurações**, a `BASE_URL` opcional estava vazia e a credencial era mostrada somente como **“Chave não configurada”**. Nenhuma URL, API key, conteúdo de armazenamento seguro, coordenada, imagem, UUID ou caminho interno foi registrado.

Na volta à tela **Operação**, a fila local estava **Pronta** com **4 pendências**. O painel **Envio futuro** mostrava o estado **Pendente** e a mensagem sanitizada:

> Configuração para envio pendente. Configure destino e credencial para habilitar o envio futuro.

Câmera traseira e GPS estavam prontos, e o controle de registro manual permanecia disponível.

## Validação da operação e fila

Com URL e chave ausentes, foi acionado uma vez o controle **Registrar buraco**. Após a conclusão controlada da captura e persistência local, a interface observada no aparelho mostrou:

| Indicador | Antes | Depois |
|---|---:|---:|
| Registros criados na sessão | 0 | 1 |
| Pendências da fila local | 4 | 5 |
| Saúde da fila | Pronta | Pronta |
| Processamento | Pronto | Concluído: ocorrência salva na fila local |
| Configuração de envio | Pendente | Pendente |

A criação local ocorreu normalmente e o painel de envio continuou explicitando que a configuração é necessária para um envio futuro. Não houve tela, estado ou feedback de envio, tentativa, autenticação, resposta HTTP, retry ou remoção da fila.

## Verificação automatizada complementar

O comando abaixo foi executado com sucesso:

```text
flutter test test/operation/operation_controller_test.dart test/operation/operation_screen_test.dart test/architecture/e3_configuration_boundaries_test.dart
```

Resultado: **31 testes aprovados**.

A cobertura relevante confirmou que:

- configuração pendente não bloqueia o registro manual nem modifica a contagem de pendências;
- a tela apresenta o indicador sanitizado de configuração pendente;
- E3 não contém cliente ou transporte de ocorrências, `POST`, `multipart/form-data`, `Authorization`, `ApiKey`, worker ou backoff.

A ausência de transporte antes de E4, combinada ao fluxo físico observado que apenas persistiu a quinta pendência, demonstra que o acionamento não gerou tráfego nem tentativa de ocorrência.

## Resultado

**SUCESSO no escopo da tarefa 60.4.** Com `BASE_URL` e credencial ausentes, Operação continuou apta à captura manual, a fila persistente recebeu e reteve a nova ocorrência local, o indicador informou configuração de envio pendente e não existe nem foi observada tentativa de tráfego de ocorrência. Esta tarefa não altera o status das tarefas, não aprova o Validation Gate E3 e deixa as tarefas 60.5–60.7 para execução própria.
