# Implementation Plan: E0 e E1

## Overview

A E0 está historicamente concluída e aprovada. A E1 permanece integralmente pendente e limitada à captura manual e ocorrência em memória.

## Tasks

### Histórico concluído — E0: Smoke test da infraestrutura Android

A E0 foi implementada, validada fisicamente no Samsung Galaxy S25+ e aprovada. As tarefas 1–15 abaixo constituem registro histórico concluído, não devem ser reabertas e permanecem preservadas com seus textos técnicos, requisitos e verificações originais.

## Regras de execução

- Trabalhar diretamente na raiz do repositório mobile atual; não criar subdiretório duplicado.
- Preservar `.kiro/specs/mvp-app-flutter/requirements.md` e `.kiro/specs/mvp-app-flutter/design.md` como documentos aprovados.
- Não instalar, atualizar ou reconfigurar globalmente Flutter, Android SDK, Gradle, Java, ADB, drivers USB ou WSL sem autorização explícita.
- Tratar toolchain ausente, incompatibilidade Windows/WSL/ADB ou dispositivo inacessível como bloqueio ou etapa manual.
- Adicionar como integrações diretas somente `camera` e `geolocator`, com versões exatas e sem `^`.
- Não adicionar bibliotecas de estado, HTTP, conectividade ou permissões; usar recursos do Flutter e `dart:io` conforme o design.
- Não executar comandos em modo watch nem iniciar processos de longa duração.
- Não criar testes automatizados para E0.

- [x] 1. Verificar o repositório e o ambiente antes de qualquer criação
  - [x] 1.1 Registrar o estado inicial da raiz e os arquivos existentes, incluindo alterações não commitadas, sem modificar ou remover conteúdo.
  - [x] 1.2 Procurar marcadores de projeto Flutter existente, incluindo `pubspec.yaml`, `.metadata`, `lib/` e `android/`.
  - [x] 1.3 Se existir projeto Flutter ou qualquer caminho que seria sobrescrito, interromper a criação e solicitar decisão do usuário; não executar `flutter create` sobre conteúdo conflitante.
  - [x] 1.4 Executar `flutter --version` e registrar as versões de Flutter e Dart.
  - [x] 1.5 Executar `flutter doctor -v` e registrar o estado da toolchain Android, sem corrigir ou atualizar componentes automaticamente.
  - [x] 1.6 Verificar a disponibilidade do Android SDK e dos componentes necessários ao build Android.
  - [x] 1.7 Verificar a disponibilidade do ADB no mesmo ambiente que executará o Flutter.
  - [x] 1.8 Confirmar se o Samsung Galaxy S25+ é reconhecido pelo Flutter/ADB desse ambiente.
  - [x] 1.9 Comparar, quando aplicável, o acesso ao aparelho pelo Windows e pelo WSL; registrar que reconhecimento no ADB do Windows não implica reconhecimento no ADB do WSL.
  - [x] 1.10 Relatar como bloqueio ou etapa manual qualquer ausência/incompatibilidade; não instalar, atualizar ou reconfigurar Flutter, SDK, Gradle, Java, ADB, drivers ou WSL sem autorização.
  - **Verificação:** nenhuma criação ocorreu; o estado do repositório, da toolchain e do aparelho está registrado e conflitos estão ausentes ou bloqueados.
  - **Requisitos:** RF-00.1, RF-00.2, RF-01.2, RF-23.10, RNF-07.1.

- [x] 2. Criar o projeto Flutter Android diretamente na raiz
  - **Depende de:** tarefa 1 concluída sem conflito ou bloqueio.
  - [x] 2.1 Executar, a partir da raiz atual, o comando equivalente a `flutter create --platforms=android --project-name pavimenta_ai_mobile --org com.vitor .`.
  - [x] 2.2 Confirmar que o projeto foi criado na raiz e que nenhum subdiretório `pavimenta_ai_mobile/` duplicado foi criado.
  - [x] 2.3 Confirmar no `pubspec.yaml` que o nome do projeto é `pavimenta_ai_mobile`.
  - [x] 2.4 Confirmar na configuração Android gerada que o `applicationId` é exatamente `com.vitor.pavimenta_ai_mobile`.
  - [x] 2.5 Confirmar que somente a plataforma Android foi gerada e que os arquivos `.kiro` existentes foram preservados.
  - **Verificação:** identidade e localização correspondem ao design, sem sobrescrita e sem plataformas adicionais.
  - **Requisitos:** RF-00.1, RF-00.2, RF-01.1, RF-23.10.

- [x] 3. Fixar somente as dependências aprovadas para E0
  - **Depende de:** tarefas 1 e 2.
  - [x] 3.1 Consultar a compatibilidade de `camera` e `geolocator` com a versão instalada do Flutter/Dart e com a configuração Android gerada.
  - [x] 3.2 Escolher e registrar versões exatas e mutuamente compatíveis de `camera` e `geolocator`.
  - [x] 3.3 Adicionar as duas versões ao `pubspec.yaml` sem `^`, intervalos ou resolução aberta de versão direta.
  - [x] 3.4 Não adicionar pacote de gerenciamento de estado, HTTP, conectividade, permissões, persistência, armazenamento seguro ou visão computacional.
  - [x] 3.5 Executar a resolução normal de pacotes somente depois das verificações da toolchain, sem atualização global de Flutter, SDK, Gradle ou Java.
  - [x] 3.6 Inspecionar `flutter pub deps` e confirmar que as únicas integrações diretas adicionadas para a aplicação são `camera` e `geolocator`.
  - **Verificação:** versões exatas estão registradas e nenhuma dependência direta fora do escopo foi adicionada.
  - **Requisitos:** RF-00.1, RF-00.9, RF-00.10, RF-23.10.

- [x] 4. Avaliar e limitar os artefatos do template Flutter
  - **Depende de:** tarefa 2.
  - [x] 4.1 Revisar o código e os assets de exemplo gerados pelo template e remover somente o conteúdo demonstrativo incompatível com a tela E0.
  - [x] 4.2 Avaliar o teste de exemplo criado pelo template; se estiver incompatível ou não tiver valor para E0, removê-lo.
  - [x] 4.3 Não substituir o teste removido e não criar novos testes automatizados nesta etapa.
  - [x] 4.4 Confirmar que não existem assets, módulos ou referências a funcionalidades fora da E0.
  - **Verificação:** o template não mantém exemplo inválido e nenhum teste automatizado novo foi criado.
  - **Requisitos:** RF-00.1, RF-00.9, RF-00.10, RF-23.10.

- [x] 5. Configurar somente as declarações Android aprovadas
  - **Depende de:** tarefas 2 e 3.
  - [x] 5.1 Declarar `android.permission.CAMERA` no `AndroidManifest.xml`.
  - [x] 5.2 Declarar `android.permission.ACCESS_FINE_LOCATION` e `android.permission.ACCESS_COARSE_LOCATION`.
  - [x] 5.3 Declarar `android.permission.INTERNET`.
  - [x] 5.4 Declarar a câmera como recurso não obrigatório (`required=false`) para permitir falha controlada.
  - [x] 5.5 Manter tráfego em texto claro desabilitado e não adicionar exceção ou bypass de validação TLS.
  - [x] 5.6 Confirmar a ausência de permissões de microfone, armazenamento, localização em segundo plano, foreground service e wake lock.
  - [x] 5.7 Confirmar que `minSdk`, `compileSdk` e `targetSdk` são compatíveis com as versões exatas escolhidas, sem atualizar a toolchain sem autorização.
  - **Verificação:** o manifesto contém somente permissões e recursos requeridos pela E0.
  - **Requisitos:** RF-00.2–5, RF-01.2, RF-01.3, RF-03.1–2, RF-06.1–2.

- [x] 6. Criar a estrutura mínima e o estado da tela E0
  - **Depende de:** tarefas 2 a 5.
  - [x] 6.1 Manter `lib/main.dart` como ponto de composição e única entrada da aplicação.
  - [x] 6.2 Criar `lib/e0/e0_screen.dart`.
  - [x] 6.3 Criar `lib/e0/e0_controller.dart` usando `ChangeNotifier`, sem biblioteca externa de estado.
  - [x] 6.4 Criar `lib/e0/e0_state.dart` com estados de permissão, câmera, localização e HTTPS e somente dados diagnósticos opcionais.
  - [x] 6.5 Criar `lib/e0/camera_diagnostic.dart`.
  - [x] 6.6 Criar `lib/e0/location_diagnostic.dart`.
  - [x] 6.7 Criar `lib/e0/diagnostic_http_client.dart` usando `dart:io` e `dart:async`.
  - [x] 6.8 Compor explicitamente esses componentes em `main.dart`, sem framework de injeção, repositórios ou camadas não exigidas.
  - [x] 6.9 Confirmar que a árvore não contém módulos de modelo, detector, ocorrência, fila, persistência, envio, autenticação ou configurações.
  - **Verificação:** todos e somente os arquivos mínimos definidos no design estão presentes e conectados.
  - **Requisitos:** RF-00.1, RF-00.9–10, RF-05.1, RF-23.10, RNF-04.1.

- [x] 7. Implementar a coordenação serial das permissões
  - **Depende de:** tarefa 6.
  - [x] 7.1 Fazer a interface aparecer imediatamente com estados iniciais, sem aguardar qualquer permissão.
  - [x] 7.2 Implementar no `E0Controller` a sequência: câmera pendente, câmera em resolução, câmera resolvida, localização pendente, localização em resolução e permissões resolvidas.
  - [x] 7.3 Garantir que somente uma solicitação Android de permissão possa estar ativa por vez.
  - [x] 7.4 Resolver primeiro a câmera e autorizar a solicitação de localização somente depois da concessão ou recusa da câmera.
  - [x] 7.5 Garantir que a recusa da câmera não impeça localização ou rede e que a recusa da localização não impeça câmera ou rede.
  - [x] 7.6 Após as decisões de permissão, permitir atualizações independentes dos estados de câmera e localização.
  - [x] 7.7 Bloquear toques/retries que tentem abrir uma segunda solicitação enquanto outra estiver ativa.
  - **Verificação:** a ordem é determinística, não há diálogos concorrentes e recusas não bloqueiam diagnósticos independentes.
  - **Requisitos:** RF-00.3–6, RF-01.3, RF-03.1–2, RF-06.1–2, RNF-04.1.

- [x] 8. Implementar o preview diagnóstico da câmera traseira
  - **Depende de:** tarefas 5 a 7.
  - [x] 8.1 Consultar as câmeras somente quando autorizado pelo `E0Controller`.
  - [x] 8.2 Selecionar a primeira câmera identificada como traseira.
  - [x] 8.3 Inicializar `CameraController` com áudio desabilitado e resolução moderada para preview.
  - [x] 8.4 Expor somente o controlador inicializado necessário ao `CameraPreview`; não iniciar stream de imagens.
  - [x] 8.5 Solicitar a permissão básica de câmera por meio do fluxo do plugin, sob coordenação do `E0Controller`.
  - [x] 8.6 Classificar permissão negada, negação permanente, ausência de câmera traseira, câmera ocupada e falha de inicialização.
  - [x] 8.7 Manter localização e rede funcionais quando a câmera estiver indisponível.
  - **Verificação:** preview traseiro aparece após autorização e todas as falhas previstas são controladas, sem captura/processamento de frames.
  - **Requisitos:** RF-00.3–4, RF-01.3, RF-03.1–2, RF-05.1.

- [x] 9. Implementar o diagnóstico de localização precisa
  - **Depende de:** tarefas 5 a 7.
  - [x] 9.1 Iniciar a verificação de localização somente após a resolução da solicitação de câmera.
  - [x] 9.2 Verificar se o serviço de localização está habilitado antes de solicitar posição.
  - [x] 9.3 Verificar e solicitar somente permissão de localização em primeiro plano.
  - [x] 9.4 Detectar localização aproximada/reduzida e não marcá-la como localização precisa aprovada.
  - [x] 9.5 Obter uma posição atual e assinar atualizações de alta precisão apenas enquanto a aplicação estiver em primeiro plano.
  - [x] 9.6 Exibir latitude e longitude em graus decimais e precisão reportada em metros.
  - [x] 9.7 Exibir velocidade em metros por segundo somente quando o provedor fornecer valor finito e não negativo.
  - [x] 9.8 Representar velocidade ausente como “Não fornecida” e demais valores ausentes como “Não disponível”, sem usar zero artificial.
  - [x] 9.9 Classificar serviço desativado, permissão negada/permanente, precisão reduzida, espera por posição e posição indisponível.
  - **Verificação:** os valores diagnósticos e as indisponibilidades aparecem sem criar ou associar qualquer ocorrência.
  - **Requisitos:** RF-00.5–6, RF-01.3, RF-05.1, RF-06.1–2.

- [x] 10. Implementar ciclo de vida e invalidação de operações antigas
  - **Depende de:** tarefas 7 a 9.
  - [x] 10.1 Observar `AppLifecycleState` na tela e delegar transições ao `E0Controller`.
  - [x] 10.2 Associar cada ciclo de inicialização a um identificador de geração e ignorar callbacks de gerações antigas.
  - [x] 10.3 Manter referência separada à solicitação de permissão em andamento para reconciliá-la após retomada, sem repetir o diálogo.
  - [x] 10.4 Em pausa/inatividade, cancelar a assinatura de localização e descartar o controlador da câmera de forma idempotente.
  - [x] 10.5 Em retomada, verificar operações e permissões já resolvidas antes de reinicializar recursos.
  - [x] 10.6 Impedir streams de localização duplicados e impedir reutilização de `CameraController` descartado.
  - [x] 10.7 No descarte definitivo, remover observers e invalidar todos os callbacks pendentes.
  - **Verificação:** segundo plano/retomada não duplica solicitações ou streams e não publica estados obsoletos.
  - **Requisitos:** RF-00.2, RF-00.4–6, RF-01.3, RNF-04.1, RNF-07.1.

- [x] 11. Implementar o diagnóstico HTTPS manual e restrito
  - **Depende de:** tarefas 3 e 6.
  - [x] 11.1 Ler a configuração de compilação `E0_DIAGNOSTIC_URL`, usando como padrão apenas a URL fictícia aprovada no design.
  - [x] 11.2 Exigir configuração presente, URI válida e absoluta, esquema exatamente HTTPS e host presente.
  - [x] 11.3 Rejeitar usuário/senha embutidos e fragmento.
  - [x] 11.4 Rejeitar explicitamente o caminho `/api/v1/occurrences` antes de abrir conexão.
  - [x] 11.5 Executar somente após ação manual uma única requisição `GET` via `dart:io`, sem corpo, API key, imagem, coordenadas, UUID, identificador ou outros dados de ocorrência.
  - [x] 11.6 Manter redirecionamentos desabilitados e validação TLS padrão ativa.
  - [x] 11.7 Definir limites numéricos pequenos e finitos de tempo e bytes para conexão, resposta e descarte do corpo, adequados a um diagnóstico que não usa conteúdo.
  - [x] 11.8 Nunca armazenar, interpretar, renderizar ou registrar o corpo ou headers da resposta.
  - [x] 11.9 Cancelar controladamente resposta excessiva, que ultrapasse o timeout ou que não termine.
  - [x] 11.10 Propagar ao `E0State` somente o código HTTP opcional e uma classificação sanitizada.
  - [x] 11.11 Classificar sucesso `2xx`, outro código recebido, configuração inválida, timeout, falha TLS e rede/destino indisponível sem semântica de ocorrência.
  - [x] 11.12 Impedir polling e retry automático e manter o botão indisponível durante uma requisição ativa.
  - [x] 11.13 Encerrar requisição ativa e `HttpClient` em pausa, mudança de ciclo de vida ou descarte e ignorar callbacks antigos.
  - [x] 11.14 Não tentar inferir automaticamente se o host é de produção; deixar essa confirmação para o controle humano do gate.
  - **Verificação:** a requisição manual respeita todas as validações, limites e proibições e somente código/classificação sanitizados chegam à interface.
  - **Requisitos:** RF-00.7–10, RF-01.3, RF-05.1, RF-23.10, RNF-04.1.

- [x] 12. Implementar a única tela diagnóstica responsiva e suas mensagens
  - **Depende de:** tarefas 6 a 11.
  - [x] 12.1 Exibir o título da E0 e aviso explícito de que nenhum dado de ocorrência é criado ou enviado.
  - [x] 12.2 Organizar câmera, localização e rede em três painéis independentes.
  - [x] 12.3 Exibir progresso local sem bloquear painéis não relacionados.
  - [x] 12.4 Exibir ações coordenadas de nova tentativa para câmera e localização e ação manual para o diagnóstico HTTPS.
  - [x] 12.5 Implementar todas as mensagens de indisponibilidade definidas para câmera, GPS/permissão/posição, configuração, TLS e rede/destino.
  - [x] 12.6 Usar `SafeArea`, conteúdo rolável, textos com quebra de linha e preview com proporção/altura controladas.
  - [x] 12.7 Adaptar uma ou mais colunas conforme largura por recursos nativos do Flutter, sem biblioteca de layout ou estado.
  - [x] 12.8 Garantir que botões, rolagem e indicadores permaneçam utilizáveis durante inicializações e requisição HTTPS.
  - [x] 12.9 Confirmar que a tela não mostra modelo, inferência, FPS, detecção, confiança, ocorrência, fila, envio ou configuração de credencial.
  - **Verificação:** a tela única permanece legível, rolável e responsiva nos estados nominais e de erro.
  - **Requisitos:** RF-00.3–8, RF-00.9–10, RF-05.1, RNF-04.1.

- [x] 13. Formatar e analisar estaticamente a implementação E0
  - **Depende de:** tarefas 3 a 12.
  - [x] 13.1 Executar `dart format` nos arquivos Dart da E0 e confirmar que não restam alterações de formatação.
  - [x] 13.2 Executar `flutter analyze` em modo de execução única e corrigir somente problemas pertencentes à E0.
  - [x] 13.3 Executar `flutter pub deps` e verificar novamente versões diretas exatas de `camera` e `geolocator` e ausência de dependências diretas não aprovadas.
  - [x] 13.4 Inspecionar manifesto, assets e árvore de fontes para confirmar ausência de YOLO, TFLite, detector, inferência, ocorrência, cooldown, fila, credencial, multipart e integração real.
  - [x] 13.5 Confirmar que não existem testes automatizados adicionados para E0 e não executar comando em modo watch.
  - **Verificação:** formatação, análise estática, dependências e inspeção de escopo estão aprovadas.
  - **Requisitos:** RF-00.1–2, RF-00.9–10, RF-23.10, RNF-04.1.

- [x] 14. Gerar o build e preparar a validação física
  - **Depende de:** tarefa 13 concluída; toolchain da tarefa 1 disponível.
  - [x] 14.1 Obter fora do repositório uma URL HTTPS funcional e confirmar operacionalmente que pertence a ambiente simulado ou exclusivo de teste, não a produção.
  - [x] 14.2 Gerar o build Android de debug, em execução única, com `--dart-define=E0_DIAGNOSTIC_URL=...` e sem versionar o valor funcional.
  - [x] 14.3 Registrar o resultado do build, versões da toolchain e caminho do artefato, sanitizando a URL de teste.
  - [x] 14.4 Preparar a instalação do build no Samsung Galaxy S25+ usando o mesmo ambiente Flutter/ADB validado na tarefa 1.
  - [x] 14.5 Se o aparelho não estiver acessível, registrar bloqueio e instrução manual; não alterar Windows, WSL, drivers ou ADB sem autorização.
  - [x] 14.6 Preparar checklist de evidências para abertura imediata, ordem das permissões, câmera, localização, rede, indisponibilidades, responsividade e ciclo de vida.
  - [x] 14.7 Preparar evidência sanitizada de que a URL foi fornecida fora do repositório, pertence a teste e não contém credencial.
  - [x] 14.8 Não considerar câmera, GPS ou rede aprovados com base apenas no build.
  - **Verificação:** APK de debug e roteiro/evidências estão prontos para validação física, ou o bloqueio manual está claramente registrado.
  - **Requisitos:** RF-00.2, RF-00.7–8, RF-00.11, RF-23.6–7, RF-23.10–11, RNF-07.1.

- [x] 15. Validation Gate da E0 no Samsung Galaxy S25+
  - **Depende de:** tarefas 1 a 14 concluídas e aparelho físico disponível.
  - **Regra obrigatória:** esta tarefa permanece não concluída até a validação física e a aprovação explícita do usuário. O agente não pode aprová-la apenas por build, análise estática, emulador ou inspeção de código.
  - [x] 15.1 Confirmar manualmente que o build Android foi concluído.
  - [x] 15.2 Instalar o aplicativo no Galaxy S25+ e confirmar `applicationId` `com.vitor.pavimenta_ai_mobile`.
  - [x] 15.3 Abrir o aplicativo e confirmar que a tela diagnóstica aparece imediatamente e sem crash.
  - [x] 15.4 Confirmar que a permissão de câmera é solicitada primeiro e pode ser concedida.
  - [x] 15.5 Confirmar que o preview utiliza a câmera traseira e permanece responsivo.
  - [x] 15.6 Confirmar que a localização só é solicitada depois da conclusão, por concessão ou recusa, da solicitação de câmera.
  - [x] 15.7 Conceder localização precisa e confirmar que o aplicativo distingue precisão aproximada de precisa.
  - [x] 15.8 Confirmar a exibição de latitude e longitude quando houver posição.
  - [x] 15.9 Confirmar a exibição da precisão reportada.
  - [x] 15.10 Confirmar a exibição da velocidade quando fornecida pelo provedor.
  - [x] 15.11 Quando a velocidade não for fornecida, confirmar a representação “Não fornecida”, sem zero artificial. **Nota histórica:** não aplicável no cenário aprovado, pois o provedor forneceu velocidade em m/s.
  - [x] 15.12 Executar manualmente o diagnóstico com URL HTTPS confirmada como exclusiva de teste e fornecida por `--dart-define` fora do repositório.
  - [x] 15.13 Confirmar que o código HTTP e somente uma classificação sanitizada são apresentados e que nenhum corpo é exibido ou registrado.
  - [x] 15.14 Confirmar que redirecionamento, URL inválida e caminho `/api/v1/occurrences` são bloqueados conforme o design.
  - [x] 15.15 Confirmar que falha de rede ou destino é tratada com mensagem clara e sem crash.
  - [x] 15.16 Negar separadamente câmera e localização e confirmar mensagens claras, ausência de crash e continuidade dos diagnósticos independentes.
  - [x] 15.17 Enviar o aplicativo ao segundo plano e retornar; confirmar ausência de stream duplicado, diálogo duplicado e controlador de câmera inválido.
  - [x] 15.18 Confirmar rolagem, legibilidade, botões e responsividade básica nos estados nominal e de erro.
  - [x] 15.19 Confirmar ausência de YOLO, TFLite, detector real/falso, inferência, FPS, captura/processamento de frames, ocorrência, cooldown, fila, API key, armazenamento seguro, multipart e integração com a API de ocorrências.
  - [x] 15.20 Confirmar que nenhuma URL ou credencial de produção está presente e que a evidência da URL de teste foi sanitizada.
  - [x] 15.21 Reunir e apresentar evidências de build, instalação, abertura, câmera, permissões sequenciais, GPS, velocidade, HTTPS, indisponibilidades, ciclo de vida e responsividade.
  - [x] 15.22 Registrar a decisão explícita do usuário como aprovação ou reprovação do Validation Gate.
  - [x] 15.23 Parar obrigatoriamente após apresentar o gate; se reprovado, permitir somente correções da E0 e, se aprovado, não iniciar etapa posterior sem nova solicitação.
  - **Verificação:** todos os itens aplicáveis foram observados no aparelho físico, as evidências foram apresentadas e existe decisão explícita do usuário.
  - **Requisitos:** RF-00.1–12, RF-01.1–3, RF-03.1–2, RF-05.1, RF-06.1–2, RF-23.1–11, RNF-04.1 e RNF-07.1, RNF-07.7.

---

### Plano pendente — E1: Captura manual e ocorrência em memória

As tarefas 16–34 cobrem exclusivamente a E1 aprovada. Todas permanecem pendentes e somente poderão ser executadas futuramente em ordem compatível com as dependências. A execução deve parar no Validation Gate E1, sem iniciar E2.

### Regras de execução da E1

- Preservar o comportamento, as responsabilidades, o cliente HTTPS diagnóstico e as evidências históricas da E0 aprovada.
- Implementar somente captura manual e ocorrência em memória; não antecipar fila, banco, integração HTTP de ocorrências, credenciais, envio ou detecção automática.
- Usar fakes Dart simples nos testes, sem framework de mocks.
- Manter testes junto às funcionalidades nas tarefas 19–28; a tarefa 31 somente executa a suíte consolidada.
- Não executar E2, E3, E4 ou E5 antes da aprovação explícita do Validation Gate E1.

- [x] 16. Verificar o baseline aprovado da E0 e os limites da E1
  - **Depende de:** histórico aprovado das tarefas 1–15.
  - [ ] 16.1 Confirmar que o Diagnóstico E0 permanece acessível, funcionalmente preservado e com evidências históricas intactas antes de qualquer alteração E1.
  - [ ] 16.2 Registrar o baseline de arquivos, dependências diretas, análise, testes e configuração Android necessários para detectar somente regressões introduzidas pela E1.
  - [ ] 16.3 Delimitar a E1 à tela Operação, captura manual, ocorrência em memória, arquivos temporários, permissões operacionais, lifecycle, navegação e tela ligada.
  - [ ] 16.4 Confirmar por inspeção negativa a ausência de implementação antecipada de fila, banco, API de ocorrências, multipart, credencial, envio, background, modelo ou inferência.
  - **Verificação:** baseline E0 e fronteira E1 estão registrados sem reabrir tarefas, alterar evidências ou iniciar funcionalidade posterior.
  - **Requisitos:** RF-00.2–5, RF-00.17–22, RF-01.1–3, RF-23.1–8, RNF-07.1.

- [x] 17. Fixar somente as dependências aprovadas da E1
  - **Depende de:** tarefa 16.
  - [ ] 17.1 Manter `camera: 0.11.0+2` e `geolocator: 13.0.2` como dependências diretas exatas, sem `^` ou intervalo aberto.
  - [ ] 17.2 Adicionar exatamente `image: 4.2.0`, `uuid: 4.6.0`, `wakelock_plus: 1.2.8` e `path_provider: 2.1.4`, sem `^` ou intervalo aberto.
  - [ ] 17.3 Resolver as dependências com a toolchain aprovada e inspecionar a árvore resultante quanto à compatibilidade Android.
  - [ ] 17.4 Confirmar que nenhuma dependência de gerenciamento de estado, DI, mocks, permissões genéricas ou funcionalidade de E2–E5 foi adicionada.
  - [ ] 17.5 Registrar os pins diretos efetivos e preservar a ausência de pacote HTTP, banco, armazenamento seguro e visão computacional.
  - **Verificação:** somente os seis pins diretos aprovados para câmera, localização e E1 estão presentes e resolvidos sem dependência direta fora do escopo.
  - **Requisitos:** RF-01.1–3, RF-10.1–8, RF-21.1–2, RF-23.7–8, RNF-01.12–13, RNF-03.10, RNF-06.6–12.

- [x] 18. Criar a estrutura arquitetural e os contratos da E1
  - **Depende de:** tarefas 16 e 17.
  - [ ] 18.1 Criar somente a estrutura E1 aprovada para apresentação, candidato, aplicação, domínio e infraestrutura, preservando `lib/e0/`.
  - [ ] 18.2 Definir `CandidateSeed`, `CandidateInput`, aquisição de imagem diferida e o contrato genérico `OccurrenceCandidateSource` sem identidade de rede da fonte.
  - [ ] 18.3 Definir o contrato genérico do `PostCandidateProcessor` e os resultados de criação, cooldown, pré-condição, cancelamento e falha controlada.
  - [ ] 18.4 Definir portas pequenas para câmera, localização, imagem, relógio, UUID, distância e wake lock, sem interfaces espelho sem necessidade concreta.
  - [ ] 18.5 Compor dependências explicitamente no composition root com recursos nativos do Flutter, sem framework de DI ou gerenciamento de estado.
  - [ ] 18.6 Confirmar que a estrutura contém apenas pontos de extensão exigidos para troca futura da fonte, sem implementar fila, API, persistência ou detector.
  - **Verificação:** contratos compiláveis separam widgets, aplicação, domínio e plugins, e nenhum componente pertencente a E2–E5 foi criado.
  - **Requisitos:** RF-03.12, RF-07.1, RF-07.11–13, RF-23.7–8, RNF-01.1–13, RNF-03.10.

- [x] 19. Implementar ocorrência em memória, horário, UUID, localização e velocidade
  - **Depende de:** tarefa 18.
  - [ ] 19.1 Implementar modelos imutáveis de ponto, snapshot e ocorrência em memória e uma fábrica que aceite somente dados obrigatórios válidos.
  - [ ] 19.2 Implementar `Clock`/`SystemClock` e geração de UUID v4, preservando o instante original e validando formato e versão do identificador.
  - [ ] 19.3 Implementar validação de latitude/longitude e conversão `m/s * 3.6`, incluindo zero e omitindo velocidade ausente, negativa, não finita ou acima de 300 km/h.
  - [ ] 19.4 Escrever testes com `FakeClock` e gerador fake para `detectedAt` lido uma vez, UUID v4, `confidence = 1.0`, `defectClass = pothole` e ausência de `source`, `highway` e `km`.
  - [ ] 19.5 Escrever testes para limites válidos e inválidos de latitude/longitude, conversão de m/s para km/h, inclusão entre 0 e 300 e omissão dos demais casos.
  - **Verificação:** a fábrica só produz ocorrência manual completa e imutável com horário, identidade, localização e velocidade opcional conformes, e todos os testes da tarefa passam.
  - **Requisitos:** RF-06.2–8, RF-07.2–10, RF-08.1–9, RF-11.1, RF-11.5–7, RNF-01.1, RNF-03.2, RNF-03.4, RNF-03.10.

- [x] 20. Implementar cooldown por tempo OU distância
  - **Depende de:** tarefas 18 e 19.
  - [ ] 20.1 Implementar Haversine em Dart puro atrás de `DistanceCalculator` e `CooldownPolicy` com defaults de 5 segundos e 15 metros.
  - [ ] 20.2 Implementar decisão que permite a primeira ocorrência, permite tempo ou distância no limite e rejeita somente quando ambos estão abaixo dos mínimos.
  - [ ] 20.3 Tratar relógio regressivo como tempo abaixo do limiar e atualizar a referência somente por `commit` após ocorrência criada.
  - [ ] 20.4 Escrever testes para primeira ocorrência, tempo, distância, limites inclusivos, regra OR, rejeição com ambos abaixo, relógio regressivo e ausência de commit após falha ou rejeição.
  - **Verificação:** decisões de cooldown são determinísticas e testáveis, seguem tempo OU distância e somente uma criação válida altera a referência.
  - **Requisitos:** RF-09.1–11, RF-23.7, RNF-01.1, RNF-03.1, RNF-03.10.

- [x] 21. Implementar imagem privada, ownership, JPEG e limpeza
  - **Depende de:** tarefas 17 e 18.
  - [ ] 21.1 Implementar armazenamento temporário no diretório privado do aplicativo, namespace E1 e lease de ownership idempotente, sem gravação na galeria.
  - [ ] 21.2 Implementar decode, correção de orientação EXIF quando disponível, proporção preservada e redução inicial para no máximo `1280x720` sem ampliação.
  - [ ] 21.3 Implementar codificação JPEG sempre com qualidade 85 e laço finito que reduz estritamente somente dimensões até no máximo 2 MiB ou rejeição.
  - [ ] 21.4 Implementar limpeza em falha, rejeição, cancelamento, substituição, descarte e fim de sessão, além de varredura restrita de órfãos reconhecíveis e logs sanitizados.
  - [ ] 21.5 Escrever testes para qualidade 85 em todas as tentativas, orientação quando testável, proporção, `1280x720`, 2 MiB, redução somente de dimensões, monotonicidade e terminação.
  - [ ] 21.6 Escrever testes para rejeição e limpeza de fonte/derivados/órfãos, transferência única de ownership, substituição, `dispose`, falha de limpeza sanitizada e ausência de galeria; manter somente o ponto futuro de transferência E2, sem fila.
  - **Verificação:** cada captura aceita resulta em JPEG privado conforme o contrato ou rejeição explícita, sem arquivo órfão conhecido ou vazamento em log, e todos os testes da tarefa passam.
  - **Requisitos:** RF-10.1–15, RF-11.6–8, RF-23.7–8, RNF-03.3, RNF-03.10, RNF-06.1–12.

- [x] 22. Implementar a fonte manual substituível
  - **Depende de:** tarefas 18 e 19.
  - [ ] 22.1 Implementar `ManualCandidateSource` que preserve `attemptedAt` e localização e produza `CandidateInput` com `pothole` e `1.0`.
  - [ ] 22.2 Encapsular a captura associada como aquisição diferida, sem invocá-la durante a emissão do candidato e sem chamar cooldown, UUID, fábrica ou preparador.
  - [ ] 22.3 Escrever testes com fakes Dart para emissão do candidato manual, preservação de instante/localização, classe/confiança exatas, aquisição não invocada e ausência de `source`, API ou persistência.
  - **Verificação:** a fonte manual produz somente o candidato normalizado e substituível, e a câmera permanece intocada até o processor autorizar a aquisição.
  - **Requisitos:** RF-03.4–5, RF-07.1–4, RF-07.11–13, RF-08.2, RF-08.6, RF-08.9, RNF-01.2–6, RNF-01.9–11, RNF-03.2, RNF-03.10.

- [x] 23. Implementar o pós-candidato genérico
  - **Depende de:** tarefas 19, 20, 21 e 22.
  - [ ] 23.1 Implementar a ordem normativa: validar candidato e snapshot, avaliar cooldown, adquirir imagem, preparar JPEG, gerar UUID, criar ocorrência e fazer commit.
  - [ ] 23.2 Garantir que bloqueio por cooldown não invoque captura nem UUID e que qualquer falha limpe temporários sem commit, contador ou ocorrência parcial.
  - [ ] 23.3 Manter o processor independente da origem do candidato e sem ramo manual, widget, persistência ou rede.
  - [ ] 23.4 Escrever testes com fakes simples para ordem completa, única aquisição após aprovação, bloqueio sem efeitos, limpeza em cada falha, commit somente no sucesso e processamento fonte-independente.
  - **Verificação:** o processor transforma qualquer candidato válido em uma única ocorrência completa ou termina sem efeitos residuais, conforme testes de ordem e falha.
  - **Requisitos:** RF-03.13–15, RF-07.5–13, RF-08.2–9, RF-09.7–11, RF-10.1, RF-10.7–15, RF-11.1, RF-11.5–7, RNF-01.4–11, RNF-03.2–4, RNF-06.1, RNF-06.6–8.

- [x] 24. Adaptar câmera e GPS operacionais preservando a E0
  - **Depende de:** tarefas 18 e 19.
  - [ ] 24.1 Implementar adaptador operacional de câmera traseira com preview e `takePicture()`, usando o mesmo controlador válido e sem stream contínuo de frames.
  - [ ] 24.2 Implementar adaptador operacional de localização precisa em primeiro plano com snapshot imutável mais recente e invalidação por serviço, permissão, precisão, rota ou lifecycle.
  - [ ] 24.3 Coordenar câmera antes de localização quando uma permissão puder ser solicitada, impedindo diálogos concorrentes e mantendo falhas independentes.
  - [ ] 24.4 Escrever testes com fakes Dart para câmera indisponível, captura, GPS sem serviço/permissão/precisão/posição, snapshot válido e coordenação serial das permissões.
  - [ ] 24.5 Executar testes regressivos automatizados aplicáveis à E0 sem modificar seu comportamento, responsabilidades ou `DiagnosticHttpClient`.
  - **Verificação:** preview, captura e snapshot operacional funcionam por portas independentes; falhas são controladas; coordenação é serial; regressão automatizável da E0 permanece aprovada.
  - **Requisitos:** RF-00.2, RF-00.4–16, RF-00.19–22, RF-03.1, RF-03.5–7, RF-05.1–2, RF-06.1–5, RF-20.1–7, RNF-01.12, RNF-03.10, RNF-04.1–3.

- [x] 25. Implementar estado, controlador e single-flight da Operação
  - **Depende de:** tarefas 19, 20 e 22–24.
  - [ ] 25.1 Implementar `OperationState` imutável com rota/lifecycle, câmera, GPS, processamento, readiness, feedback, resumo da ocorrência, contador e wake lock.
  - [ ] 25.2 Implementar `OperationController` para adquirir single-flight, validar readiness e capturar `attemptedAt` e snapshot antes do primeiro `await`.
  - [ ] 25.3 Entregar o seed à fonte e o candidato ao processor, preservar `detectedAt`, incrementar contador somente no sucesso e liberar single-flight em todos os caminhos.
  - [ ] 25.4 Implementar geração monotônica para ignorar callbacks obsoletos sem publicar estado, commit, contador ou ownership.
  - [ ] 25.5 Escrever testes para estados, botão habilitado/bloqueado, uma captura sob toques concorrentes, `detectedAt` preservado após atrasos, contador e ausência de efeito de callback obsoleto.
  - **Verificação:** no máximo uma operação manual é processada, readiness é objetivo, horário não é recalculado e resultados antigos não alteram o estado; todos os testes passam.
  - **Requisitos:** RF-03.5–10, RF-05.1–5, RF-06.3–4, RF-08.2, RF-08.6–9, RF-09.11, RF-21.3–5, RNF-01.1, RNF-01.7, RNF-03.4, RNF-04.2–3.

- [x] 26. Implementar a tela Operação, tema e feedbacks
  - **Depende de:** tarefa 25.
  - [ ] 26.1 Implementar tema com `#111827`, `#1F2937`, `#F59E0B`, `#22C55E`, `#EF4444` e `#F9FAFB`, usando foreground contrastante e significado além da cor.
  - [ ] 26.2 Implementar preview, banner permanente “Modo manual — YOLO ainda não configurado”, botão “Registrar buraco” com indicação de confirmação manual, GPS, precisão, velocidade, contador e processamento.
  - [ ] 26.3 Implementar botão habilitado somente pelo readiness, desabilitado durante busy e feedback explícito quando tempo e distância do cooldown estiverem simultaneamente abaixo dos mínimos.
  - [ ] 26.4 Implementar mensagens controladas de câmera, localização, captura, imagem e lifecycle com `SafeArea`, rolagem, quebra de texto, semântica e layout responsivo.
  - [ ] 26.5 Escrever widget tests para banner, labels, paleta/contraste sem estado somente por cor, botão enabled/disabled, busy, cooldown, status, erros, acessibilidade e dimensões/escala de texto representativas.
  - **Verificação:** a única tela operacional comunica modo manual, readiness, processamento e falhas de forma legível e responsiva, e os widget tests passam.
  - **Requisitos:** RF-03.1–4, RF-03.6–10, RF-03.14–16, RF-05.1–4, RF-05.9–11, RF-20.3–7, RNF-03.4, RNF-04.2–3, RNF-08.1–14.

- [x] 27. Implementar lifecycle operacional e tela ligada
  - **Depende de:** tarefas 24 e 25.
  - [ ] 27.1 Calcular Operação ativa por `visible && foreground && resumed && currentRoute` e habilitar o wake lock somente nessa condição.
  - [ ] 27.2 Invalidar geração, bloquear registros, desabilitar wake lock, cancelar localização, liberar câmera e limpar captura/ocorrência conforme pausa, ocultação, detach e `dispose`.
  - [ ] 27.3 Implementar cancelamento lógico e limpeza de conclusões assíncronas inevitáveis, readquirindo recursos somente após limpeza e retomada válidas.
  - [ ] 27.4 Escrever testes de lifecycle, bloqueios fora de `resumed`, callbacks tardios, limpeza e sequência/balanceamento idempotente de enable/disable do wake lock, inclusive em falhas.
  - **Verificação:** recursos e tela ligada acompanham exclusivamente a Operação ativa, sem captura segura fora de `resumed`, vazamento ou chamada desbalanceada; testes passam.
  - **Requisitos:** RF-03.9, RF-21.1–7, RF-23.7, RNF-03.4, RNF-03.10, RNF-04.2–3, RNF-06.7–8.

- [x] 28. Integrar navegação Operação–Diagnóstico com exclusão mútua
  - **Depende de:** tarefas 24–27.
  - [x] 28.1 Tornar Operação a rota inicial e oferecer ação claramente rotulada para abrir o Diagnóstico E0 preservado.
  - [x] 28.2 Antes do `push`, suspender Operação, bloquear ações, desabilitar wake lock, invalidar callbacks, limpar processamento e liberar completamente câmera/GPS.
  - [x] 28.3 Após o `pop`, aguardar o `dispose` completo da sessão E0 antes de marcar Operação corrente e readquirir recursos em `resumed`.
  - [x] 28.4 Escrever testes de navegação e ordem de recursos para Operação → Diagnóstico → Operação, repetição de rotas, exclusão mútua de câmera/GPS e ausência de diálogo/stream duplicado.
  - [x] 28.5 Escrever testes regressivos do acesso E0 para preview, GPS, permissões, HTTPS diagnóstico, mensagens e lifecycle, mantendo intactas as evidências históricas.
  - **Verificação:** nunca coexistem sessões operacionais e diagnósticas de câmera/GPS; a retomada obedece à ordem; a E0 permanece acessível e sem regressão nos testes.
  - **Requisitos:** RF-00.2–5, RF-00.17–22, RF-03.11, RF-21.2, RF-21.6, RF-23.7, RNF-04.1–3, RNF-07.1, RNF-07.10.

- [x] 29. Formatar somente a implementação E1
  - **Depende de:** tarefas 19–28.
  - [x] 29.1 Executar `dart format` somente nos arquivos Dart criados ou modificados pela E1.
  - [x] 29.2 Verificar que uma nova checagem de formatação não produz alterações pendentes e que arquivos/evidências históricas fora do escopo permanecem intactos.
  - **Verificação:** todos os arquivos Dart E1 estão formatados e uma segunda verificação não gera diff.
  - **Requisitos:** RF-23.7–8, RNF-01.1–13, RNF-03.1–4.

- [x] 30. Executar análise estática consolidada
  - **Depende de:** tarefa 29.
  - [x] 30.1 Executar `flutter analyze` uma vez em modo não interativo e registrar a saída completa.
  - [x] 30.2 Corrigir somente problemas da E1 ou regressões introduzidas pela integração e repetir até obter zero issues.
  - **Verificação:** `flutter analyze` termina com zero issues sem mudança funcional fora da E1.
  - **Requisitos:** RF-00.22, RF-23.7–8, RNF-01.1–13, RNF-07.2, RNF-08.1–14.

- [x] 31. Executar a suíte automatizada consolidada
  - **Depende de:** tarefa 30.
  - [x] 31.1 Executar `flutter test` completo uma vez e registrar a saída consolidada, sem modo watch.
  - [x] 31.2 Corrigir somente falhas pertencentes à E1 ou regressões introduzidas pela integração e repetir a suíte quando necessário.
  - [x] 31.3 Confirmar que todos os testes planejados e criados nas tarefas 19–28 estão presentes, executados e aprovados.
  - **Verificação:** a suíte completa termina aprovada e cobre explicitamente os contratos e cenários obrigatórios distribuídos nas tarefas 19–28.
  - **Requisitos:** RF-23.7, RNF-03.1–10, RNF-07.2.

- [x] 32. Gerar o build Android debug da E1
  - **Depende de:** tarefa 31.
  - [x] 32.1 Gerar build Android debug em execução única, sem URL de produção, API key ou configuração de integração de ocorrências.
  - [x] 32.2 Registrar versões da toolchain, resultado do build, caminho do artefato e hash criptográfico do APK.
  - [x] 32.3 Inspecionar o artefato e as dependências quanto ao escopo exclusivo E1 e à preservação da identidade Android aprovada.
  - [x] 32.4 Confirmar por inspeção negativa a ausência de fila, banco, cliente de ocorrências, multipart, credencial, envio, modelo, inferência e FPS.
  - **Verificação:** APK debug reproduzível está disponível com identidade correta, metadados registrados e somente capacidades E0/E1.
  - **Requisitos:** RF-00.5, RF-01.1–3, RF-23.7–8, RNF-07.2.

- [x] 33. Preparar a validação física E1 no Samsung Galaxy S25+
  - **Depende de:** tarefa 32.
  - [x] 33.1 Instalar o APK no Galaxy S25+ pelo ambiente Flutter/ADB aprovado; se o aparelho estiver ausente, registrar instrução manual sem alterar toolchain ou aprovar fisicamente.
  - [x] 33.2 Preparar roteiro e evidências para abertura, preview, banner, botão/readiness, captura única, GPS, velocidade, `detectedAt`, UUID, classe, confiança e contador.
  - [x] 33.3 Preparar cenários para permissões, blockers, concorrência, cooldown por tempo/distância/OR, JPEG 85, orientação, proporção, `1280x720`, 2 MiB, rejeição e limpeza temporária.
  - [x] 33.4 Preparar cenários para lifecycle, wake lock, responsividade, acessibilidade, navegação, exclusão mútua de recursos e regressão do Diagnóstico E0.
  - [x] 33.5 Preparar inspeção negativa de E2–E5 e modelo de evidências sanitizadas, sem executar aprovação nem alterar evidências históricas E0.
  - **Verificação:** instalação e roteiro físico detalhado estão prontos ou há instrução manual clara; nenhuma aprovação física foi presumida.
  - **Requisitos:** RF-00.2–22, RF-01.2–3, RF-03.1–16, RF-05.1–4, RF-05.9–11, RF-06.1–8, RF-07.1–13, RF-08.1–9, RF-09.1–11, RF-10.1–15, RF-11.1–8, RF-20.1–7, RF-21.1–7, RF-23.3–8, RF-23.19–20, RNF-04.2–6, RNF-06.1–12, RNF-07.2, RNF-07.10, RNF-08.1–14.

- [x] 34. Validation Gate E1 no Samsung Galaxy S25+
  - **Depende de:** tarefas 16–33 concluídas.
  - **Regra obrigatória:** esta tarefa permanece pendente até observação física no Samsung Galaxy S25+ e aprovação explícita do usuário; análise, testes, build, inspeção ou emulador não substituem o gate físico.
  - [x] 34.1 Confirmar e apresentar resultados aprovados de `flutter analyze`, `flutter test`, build debug, hash, instalação, identidade e abertura no Galaxy S25+.
  - [x] 34.2 Observar fisicamente preview, banner manual, botão e blockers, captura única, GPS/velocidade, horário/UUID, classe/confiança, contador e responsividade.
  - [x] 34.3 Observar cooldown de 5 segundos OU 15 metros, rejeição somente com ambos abaixo, feedback explícito e ausência de captura/UUID no bloqueio.
  - [x] 34.4 Verificar JPEG privado, orientação, proporção, `1280x720`, qualidade 85, até 2 MiB, rejeição controlada, ownership e limpeza temporária.
  - [x] 34.5 Verificar lifecycle, wake lock, navegação, exclusão mútua câmera/GPS, regressão E0 e ausência de fila, banco, API, credencial, envio, YOLO, TFLite, inferência ou FPS.
  - [x] 34.6 Apresentar todas as evidências e registrar aprovação ou reprovação explícita; parar no gate, limitar eventual correção à E1 e não iniciar E2.
  - **Verificação:** todos os itens automatizados e físicos aplicáveis possuem evidência, a regressão E0 e o escopo negativo foram verificados e existe decisão explícita do usuário.
  - **Requisitos:** RF-00.2–22, RF-01.1–3, RF-03.1–16, RF-05.1–4, RF-05.9–11, RF-06.1–8, RF-07.1–13, RF-08.1–9, RF-09.1–11, RF-10.1–15, RF-11.1–8, RF-20.1–7, RF-21.1–7, RF-23.1–8, RF-23.19–20, RNF-01.1–13, RNF-03.1–10, RNF-04.2–6, RNF-06.1–12, RNF-07.2, RNF-07.10, RNF-08.1–14.

## Notes

### Notas da E1

- Nenhuma tarefa E1 está executada neste documento.
- Testes são obrigatórios e foram distribuídos junto às funcionalidades nas tarefas 19–28.
- A tarefa 31 apenas executa e consolida a suíte já criada.
- O Validation Gate E1 é a última tarefa e bloqueia qualquer início de E2.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["16.1", "16.2", "16.3", "16.4"] },
    { "id": 1, "tasks": ["17.1"] },
    { "id": 2, "tasks": ["17.2"] },
    { "id": 3, "tasks": ["17.3"] },
    { "id": 4, "tasks": ["17.4", "17.5"] },
    { "id": 5, "tasks": ["18.1"] },
    { "id": 6, "tasks": ["18.2", "18.3", "18.4"] },
    { "id": 7, "tasks": ["18.5"] },
    { "id": 8, "tasks": ["18.6"] },
    { "id": 9, "tasks": ["19.1", "21.1"] },
    { "id": 10, "tasks": ["19.2", "21.2"] },
    { "id": 11, "tasks": ["19.3", "21.3"] },
    { "id": 12, "tasks": ["19.4", "21.4"] },
    { "id": 13, "tasks": ["19.5", "21.5"] },
    { "id": 14, "tasks": ["20.1", "21.6", "22.1", "24.1"] },
    { "id": 15, "tasks": ["20.2", "22.2", "24.2"] },
    { "id": 16, "tasks": ["20.3", "22.3", "24.3"] },
    { "id": 17, "tasks": ["20.4", "24.4"] },
    { "id": 18, "tasks": ["24.5"] },
    { "id": 19, "tasks": ["23.1"] },
    { "id": 20, "tasks": ["23.2"] },
    { "id": 21, "tasks": ["23.3"] },
    { "id": 22, "tasks": ["23.4"] },
    { "id": 23, "tasks": ["25.1"] },
    { "id": 24, "tasks": ["25.2"] },
    { "id": 25, "tasks": ["25.3"] },
    { "id": 26, "tasks": ["25.4"] },
    { "id": 27, "tasks": ["25.5"] },
    { "id": 28, "tasks": ["26.1", "27.1"] },
    { "id": 29, "tasks": ["26.2", "27.2"] },
    { "id": 30, "tasks": ["26.3", "27.3"] },
    { "id": 31, "tasks": ["26.4", "27.4"] },
    { "id": 32, "tasks": ["26.5"] },
    { "id": 33, "tasks": ["28.1"] },
    { "id": 34, "tasks": ["28.2"] },
    { "id": 35, "tasks": ["28.3"] },
    { "id": 36, "tasks": ["28.4", "28.5"] },
    { "id": 37, "tasks": ["29.1"] },
    { "id": 38, "tasks": ["29.2"] },
    { "id": 39, "tasks": ["30.1"] },
    { "id": 40, "tasks": ["30.2"] },
    { "id": 41, "tasks": ["31.1"] },
    { "id": 42, "tasks": ["31.2"] },
    { "id": 43, "tasks": ["31.3"] },
    { "id": 44, "tasks": ["32.1"] },
    { "id": 45, "tasks": ["32.2"] },
    { "id": 46, "tasks": ["32.3", "32.4"] },
    { "id": 47, "tasks": ["33.1"] },
    { "id": 48, "tasks": ["33.2"] },
    { "id": 49, "tasks": ["33.3"] },
    { "id": 50, "tasks": ["33.4"] },
    { "id": 51, "tasks": ["33.5"] },
    { "id": 52, "tasks": ["34.1"] },
    { "id": 53, "tasks": ["34.2"] },
    { "id": 54, "tasks": ["34.3"] },
    { "id": 55, "tasks": ["34.4"] },
    { "id": 56, "tasks": ["34.5"] },
    { "id": 57, "tasks": ["34.6"] }
  ]
}
```


---

# Plano adicional pendente — E2: Fila local persistente

## Estado e limite da etapa

A E0 e a E1 permanecem historicamente concluídas e aprovadas, incluindo a aprovação explícita do Validation Gate E1 registrada na tarefa 34 e em `evidence/task-34.6-validation-gate.md`. As tarefas 35–52 abaixo formam o plano implementável exclusivo da E2 e permanecem pendentes. Nenhuma tarefa deste bloco reabre, altera ou reclassifica os status e as evidências de E0/E1.

A E2 adiciona persistência local de ocorrências e JPEGs, recuperação após reabertura, contagem de pendências e integração do aceite durável ao fluxo E1. A E2 não adiciona configuração, API key, armazenamento seguro, cliente HTTP de ocorrências, multipart, envio, classificação HTTP, retry, backoff, worker, YOLO, TFLite, inferência ou FPS. A execução deve parar no Validation Gate E2 e somente uma decisão explícita do usuário poderá aprová-lo.

## Regras de execução da E2

- Preservar integralmente o comportamento, as responsabilidades, o código aplicável e as evidências históricas aprovadas de E0/E1.
- Trabalhar somente na fila persistente E2 e nas integrações mínimas necessárias ao aceite local; não criar scaffolding, campos ou dependências de E3–E5.
- Manter SQLite e filesystem sob um único coordenador assíncrono single-writer durante bootstrap, recuperação, persistência e remoção.
- Persistir somente referências relativas validadas; não expor path, UUID completo, coordenadas, horário, digest ou imagem em logs ou UI.
- Não executar comandos em modo watch nem alterar globalmente Flutter, Android SDK, Gradle, Java, ADB, drivers ou WSL sem autorização explícita.
- Confirmar compatibilidade antes de fixar versões exatas de `sqflite`, `crypto`, `glados` e, somente se necessário, do adaptador SQLite para testes host. Não adicionar pacote incompatível nem usar `^` ou intervalo aberto.
- Manter testes junto às funcionalidades nas tarefas 38–47. Cada propriedade 13–20 deve possuir exatamente um teste PBT com `glados`, no mínimo 100 casos e comentário de rastreabilidade exigido pelo design.
- Implementar a remoção consistente como contrato interno testado, sem botão, tela, endpoint, worker ou outro chamador funcional em produção E2.
- Não declarar o gate aprovado por análise, testes, build, emulador ou inspeção; o Gate E2 exige validação física aplicável no Samsung Galaxy S25+ e decisão explícita do usuário.

## Tarefas

- [ ] 35. Registrar o baseline aprovado E0/E1 e delimitar a E2
  - **Depende de:** tarefa 34 aprovada explicitamente.
  - [x] 35.1 Registrar `git status`, árvore relevante, dependências diretas, versões da toolchain, manifesto, regras Android existentes e resultados reproduzíveis de `flutter analyze` e `flutter test`, sem modificar nem descartar alterações preexistentes.
  - [x] 35.2 Confirmar o acesso ao Diagnóstico E0, o fluxo Operação E1, a aprovação do Gate E1 e a integridade das evidências históricas antes de qualquer alteração E2.
  - [x] 35.3 Mapear os pontos concretos de integração do `PostCandidateProcessor`, `OperationController`, `OperationState`, ownership/lease de imagem, cooldown e composition root, sem alterar comportamento ainda.
  - [x] 35.4 Executar inspeção negativa inicial e registrar a ausência de fila E2 preexistente e de funcionalidades E3–E5, distinguindo o `DiagnosticHttpClient` E0 permitido de qualquer cliente de ocorrências proibido.
  - **Verificação:** baseline reproduzível e fronteira E2 estão registrados; nenhuma evidência/status E0/E1 foi alterado e nenhum código E2 foi criado nesta tarefa.
  - **Requisitos:** RF-00.2–5, RF-00.17–22, RF-01.1–3, RF-12.6, RF-23.1–10, RF-23.19–20, RNF-07.1, RNF-07.3, RNF-07.10.

- [x] 36. Confirmar e fixar somente as dependências compatíveis da E2
  - **Depende de:** tarefa 35.
  - [x] 36.1 Preservar os seis pins diretos aprovados da E1 e verificar a compatibilidade de versões candidatas exatas de `sqflite`, `crypto` e `glados` com Flutter 3.24.3, Dart 3.5.3, Android e as dependências já resolvidas.
  - [x] 36.2 Verificar se testes SQLite reais no host exigem adaptador compatível; adicionar um único adaptador de desenvolvimento com pin exato somente se a suíte não puder usar adequadamente a API escolhida sem ele.
  - [x] 36.3 Registrar a justificativa e fixar no `pubspec.yaml`, sem `^` ou intervalos, as versões exatas confirmadas de `sqflite`, `crypto`, `glados` e do eventual adaptador de teste; atualizar o lockfile pela resolução normal.
  - [x] 36.4 Executar resolução e inspeção de dependências, rejeitando incompatibilidades sem atualizar globalmente a toolchain e sem adicionar Hive, ORM, gerador de código, rede, secure storage, worker, estado, DI, mocks ou visão computacional.
  - [x] 36.5 Escrever verificação automatizada ou inspeção reproduzível que confirme os pins diretos e a ausência de dependências E3–E5.
  - **Verificação:** versões diretas exatas e compatíveis estão registradas e resolvidas; o adaptador host existe somente se tecnicamente necessário; nenhuma dependência fora da E2 foi adicionada.
  - **Requisitos:** RF-12.1–8, RF-23.9, RNF-01.12–13, RNF-03.5, RNF-03.10, RNF-05.1–5.

- [x] 37. Definir portas, resultados e modelos persistentes da E2
  - **Depende de:** tarefas 35 e 36.
  - [x] 37.1 Criar `OccurrenceAcceptancePort` e resultados tipados para nova persistência, equivalência existente, conflito de identidade, armazenamento indisponível, dados inválidos, falha de imagem e falha transacional.
  - [x] 37.2 Definir contratos de `PersistentOccurrenceQueue`, `DurableImageStore`, observação de snapshot, bootstrap, listagem/reconstrução, contagem e remoção interna, sem API de envio ou ação de remoção na UI.
  - [x] 37.3 Criar projeções imutáveis de registro, imagem persistida, saúde da fila e pendência reconstruída, preservando `null` versus zero e sem propagar paths absolutos ou bytes à apresentação.
  - [x] 37.4 Evoluir a lease E1 apenas com operações mínimas para leitura em streaming, promoção e retirada idempotente de ownership, preservando limpeza E1 em falha.
  - [x] 37.5 Escrever testes de contrato para transições de ownership, resultados tipados, snapshots imutáveis e ausência de imports Flutter/SQLite nos modelos e portas de domínio/aplicação.
  - **Verificação:** contratos compiláveis permitem persistir, reconstruir, contar e remover internamente sem acoplar widgets, fonte, câmera, GPS ou rede ao armazenamento concreto.
  - **Requisitos:** RF-11.8, RF-12.1–11, RF-23.9, RNF-01.1, RNF-01.6–8, RNF-01.11–13, RNF-03.5, RNF-03.10, RNF-05.1–5, RNF-06.3, RNF-06.9–11.

- [x] 38. Implementar o schema SQLite v1 e o mapper canônico
  - **Depende de:** tarefa 37.
  - [x] 38.1 Criar o banco privado `e2_occurrence_queue_v1.db`, versão 1, e a tabela de pendências com `queueSequence` monotônico, `idempotencyKey` UUID v4 única e todos os campos canônicos definidos em E2.7.
  - [x] 38.2 Incluir `imageRelativeName`, MIME `image/jpeg`, tamanho entre 1 e 2 MiB, `imageSha256` hexadecimal minúsculo de 64 caracteres, dimensões máximas `1280x720` e qualidade exatamente 85, com constraints defensivas aplicáveis.
  - [x] 38.3 Omitir do schema `source`, `highway`, `km`, URL, API key, status HTTP, tentativas, `nextAttemptAt`, backoff, pausa e qualquer campo reservado a etapas posteriores.
  - [x] 38.4 Implementar `QueueRecordMapper` para persistir e reconstruir os valores canônicos sem recalcular UUID, horário, coordenadas, precisão, velocidade, confiança, classe, digest ou metadados da imagem.
  - [x] 38.5 Escrever testes com SQLite temporário real para criação/reabertura do schema, constraints, unicidade, offsets ISO 8601, `null` versus zero, ordem por `queueSequence`, versão futura sem reset e round-trip de todos os campos.
  - **Verificação:** o schema v1 reabre sem perda, rejeita registros inválidos e futuros sem `drop`, mantém somente campos E2 e reconstrói exatamente os valores persistidos.
  - **Requisitos:** RF-07.2–9, RF-08.1–5, RF-12.1–4, RF-12.7–8, RNF-03.5, RNF-05.1–3.

- [x] 39. Implementar o armazenamento durável privado e a integridade SHA-256
  - **Depende de:** tarefas 37 e 38.
  - [x] 39.1 Criar o namespace privado durável `e2_queue_images_v1` no diretório de suporte do aplicativo e resolver somente nomes relativos opacos, sem separador, traversal, symlink ou escape do namespace.
  - [x] 39.2 Implementar criação exclusiva de `.staging`, cópia e flush assíncronos, SHA-256 por streaming com `crypto`, validação de bytes/metadados e publicação por rename no mesmo diretório sem substituir destino existente.
  - [x] 39.3 Implementar nomes canônicos e marcadores `.deleting` reconhecíveis, exclusivos e opacos, sem coordenadas, data, classe, UUID completo ou digest no nome.
  - [x] 39.4 Implementar exclusão idempotente e varredura estritamente limitada a artefatos reconhecidos, sem seguir links, percorrer subdiretórios arbitrários ou tocar temporários E1/arquivos externos.
  - [x] 39.5 Escrever testes de filesystem para streaming, flush, digest, MIME/dimensões/qualidade/tamanho, no-overwrite, colisões, traversal, symlink, nomes desconhecidos, falhas de limpeza e logs sanitizados.
  - **Verificação:** JPEGs válidos são promovidos sem overwrite para armazenamento privado durável, possuem digest correspondente e nenhum path, byte, digest ou dado da ocorrência é exposto.
  - **Requisitos:** RF-10.7, RF-10.10–15, RF-12.2, RF-12.4, RF-12.8, RF-12.10–11, RNF-02.3, RNF-05.1–3, RNF-06.2–5, RNF-06.9–12.

- [x] 40. Configurar a exclusão Android de backup e transferência
  - **Depende de:** tarefas 38 e 39.
  - [x] 40.1 Criar regras legadas de `android:fullBackupContent` que excluam o banco `e2_occurrence_queue_v1.db`, sidecars `-journal`, `-wal`, `-shm` e o diretório `e2_queue_images_v1/` nos domínios efetivos.
  - [x] 40.2 Criar regras Android 12+ de `android:dataExtractionRules` com exclusões simétricas em `cloud-backup` e `device-transfer` para os mesmos artefatos.
  - [x] 40.3 Referenciar ambas as regras no elemento `<application>` sem adicionar permissão, desabilitar genericamente todo backup ou alterar cleartext/TLS e permissões aprovadas.
  - [x] 40.4 Escrever testes estáticos do manifesto/XML e teste de integração que confronte os paths relativos reais produzidos por `sqflite`/`path_provider` com os paths excluídos.
  - [x] 40.5 Verificar o manifesto mesclado de debug e registrar qualquer limitação da toolchain para testar backup/transferência sem substituir ausência de evidência por aprovação.
  - **Verificação:** banco, sidecars e JPEGs E2 são excluídos conjuntamente das duas gerações de backup/transferência, e os paths declarados coincidem com os paths reais.
  - **Requisitos:** RF-12.2, RF-12.4, RF-12.11, RNF-02.1, RNF-05.1–3, RNF-06.3, RNF-06.9–12.

- [x] 41. Implementar o coordenador single-writer e o bootstrap da fila
  - **Depende de:** tarefas 38–40.
  - [x] 41.1 Implementar uma única região crítica assíncrona para inicialização, retry, recuperação, persistência, leitura confirmada e remoção, compartilhando a mesma execução de bootstrap entre chamadas concorrentes.
  - [x] 41.2 Abrir/criar o schema sem fallback destrutivo, recusar versão futura, impedir fechamento durante mutação adquirida e bloquear leituras públicas até snapshot confirmado.
  - [x] 41.3 Publicar `QueueSnapshot` com estado inicializando, pronta, degradada ou indisponível e contagem derivada das linhas confirmadas, sem dados completos de ocorrências.
  - [x] 41.4 Implementar retry controlado de inicialização sem reinicializar câmera/GPS e sem impedir abertura do Diagnóstico quando a fila falhar.
  - [x] 41.5 Escrever testes determinísticos de concorrência para bootstrap/retry compartilhado, exclusão mútua de mutações, ordem observável, ausência de leitura intermediária e fechamento seguro.
  - **Verificação:** nenhuma recuperação ou mutação observa staging de outra operação em andamento; chamadas concorrentes são serializadas e falhas de fila permanecem controladas.
  - **Requisitos:** RF-05.5, RF-12.3, RF-12.5, RF-12.7–8, RF-23.9, RNF-03.5, RNF-03.10, RNF-04.2–3, RNF-05.1–5.

- [x] 42. Implementar persistência crash-consistent, idempotente e sem substituição
  - **Depende de:** tarefas 39 e 41.
  - [x] 42.1 Implementar preflight por `idempotencyKey` antes de criar arquivo E2 e comparar todos os campos canônicos, metadados e SHA-256 do preparado, da linha e do JPEG existente.
  - [x] 42.2 Para chave nova, criar staging exclusivo, copiar/validar/hash, reconsultar a chave dentro da transação, confirmar destino livre, publicar sem overwrite, inserir a linha e confirmar a transação nessa ordem.
  - [x] 42.3 Tratar chave equivalente como confirmação idempotente sem nova linha, imagem, contagem ou aceite da sessão; tratar qualquer divergência como conflito que preserva integralmente a primeira pendência.
  - [x] 42.4 Compensar falha após publicação removendo somente o canônico criado pela operação corrente; preservar órfão reconhecível para recuperação se a compensação falhar e jamais remover destino preexistente.
  - [x] 42.5 Transferir ownership à fila somente após linha e JPEG íntegros confirmados; manter/limpar a lease E1 no caminho correto e retornar resultado `persistida` somente para novo aceite.
  - [x] 42.6 Escrever testes com falhas injetadas em preflight, staging, copy, flush, hash, rechecagem, destino, rename, insert, commit e retirada de lease, além de concorrência da mesma chave e imagens diferentes com mesmo tamanho.
  - **Verificação:** somente commit íntegro gera novo aceite; repetição equivalente é idempotente; conflito/no-overwrite preserva o original; falhas não alteram cooldown, contadores nem deixam estado não recuperável.
  - **Requisitos:** RF-08.3–5, RF-11.8, RF-12.1–2, RF-12.4, RF-12.7–8, RF-12.10–11, RNF-03.5, RNF-05.1–5, RNF-06.3, RNF-06.9–11.

- [x] 43. Implementar recuperação e reconstrução idempotentes
  - **Depende de:** tarefas 41 e 42.
  - [x] 43.1 Sob o coordenador exclusivo, ler linhas antes da varredura, restaurar ou concluir `.deleting` conforme a linha, remover `.staging` não confirmado e remover canônico reconhecido sem linha somente após leitura confirmada.
  - [x] 43.2 Validar por streaming nome, existência, tamanho e SHA-256 de cada JPEG referenciado; preservar linha/arquivo e marcar fila degradada em ausência, corrupção ou divergência, sem descarte silencioso.
  - [x] 43.3 Reconstruir pendências por `queueSequence` com os mesmos campos canônicos, referência privada validada e distinção entre velocidade nula e zero, sem abrir/enviar imagens.
  - [x] 43.4 Tornar a recuperação idempotente e restrita ao namespace E2, sem importar temporários E1 nem apagar arquivo desconhecido, externo, em subdiretório ou operação corrente.
  - [x] 43.5 Escrever testes de reabertura e estados de crash para cada fronteira alcançável: staging, canônico órfão, deleting, linha íntegra, linha sem imagem, digest divergente, colisão e repetição da recuperação.
  - **Verificação:** reabrir após qualquer estado simulado converge para o mesmo conjunto confirmado ou para degradação preservadora; nenhuma linha corrompida ou artefato externo é apagado silenciosamente.
  - **Requisitos:** RF-08.4–5, RF-12.2–5, RF-12.8, RNF-03.5, RNF-05.2–4, RNF-06.3, RNF-06.9–11.

- [x] 44. Implementar remoção interna consistente sem chamador funcional
  - **Depende de:** tarefas 41 e 43.
  - [x] 44.1 Implementar o contrato interno de remoção por `idempotencyKey`: localizar/revalidar linha, renomear JPEG para `.deleting` exclusivo sem overwrite, remover a linha em transação e apagar o marcador após commit.
  - [x] 44.2 Restaurar `.deleting` quando a linha ainda existir e o destino estiver livre; excluir o marcador quando a linha não existir; preservar ambos e degradar em colisão.
  - [x] 44.3 Atualizar a contagem somente após remoção confirmada e garantir que a operação use o mesmo coordenador single-writer.
  - [x] 44.4 Escrever testes para sucesso, chave ausente, referência divergente, falha/interrupção em cada etapa, recuperação antes/depois do commit, colisão e repetição idempotente.
  - [x] 44.5 Confirmar por inspeção/teste arquitetural que nenhum widget, botão, rota, controller de produção, timer, worker ou serviço chama a remoção na E2.
  - **Verificação:** remoção interna termina sem linha/JPEG ou recupera a pendência íntegra após interrupção, e permanece sem chamador funcional no aplicativo E2.
  - **Requisitos:** RF-12.9, RF-12.11, RNF-03.5, RNF-05.4, RNF-06.2, RNF-06.10–11.

- [x] 45. Integrar o aceite persistente ao pós-candidato e ao ownership
  - **Depende de:** tarefas 37 e 42–44.
  - [x] 45.1 Injetar `OccurrenceAcceptancePort` no `PostCandidateProcessor` e preservar a ordem E1 até a criação completa em memória.
  - [x] 45.2 Inserir o aceite durável depois da fábrica e antes de commit do cooldown, contador da sessão e resultado de sucesso.
  - [x] 45.3 Publicar sucesso novo somente para resultado `persistida`; para equivalência, preservar/reconciliar a pendência sem segundo incremento; para falha/conflito, limpar ownership temporário e não avançar cooldown ou contadores.
  - [x] 45.4 Tratar lifecycle antes do commit com cancelamento/limpeza e, depois de iniciada a seção final durável, concluir sucesso ou rollback sem publicar callback obsoleto.
  - [x] 45.5 Substituir no controlador qualquer retenção de lease/path por resumo sanitizado após aceite, preservando o JPEG da fila ao navegar, pausar ou encerrar sessão.
  - [x] 45.6 Escrever testes de aplicação para ordem `fábrica -> persistência -> cooldown -> sucesso`, equivalência, conflito, falhas, lifecycle nos dois lados do ponto de não retorno e transferência única de ownership.
  - **Verificação:** uma ocorrência só é aceita visivelmente após persistência íntegra; falha não produz sucesso parcial; a fila é a única proprietária do JPEG confirmado.
  - **Requisitos:** RF-05.4–5, RF-07.5–10, RF-08.4, RF-11.1, RF-11.8, RF-12.1–2, RF-12.7, RF-12.10–11, RF-21.4–5, RNF-01.6–8, RNF-05.1–3, RNF-06.3, RNF-06.9–10.

- [x] 46. Integrar bootstrap, contagem, cooldown restaurado e estado da Operação
  - **Depende de:** tarefas 41, 43 e 45.
  - [x] 46.1 Inicializar e recuperar a fila antes de habilitar “Registrar buraco”, mantendo câmera, GPS, interface e acesso ao Diagnóstico independentes durante inicialização ou falha.
  - [x] 46.2 Restaurar no `CooldownPolicy` a ocorrência pendente de maior `queueSequence`; limpar a referência somente quando a fila recuperada estiver vazia e não incrementar o contador da sessão por recuperação.
  - [x] 46.3 Ampliar `OperationState` com saúde da fila, recuperação, persistência e `pendingCount`, calculando `canRegister` somente com fila pronta além das precondições E1.
  - [x] 46.4 Observar snapshots confirmados para atualizar pendências; incrementar contador da sessão uma vez apenas para novo aceite corrente e reiniciá-lo em nova execução sem zerar a fila.
  - [x] 46.5 Escrever testes de controller/composição para fila vazia/não vazia, inicializando, pronta, degradada, indisponível, retry, reabertura, relógio regressivo, restauração por maior sequência e separação dos contadores.
  - **Verificação:** a tela nunca habilita registro sem fila pronta, pendências vêm do repositório, reabertura restaura cooldown/fila e o contador da sessão mantém a semântica E1.
  - **Requisitos:** RF-03.6–10, RF-05.3–5, RF-09.1–4, RF-12.3, RF-12.5, RF-12.7, RF-20.6–7, RF-21.3–5, RNF-04.2–3, RNF-05.3–5.

- [x] 47. Atualizar a interface E2 sem criar gestão de fila
  - **Depende de:** tarefa 46.
  - [x] 47.1 Exibir “Pendências: N” e estados textuais de fila inicializando, pronta, degradada ou indisponível, sem listar registros, paths, UUIDs, horários, coordenadas ou digests.
  - [x] 47.2 Exibir etapa de persistência no processamento e alterar o feedback nominal para “Buraco salvo na fila local” ou equivalente inequívoco somente após novo aceite.
  - [x] 47.3 Manter botão desabilitado enquanto a fila não estiver pronta e oferecer retry controlado de fila sem reinicializar câmera/GPS ou esconder o acesso ao Diagnóstico.
  - [x] 47.4 Preservar integralmente banner manual, preview, GPS, cooldown, tema, acessibilidade, lifecycle, wake lock e navegação aprovados na E1.
  - [x] 47.5 Escrever widget tests para zero/múltiplas pendências, estados e mensagens, persistência em andamento, erro sanitizado, retry, contadores separados e ausência de lista/remoção/configuração/envio/detecção automática.
  - **Verificação:** a UI comunica durabilidade e pendências sem expor dados ou oferecer gestão da fila, permanece responsiva e não regride os estados E1.
  - **Requisitos:** RF-03.1–11, RF-05.1–5, RF-05.9–11, RF-12.5, RF-20.1–7, RF-21.1–7, RNF-04.2–3, RNF-08.1–14.

- [x] 48. Implementar as propriedades PBT 13–20 e consolidar testes de integração
  - **Depende de:** tarefas 38–47.
  - [x] 48.1 Implementar com `glados` exatamente um teste de no mínimo 100 casos para a **Property 13: Aceite somente após persistência íntegra**, com comentário `Feature: mvp-app-flutter, Property 13: Aceite somente após persistência íntegra`.
  - [x] 48.2 Implementar com `glados` exatamente um teste de no mínimo 100 casos para a **Property 14: Round-trip da fila**, com o comentário de rastreabilidade correspondente.
  - [x] 48.3 Implementar com `glados` exatamente um teste de no mínimo 100 casos para a **Property 15: Unicidade idempotente**, cobrindo sequências serializadas/concorrentes, equivalência, conflito e no-overwrite.
  - [x] 48.4 Implementar com `glados` exatamente um teste de no mínimo 100 casos para a **Property 16: Contagem derivada da fila**, cobrindo aceite, falha, recuperação e remoção interna.
  - [x] 48.5 Implementar com `glados` exatamente um teste de no mínimo 100 casos para a **Property 17: Ownership exclusivo após aceite**, cobrindo retirada/limpeza da lease e ausência de JPEG E2 referenciado em rejeição.
  - [x] 48.6 Implementar com `glados` exatamente um teste de no mínimo 100 casos para a **Property 18: Remoção consistente**, cobrindo interrupção antes/depois do commit e recuperação.
  - [x] 48.7 Implementar com `glados` exatamente um teste de no mínimo 100 casos para a **Property 19: Recuperação idempotente**, gerando somente estados alcançáveis e artefatos reconhecíveis dentro do sandbox.
  - [x] 48.8 Implementar com `glados` exatamente um teste de no mínimo 100 casos para a **Property 20: Restauração da referência de cooldown**, incluindo fila vazia e ordenação independente do relógio.
  - [x] 48.9 Consolidar testes com SQLite temporário real e filesystem sandbox para mapper, reabertura, digest, falhas injetadas, concorrência single-writer, regras de backup e regressões E0/E1.
  - [x] 48.10 Confirmar que cada propriedade possui um único teste, no mínimo 100 iterações e referência ao requisito/propriedade do design, sem substituir os testes de exemplos, erros e integração.
  - **Verificação:** propriedades 13–20 e testes de integração executam com `flutter test`, reproduzem falhas com seeds/casos minimizados quando suportado e cobrem todas as invariantes E2 sem hardware/rede real.
  - **Requisitos:** RF-08.3–5, RF-09.1–4, RF-11.8, RF-12.1–11, RNF-03.5, RNF-03.10, RNF-05.1–5, RNF-06.2–3, RNF-06.9–11.

- [x] 49. Executar formatação, análise, suíte completa e inspeção negativa
  - **Depende de:** tarefa 48.
  - [x] 49.1 Executar `dart format` somente nos arquivos Dart criados/modificados pela E2 e repetir em modo de verificação até não haver alteração pendente.
  - [x] 49.2 Executar `flutter analyze` em modo não interativo, corrigir somente problemas E2 ou regressões introduzidas e repetir até zero issues.
  - [x] 49.3 Executar `flutter test` completo, incluindo PBT 13–20, SQLite/filesystem, manifesto/XML e regressões E0/E1, corrigindo somente problemas da E2 ou regressões da integração.
  - [x] 49.4 Inspecionar dependências, fontes, schema, manifesto, assets e strings para confirmar ausência de `BASE_URL`, API key, secure storage, cliente de ocorrências, endpoint, multipart, envio, HTTP status, retry/backoff, worker/background, YOLO, TFLite, inferência e FPS.
  - [x] 49.5 Confirmar que o único HTTP permitido continua isolado no Diagnóstico E0 e que não existe chamador funcional da remoção interna E2.
  - [x] 49.6 Registrar saídas completas, quantidade de testes/propriedades e inspeção negativa em evidência E2 nova, sem alterar evidências históricas E0/E1.
  - **Verificação:** formatação está estável, análise tem zero issues, suíte completa passa e somente capacidades E0–E2 estão presentes.
  - **Requisitos:** RF-00.22, RF-12.6, RF-23.1–10, RNF-01.1–13, RNF-03.1–10, RNF-07.3, RNF-07.10.

- [x] 50. Gerar e inspecionar o build Android debug E2
  - **Depende de:** tarefa 49.
  - [x] 50.1 Gerar APK debug em execução única, sem URL/API key de ocorrências ou configuração E3–E5.
  - [x] 50.2 Registrar versões da toolchain, pins diretos, resultado, caminho, tamanho e SHA-256 do APK, preservando o `applicationId` aprovado.
  - [x] 50.3 Inspecionar manifesto mesclado e APK para permissões inalteradas, referências corretas às regras de backup e ausência de componentes/serviços/workers E3–E5.
  - [x] 50.4 Instalar o APK no Galaxy S25+ pelo ambiente Flutter/ADB aprovado quando disponível; se indisponível, registrar bloqueio manual sem alterar toolchain ou presumir validação física.
  - **Verificação:** APK debug E2 reproduzível possui identidade correta, políticas de backup esperadas, somente escopo E0–E2 e está instalado ou acompanhado de bloqueio manual explícito.
  - **Requisitos:** RF-01.1–3, RF-12.1–6, RF-23.9, RF-23.19–20, RNF-06.3, RNF-06.9–12, RNF-07.3.

- [x] 51. Preparar e executar o roteiro físico E2 no Samsung Galaxy S25+
  - **Depende de:** tarefa 50.
  - [x] 51.1 Preservar o pacote histórico E0/E1, instalar E2 como atualização quando possível e registrar toolchain, hash, dispositivo e ausência de configuração de ocorrências.
  - [x] 51.2 Confirmar criação/inicialização da fila, zero pendências em instalação sem fila E2, preview/GPS/banner/permissões E1 preservados e botão bloqueado até fila pronta.
  - [x] 51.3 Registrar ocorrências válidas respeitando cooldown e confirmar salvamento local antes do sucesso, contador da sessão e aumento derivado de pendências.
  - [x] 51.4 Pausar/retomar, fechar ou force-stop e reabrir; confirmar pendências recuperadas, contador da sessão reiniciado sem zerar a fila e cooldown restaurado de forma observável segura.
  - [x] 51.5 Confirmar por evidência técnica sanitizada a reconstrução de UUID, horário, coordenadas, velocidade opcional, classe, confiança, SHA-256 e JPEG associados, sem imprimir ou expor os valores sensíveis proibidos.
  - [x] 51.6 Confirmar JPEG privado fora da galeria, responsividade durante persistência, navegação ao Diagnóstico sem alteração da fila e exclusão mútua de câmera/GPS.
  - [x] 51.7 Inspecionar manifesto/regras para exclusão conjunta de banco, sidecars e imagens de backup/transferência; executar ciclo controlado somente se suportado e marcar honestamente como não executado quando indisponível.
  - [x] 51.8 Reexecutar regressão física essencial E0/E1 e inspecionar tráfego/interface/dependências para ausência de envio e de funcionalidades E3–E5.
  - [x] 51.9 Classificar cada cenário como aprovado, reprovado ou não executado, referenciar as evidências novas E2 e não criar UI de debug nem manipular o sandbox de forma insegura para simular corrupção.
  - **Verificação:** roteiro físico aplicável possui evidência no Galaxy S25+, limitações estão explícitas e nenhuma observação automatizada é apresentada como física.
  - **Requisitos:** RF-00.4–22, RF-01.2–3, RF-03.1–11, RF-05.1–5, RF-06.1–8, RF-07.1–10, RF-08.1–5, RF-09.1–11, RF-10.1–15, RF-11.8, RF-12.1–11, RF-20.1–8, RF-21.1–7, RF-23.3–10, RF-23.19–20, RNF-04.2–3, RNF-04.6, RNF-05.1–5, RNF-06.2–3, RNF-06.9–12, RNF-07.3, RNF-07.10, RNF-08.1–14.

- [x] 52. Validation Gate E2 no Samsung Galaxy S25+
  - **Depende de:** tarefas 35–51 concluídas.
  - **Regra obrigatória:** esta tarefa permanece pendente até validação física aplicável no Samsung Galaxy S25+ e aprovação explícita do usuário. A execução para neste gate; análise, testes, build, instalação, emulador ou inspeção não aprovam o gate isoladamente.
  - [x] 52.1 Apresentar `flutter analyze` sem issues, `flutter test` completo, propriedades 13–20, integrações SQLite/filesystem, build, hash, identidade, instalação e abertura do APK E2.
  - [x] 52.2 Apresentar evidência de persistência antes do sucesso, recuperação após fechamento/force-stop, reconstrução íntegra com SHA-256, pendências corretas e contador da sessão separado.
  - [x] 52.3 Apresentar evidência automatizada de idempotência equivalente, conflito preservador, no-overwrite, single-writer, crash consistency, ownership/lease, rollback, remoção interna e recuperação idempotente.
  - [x] 52.4 Apresentar manifesto mesclado e regras Android que excluem conjuntamente banco, sidecars e JPEGs E2 de backup e transferência, registrando como não executado qualquer ciclo físico não suportado.
  - [x] 52.5 Apresentar regressão E0/E1, responsividade, privacidade, logs sanitizados e inspeção negativa demonstrando ausência de configuração, credencial, envio, backoff, worker, YOLO, TFLite, inferência e FPS.
  - [x] 52.6 Reunir roteiro e evidências E2, registrar a decisão do usuário exatamente como aprovação ou reprovação explícita e manter a tarefa pendente se a decisão não existir.
  - [x] 52.7 Parar obrigatoriamente após a decisão: se reprovado, permitir somente correções E2; se aprovado, encerrar E2 sem iniciar E3 e aguardar nova solicitação.
  - **Verificação:** todos os itens obrigatórios possuem evidência, limitações/não executados estão declarados, E0/E1 permanecem preservadas e existe decisão explícita do usuário registrada.
  - **Requisitos:** RF-00.2–22, RF-01.1–3, RF-03.1–11, RF-05.1–5, RF-06.1–8, RF-07.1–10, RF-08.1–5, RF-09.1–11, RF-10.1–15, RF-11.1, RF-11.8, RF-12.1–11, RF-20.1–8, RF-21.1–7, RF-23.1–10, RF-23.19–20, RNF-01.1–13, RNF-03.1–10, RNF-04.1–3, RNF-04.6, RNF-05.1–5, RNF-06.1–12, RNF-07.1, RNF-07.3, RNF-07.10, RNF-08.1–14.

## Notas da E2

- As tarefas 35–52 foram concluídas. O Gate E2 foi aprovado explicitamente após a revalidação física do APK no Samsung Galaxy S25+; a implementação E3 continua dependente de seu próprio ciclo de design, tarefas e gate.
- Os pins exatos novos são escolhidos somente após confirmação de compatibilidade na tarefa 36; o adaptador SQLite host é condicional e exclusivamente de desenvolvimento.
- Testes de exemplos, falhas e integração ficam junto às respectivas implementações; a tarefa 48 materializa individualmente as propriedades 13–20 e consolida a cobertura transversal.
- A remoção E2 existe somente como contrato interno necessário à consistência e aos testes, sem chamador funcional em produção.
- A fila E2 não envia ocorrências. Não há configuração, credencial, rede de ocorrências, retry, worker ou detecção automática.
- O Validation Gate E2 é a última tarefa deste plano e bloqueia qualquer início de E3.

## Task Dependency Graph — E2

```json
{
  "waves": [
    { "id": 0, "tasks": ["35.1", "35.2", "35.3", "35.4"] },
    { "id": 1, "tasks": ["36.1"] },
    { "id": 2, "tasks": ["36.2"] },
    { "id": 3, "tasks": ["36.3"] },
    { "id": 4, "tasks": ["36.4", "36.5"] },
    { "id": 5, "tasks": ["37.1", "37.2", "37.3", "37.4"] },
    { "id": 6, "tasks": ["37.5"] },
    { "id": 7, "tasks": ["38.1", "39.1"] },
    { "id": 8, "tasks": ["38.2", "39.2"] },
    { "id": 9, "tasks": ["38.3", "39.3"] },
    { "id": 10, "tasks": ["38.4", "39.4"] },
    { "id": 11, "tasks": ["38.5", "39.5"] },
    { "id": 12, "tasks": ["40.1"] },
    { "id": 13, "tasks": ["40.2"] },
    { "id": 14, "tasks": ["40.3"] },
    { "id": 15, "tasks": ["40.4"] },
    { "id": 16, "tasks": ["40.5"] },
    { "id": 17, "tasks": ["41.1"] },
    { "id": 18, "tasks": ["41.2"] },
    { "id": 19, "tasks": ["41.3"] },
    { "id": 20, "tasks": ["41.4"] },
    { "id": 21, "tasks": ["41.5"] },
    { "id": 22, "tasks": ["42.1"] },
    { "id": 23, "tasks": ["42.2"] },
    { "id": 24, "tasks": ["42.3"] },
    { "id": 25, "tasks": ["42.4"] },
    { "id": 26, "tasks": ["42.5"] },
    { "id": 27, "tasks": ["42.6"] },
    { "id": 28, "tasks": ["43.1"] },
    { "id": 29, "tasks": ["43.2"] },
    { "id": 30, "tasks": ["43.3"] },
    { "id": 31, "tasks": ["43.4"] },
    { "id": 32, "tasks": ["43.5"] },
    { "id": 33, "tasks": ["44.1"] },
    { "id": 34, "tasks": ["44.2"] },
    { "id": 35, "tasks": ["44.3"] },
    { "id": 36, "tasks": ["44.4"] },
    { "id": 37, "tasks": ["44.5"] },
    { "id": 38, "tasks": ["45.1"] },
    { "id": 39, "tasks": ["45.2"] },
    { "id": 40, "tasks": ["45.3"] },
    { "id": 41, "tasks": ["45.4"] },
    { "id": 42, "tasks": ["45.5"] },
    { "id": 43, "tasks": ["45.6"] },
    { "id": 44, "tasks": ["46.1"] },
    { "id": 45, "tasks": ["46.2"] },
    { "id": 46, "tasks": ["46.3"] },
    { "id": 47, "tasks": ["46.4"] },
    { "id": 48, "tasks": ["46.5"] },
    { "id": 49, "tasks": ["47.1"] },
    { "id": 50, "tasks": ["47.2"] },
    { "id": 51, "tasks": ["47.3"] },
    { "id": 52, "tasks": ["47.4"] },
    { "id": 53, "tasks": ["47.5"] },
    { "id": 54, "tasks": ["48.1", "48.2", "48.3", "48.4", "48.5", "48.6", "48.7", "48.8"] },
    { "id": 55, "tasks": ["48.9"] },
    { "id": 56, "tasks": ["48.10"] },
    { "id": 57, "tasks": ["49.1"] },
    { "id": 58, "tasks": ["49.2"] },
    { "id": 59, "tasks": ["49.3"] },
    { "id": 60, "tasks": ["49.4"] },
    { "id": 61, "tasks": ["49.5", "49.6"] },
    { "id": 62, "tasks": ["50.1"] },
    { "id": 63, "tasks": ["50.2"] },
    { "id": 64, "tasks": ["50.3"] },
    { "id": 65, "tasks": ["50.4"] },
    { "id": 66, "tasks": ["51.1"] },
    { "id": 67, "tasks": ["51.2"] },
    { "id": 68, "tasks": ["51.3"] },
    { "id": 69, "tasks": ["51.4"] },
    { "id": 70, "tasks": ["51.5"] },
    { "id": 71, "tasks": ["51.6"] },
    { "id": 72, "tasks": ["51.7"] },
    { "id": 73, "tasks": ["51.8"] },
    { "id": 74, "tasks": ["51.9"] },
    { "id": 75, "tasks": ["52.1"] },
    { "id": 76, "tasks": ["52.2"] },
    { "id": 77, "tasks": ["52.3"] },
    { "id": 78, "tasks": ["52.4"] },
    { "id": 79, "tasks": ["52.5"] },
    { "id": 80, "tasks": ["52.6"] },
    { "id": 81, "tasks": ["52.7"] }
  ]
}


---

# Plano de tarefas — E3: Configuração local e credencial protegida

> **Pré-condição atendida:** E2 foi aprovada explicitamente no Gate 52. Este plano não inicia E4/E5; cada tarefa E3 deve preservar a fila E2 e as rotas Operação/Diagnóstico aprovadas.

## 53. Preparar a baseline E3 e fechar as fronteiras

- [ ] 53.1 Registrar a aprovação do Gate E2, revisar o design E3 e executar a baseline de formatação, análise, suíte completa e build sem alterar E0–E2.
- [ ] 53.2 Inventariar a composição atual de `main.dart`, `CooldownPolicy`, `OperationController`, rotas, permissões, manifestos e regras de backup para definir os pontos mínimos de integração E3.
- [ ] 53.3 Criar teste arquitetural de fronteira E3: liberar somente stores de configuração/credencial e proibir cliente de ocorrência, endpoint, multipart, `Authorization`, worker, backoff, YOLO/TFLite/modelo/inferência.
- **Verificação:** baseline aprovada e fronteiras futuras automatizadas sem alterar comportamento E0–E2.
- **Requisitos:** RF-23.1–10, RNF-01.7–13, RNF-03.6, RNF-07.1,10.

## 54. Preparar dependências e segurança Android

- [ ] 54.1 Verificar compatibilidade Android/Flutter e escolher versões exatas de `shared_preferences` e `flutter_secure_storage`; atualizar `pubspec.yaml`, lockfile e a política arquitetural E2 que hoje proíbe secure storage.
- [ ] 54.2 Criar adaptadores/fakes mínimos para preferences e armazenamento seguro, sem expor credencial pela camada de apresentação.
- [ ] 54.3 Adicionar configuração de segurança exclusiva de debug que permita somente `http://localhost:3000`, mantendo cleartext bloqueado no manifesto principal/release.
- [ ] 54.4 Identificar os artefatos reais do adaptador de credencial e atualizar regras de backup/data extraction para excluir a credencial sem remover exclusões E2 de banco, sidecars e JPEGs.
- [ ] 54.5 Criar testes estáticos de manifests/regras de backup e inspeção de dependências: HTTPS obrigatório em release, exceção limitada a localhost/debug e nenhuma abertura global de HTTP.
- **Depende de:** 53.
- **Verificação:** dependências pinadas, adaptação segura testável e políticas Android preservadas/verificadas.
- **Requisitos:** RF-13.2–8, RNF-02.4–14, RNF-03.10, RNF-06.9–12.

## 55. Implementar o núcleo de configuração e validação

- [ ] 55.1 Criar value objects imutáveis para configuração, draft, estado sanitizado da credencial e defaults: 5 s, 15 m, 0,5 e 5 FPS.
- [ ] 55.2 Implementar validadores de valores numéricos, campos obrigatórios/ausentes, URI e formato mínimo `prefixo.segredo`; assegurar que os erros não carreguem a chave completa.
- [ ] 55.3 Implementar regra de URI por variante: HTTPS em todas, `http://localhost:3000` apenas debug, sem sufixo de endpoint, query, fragmento, userinfo ou paths indevidos.
- [ ] 55.4 Escrever testes unitários e de propriedade para defaults, limites inclusivos/exclusivos, normalização de URL, ausência de configuração e sanitização da credencial.
- **Depende de:** 54.
- **Verificação:** nenhuma entrada inválida persiste e nenhum teste/arredondamento torna a chave observável.
- **Requisitos:** RF-13.1–5,17, RF-19.4–8,14, RNF-02.1–6, RNF-03.6.

## 56. Implementar stores e fluxos de credencial

- [ ] 56.1 Implementar repositório versionado de configuração não secreta com carregamento de defaults, save atômico por documento e recuperação controlada de dado ausente/corrompido.
- [ ] 56.2 Implementar adaptador seguro Android para verificar, salvar e remover a API key; restringir leitura completa a uma porta futura de E4, sem acesso de widgets/controllers de tela.
- [ ] 56.3 Implementar casos de uso separados para salvar parâmetros, salvar/substituir credencial e remover credencial com confirmação.
- [ ] 56.4 Cobrir round-trip, falha de storage, configuração parcial/corrompida, substituição, remoção, status sem valor e ausência de logs com fakes, sem depender de keystore físico nos testes Dart.
- **Depende de:** 55.
- **Verificação:** valores não secretos reabrem corretamente; a API key nunca reabre na UI e falhas não derrubam Operação/Fila.
- **Requisitos:** RF-13.6–8,17,22–26, RF-19.9–18, RNF-02.4–14, RNF-03.6,10.

## 57. Implementar apresentação e permissões E3

- [ ] 57.1 Criar `SettingsController`, estado e tela com carregamento, erros por campo, feedback sanitizado, defaults/unidades e ações independentes de parâmetros e credencial.
- [ ] 57.2 Exibir somente “Chave configurada”/“Chave não configurada”; manter o campo de chave vazio ao reabrir, exigir valor completo para troca e confirmação explícita para remoção.
- [ ] 57.3 Adicionar orientação de rotação da chave no Next.js e exemplos exclusivamente fictícios, sem URL/chave reais.
- [ ] 57.4 Integrar painel de permissões: explicar estado e abrir detalhes do app Android quando negação for permanente, preservando o Diagnóstico.
- [ ] 57.5 Criar testes de widget/controller para carregamento, salvar inválido/válido, troca/remoção, ausência de configuração, semântica/acessibilidade e falhas controladas.
- **Depende de:** 56.
- **Verificação:** UI não contém nem reconstrói o segredo, e a ausência de URL/chave não desabilita registro manual ou fila.
- **Requisitos:** RF-13.14–26, RF-19.1–18, RF-20.8, RNF-02.1–8,11–14, RNF-04.2.

## 58. Integrar Operação sem regressão E1/E2

- [ ] 58.1 Adicionar entrada/retorno de Configurações na navegação, aplicando o protocolo de liberar/reconciliar câmera, GPS e wake lock antes/depois da rota.
- [ ] 58.2 Exibir em Operação indicador sanitizado de configuração de envio pendente/pronta, sem bloquear captura, pendências ou chamar rede.
- [ ] 58.3 Tornar cooldown e distância configuráveis em runtime, preservando a referência de último aceite restaurada da fila E2 em atualizações e reaberturas.
- [ ] 58.4 Manter confiança/FPS apenas persistidos e visíveis como parâmetros futuros; proibir qualquer inferência/modelo/frame loop.
- [ ] 58.5 Cobrir com testes controladores, widgets e integração: atualização sem reset de cooldown, reabertura com fila existente, rota Operação → Configurações → Operação, Diagnóstico preservado e permissões independentes.
- **Depende de:** 57.
- **Verificação:** nenhum recurso duplica, nenhum toque precoce é liberado por salvar configuração e E0/E2 seguem íntegros.
- **Requisitos:** RF-05.6, RF-09.5–6, RF-19.2–5,12, RF-20.8, RF-21.1–7, RNF-04.2–3, RNF-05.5.

## 59. Consolidar segurança, qualidade e artefato E3

- [ ] 59.1 Executar formatação, análise, suíte completa e testes dirigidos de configuração, segurança Android, stores, controller e integração do cooldown; corrigir somente falhas E3.
- [ ] 59.2 Inspecionar fontes, dependências, assets, manifesto, logs de teste e APK para confirmar segredo ausente, exceção HTTP restrita e ausência total de E4/E5.
- [ ] 59.3 Gerar APK debug E3, registrar ferramentas, versões pinadas, identidade, tamanho e SHA-256; inspecionar manifesto debug e release/produção separadamente.
- [ ] 59.4 Preparar evidências sanitizadas dos resultados, sem URL de produção, API key, UUID, coordenada, path, imagem ou conteúdo de storage seguro.
- **Depende de:** 58.
- **Verificação:** qualidade e inspeções aprovadas, artefato rastreável e fronteiras E3 confirmadas.
- **Requisitos:** RF-13, RF-19, RF-23.3–10, RNF-02, RNF-03.6, RNF-04.6, RNF-07.4,10.

## 60. Executar roteiro físico E3 no Samsung Galaxy S25+

- [ ] 60.1 Instalar o APK E3 como atualização preservadora, registrar dispositivo/hash e confirmar preservação de pendências E2, preview, GPS e modo manual.
- [ ] 60.2 Verificar defaults, editar/salvar/reabrir cooldown, distância, confiança, FPS e URL válida de teste fictícia/sanitizada; confirmar erros de URL/números inválidos e que o sufixo de ocorrências é recusado.
- [ ] 60.3 Colar chave de teste do dispositivo somente quando fornecida fora do repositório, salvar, reabrir e confirmar apenas o status “configurada”; validar troca, remoção com confirmação e orientação de rotação sem registrar o segredo.
- [ ] 60.4 Verificar ausência de URL/chave: Operação e fila continuam funcionando, indicador informa configuração pendente e não há tráfego/tentativa de ocorrência.
- [ ] 60.5 Confirmar que alteração de cooldown/distância é observável sem perder a pendência/estado E2; force-stop/reabrir e confirmar recuperação de configuração e fila.
- [ ] 60.6 Verificar permissão permanentemente negada em cenário controlado, ação de detalhes Android e retorno; regressar Operação → Diagnóstico → Operação sem câmera/GPS duplicados ou crash.
- [ ] 60.7 Classificar cada cenário como aprovado, reprovado ou não executado; preservar limitações e nunca usar screenshot/log que exponha segredos ou dados sensíveis.
- **Depende de:** 59.
- **Verificação:** roteiro físico aplicável cobre configuração, segredo, permissões, ausência de configuração e regressões E0–E2 no S25+.
- **Requisitos:** RF-13.1–26, RF-19.1–18, RF-20.8, RF-21, RF-23, RNF-04.6, RNF-07.4,10.

## 61. Validation Gate E3 no Samsung Galaxy S25+

- [ ] 61.1 Apresentar análise/testes/build, inspeção de dependências/manifests/backup, APK e hash E3.
- [ ] 61.2 Apresentar evidência de validação/persistência de parâmetros, secure storage, status sanitizado, troca/remoção e ausência de configuração sem bloqueio E1/E2.
- [ ] 61.3 Apresentar atualização segura de cooldown/distância, permissões e regressões E0/E1/E2, incluindo Diagnóstico.
- [ ] 61.4 Apresentar inspeção negativa comprovando ausência de HTTP de ocorrência, autenticação, multipart, worker, backoff, YOLO/TFLite/modelo/inferência.
- [ ] 61.5 Reunir o roteiro e registrar decisão do usuário exatamente como `Aprovação explícita do Validation Gate E3` ou `Reprovação explícita do Validation Gate E3`.
- [ ] 61.6 Parar obrigatoriamente após a decisão: reprovação permite somente correções E3; aprovação encerra E3 e aguarda solicitação posterior para novo ciclo E4.
- **Depende de:** 60.
- **Verificação:** todos os critérios E3 possuem evidência sanitizada, limitações estão declaradas e há decisão explícita do usuário.
- **Requisitos:** RF-23.1–10, RNF-07.4,10.

## Grafo de dependências — E3

```json
{
  "waves": [
    { "id": 0, "tasks": ["53.1", "53.2", "53.3"] },
    { "id": 1, "tasks": ["54.1", "54.2", "54.3", "54.4", "54.5"] },
    { "id": 2, "tasks": ["55.1", "55.2", "55.3", "55.4"] },
    { "id": 3, "tasks": ["56.1", "56.2", "56.3", "56.4"] },
    { "id": 4, "tasks": ["57.1", "57.2", "57.3", "57.4", "57.5"] },
    { "id": 5, "tasks": ["58.1", "58.2", "58.3", "58.4", "58.5"] },
    { "id": 6, "tasks": ["59.1", "59.2", "59.3", "59.4"] },
    { "id": 7, "tasks": ["60.1", "60.2", "60.3", "60.4", "60.5", "60.6", "60.7"] },
    { "id": 8, "tasks": ["61.1", "61.2", "61.3", "61.4", "61.5", "61.6"] }
  ]
}
```

## Limites explícitos da E3

- Não adicionar endpoint, `Authorization`, multipart, envio, classificação HTTP, remoção remota, retry/backoff ou worker; são E4.
- Não adicionar modelo, asset, detector, stream de frames, inferência, FPS real ou substituição da fonte manual; são E5.
- Não gravar URL de produção ou API key em código, testes, documentação, assets, logs, screenshots ou evidências.
- Não alterar a propriedade, recuperação ou política de backup dos dados E2 fora do ajuste mínimo e testado necessário para excluir a credencial segura.
