# Evidência suplementar da tarefa 60.6 — Reexecução controlada de permissão

## Escopo e preservação

- Tarefa reexecutada: **60.6 — Verificar permissão permanentemente negada em cenário controlado, ação de detalhes Android e retorno; regressar Operação → Diagnóstico → Operação sem câmera/GPS duplicados ou crash.**
- Dispositivo físico acessado: Samsung Galaxy S25+ pelo ADB local do Windows, em estado `device`.
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`. Não há arquivo `.config` na pasta da spec, portanto não é bugfix.
- A evidência anterior `task-60.6-permanent-permission-denial-navigation.md` foi preservada sem edição. Este arquivo registra somente esta reexecução.
- Não foram limpos dados do aplicativo, desinstalado o pacote, removidas pendências, alteradas configurações E3, credencial, URL, imagens ou registros. Não houve acionamento de captura manual.
- Não foram gravados screenshots, dumps de tela, conteúdo de armazenamento, coordenadas, UUIDs, URLs ou credenciais. Um artefato temporário de consulta de interface, criado pelo roteiro, foi removido após a tentativa.

## Procedimento físico e evidências sanitizadas

1. O processo do aplicativo foi encerrado de forma controlada para aplicar o cenário de permissão. Isso não limpa dados do pacote.
2. A permissão de câmera foi revogada no pacote de teste e as flags Android `user-set` e `user-fixed` foram aplicadas em chamadas separadas.
3. A consulta sanitizada do gerenciador de pacotes confirmou a pré-condição:

```text
CHECKPOINT_CAMERA_PERMANENT_DENIAL=True
CHECKPOINT_OPERATION_LAUNCHED=True
```

4. O aplicativo foi aberto no aparelho físico. A coleta seguinte tentou consultar apenas rótulos permitidos da tela, sem imprimir o conteúdo bruto. A primeira consulta não confirmou os rótulos esperados e a segunda consulta atingiu o timeout do executor antes de retornar checkpoints. Como não há observação sanitizada suficiente da interface, a reexecução não infere o resultado da ação de detalhes, do retorno ou da rota.
5. A restauração de segurança foi executada imediatamente. A câmera foi novamente concedida e as flags temporárias foram removidas. A localização permaneceu concedida, e o aplicativo foi aberto novamente sem limpar dados:

```text
CAMERA_PERMISSION_BASELINE_RESTORED=True
FINAL_CAMERA_BASELINE_RESTORED=True
FINAL_LOCATION_PRESERVED=True
FINAL_APP_PROCESS_ALIVE=True
TEMPORARY_UI_ARTIFACT_REMOVED=True
```

## Classificação dos cenários da tarefa 60.6

| Cenário | Classificação | Evidência e limite |
|---|---|---|
| Aplicar no aparelho uma negação permanente controlada apenas para a câmera | **Aprovado** | O estado Android confirmou permissão de câmera revogada com flag permanente antes da abertura do aplicativo. |
| Operação apresentar o estado de permissão bloqueada e a ação para detalhes Android | **Não executado** | A consulta sanitizada dos rótulos da interface não concluiu: uma tentativa não comprovou os rótulos e a seguinte expirou. Nenhuma inferência foi feita a partir do código ou dos testes. |
| Acionar os detalhes Android pelo botão da Operação e retornar ao aplicativo | **Não executado** | Sem checkpoint de interface que localize a ação, o botão não foi acionado por coordenada ou por atalho. A abertura direta de Configurações não substitui a ação exigida e não foi usada. |
| Navegar fisicamente de Operação para Diagnóstico e retornar a Operação | **Não executado** | O cenário depende do retorno anterior e não foi iniciado para não substituir a evidência física exigida por automação indireta. |
| Confirmar, após a rota, uma única câmera, um único GPS e ausência de crash | **Não executado** | O processo estava vivo após a restauração, mas isso não comprova a sequência de rota nem ausência de duplicação. |

Não houve cenário **Reprovado**: não foi observado comportamento físico contrário ao requisito. Os cenários não executados permanecem assim por ausência de prova física sanitizada suficiente, não por aprovação automatizada.

## Alterações e bloqueio

- **Alteração produzida:** somente esta evidência suplementar. Nenhum arquivo de código, dependência, manifesto, configuração do aplicativo ou evidência histórica foi modificado por esta reexecução.
- **Bloqueio:** o mecanismo disponível para consultar a semântica da UI do aparelho não concluiu de forma confiável dentro do tempo. Uma repetição futura precisa de observação física direta da ação de detalhes e dos retornos, ou de instrumentação de UI que produza somente checkpoints sanitizados e responda de forma estável.
- Esta reexecução não aprova a tarefa 60.6, não reclassifica a tarefa 60.7 e não executa o Validation Gate E3.
