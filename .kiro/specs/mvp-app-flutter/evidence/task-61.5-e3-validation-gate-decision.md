# Evidência da tarefa 61.5 — Roteiro e decisão do Validation Gate E3

## Escopo

- Tarefa executada: **61.5 — Reunir o roteiro e registrar decisão do usuário.**
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- A pasta da spec não contém `.config` nem `.config.kiro`; é uma spec regular, não um bugfix.
- Esta tarefa não alterou código, dependências, configuração Android, fila, credencial, dados locais ou evidências históricas. Não iniciou E4 ou E5.

## Roteiro reunido

| Área | Evidência reunida | Situação registrada |
|---|---|---|
| Qualidade, APK, manifestos, backup e escopo de dependências | `task-61.1-e3-technical-validation.md` | Formatação, análise, 265 testes, build debug, manifests e inspeção de backup aprovados tecnicamente. |
| Parâmetros, credencial e ausência de configuração de entrega | `task-61.2-e3-settings-credential-and-missing-configuration-evidence.md` | Persistência não secreta, armazenamento seguro, status sanitizado e operação local sem destino/chave foram apresentados. |
| Cooldown, permissões e regressões E0–E2 | `task-61.3-e3-cooldown-permissions-and-regression-evidence.md` | Cobertura automatizada aprovada; limitações físicas pendentes preservadas. |
| Limites negativos E3 | `task-61.4-e3-negative-scope-inspection.md` | Sem transporte de ocorrência, autenticação, multipart, worker, backoff, YOLO/TFLite/modelo/inferência. |
| Classificação física consolidada | `task-60.7-e3-scenario-classification.md` | Cenários aprovados e não executados separados sem inferir aprovação a partir de testes. |

## Limitações físicas declaradas antes da decisão

Os seguintes cenários continuam classificados como **não executados** na evidência consolidada:

1. salvar e reabrir confiança futura, FPS futuro e URL HTTPS fictícia válida;
2. mensagens inequívocas para URL e números inválidos, incluindo recusa do sufixo `/api/v1/occurrences`;
3. permissão permanentemente negada, abertura dos detalhes Android e retorno ao aplicativo;
4. rota física `Operação → Diagnóstico → Operação` sem duplicação de câmera/GPS ou crash;
5. regressão física combinada E0–E2 que depende dessa rota.

Nenhuma dessas limitações foi ocultada, reclassificada ou tratada como aprovada por evidência automatizada.

## Decisão explícita do usuário

Aprovação explícita do Validation Gate E3

A decisão acima foi fornecida explicitamente pelo usuário após a apresentação do roteiro e das limitações. Este registro conserva tais limitações como evidência factual e não inicia nenhuma tarefa da E4.
