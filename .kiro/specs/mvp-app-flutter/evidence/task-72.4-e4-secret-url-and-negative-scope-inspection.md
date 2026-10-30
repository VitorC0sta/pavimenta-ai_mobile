# Evidência da tarefa 72.4 — Inspeção de segredo/URL real, HTTP release/localhost e ausência de E5/worker

Data: 2026-10-29. Inspeção somente leitura de fontes, `pubspec`, assets, README, evidências, testes e do APK debug de SHA-256 `434DB52C642F8324E12437C7CEFE6E5233E46193DAED435A4E5E4D21EA1CA669` (ver 72.3). Nenhum código, dependência ou configuração foi alterado.

## 1. Segredo e URL real ausentes

| Alvo | Verificação | Resultado |
|---|---|---|
| `lib/**/*.dart` | Busca de `https?://` | 4 ocorrências, todas permitidas: dois comentários de documentação sobre `http://localhost:3000` (`configuration_validators.dart`, `streamed_http_client_adapter.dart`), o destino do Diagnóstico E0 `https://e0-diagnostic.example.invalid/health` e o hint `https://servidor-exemplo.invalid` da tela de Configurações. Todos usam domínios `.invalid`. |
| `lib`, `android/app/src`, `test`, `README.md`, `pubspec.yaml` | Padrões de chave/segredo (`ApiKey` + valor, `sk_live`, `AKIA…`, chave privada PEM) | Nenhuma ocorrência. Os únicos UUIDs são idempotency keys fictícias em testes. |
| `String.fromEnvironment`, `dart-define`, `BuildConfig`, `.env` | Busca em `lib` e `android/app` | Uma ocorrência: `lib/e0/diagnostic_http_client.dart`, URL do Diagnóstico E0 com default `.invalid`. Sem URL ou chave de entrega embutida por build. |
| Arquivos do repositório | `git ls-files` por `.env`, keystore, `.pem`, `key.properties`, `google-services`, `.log` | Nenhum arquivo versionado. |
| Evidências e README | URLs, `ApiKey`/`Bearer` com valor, tokens longos, UUIDs | URLs só fictícias (`analytics.example.test`, `.invalid`, `<…>`) ou de documentação (Flutter, pub.dev). Os tokens longos são SHA-256 de artefatos. Nenhum UUID, chave ou header preenchido. |
| Testes (`test/**`) | URLs e `ApiKey` | Somente `.invalid`, `.test`, `example`, loopback e entradas negativas como `https://user:pass`. Nenhum literal `ApiKey <valor>`. Os logs de teste desta fase são os de `task-72.1` e `task-72.2`, sem dado real. |
| `assets` | `pubspec.yaml` | Sem seção `assets`. O APK contém apenas arquivos do framework (`kernel_blob.bin`, snapshots, `MaterialIcons`, `ink_sparkle.frag`, `NOTICES.Z`, manifestos de asset) e `no_sleep.js` do plugin `wakelock_plus`. |
| APK (`kernel_blob.bin`, `classes*.dex`, XML de recursos) | Extração e varredura de strings | Zero literais `ApiKey <valor>`. XML de recursos e manifestos de asset sem `api_key`/`secret`/`token`/`password`/`Bearer` e sem URL. O blob Dart traz URLs de comentários do SDK e de dependências. Do projeto aparecem só as fictícias `.invalid` e as menções em comentário a `http://localhost:3000`. As 25 ocorrências da palavra `Authorization` vêm do SDK Dart, de `package:http` e do transporte E4; o escopo do transporte é fixado pelo teste arquitetural abaixo. |

## 2. HTTP em release bloqueado e localhost só em debug

- `ConfigurationValidators.optionalBaseUrl`: HTTPS é válido em qualquer build; `http` só é aceito se o build for debug **e** o destino for exatamente `http://localhost:3000`. Teste `allows exact localhost HTTP origin only in debug` confirma `release` inválido para `http://localhost:3000`, além de rejeitar `http://localhost` e `http://localhost:3001`.
- Android (ver 72.3): manifesto mesclado de release sem `networkSecurityConfig`, com `usesCleartextTraffic="false"`. A exceção cleartext para `localhost` (sem subdomínios) existe só em `src/debug/res/xml/network_security_config_debug.xml`, referenciada só pelo manifesto de debug.
- O manifesto principal mantém `usesCleartextTraffic="false"`; o teste arquitetural exige exatamente uma permissão `INTERNET` nele.

## 3. Ausência integral de E5/worker

- `lib`: nenhuma ocorrência de `workmanager`, `background_fetch`, `flutter_background_service`, `ultralytics`, `tflite`, `tensorflow`, `.onnx`, `startImageStream`, `CameraImage`, `Isolate.spawn`, `compute(` ou `Timer.periodic`.
- `pubspec.yaml` e `pubspec.lock`: nenhum pacote de worker, conectividade, `dio` ou modelo. O único pacote de rede é `http 1.6.0`, confinado ao transporte E4.
- APK: nenhum arquivo `.tflite`, `.onnx`, `.pt`, `.pb`, `.mlmodel`, `.lite`, `.ncnn`; nenhum `tensorflow`, `yolo`, `workmanager` ou `androidx/work` nos nomes de entrada; nenhuma referência a `androidx.work`, `org.tensorflow`, `com.ultralytics` ou `org.pytorch` nos seis `classes*.dex`; nenhum `package:` de pacote proibido nem arquivo do projeto com nome de worker/modelo no kernel Dart (81 arquivos Dart do projeto). Bibliotecas nativas: apenas Flutter, câmera, `datastore` e a camada de validação Vulkan do build debug.
- Manifesto principal sem `<service>`, `<receiver>` ou `<provider>`; os componentes do manifesto mesclado de debug vêm de geolocator, câmera e AndroidX.
- Único texto YOLO em produção: o banner aprovado `Modo manual — YOLO ainda não configurado`.

## 4. Testes dirigidos executados

```text
flutter test test/architecture/e4_delivery_boundaries_test.dart \
  test/architecture/e3_configuration_boundaries_test.dart \
  test/infrastructure/delivery/e4_delivery_sanitization_inspection_test.dart
→ +28: All tests passed!
```

(Uma primeira chamada com caminho errado para o teste de sanitização falhou ao carregar o arquivo; foi erro de invocação, não de teste, e a reexecução com o caminho correto passou.)

## Resultado

**SUCESSO no escopo da 72.4.** Não há segredo nem URL real nas fontes, dependências, assets, evidências, testes ou no APK. O HTTP em release está bloqueado e o `localhost` fica restrito ao debug. Não há E5, worker, modelo nem inferência.
