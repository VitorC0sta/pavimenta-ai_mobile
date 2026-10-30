# Evidência da tarefa 61.2 — Parâmetros, credencial segura e configuração ausente

## Escopo

Esta evidência apresenta somente a validação E3 solicitada em 61.2: validação e persistência de parâmetros não secretos, armazenamento seguro de credencial, apresentação sanitizada, substituição e remoção de chave, e o comportamento de E1/E2 sem configuração de entrega. Não aprova o Validation Gate E3 e não cobre permissões, regressões de navegação, nem fronteiras negativas de E4/E5, que pertencem às tarefas 61.3 e 61.4.

A spec não contém `.config` nem `.config.kiro`; portanto, é uma spec regular, não um bugfix.

Nenhuma URL funcional, API key, prefixo, comprimento de chave, identificador de ocorrência, coordenada, imagem, path privado, conteúdo de preferência ou conteúdo de armazenamento seguro é reproduzido neste registro.

## Evidência automatizada executada nesta tarefa

Os comandos abaixo foram executados no repositório mobile em modo único e concluíram sem falhas:

| Verificação | Resultado |
|---|---|
| `flutter test` dirigido a adapters E3, controller/tela de Configurações, casos de uso de configuração, controller de Operação e limites arquiteturais | **37 testes aprovados** |
| Teste dirigido de `SharedPreferencesOperationalConfigurationStore` para salvar e recarregar todos os campos não secretos no documento versionado | **1 teste aprovado** |

A primeira execução comprovou que a store de credencial só consulta presença, aceita substituição e remoção, sem leitura pela porta de status; que a interface mantém o campo vazio após salvamento; que falhas usam feedback estático; e que a projeção de configuração pendente não bloqueia a operação local. A segunda execução comprovou o round-trip de `BASE_URL` opcional, cooldown, distância mínima, limiar de confiança e FPS máximo futuro.

## Parâmetros não secretos: validação e persistência

- `SharedPreferencesOperationalConfigurationStore` persiste um documento versionado separado, sem campo de API key ou credencial.
- O teste de round-trip executado nesta tarefa comprovou que todos os cinco parâmetros não secretos são restaurados sem alteração.
- A tela e os casos de uso verificam valores positivos para cooldown, distância e FPS, intervalo inclusivo de 0 a 1 para confiança, e origem válida para `BASE_URL`; URL ausente continua permitida.
- A evidência física `task-60.5-cooldown-distance-force-stop-recovery.md` comprova no Galaxy S25+ o salvamento de cooldown e distância, preservação das cinco pendências E2, force-stop e reabertura com os mesmos valores e a fila pronta.
- A evidência física `task-60.2-e3-settings-physical-reexecution.md` confirma os defaults de confiança e FPS na reabertura, mas registra como **não executados** os round-trips físicos de confiança, FPS e URL, além das mensagens físicas inequívocas para URL e números inválidos. Esses pontos não são declarados como aprovados por esta tarefa; os testes automatizados são evidência complementar, não substituto de observação física pendente.

## Credencial: armazenamento, status e ciclo de troca

- A credencial é gravada pelo `DeviceCredentialStore` em `FlutterSecureStorage`. A configuração Android do backend usa `AndroidOptions` com `encryptedSharedPreferences: true`.
- A porta usada por E3 (`DeviceCredentialStatusPort`) expõe somente presença, gravação e remoção. Ela não expõe leitura do valor completo à tela ou ao estado de Configurações.
- Os 37 testes dirigidos aprovados nesta tarefa cobriram status sem leitura, substituição, remoção, falhas de armazenamento controladas, campo vazio depois do salvamento e ausência do segredo em feedback de falha.
- A evidência física `task-60.3-e3-device-credential-physical-validation.md` confirma no Galaxy S25+:
  - salvamento de uma chave de teste inserida pelo operador fora do repositório;
  - reabertura com apenas o estado sanitizado **“Chave configurada”** e campo vazio;
  - substituição por novo valor completo externo e nova reabertura sanitizada;
  - cancelamento de remoção sem apagar a chave;
  - remoção somente após confirmação, seguida do estado **“Chave não configurada”**;
  - orientação para rotação na Administração Next.js, sem alegação de recuperar a chave.

## Configuração ausente sem bloqueio de E1/E2

A evidência física `task-60.4-e3-missing-delivery-configuration.md` registra que, com `BASE_URL` vazia e chave não configurada no Galaxy S25+:

- a tela Operação manteve câmera e GPS prontos e o registro manual disponível;
- uma captura manual foi criada e persistida localmente, elevando as pendências E2 de 4 para 5;
- a fila permaneceu **Pronta**;
- o estado exibido foi sanitizado como configuração de envio pendente;
- não houve envio, autenticação, resposta HTTP, retry ou remoção de fila.

Os testes dirigidos executados nesta tarefa também confirmaram que o status de configuração pendente não altera a capacidade de registro nem a contagem local de pendências.

## Resultado

**SUCESSO no escopo documental e de validação automatizada da tarefa 61.2.** Há evidência sanitizada atual para persistência de todos os parâmetros não secretos e para o ciclo de status, troca e remoção da credencial, além de validação física da operação E1/E2 sem configuração de entrega. As lacunas físicas já registradas para round-trip de confiança, FPS, URL e mensagens de validação permanecem explicitamente classificadas como não executadas e não são ocultadas por testes automatizados.
