# Evidência da tarefa 51.4 — Ciclo de vida, recuperação e cooldown E2

## Escopo executado

- Subtarefa executada: **51.4 — Pausar/retomar, fechar ou force-stop e reabrir; confirmar pendências recuperadas, contador da sessão reiniciado sem zerar a fila e cooldown restaurado de forma observável segura.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Dispositivo físico: Samsung Galaxy S25+ (`SM-S936B`), conectado por ADB autorizado durante a execução.
- Aplicativo instalado: `com.vitor.pavimenta_ai_mobile`, versão `1.0.0` (`versionCode=1`).
- Nenhum arquivo de código, dependência, configuração Android, dado de fila, tarefa adjacente ou Validation Gate foi alterado. Os acionamentos manuais abaixo somente criaram as pendências necessárias ao cenário físico.

## Pausa e retomada

Com a tela física exibindo `Pendências: 4` e `4 registros criados`, o aplicativo foi enviado ao segundo plano e retomado. A atividade voltou em estado `HOT`, sem crash; a interface continuou exibindo a fila pronta, o resultado local já confirmado e o controle de registro habilitado. Este cenário não reiniciou o processo nem alterou a pendência observada.

## Force-stop, reabertura e separação de contadores

1. Com cinco pendências locais confirmadas, foi executado `am force-stop` e a atividade foi aberta novamente em início frio (`LaunchState: COLD`).
2. Após a recuperação física, a tela exibiu simultaneamente `Fila local: Pronta`, `Pendências: 5` e `0 registros criados`.
3. Portanto, as pendências persistentes foram reconstruídas depois do processo ser encerrado, enquanto o contador da sessão iniciou uma nova execução em zero; a reabertura não limpou a fila.

Nenhum UUID, horário, coordenada, velocidade, digest, caminho privado ou conteúdo de JPEG foi registrado nesta evidência.

## Cooldown restaurado — cenário cronometrado

O aparelho permaneceu sem deslocamento intencional. Para evitar a ambiguidade observada na tarefa 51.3, foi executado um único ciclo cronometrado após a fila já estar pronta:

1. Um novo registro aceito elevou a fila de 9 para 10 pendências.
2. Após **1.597 ms**, o aplicativo sofreu force-stop.
3. A atividade foi aberta novamente, a fila recuperou e um novo toque de registro ocorreu **3.946 ms** após o toque inicial — abaixo do cooldown padrão de 5 segundos.
4. A interface física exibiu `Status: Ignorado por cooldown` e `Cooldown: Registro ignorado: tempo e distância ainda abaixo dos mínimos.`
5. A contagem permaneceu em `Pendências: 10`; a própria interface informou que nenhuma imagem, UUID ou ocorrência foi criada para o toque rejeitado.

Esse resultado demonstra de forma observável que a referência de cooldown foi restaurada a partir da pendência recuperada: a tentativa pós-reabertura não foi tratada como primeira ocorrência, não criou uma pendência adicional e recebeu o feedback seguro previsto.

## Observação de versão instalada

Em estados de sucesso, a árvore de acessibilidade do APK instalado ainda mostrou a descrição residual `A ocorrência foi criada somente em memória.`, embora o mesmo APK tenha exibido `Sucesso: Buraco salvo na fila local.` e a contagem persistente. Essa inconsistência textual não impediu as observações de recuperação desta subtarefa, mas deve ser considerada antes de qualquer apresentação do Gate E2; esta tarefa não reinstalou APK nem alterou a interface.

## Resultado

| Critério da 51.4 | Resultado | Evidência física |
|---|---|---|
| Pausar e retomar sem perda observável | Aprovado | Retomada `HOT`, sem crash, com fila pronta e pendências mantidas. |
| Force-stop/reabertura recupera pendências | Aprovado | Reabertura `COLD` mostrou `Pendências: 5`. |
| Contador da sessão reinicia sem zerar a fila | Aprovado | Mesma tela física mostrou `0 registros criados` e `Pendências: 5`. |
| Cooldown é restaurado com feedback seguro | Aprovado | Retentativa em 3.946 s foi ignorada, com `Pendências: 10` inalteradas e feedback explícito de tempo/distância abaixo dos mínimos. |

A subtarefa **51.4 foi executada com sucesso**. As tarefas 51.5–51.9 e o Validation Gate E2 permanecem inalterados e não foram executados.
