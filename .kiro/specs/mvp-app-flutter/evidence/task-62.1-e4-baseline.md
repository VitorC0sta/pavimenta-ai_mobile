# Evidência da tarefa 62.1 — Aprovação do Gate E3 e baseline E4

## Escopo executado

- Tarefa: **62.1 — Registrar a aprovação do Gate E3 e executar a baseline de formatação, análise, suíte completa e build Android sem alterar comportamento E0–E3.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Documentos consultados: `requirements.md`, `design.md` e `tasks.md` do spec `mvp-app-flutter`.
- O diretório do spec não contém `.config` nem `.config.kiro`; trata-se de uma spec regular, não de bugfix.
- Esta é uma nova evidência exclusiva da baseline E4. Nenhuma evidência histórica (E0, E1, E2, E3) foi editada. Nenhum arquivo em `lib/`, `test/`, `android/`, `pubspec.yaml` ou `pubspec.lock` foi alterado. A dependência `http` ainda não foi adicionada (tarefa 62.4) e nenhuma funcionalidade E4 foi iniciada.

## Gate E3 registrado

A pré-condição da E4 está atendida. A evidência [task-61.5-e3-validation-gate-decision.md](task-61.5-e3-validation-gate-decision.md) registra literalmente:

> **Decisão do usuário: Aprovação explícita do Validation Gate E3.**

A aprovação foi dada após a apresentação do roteiro e das limitações físicas E3. O encerramento do ciclo E3 está em [task-61.6-e3-stop-after-decision.md](task-61.6-e3-stop-after-decision.md), e o novo ciclo E4 foi iniciado por solicitação posterior do usuário.

As limitações físicas declaradas no Gate E3 permanecem históricas e **não foram reclassificadas** por esta baseline:

1. salvar e reabrir confiança futura, FPS futuro e URL HTTPS fictícia válida;
2. mensagens de URL e números inválidos, incluindo recusa do sufixo `/api/v1/occurrences`;
3. permissão permanentemente negada, detalhes Android e retorno;
4. rota física `Operação → Diagnóstico → Operação`;
5. regressão física combinada E0–E2 que depende dessa rota.

## Baseline técnica

Toolchain observada (sem instalar ou atualizar nenhum componente global): Flutter `3.24.3` stable (framework `2663184aa7`, engine `36335019a8`), Dart `3.5.3`, DevTools `2.37.3`.

| Verificação | Comando | Resultado |
|---|---|---|
| Formatação | `dart format --output=none --set-exit-if-changed lib test` | Aprovada: `Formatted 94 files (0 changed)`; código de saída 0. |
| Análise estática | `flutter analyze` | Aprovada: `No issues found!`; código de saída 0. |
| Suíte completa | `flutter test` (execução única) | Aprovada: `All tests passed!` com **265 testes**; código de saída 0. |
| Build Android debug | `flutter build apk --debug` | Aprovado: `Built build\app\outputs\flutter-apk\app-debug.apk`; código de saída 0. |

O número de testes (265) coincide com o registrado na validação técnica do Gate E3 (tarefa 61.1).

O build emitiu somente o aviso não bloqueante já conhecido: os plugins `package_info_plus`, `path_provider_android`, `shared_preferences_android`, `sqflite_android`, `wakelock_plus` e outros requerem Android NDK `26.1.10909125`, enquanto o projeto usa NDK `23.1.7779620`. O APK foi produzido com sucesso. Nenhuma mudança de NDK, Flutter, SDK, Gradle, Java ou configuração Android foi feita; o aviso é um achado de baseline preexistente.

## Artefato

| Campo | Valor |
|---|---|
| APK | `build\app\outputs\flutter-apk\app-debug.apk` |
| Tamanho | `125953478` bytes |
| SHA-256 | `175131A96F789807EEA81471A2EE1BFB4671E4487335E9BFC7426A6200360D9A` |

O APK debug E3 registrado na tarefa 59.3 tinha `125953496` bytes e SHA-256 `2FAC8A62…C1D23E`. A diferença de 18 bytes e do hash ocorre porque o APK debug não é reproduzível bit a bit entre builds (metadados de empacotamento e assinatura debug). O código-fonte, o `pubspec.yaml`, o `pubspec.lock` e a configuração Android não mudaram desde o Gate E3. Portanto, o hash acima identifica este build da baseline E4 e não substitui o hash E3 histórico.

## Integridade do escopo

- `git diff --stat -- lib test android pubspec.yaml pubspec.lock` não retornou diferenças.
- `pubspec.yaml` não contém `http` nem `dio`.
- O estado Git antes desta evidência continha somente as modificações de orquestração (`design.md`, `tasks.md`, `tasks.meta.json`) e as evidências não versionadas 61.1–61.6.

## Achados de baseline

Nenhuma falha preexistente em formatação, análise ou testes. Único achado: o aviso de NDK acima, já conhecido e não bloqueante. Nenhum bloqueio de ferramenta.

## Reprodução

Na raiz do repositório, com Flutter `3.24.3` / Dart `3.5.3`:

```
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

## Resultado

**Baseline da tarefa 62.1 aprovada.** O Gate E3 foi registrado e as quatro validações passaram. Este registro não executa 62.2–62.5 e não altera o comportamento ou as evidências de E0–E3.
