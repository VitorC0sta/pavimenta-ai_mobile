# Evidência da tarefa 75.1 — Aprovação do Gate E4 e baseline E5

## Escopo executado

- Tarefa: **75.1 — Registrar a aprovação do Gate E4 e executar a baseline de formatação, análise, suíte completa e build Android na toolchain atual, sem alterar código.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Nenhum arquivo em `lib/`, `test/`, `android/`, `pubspec.yaml` ou `pubspec.lock` foi alterado. Nenhuma dependência, asset ou código E5 foi adicionado.
- O estado Git antes desta evidência continha somente as alterações de planejamento E5 em `requirements.md`, `design.md`, `tasks.md` e `tasks.meta.json`.

## Gate E4 registrado

A pré-condição da E5 está atendida: a decisão `Aprovação explícita do Validation Gate E4` está registrada em [task-74.7-74.8-e4-validation-gate-decision.md](task-74.7-74.8-e4-validation-gate-decision.md). Nenhuma evidência histórica foi editada.

## Baseline técnica

Toolchain observada, sem instalar ou atualizar componentes: Flutter `3.24.3` stable (framework `2663184aa7`, engine `36335019a8`), Dart `3.5.3`, Java `21.0.2`, Android SDK com `android-34` e build-tools `34.0.0`, AGP `8.5.1`, Kotlin `1.8.22`, Gradle wrapper `8.7`.

| Verificação | Comando | Resultado |
|---|---|---|
| Formatação | `dart format --output=none --set-exit-if-changed lib test` | Aprovada: `Formatted 165 files (0 changed)`; código de saída 0. |
| Análise estática | `flutter analyze` | Aprovada: `No issues found!`; código de saída 0. |
| Suíte completa | `flutter test` | Aprovada: `All tests passed!` com **819 testes**; código de saída 0. |
| Build Android debug | `flutter build apk --debug` | Aprovado: `Built build\app\outputs\flutter-apk\app-debug.apk`; código de saída 0. |

O build repetiu o aviso não bloqueante já conhecido sobre plugins que pedem NDK `26.1.10909125`.

## Artefato

| Campo | Valor |
|---|---|
| APK | `build\app\outputs\flutter-apk\app-debug.apk` |
| Tamanho | `126327599` bytes |
| SHA-256 | `624E06CBEFC69DF3B50DAB7009650597590511948C701BC3C7C38F18EA1FE34F` |

O APK debug não é reproduzível bit a bit; este hash identifica o build de referência E4 antes de qualquer mudança da E5.

## Resultado

**Baseline da tarefa 75.1 aprovada.** As quatro validações passaram na toolchain atual. Esta evidência não executa 75.2–75.6.
