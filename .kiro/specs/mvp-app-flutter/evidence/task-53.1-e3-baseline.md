# Evidência da tarefa 53.1 — Aprovação E2, revisão do design E3 e baseline

## Escopo executado

- Tarefa: **53.1 — Registrar a aprovação do Gate E2, revisar o design E3 e executar a baseline de formatação, análise, suíte completa e build sem alterar E0–E2.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Documentos consultados antes da execução: `requirements.md`, `design.md` e `tasks.md` do spec `mvp-app-flutter`.
- O diretório do spec não contém `.config` nem `.config.kiro`; trata-se de uma spec regular, não de bugfix.
- Esta é uma nova evidência exclusiva da E3. Nenhuma evidência histórica E0, E1 ou E2 foi editada, e nenhum arquivo em `lib/`, `test/`, `android/`, `pubspec.yaml` ou `pubspec.lock` foi alterado nesta tarefa.

## Gate E2 registrado

A pré-condição da E3 está atendida. A evidência [task-52.6-validation-gate-decision.md](task-52.6-validation-gate-decision.md) registra literalmente:

> **Decisão do usuário: Aprovação explícita do Validation Gate E2.**

A aprovação sucedeu a revalidação física no Samsung Galaxy S25+ registrada em [task-52.6-e2-revalidation-2026-10-26.md](task-52.6-e2-revalidation-2026-10-26.md). As limitações físicas então declaradas permanecem históricas e não foram reclassificadas por esta baseline.

## Revisão do design E3

A seção `Design adicional — E3: Configuração local e credencial protegida` foi revisada contra RF-13, RF-19, RF-20.8, RF-21 e as fronteiras do plano E3. Ela estabelece, sem implementar nesta tarefa:

- configuração não secreta versionada para `BASE_URL`, cooldown, distância, confiança futura e FPS futuro, com defaults de 5 s, 15 m, 0,5 e 5;
- credencial separada, cujo valor completo só existe durante a submissão e dentro do adaptador seguro Android; interface, estados, logs e evidências usam somente status sanitizado;
- HTTPS em todas as variantes, com futura exceção limitada a `http://localhost:3000` exclusivamente em debug;
- atualização futura de cooldown/distância sem apagar a referência de último aceite recuperada pela fila E2;
- navegação de Configurações usando o protocolo de suspensão/reconciliação de recursos da Operação, preservando também a rota e o ciclo próprio do Diagnóstico E0.

O design exclui expressamente nesta etapa cliente HTTP de ocorrências, endpoint, `Authorization`, multipart, envio, remoção remota, retry/backoff, worker, URL real, chave funcional, YOLO, TFLite e inferência. Assim, a E3 futura não altera a operação E1/E2 sem URL/chave nem a fila E2; esta tarefa 53.1 não introduziu nenhum desses comportamentos.

## Baseline técnica

Toolchain observada: Flutter `3.24.3` stable (framework `2663184aa7`), Dart `3.5.3`.

| Verificação | Comando | Resultado |
|---|---|---|
| Formatação | `dart format --output=none --set-exit-if-changed lib test` | Aprovada: `Formatted 75 files (0 changed) in 0.88 seconds.` |
| Análise estática | `flutter analyze` | Aprovada: `No issues found! (ran in 3.4s)` |
| Suíte completa | `flutter test` | Aprovada: `All tests passed!` com 207 testes no runner, incluindo propriedades E2 de 120 entradas. |
| Build Android debug | `flutter build apk --debug` | Aprovado: `Built build\app\outputs\flutter-apk\app-debug.apk`. |

Durante a suíte, o teste de recusa de versão futura do schema emitiu a mensagem esperada `Unsupported queue schema version: found 2, supported 1.` e ainda concluiu com êxito; não é falha de baseline.

O build emitiu somente o aviso não bloqueante já conhecido de que plugins Android requerem NDK `26.1.10909125`, enquanto o projeto está configurado com NDK `23.1.7779620`. O APK foi produzido com sucesso. Nenhuma atualização de NDK, Flutter, SDK, Gradle, Java ou configuração Android foi feita nesta tarefa.

## Artefato e integridade do escopo

| Campo | Valor |
|---|---|
| APK | `build\app\outputs\flutter-apk\app-debug.apk` |
| Tamanho | `109794930` bytes |
| SHA-256 | `6F70B80B4D5D7345C9F58234354A8C00834A004BA7CAFE5F7B9C8BA2DC8142EF` |

Antes da criação desta nova evidência, o estado Git continha somente as modificações preexistentes de orquestração em `tasks.md` e `tasks.meta.json`, referentes ao estado em progresso da tarefa. A inspeção não encontrou diferenças em evidências históricas nem em fontes, testes, configuração Android, `pubspec.yaml` ou `pubspec.lock` atribuíveis a esta tarefa.

## Resultado

**Baseline da tarefa 53.1 aprovada.** O Gate E2 aprovado foi registrado, o design E3 foi revisado e as quatro validações exigidas passaram. Este registro não aprova o Gate E3, não executa 53.2 ou 53.3 e não modifica comportamento, evidência histórica ou escopo de E0–E2.
