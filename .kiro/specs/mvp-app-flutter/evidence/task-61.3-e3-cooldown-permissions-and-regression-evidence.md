# Evidência da tarefa 61.3 — Cooldown/distância, permissões e regressões E0/E1/E2

## Escopo

- Tarefa executada: **61.3 — Apresentar atualização segura de cooldown/distância, permissões e regressões E0/E1/E2, incluindo Diagnóstico.**
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- O diretório da spec não contém `.config` nem `.config.kiro`; é uma spec regular, não um bugfix.
- Esta tarefa consolida evidências físicas sanitizadas e executa regressões automatizadas dirigidas. Não altera código de produção, dependências, manifestos, dados locais, configurações, credenciais, evidências históricas ou o estado das tarefas 61.4–61.6. E4 e E5 não foram iniciadas.

## Atualização segura de cooldown e distância

A atualização de parâmetros E3 preserva a referência de último aceite que protege o cooldown. O contrato `CooldownConfigurationUpdater` altera apenas os mínimos ativos; a referência é mantida por criação confirmada (`commit`) ou pela restauração E2 da fila. Portanto, salvar parâmetros não converte um toque ainda precoce em registro aceito e não reinicia a deduplicação local.

A validação automatizada dirigida desta tarefa incluiu:

- defaults aprovados de 5 segundos e 15 metros;
- regra de aceite por tempo **ou** distância, com limites inclusivos;
- bloqueio somente quando tempo e distância permanecem ambos abaixo dos mínimos;
- relógio regressivo tratado como abaixo do limiar temporal;
- restauração da referência de cooldown pela maior `queueSequence` da fila E2;
- atualização de mínimos sem limpar uma referência E2 restaurada;
- retorno de Configurações para Operação recarregando os mínimos sem liberar um toque precoce;
- preservação de recursos e da fila durante a atualização da rota.

A observação física sanitizada em [task-60.5-cooldown-distance-force-stop-recovery.md](task-60.5-cooldown-distance-force-stop-recovery.md) confirma no Galaxy S25+ que valores positivos não secretos de cooldown e distância foram salvos, mantidos após force-stop e reabertura, e não removeram nem degradaram as cinco pendências E2. A fila permaneceu `Pronta`, sem captura em andamento ou crash. Essa evidência não reproduz URL, credencial, coordenadas, imagens, UUIDs ou paths internos.

## Permissões da Operação

A cobertura dirigida confirma que a Operação:

- mantém `Registrar buraco` desabilitado enquanto câmera ou localização válida não estiverem prontas;
- permite tentar novamente somente a permissão recusada, sem reinicializar o recurso independente;
- deduplica tentativas repetidas enquanto uma nova aquisição está em curso;
- orienta a abertura dos detalhes Android quando a permissão está permanentemente negada e serializa a ação;
- bloqueia registros fora de `resumed`, libera recursos ao suspender a rota e aguarda a limpeza antes de readquirir câmera e GPS.

A observação física de negação permanente, ação de detalhes Android e retorno ainda não pode ser marcada como aprovada. Conforme [task-60.6-permanent-permission-denial-navigation.md](task-60.6-permanent-permission-denial-navigation.md), as tentativas controladas não produziram checkpoints físicos suficientes antes de falhar; a permissão de câmera foi restaurada ao baseline. A limitação permanece classificada como **não executada**, e não como comportamento aprovado ou reprovado.

## Regressões E0, E1 e E2, incluindo Diagnóstico

Os testes cobrem a transferência ordenada de ownership entre Operação e Diagnóstico: a Operação libera câmera, localização, stream e tela ligada antes de abrir a sessão E0; o retorno só readquire um conjunto novo após o descarte completo da sessão de Diagnóstico. Toques repetidos não criam rotas/sessões duplicadas e a cobertura verifica que não há sobreposição de câmera, GPS, stream ou autoridade de permissão.

A regressão E0 valida a preservação de preview traseiro, permissões seriais, GPS, mensagens controladas, HTTPS diagnóstico restrito e limpeza por ciclo de vida. A E0 continua separada de ocorrência, fila e configuração de entrega. A rota preservada continua sendo:

```text
Operação E1/E2 → Diagnóstico E0 → Operação E1/E2
```

A evidência física histórica [task-51.8-e0-e1-regression-and-negative-scope.md](task-51.8-e0-e1-regression-and-negative-scope.md) observou essa rota integralmente no Galaxy S25+, incluindo preview/GPS antes e depois, banner manual, Diagnóstico E0, HTTPS diagnóstico manual com falha controlada no destino fictício e pendências preservadas. A atualização E3 também preservou fisicamente pendências, preview, GPS e modo manual no aparelho, conforme [task-60.1-e3-preserving-update.md](task-60.1-e3-preserving-update.md).

Contudo, a reexecução física específica de E3 da rota Operação → Diagnóstico → Operação pertence ao cenário não concluído da tarefa 60.6. A classificação consolidada em [task-60.7-e3-scenario-classification.md](task-60.7-e3-scenario-classification.md) mantém a regressão combinada E0–E2 como **não executada** até que o roteiro sanitizado obtenha seus checkpoints no aparelho. A evidência histórica e os testes atuais são complementares e não substituem essa observação E3 pendente.

## Validação automatizada executada nesta tarefa

O comando de execução única abaixo concluiu com código de saída `0`:

```text
flutter test test/domain/cooldown_policy_test.dart test/operation/operation_controller_test.dart test/operation/operation_diagnostic_navigation_test.dart test/operation/operation_permission_denial_test.dart test/operation/operation_queue_bootstrap_test.dart test/e0/e0_regression_test.dart --reporter expanded
```

| Conjunto | Resultado e cobertura relevante |
|---|---|
| Cooldown | Defaults, regra OR, referências recuperadas E2, atualização de mínimos e toque precoce bloqueado. |
| Operação | Readiness, bloqueio por lifecycle, cancelamento/limpeza, tela ligada e atualização de cooldown sem reset. |
| Navegação | Configurações e Diagnóstico usam sessões únicas, liberam recursos antes da rota e readquirem somente após descarte. |
| Permissões | Negação temporária, retry independente, negação permanente, orientação de detalhes Android e ação serializada. |
| Fila E2 | Bootstrap, restauração de pendências/referência, contagens e suspensão para Diagnóstico independente da inicialização da fila. |
| Diagnóstico E0 | Preview traseiro, permissões seriais, GPS, HTTPS restrito, mensagens controladas e limpeza de lifecycle. |

**Resultado:** `51` testes aprovados, sem falha.

## Resultado e pendência manual

**Sucesso no escopo da tarefa 61.3.** A atualização segura de cooldown/distância, as garantias de permissões e as regressões automatizadas E0/E1/E2, incluindo Diagnóstico, foram apresentadas com referências sanitizadas às evidências físicas aplicáveis.

Antes de qualquer decisão de aprovação do Validation Gate E3, permanece obrigatória a reexecução física sanitizada no Galaxy S25+ do cenário de permissão permanentemente negada, abertura dos detalhes Android e rota Operação → Diagnóstico → Operação. A aprovação explícita do usuário para o Gate E3 também continua reservada às tarefas 61.5 e 61.6; esta tarefa não solicita nem registra essa decisão.
