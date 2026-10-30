# Evidência da tarefa 72.3 — APK debug E4, ferramentas, identidade e manifestos

Data: 2026-10-29. Escopo: gerar o APK **debug** E4 e inspecionar os manifestos debug e release separadamente. Não foi gerado APK release, nada foi instalado em aparelho, nenhum código, dependência ou configuração Android foi alterado.

## Build

- `flutter build apk --debug` → `Built build\app\outputs\flutter-apk\app-debug.apk`.
- `android\gradlew.bat app:processDebugMainManifest app:processReleaseMainManifest` → `BUILD SUCCESSFUL`.
- Aviso já conhecido: plugins pedem NDK `26.1.10909125`; o projeto declara o NDK padrão do Flutter 3.24.3. Não bloqueou o build e nada foi alterado.
- O código de saída 1 do PowerShell no `flutter build` decorre do aviso em stderr; o APK foi gerado.

## Ferramentas

| Ferramenta | Versão |
|---|---|
| Flutter | 3.24.3 stable, framework `2663184aa7`, engine `36335019a8` |
| Dart | 3.5.3 (DevTools 2.37.3) |
| Java | 21.0.2 LTS (`21.0.2+13-LTS-58`) |
| Gradle wrapper | 8.7 |
| Android SDK compile/target | 34 (build-tools usado na inspeção: 35.0.0, `aapt2`) |

## Versões pinadas (`pubspec.yaml`)

Produção: `camera 0.11.0+2`, `geolocator 13.0.2`, `image 4.2.0`, `uuid 4.6.0`, `wakelock_plus 1.2.8`, `path_provider 2.1.4`, `shared_preferences 2.5.2`, `flutter_secure_storage 9.2.4`, `sqflite 2.4.1`, `crypto 3.0.7`, `http 1.6.0`.
Desenvolvimento: `glados 1.1.7`, `sqflite_common_ffi 2.3.4+4`, `flutter_lints ^4.0.0` (constraint do template).

## Identidade e integridade

| Campo | Valor |
|---|---|
| Variante | debug (`output-metadata.json`) |
| Application ID | `com.vitor.pavimenta_ai_mobile` |
| Version code / name | `1` / `1.0.0` |
| minSdk / targetSdk / compileSdk | 21 / 34 / 34 |
| Debuggable | sim |
| Atividade iniciável | `com.vitor.pavimenta_ai_mobile.MainActivity` |
| Tamanho | 126325365 bytes |
| SHA-256 | `434DB52C642F8324E12437C7CEFE6E5233E46193DAED435A4E5E4D21EA1CA669` |

Permissões no APK (`aapt2 dump badging`): `INTERNET`, `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` e a permissão de assinatura interna `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (AndroidX). Câmera é recurso não obrigatório. Sem permissões de áudio ou armazenamento externo.

## Manifestos

Manifestos usados: `merged_manifests\debug\processDebugManifest\AndroidManifest.xml` e `merged_manifest\release\processReleaseMainManifest\AndroidManifest.xml`. Os dois foram reconfirmados como atuais pelo Gradle (tarefas up-to-date, entradas inalteradas). O arquivo `merged_manifests\debug\AndroidManifest.xml` (20/10) é resíduo antigo, anterior às regras de backup e à config de rede, e foi ignorado; o manifesto do próprio APK foi lido diretamente para confirmar.

| Atributo | Debug (manifesto mesclado e APK) | Release (manifesto mesclado) |
|---|---|---|
| `debuggable` | `true` | ausente |
| `usesCleartextTraffic` | `false` | `false` |
| `networkSecurityConfig` | `@xml/network_security_config_debug` | **ausente** |
| `fullBackupContent` | `@xml/backup_rules` | `@xml/backup_rules` |
| `dataExtractionRules` | `@xml/data_extraction_rules` | `@xml/data_extraction_rules` |
| Permissões | INTERNET, CAMERA, FINE/COARSE_LOCATION | idem |
| minSdk / targetSdk / versão | 21 / 34 / 1.0.0 (1) | idem |

`network_security_config_debug.xml` (apenas em `src/debug`): `base-config cleartextTrafficPermitted="false"` e cleartext permitido somente para o domínio `localhost`, sem subdomínios. O release não referencia esse recurso e mantém cleartext bloqueado.

## Backup e transferência

`backup_rules.xml` (`fullBackupContent`) e `data_extraction_rules.xml` (`cloud-backup` e `device-transfer`) excluem:

- banco `e2_occurrence_queue_v1.db` e seus `-journal`, `-wal`, `-shm`;
- diretório de arquivos `e2_queue_images_v1/`;
- `sharedpref` `pavimenta_ai_mobile_secure_storage.xml` (chave do dispositivo).

As mesmas regras valem em debug e release.

## Resultado

**SUCESSO no escopo da 72.3.** APK debug E4 gerado e rastreável por identidade, tamanho e SHA-256. Exceção HTTP restrita ao debug e a `localhost`; release com cleartext bloqueado; backup e transferência excluem fila, JPEGs e credencial. Isto não é evidência do gate real E4.
