# Evidência da tarefa 60.6 — Permissão permanentemente negada e retorno de navegação

## Escopo

- Tarefa: **60.6 — Verificar permissão permanentemente negada em cenário controlado, ação de detalhes Android e retorno; regressar Operação → Diagnóstico → Operação sem câmera/GPS duplicados ou crash.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- A pasta da spec não contém `.config`; trata-se de uma spec regular, não bugfix.
- Limite: não houve alteração de código, dependências, configurações E3, credencial, fila, imagens ou registros. Nenhuma URL, API key, coordenada, UUID, screenshot ou dump de interface foi persistido.

## Baseline e cobertura automatizada dirigida

- Flutter local: `3.24.3` com Dart `3.5.3`.
- Dispositivo físico reconhecido pelo ADB Windows: Samsung `SM-S936B` (Galaxy S25+), serial `RQGL701ZV7Z`, estado `device`.
- Pacote instalado: `com.vitor.pavimenta_ai_mobile`.
- Antes do cenário, o pacote possuía câmera e localização precisa/aproximada concedidas.
- A execução dirigida de `flutter test test/operation/operation_screen_test.dart test/operation/operation_controller_test.dart test/e0/e0_regression_test.dart --reporter expanded` concluiu com êxito para a suíte efetivamente executada, `operation_screen_test.dart`: **31 testes aprovados**. Ela cobre a abertura do Diagnóstico somente após liberar recursos de Operação, a espera pelo descarte completo da sessão E0 antes da reaquisição e o adiamento da reaquisição até `resumed`.

## Tentativa de cenário físico controlado

O cenário planejava aplicar uma negação permanente **somente de câmera** no pacote de teste, verificar a presença da ação **“Abrir configurações da câmera”**, abrir os detalhes Android pelo próprio botão, restaurar a concessão enquanto os detalhes estavam abertos e confirmar, por rótulos de acessibilidade sem registrar conteúdo sensível:

1. retorno para Operação com exatamente um preview traseiro e um indicador GPS pronto;
2. abertura do Diagnóstico E0;
3. retorno Diagnóstico → Operação com exatamente um preview e um indicador GPS pronto;
4. processo vivo e ausência de crash de `AndroidRuntime` para o pacote.

A primeira tentativa não iniciou o cenário porque esta versão de `pm` do aparelho rejeitou a lista de flags em uma única invocação (`user-set,user-fixed`). A mensagem indicou que cada flag deve ser aplicada separadamente.

A segunda tentativa foi ajustada para aplicar `user-set` e `user-fixed` em chamadas separadas. O comando terminou com código `1` antes de emitir qualquer checkpoint sanitizado do roteiro. Portanto, não existe evidência suficiente para afirmar que a ação de detalhes Android, o retorno de configurações ou a sequência Operação → Diagnóstico → Operação foram observados nesta execução.

## Restauração e resultado

A restauração de segurança foi executada e verificada após as tentativas:

```text
CAMERA_PERMISSION_BASELINE_RESTORED=True
```

A câmera terminou concedida e sem `USER_FIXED`; a localização, a fila e as configurações E3 não foram alteradas.

**Resultado da tarefa 60.6: não executada integralmente / bloqueada.** O ambiente físico está acessível e a cobertura automatizada dirigida passou, mas a evidência física obrigatória da ação de detalhes e dos dois retornos ainda precisa ser repetida com instrumentação ADB de UI que exponha somente checkpoints sanitizados. Esta evidência não aprova o Validation Gate E3 e não executa as tarefas 60.7 ou 61.
