# Checklist preparado — validação física E0 no Samsung Galaxy S25+

## Uso e limite

Este roteiro foi preparado na tarefa 14 para uso posterior. Todos os itens observacionais permanecem **não executados**. A retomada da tarefa 14 gerou e instalou o APK no Galaxy S25+, mas não abriu o aplicativo nem realizou observação física. Preencher evidência real somente na tarefa 15; este documento não aprova o Validation Gate.

### Estado de prontidão atualizado na tarefa 14

- Dispositivo físico: acessível; ADB reportou estado `device` com serial e identificadores sanitizados.
- Flutter: listou o mesmo destino Android como `SM S936B (mobile)`, com identificador sanitizado.
- APK: presente em `build/app/outputs/flutter-apk/app-debug.apk`.
- Tamanho: `90.075.154 bytes` (aproximadamente `85,90 MiB`).
- SHA-256: `E9FB2F248A46E713982C00C6A6A276293E1928C8B7485548E05EE5071548EA50`.
- Instalação: concluída com `adb install -r`; resultado `Success`.
- Pacote confirmado: `com.vitor.pavimenta_ai_mobile`.
- Aplicativo aberto: não.
- Bloqueio técnico para iniciar posteriormente a tarefa 15: nenhum.
- Validação física: não iniciada; câmera, GPS, rede, permissões, responsividade e ciclo de vida continuam sem aprovação.

### Histórico preservado

Antes desta retomada, o aparelho já havia passado de ausente para `device`, mas o APK continuava ausente devido à falha em `:camera_android_camerax:compileDebugJavaWithJavac` / `JdkImageTransform` com AGP 8.1.0, Gradle 8.3 e JDK 21. A retomada corrigiu localmente AGP/Gradle, gerou o artefato e concluiu a instalação. O histórico detalhado das tentativas está em `task-14-build-and-installation.md`.

Para cada item observacional, registrar `Aprovado`, `Reprovado` ou `Não executado`, referência da evidência (captura, gravação ou log sanitizado) e observação objetiva. Não registrar URL funcional, query string, coordenadas integrais desnecessárias, identificador do aparelho ou outro dado sensível.

## 1. Pré-condições técnicas

- [x] APK debug existe em `build/app/outputs/flutter-apk/app-debug.apk`; tamanho e SHA-256 registrados acima.
- [x] Build foi produzido com `E0_DIAGNOSTIC_URL` fornecida fora do repositório e representada somente como `<URL_HTTPS_EXCLUSIVA_DE_TESTE>`.
- [x] Responsável confirmou que o destino é público e destinado exclusivamente a testes de clientes HTTP, não produção, e não exige credencial.
- [x] ADB Windows lista o Galaxy S25+ com estado `device`.
- [x] Flutter Windows lista o mesmo Galaxy S25+.
- [x] Aplicativo instalado; sucesso e `applicationId` `com.vitor.pavimenta_ai_mobile` confirmados.
- [ ] Para validar primeira abertura, dados/permissões anteriores deverão ser removidos manualmente ou deverá ser usada instalação limpa na tarefa 15.

## 2. Abertura imediata

- [ ] Ao abrir, a tela E0 aparece imediatamente, antes de concluir permissões.
- [ ] Título e aviso deixam claro que nenhum dado de ocorrência é criado ou enviado.
- [ ] Painéis de câmera, localização e rede aparecem sem crash ou tela congelada.
- [ ] Evidência: captura/gravação desde o toque no ícone até a primeira tela.

## 3. Ordem e independência das permissões

- [ ] Câmera é a primeira solicitação Android.
- [ ] Localização não aparece simultaneamente à câmera.
- [ ] Localização só é solicitada após concessão **ou recusa** da câmera.
- [ ] Toques repetidos e retomadas não duplicam diálogos.
- [ ] Recusar câmera não bloqueia localização e rede.
- [ ] Recusar localização não bloqueia câmera e rede.
- [ ] Evidência: gravação de primeira execução e dos dois cenários de recusa.

## 4. Câmera traseira

- [ ] Após conceder permissão, o preview usa uma câmera traseira.
- [ ] Preview preserva proporção e permanece utilizável durante rolagem/orientação.
- [ ] Câmera ocupada, ausente ou com permissão negada produz mensagem clara, sem crash.
- [ ] Não há inferência, stream para processamento, detecção, FPS ou captura de ocorrência.
- [ ] Evidência: captura do preview e captura da indisponibilidade.

## 5. Localização precisa

- [ ] Solicitação é somente em primeiro plano.
- [ ] Localização aproximada é distinguida e não apresentada como precisa.
- [ ] Com localização precisa, latitude, longitude e precisão reportada aparecem quando há posição.
- [ ] Velocidade aparece em m/s quando fornecida; caso contrário, aparece `Não fornecida`, sem zero artificial.
- [ ] Serviço desligado, permissão negada/permanente e posição indisponível têm mensagens distintas e não causam crash.
- [ ] Nenhum valor de GPS é associado a ocorrência.
- [ ] Evidência: capturas sanitizadas dos estados disponível, precisão reduzida, serviço desligado e posição indisponível.

## 6. Rede e HTTP diagnóstico

- [ ] Nenhuma requisição ocorre automaticamente; o diagnóstico começa apenas por ação manual.
- [ ] Durante a requisição, há progresso local e os demais painéis continuam utilizáveis.
- [ ] Destino HTTPS de teste responde e a tela mostra somente código/classificação sanitizados.
- [ ] Corpo e headers da resposta não aparecem em tela, armazenamento ou logs.
- [ ] Não há corpo de requisição, autenticação, API key, imagem, coordenadas, UUID ou endpoint de ocorrências.
- [ ] Redirecionamento não é seguido.
- [ ] Falha de rede/destino apresenta mensagem clara sem crash.
- [ ] Configuração fictícia `.invalid` produz falha controlada.
- [ ] URL ausente, relativa, não HTTPS, sem host, com usuário/senha, com fragmento ou com `/api/v1/occurrences` é rejeitada antes da conexão.
- [ ] Certificado inválido e resposta excessiva/incompleta: executar somente se houver ambiente de teste controlado; caso contrário marcar `Não executado`, sem desabilitar TLS ou inventar endpoint.
- [ ] Evidência: captura do sucesso sanitizado e das indisponibilidades, além de log sem conteúdo/segredo.

## 7. Responsividade

- [ ] Conteúdo permanece acessível por rolagem em retrato e paisagem, quando permitido.
- [ ] Com escala de fonte aumentada, textos quebram linha e botões continuam acessíveis.
- [ ] Preview, botões e indicadores permanecem responsivos durante inicialização e HTTP.
- [ ] Estados não dependem somente de cor.
- [ ] Evidência: capturas nas orientações e escalas observadas; registrar qualitativamente, sem inventar meta numérica.

## 8. Ciclo de vida

- [ ] Enviar ao segundo plano durante inicialização e retornar não causa crash.
- [ ] Enviar ao segundo plano após diagnósticos e retornar não duplica stream, diálogo ou requisição.
- [ ] Câmera é restaurada sem reutilizar controlador inválido.
- [ ] Localização é retomada sem múltiplas assinaturas aparentes.
- [ ] Requisição ativa é cancelada/controlada ao sair do primeiro plano.
- [ ] Evidência: gravação de pelo menos um ciclo pausa/retomada em estado inicial e outro após diagnósticos.

## 9. Indisponibilidades e recuperação

- [ ] Câmera negada/indisponível: mensagem clara; GPS e rede seguem operacionais.
- [ ] Localização negada/aproximada/serviço desligado/sem posição: mensagem clara; câmera e rede seguem operacionais.
- [ ] Modo avião ou destino inacessível: mensagem de rede/destino; câmera e GPS seguem operacionais.
- [ ] Após restaurar cada condição, a ação de tentar novamente recupera o painel aplicável sem duplicação ou crash.
- [ ] Evidência: capturas antes/depois da recuperação de cada condição executada.

## 10. Fechamento do pacote de evidências

- [ ] Saída do build e hash do APK.
- [ ] Saída sanitizada da instalação e confirmação do applicationId.
- [ ] Abertura imediata.
- [ ] Ordem das permissões.
- [ ] Preview traseiro.
- [ ] GPS, precisão e velocidade/ausência.
- [ ] HTTP de teste e indisponibilidade de rede/destino.
- [ ] Mensagens de câmera e localização indisponíveis.
- [ ] Responsividade e ciclo de vida.
- [ ] Declaração sanitizada da URL: fornecida fora do repositório; destino de teste; não produção; sem credencial.
- [ ] Inspeção de limite: sem YOLO/TFLite/inferência/detecção/ocorrência/cooldown/fila/API key/multipart/API de ocorrências.

## Declaração obrigatória antes do gate

O build e a instalação, isoladamente, **não aprovam câmera, GPS ou rede**. Esses itens só podem receber resultado após observação no Galaxy S25+ durante a tarefa 15. A decisão do Validation Gate deve ser explícita e não é preenchida neste checklist preparado.
