# Evidência da tarefa 59.3 — APK debug E3 e manifestos por variante

## Escopo executado

- Tarefa: **59.3 — Gerar APK debug E3, registrar ferramentas, versões pinadas, identidade, tamanho e SHA-256; inspecionar manifesto debug e release/produção separadamente.**
- Spec consultada antes da execução: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- O diretório da spec não contém `.config`; trata-se de uma spec regular, não de bugfix.
- Limite preservado: esta tarefa gerou somente o APK **debug** e os manifestos mesclados de debug/release para inspeção. Não gerou APK release, não instalou em dispositivo, não alterou código, dependências ou configuração Android, não executou o Gate E3 e não iniciou E4/E5.

## Build debug

A execução única abaixo terminou com êxito:

```text
flutter build apk --debug
```

Resultado: `Built build\app\outputs\flutter-apk\app-debug.apk`.

Também foram gerados os manifestos mesclados de ambas as variantes para a inspeção requerida:

```text
android\gradlew.bat -p android app:processDebugMainManifest app:processReleaseMainManifest
```

Resultado: `BUILD SUCCESSFUL`.

O build exibiu o aviso já conhecido de que os plugins Android requerem NDK `26.1.10909125`, enquanto o projeto declara NDK `23.1.7779620`. O aviso não bloqueou a geração do APK ou dos manifestos. Nenhuma versão de NDK, Flutter, SDK, Gradle ou Java foi modificada nesta tarefa.

## Ferramentas registradas

| Ferramenta | Versão observada |
|---|---|
| Flutter | `3.24.3` stable, framework revision `2663184aa7` |
| Flutter Engine | revision `36335019a8` |
| Dart | `3.5.3` |
| DevTools | `2.37.3` |
| Java | `21.0.2` LTS (`21.0.2+13-LTS-58`) |
| Android SDK platform/build-tools | `34` |
| Gradle wrapper | `8.7` |

## Versões diretas efetivas

| Grupo | Dependência | Versão declarada |
|---|---|---|
| Produção | `camera` | `0.11.0+2` |
| Produção | `geolocator` | `13.0.2` |
| Produção | `image` | `4.2.0` |
| Produção | `uuid` | `4.6.0` |
| Produção | `wakelock_plus` | `1.2.8` |
| Produção | `path_provider` | `2.1.4` |
| Produção | `shared_preferences` | `2.5.2` |
| Produção | `flutter_secure_storage` | `9.2.4` |
| Produção | `sqflite` | `2.4.1` |
| Produção | `crypto` | `3.0.7` |
| Desenvolvimento | `glados` | `1.1.7` |
| Desenvolvimento | `sqflite_common_ffi` | `2.3.4+4` |

`flutter` e `flutter_test` são fornecidos pelo SDK. `flutter_lints: ^4.0.0` permanece a constraint de lint do template e não é um pin funcional E3.

## Identidade e integridade do APK debug

A inspeção do `output-metadata.json` gerado e do próprio APK com a ferramenta Android confirmou:

| Campo | Valor |
|---|---|
| Variante | `debug` |
| Application ID / pacote | `com.vitor.pavimenta_ai_mobile` |
| Nome da aplicação | `pavimenta_ai_mobile` |
| Version code | `1` |
| Version name | `1.0.0` |
| Min SDK | `21` |
| Target / compile SDK | `34` |
| Tamanho | `125953496` bytes |
| Algoritmo de integridade | `SHA-256` |
| SHA-256 | `2FAC8A62713157F23739FBB726CDD589E70E4691455BB84113FF731608C1D23E` |

A inspeção do APK também confirmou que ele é depurável, possui como atividade iniciável `com.vitor.pavimenta_ai_mobile.MainActivity`, e declara somente câmera, localização precisa/aproximada, internet e a permissão de assinatura interna criada pelo merge AndroidX.

## Inspeção separada dos manifestos mesclados

### Debug

O manifesto mesclado de debug confirma:

- pacote `com.vitor.pavimenta_ai_mobile`, versão `1.0.0`/código `1`, `minSdk=21` e `targetSdk=34`;
- `android:debuggable="true"`;
- `android:usesCleartextTraffic="false"` no elemento `application`;
- referência exclusiva da variante debug a `@xml/network_security_config_debug`;
- permissões de câmera, localização precisa/aproximada e internet;
- câmera marcada como recurso não obrigatório;
- referências às regras de backup e extração de dados preservadas.

O recurso debug referenciado estabelece `cleartextTrafficPermitted="false"` em `base-config` e autoriza cleartext apenas para o domínio `localhost`, sem subdomínios. Assim, a exceção HTTP está confinada à configuração de segurança da variante debug; ela não abre cleartext globalmente.

### Release/produção

O manifesto mesclado de release foi processado e inspecionado separadamente, sem gerar um APK release. Ele confirma:

- o mesmo pacote, versão, `minSdk=21`, `targetSdk=34`, permissões e recurso de câmera não obrigatório do aplicativo aprovado;
- `android:usesCleartextTraffic="false"` no elemento `application`;
- ausência de `android:networkSecurityConfig` e, portanto, ausência da referência a `network_security_config_debug`;
- ausência de `android:debuggable="true"`;
- preservação das referências de backup e extração de dados.

Conclusão da fronteira Android: a exceção de cleartext para `localhost` pertence somente ao debug. A configuração release/produção mantém transporte em texto claro bloqueado.

## Resultado

**SUCESSO no escopo da tarefa 59.3.** O APK debug E3 foi gerado, sua identidade, tamanho e SHA-256 foram registrados junto com ferramentas e dependências diretas. Os manifestos mesclados debug e release foram gerados e inspecionados separadamente, confirmando a exceção HTTP limitada ao debug e o bloqueio de cleartext em release/produção. Nenhuma tarefa posterior foi executada.
