# Evidência da tarefa 32.3 — Artefato, dependências e identidade Android

## Escopo

- Repositório: `c:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`
- Subtarefa exclusiva: **32.3 — Inspecionar o artefato e as dependências quanto ao escopo exclusivo E1 e à preservação da identidade Android aprovada**.
- Documentos normativos consultados: `requirements.md`, `design.md` e `tasks.md` da spec `mvp-app-flutter`, além das evidências 32.1 e 32.2.
- O diretório da spec não contém `.config`; a execução foi tratada como spec comum, não bugfix.
- Limite preservado: inspeção do APK já produzido e das dependências diretas/resolvidas. Nenhuma reconstrução, alteração funcional ou implementação E2–E5 foi realizada. A inspeção negativa ampliada da tarefa 32.4 não foi executada nesta subtarefa.

## Artefato inspecionado

```text
C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile\build\app\outputs\flutter-apk\app-debug.apk
```

O SHA-256 atual é:

```text
FA8535852E4E5151B9F59EAB36D89047E54E4BE41DEA80F7347BDF74E1E2349F
```

O valor coincide exatamente com a evidência 32.2. Portanto, a inspeção incidiu sobre o mesmo APK aprovado nas subtarefas anteriores; o artefato não foi reconstruído nem modificado.

## Identidade Android compilada

A inspeção direta com `aapt2 dump badging` e `aapt2 dump permissions`, confrontada com `android/app/build.gradle`, o manifesto empacotado e `output-metadata.json`, produziu:

| Campo | Valor observado | Resultado |
|---|---|---|
| package/applicationId do APK | `com.vitor.pavimenta_ai_mobile` | corresponde exatamente à identidade aprovada |
| namespace Gradle | `com.vitor.pavimenta_ai_mobile` | preservado |
| activity inicial | `com.vitor.pavimenta_ai_mobile.MainActivity` | preservada sob o package aprovado |
| label | `pavimenta_ai_mobile` | preservado |
| variante | `debug` | conforme tarefa 32 |
| versionName | `1.0.0` | consistente entre metadados e APK |
| versionCode | `1` | consistente entre metadados e APK |
| minSdk | `21` | compilado no artefato |
| targetSdk | `34` | compilado no artefato |
| compileSdk | `34` | compilado no artefato |
| câmera | `android.hardware.camera`, `required=false` | preserva falha controlada |
| cleartext | `android:usesCleartextTraffic="false"` | preservado no manifesto empacotado |

Permissões efetivamente compiladas:

- `android.permission.INTERNET`;
- `android.permission.CAMERA`;
- `android.permission.ACCESS_FINE_LOCATION`;
- `android.permission.ACCESS_COARSE_LOCATION`;
- `com.vitor.pavimenta_ai_mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, permissão de assinatura gerada pela infraestrutura AndroidX para receivers não exportados.

Não foram reincorporadas as permissões de áudio ou armazenamento removidas pelo manifesto principal. A permissão dinâmica AndroidX usa o mesmo applicationId aprovado e não altera a identidade da aplicação.

O manifesto compilado contém, além da `MainActivity`, somente componentes trazidos pela infraestrutura Flutter/AndroidX e pelas integrações aprovadas: serviço do Geolocator, serviço de metadados CameraX, `GoogleApiActivity` do Google Play Services usado pela cadeia Android de localização, inicializador/profile installer AndroidX e respectivos metadados. Esses componentes correspondem à câmera, localização e infraestrutura Android transitiva; não configuram módulos funcionais adicionais da aplicação.

## Dependências diretas aprovadas

`pubspec.yaml`, `pubspec.lock` e `flutter pub deps --style=compact` concordam quanto aos pins diretos principais:

| Dependência direta | Versão resolvida | Uso no escopo E0/E1 |
|---|---:|---|
| `camera` | `0.11.0+2` | preview e captura operacional |
| `geolocator` | `13.0.2` | localização precisa e snapshot operacional |
| `image` | `4.2.0` | preparação JPEG |
| `uuid` | `4.6.0` | UUID v4 |
| `wakelock_plus` | `1.2.8` | tela ligada somente durante Operação ativa |
| `path_provider` | `2.1.4` | diretório temporário privado |

Todos os seis pins são exatos, sem `^` ou intervalo aberto. Além deles, existem apenas o Flutter SDK e as dependências de desenvolvimento já previstas (`flutter_test` e `flutter_lints`). Não há outra dependência direta principal.

## Dependências resolvidas e plugins Android

A árvore resolvida terminou com código `0` e mostra transitivos compatíveis com os seis pins, incluindo adaptadores de plataforma, CameraX, Android lifecycle, Google Play Services de localização, codecs/arquivos do pacote `image`, criptografia/fixnum do `uuid`, interfaces de plugin e utilitários do SDK/testes.

O registrador Android gerado contém exatamente estes plugins nativos:

1. `camera_android_camerax`;
2. `flutter_plugin_android_lifecycle`;
3. `geolocator_android`;
4. `package_info_plus`;
5. `path_provider_android`;
6. `wakelock_plus`.

`flutter_plugin_android_lifecycle` é transitivo de `camera`; `package_info_plus` é transitivo de `wakelock_plus`. `image` e `uuid` são Dart puros e, portanto, não registram plugins Android. O arquivo gerado `.flutter-plugins-dependencies` confirma a mesma cadeia.

A árvore Pub também contém `http` como dependência **transitiva** de `package_info_plus`, que por sua vez é transitiva do pin aprovado `wakelock_plus`. `http` não consta no `pubspec.yaml` como dependência direta, não é cliente de ocorrências e não representa integração implementada pela aplicação. Esta distinção é relevante porque a versão aprovada de `wakelock_plus` determina essa cadeia transitiva.

## Conteúdo do APK

A listagem ZIP do APK encontrou 211 entradas. Os elementos funcionais identificáveis são coerentes com o build Flutter debug e as integrações aprovadas:

- snapshots/assets padrão do Flutter;
- asset `packages/wakelock_plus/assets/no_sleep.js` pertencente ao pacote aprovado;
- bibliotecas `libflutter.so`;
- utilitários nativos CameraX de processamento/superfície;
- metadados AndroidX/CameraX/lifecycle/profile installer;
- manifesto, recursos, assinatura debug e ícones padrão.

Os recursos adicionais do Google Play Services e AndroidX são transitivos da implementação Android de localização/câmera e não constituem dependências diretas nem funcionalidades de etapas posteriores.

## Comandos e verificações

Inspeção concluída com sucesso:

```powershell
Get-FileHash -Algorithm SHA256 build\app\outputs\flutter-apk\app-debug.apk
C:\Users\vitor\AppData\Local\Android\sdk\build-tools\34.0.0\aapt2.exe dump badging build\app\outputs\flutter-apk\app-debug.apk
C:\Users\vitor\AppData\Local\Android\sdk\build-tools\34.0.0\aapt2.exe dump permissions build\app\outputs\flutter-apk\app-debug.apk
flutter pub deps --style=compact
```

Também foram inspecionados diretamente:

- `pubspec.yaml` e `pubspec.lock`;
- `android/app/build.gradle`;
- `android/app/src/main/AndroidManifest.xml`;
- manifesto empacotado de debug;
- `build/app/outputs/apk/debug/output-metadata.json`;
- `.flutter-plugins-dependencies`;
- `GeneratedPluginRegistrant.java`;
- entradas internas do APK por `System.IO.Compression`.

Uma consulta suplementar a `:app:dependencies --configuration debugRuntimeClasspath` não produziu evidência adicional porque o PowerShell promoveu o aviso já conhecido de divergência do NDK a `NativeCommandError` antes do processamento da saída. Nenhuma configuração foi alterada. Isso não bloqueia a conclusão: o APK existe e foi diretamente inspecionado, enquanto `pubspec.lock`, `flutter pub deps`, `.flutter-plugins-dependencies` e o registrador Android fornecem a árvore resolvida e os plugins efetivamente incorporados.

## Conclusão

**SUCESSO.** O APK inspecionado permanece no escopo exclusivo E0/E1 quanto ao artefato e às dependências: os únicos pins diretos principais são os seis aprovados, e os plugins/componentes Android observados decorrem dessas integrações e da infraestrutura Flutter/AndroidX. A identidade Android compilada está preservada exatamente como `com.vitor.pavimenta_ai_mobile`, com `MainActivity` e label coerentes. O hash confirma que o artefato não mudou desde a tarefa 32.2. Nenhuma funcionalidade E2–E5 foi implementada ou adicionada.