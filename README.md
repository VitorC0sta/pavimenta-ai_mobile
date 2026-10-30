# pavimenta_ai_mobile

Aplicativo Flutter, exclusivo para Android, que registra ocorrências manuais de buracos (foto, localização e metadados) em uma fila local persistente e as envia ao Pavimenta AI Analytics. Esta documentação cobre até a etapa E4 (envio). Não há worker nem serviço em segundo plano.

Todos os valores de URL, chave e identificadores neste documento são **fictícios**. Nunca versione URL real de teste, chave real, UUID, coordenada ou imagem.

## 1. Ambiente, build e execução

### Pré-requisitos

- Flutter **3.24.3** (canal stable, revisão do framework `2663184aa7`) com Dart **3.5.3**. O `pubspec.yaml` exige `sdk: ^3.5.3`.
- Android SDK instalado e licenças aceitas (`flutter doctor --android-licenses`). O wrapper do projeto usa Gradle 8.7.
- JDK compatível com o Android Gradle Plugin, normalmente o JDK que acompanha o Android Studio.
- Aparelho Android físico com depuração USB habilitada.

### Instalar o Flutter

1. Baixe o SDK 3.24.3 em <https://docs.flutter.dev/release/archive> ou, com o repositório Git, execute `git clone https://github.com/flutter/flutter.git -b 3.24.3 --depth 1`.
2. Adicione `flutter/bin` ao `PATH`.
3. Execute `flutter --version` e confirme Flutter 3.24.3 e Dart 3.5.3.
4. Execute `flutter doctor` e resolva as pendências de Android.

### Dependências, análise e testes

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Os testes não usam a API real. O envio é exercitado com fakes e servidor local controlado.

### Build Android

```powershell
flutter build apk --debug     # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release   # exige configuração de assinatura própria
```

### Instalar e executar no aparelho físico

```powershell
adb devices                    # o aparelho deve aparecer como "device"
flutter install -d <ID_DO_APARELHO>
# ou, para executar com hot reload em debug:
flutter run -d <ID_DO_APARELHO>
```

Para atualizar sem apagar dados, reinstale por cima (`adb install -r build/app/outputs/flutter-apk/app-debug.apk`). Não desinstale o app se quiser preservar a fila e a configuração. Conceda as permissões de câmera e localização quando solicitado.

## 2. Configuração de envio

Na tela de Configurações informe:

- **`BASE_URL`**: apenas a origem, **sem** o sufixo `/api/v1/occurrences`. O app acrescenta o caminho. Sem query, fragmento, credenciais na URL nem redirect.
  - Exemplo fictício: `https://analytics.example.test`
  - Incorreto: `https://analytics.example.test/api/v1/occurrences`
- **`DEVICE_API_KEY`**: chave do dispositivo, provisionada **manualmente** pelo operador do Analytics (cadastro do dispositivo no painel) e colada no campo. O app não gera nem baixa chaves. Prefira uma chave de dispositivo de teste do tipo `mobile`. A chave fica no armazenamento seguro do Android, não é exibida de volta e não entra em logs, backup ou transferência.

Em release, apenas HTTPS é aceito. Sem `BASE_URL` ou sem chave, nenhuma chamada de rede é feita e a tela Operação informa que a configuração é necessária. O registro manual continua funcionando e as ocorrências ficam na fila.

### Autenticação

Cada requisição envia exatamente este header:

```text
Authorization: ApiKey {DEVICE_API_KEY}
```

Onde `{DEVICE_API_KEY}` é substituído pela chave configurada. O app não envia `Bearer`, `X-API-Key`, cookies nem outro header de credencial.

## 3. Contrato de envio

```text
POST {BASE_URL}/api/v1/occurrences
Authorization: ApiKey {DEVICE_API_KEY}
Content-Type: multipart/form-data; boundary=<boundary-da-tentativa>
```

### Campos multipart

| Campo | Conteúdo |
|---|---|
| `idempotencyKey` | UUID gerado ao registrar a ocorrência e persistido |
| `latitude` | número entre -90 e 90 |
| `longitude` | número entre -180 e 180 |
| `confidence` | `1.0` (ocorrência manual) |
| `defectClass` | `pothole` |
| `detectedAt` | ISO 8601 com fuso |
| `speedKmh` | opcional; enviado só se houver valor válido (inclusive `0`), caso contrário omitido |
| `image` | JPEG, nome de arquivo genérico `occurrence.jpg`, até 2 MiB |

**Nunca enviados no MVP:** `highway`, `km`, `source`, `accuracyMeters`, digest, sequência local e estado de retry.

### Idempotência

A `idempotencyKey` é criada uma única vez e reutilizada em todas as tentativas do mesmo item, junto com os mesmos campos e os mesmos bytes da imagem. Se uma resposta se perder, a repetição não duplica a ocorrência. O boundary multipart pode mudar entre tentativas. Isso não afeta o conteúdo lógico.

### Respostas e decisões

| Resposta | Efeito | Ocorrência local |
|---|---|---|
| `200` (já existente) ou `201` (criada) | sucesso | removida com a imagem |
| `400`, `409`, `413`, `415` | descarte definitivo | removida com a imagem |
| `401` | pausa "autenticação" | preservada |
| `403` | pausa "acesso" (dispositivo inativo) | preservada |
| `5xx`, rede, DNS, TLS, timeout | falha recuperável com backoff | preservada |
| demais códigos, inclusive `3xx` | pausa "resposta inesperada" | preservada |
| imagem ausente ou inválida | pausa "falha local", sem abrir conexão | preservada |

A decisão usa somente o código de status, nunca o corpo da resposta. Redirects não são seguidos.

Limites por tentativa: conexão 10 s, tentativa total até os headers 45 s, descarte do corpo de resposta até 64 KiB / 5 s, um upload por vez.

### Backoff

Após a falha recuperável de número `n`, a espera é `min(5 s × 3^(n-1), 15 min)`: 5 s, 15 s, 45 s, 2 min 15 s, 6 min 45 s, depois 15 min. O estado de tentativa e o próximo instante são persistidos e sobrevivem a reinício do app. Cancelamento por saída do primeiro plano não conta como falha.

### Pausas e retry manual

`401`, `403`, resposta inesperada e falha local **não** repetem sozinhas. A pausa termina quando:

- uma nova `BASE_URL` ou chave é salva, ou a chave ausente é restaurada; ou
- o usuário toca em **Tentar envio novamente** na tela Operação.

Esse botão só aparece quando pode produzir nova avaliação. Ele não antecipa um backoff recuperável, não zera a contagem de tentativas, não cria ocorrência e não remove itens. Remover a chave ou a URL nunca dispara rede.

### Sem garantia com o app fechado

O envio ocorre somente enquanto o app está em primeiro plano (`resumed`). Ao ir para segundo plano, o app cancela a tentativa em curso e o timer. As ocorrências permanecem na fila e a mesma `idempotencyKey` é reutilizada na retomada. **Não há worker, serviço em segundo plano nem garantia de envio com o app fechado, em segundo plano ou com a tela bloqueada.** Reabra o app para retomar.

## 4. Desenvolvimento local com o Analytics real

Para testar contra um Analytics rodando no seu computador, sem expor um servidor público nem exigir deploy de produção:

1. Inicie o Analytics localmente na porta 3000.
2. Conecte o aparelho por USB e confirme com `adb devices`.
3. Encaminhe a porta do aparelho para o computador:

   ```powershell
   adb reverse tcp:3000 tcp:3000
   ```

4. Instale um build **debug** e configure `BASE_URL` como `http://localhost:3000` (sem sufixo), mais a chave de um dispositivo de teste cadastrado no Analytics local.

`http://localhost:3000` é aceito **somente em builds debug**, por meio de uma configuração de rede exclusiva de debug. Builds release exigem HTTPS e bloqueiam tráfego em texto claro. Se o USB for desconectado ou o aparelho reiniciar, repita o `adb reverse`.

## 5. Gates de validação E4

Há dois gates distintos. Passar no primeiro não autoriza declarar o segundo.

### Gate simulado (de desenvolvimento)

Usa fakes e servidor HTTP local controlado, sem API real. Comprova contrato, matriz de status, autenticação, payload, backoff, pausas, persistência, lifecycle, segurança e regressões E0–E3. Não comprova integração real.

### Gate real

Exige tudo do gate simulado e, adicionalmente:

1. APK, hash SHA-256 e versões das ferramentas registrados.
2. Instalação preservadora e roteiro executados em aparelho físico (Samsung Galaxy S25+).
3. **URL de teste acessível** pelo aparelho, fornecida fora do repositório.
4. **Chave válida de dispositivo de teste**, fornecida fora do repositório.
5. Ocorrência manual persistida antes da tentativa de envio.
6. **Recebimento comprovado no back-end**, com evidência sanitizada.
7. Repetição idempotente controlada, sem duplicação indevida.
8. Cenários aplicáveis: sem configuração, falha recuperável, pausa e retomada.
9. Contagem e imagem locais consistentes após a conclusão.
10. Regressões E0–E3 e ausência de E5.
11. Decisão explícita do usuário.

A evidência sanitizada deve conter apenas resultado e contagens (por exemplo, "1 ocorrência recebida, 1 imagem associada, repetição sem duplicação"). Não inclua URL, chave, header, UUID, coordenadas, horário da ocorrência, nome de arquivo, caminho, digest nem a imagem.

Se a URL, a chave ou a evidência do back-end não estiverem disponíveis, o gate real fica **não executado**, ainda que todos os testes simulados passem.

## 6. Segurança e dados sensíveis

- Nada de URL real, chave real, header preenchido, UUID, coordenada ou imagem deve aparecer no repositório, em issues, logs ou evidências.
- Logs técnicos usam apenas eventos fixos (por exemplo `delivery_timeout`, `delivery_http_401`).
- Configure URL e chave apenas no aparelho, em tempo de uso.
