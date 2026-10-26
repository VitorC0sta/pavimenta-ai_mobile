# Evidência da tarefa 32.1 — Build Android debug da E1

## Escopo

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`
- Subtarefa exclusiva: **32.1 — Gerar build Android debug em execução única, sem URL de produção, API key ou configuração de integração de ocorrências**.
- Documentos normativos consultados: `requirements.md`, `design.md` e `tasks.md` da spec `mvp-app-flutter`.
- Limite preservado: somente E0/E1; nenhuma tarefa 32.2–32.4 ou funcionalidade E2–E5 foi executada ou implementada.

## Verificação sanitizada anterior ao build

A configuração e os fontes relevantes do repositório mobile foram inspecionados antes da compilação:

- nenhuma `BASE_URL`, `DEVICE_API_KEY` ou API key foi encontrada na configuração incorporável da aplicação;
- nenhuma configuração de cliente, envio ou integração real com a API de ocorrências foi encontrada;
- a única configuração de URL em código é `E0_DIAGNOSTIC_URL`, pertencente ao Diagnóstico E0 preservado;
- sem `--dart-define`, esse diagnóstico usa somente o destino fictício padrão sob `.invalid`;
- a referência a `/api/v1/occurrences` no cliente E0 é exclusivamente uma regra local de rejeição do caminho, não uma integração;
- nenhum valor funcional de URL, credencial ou segredo foi registrado nesta evidência.

## Comando executado

O build foi executado exatamente uma vez, sem `--dart-define`, variável de URL, API key ou qualquer argumento de integração:

```powershell
flutter build apk --debug
```

Diretório de execução:

```text
c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile
```

## Resultado

Saída conclusiva normalizada:

```text
Running Gradle task 'assembleDebug'... 33.1s
√ Built build\app\outputs\flutter-apk\app-debug.apk
Exit Code: 0
```

O build apresentou aviso não bloqueante: o projeto declara Android NDK `23.1.7779620`, enquanto plugins resolvidos solicitam `26.1.10909125`. Apesar do aviso, `assembleDebug` terminou com sucesso. Nenhuma configuração Android foi alterada, pois correção ou inspeção ampliada extrapolaria a subtarefa 32.1.

Artefato confirmado no filesystem:

```text
c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile\build\app\outputs\flutter-apk\app-debug.apk
```

A verificação de presença não executou nova compilação. Hash, metadados, identidade e inspeção ampliada do APK não foram realizados, pois pertencem às subtarefas 32.2–32.4.

## Conclusão

**SUCESSO.** O APK Android debug da E1 foi gerado em uma única execução, com código de saída `0`, sem fornecer URL de produção, API key ou configuração de integração de ocorrências. O escopo E0/E1 foi preservado e nenhuma subtarefa posterior da tarefa 32 foi executada.
