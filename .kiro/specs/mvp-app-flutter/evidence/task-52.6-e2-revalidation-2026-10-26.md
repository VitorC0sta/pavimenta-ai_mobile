# Revalidação física E2 — 2026-10-26

## Objetivo

Revalidar no Samsung Galaxy S25+ o único cenário físico que permanecia reprovado na classificação E2: a coerência integral da mensagem de sucesso no APK realmente instalado. A revalidação também repetiu os fluxos físicos essenciais de persistência, recuperação e navegação para assegurar que a atualização não introduziu regressões.

## Artefato e dispositivo

- Dispositivo detectado pelo Flutter: **SM S936B**, serial `RQGL701ZV7Z`, Android 17 (API 37).
- Pacote: `com.vitor.pavimenta_ai_mobile`.
- Artefato: `build/app/outputs/flutter-apk/app-debug.apk`.
- Tamanho: `109794930` bytes.
- SHA-256: `6F70B80B4D5D7345C9F58234354A8C00834A004BA7CAFE5F7B9C8BA2DC8142EF`.
- Instalação: atualização por `adb install -r`, concluída com `Success`; nenhuma desinstalação, `pm clear` ou limpeza de dados foi executada.
- Versão instalada: `versionName=1.0.0`, `versionCode=1`, `lastUpdateTime=2026-10-26 09:34:27`.

## Validação automatizada contemporânea

| Verificação | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | Aprovada — 75 arquivos, 0 alterações. |
| `flutter analyze` | Aprovada — `No issues found!`. |
| `flutter test` | Aprovada — 207 testes. |
| `flutter test test/infrastructure/android_backup_policy_test.dart` | Aprovada — 3 testes. |
| `flutter build apk --debug` | Aprovada — APK acima produzido. |
| `android\gradlew.bat -p android app:processDebugMainManifest` | Aprovada — manifesto debug processado. |

O build emitiu avisos não bloqueantes de compatibilidade de versão NDK e recursos Gradle depreciados; não houve falha de análise, testes, build ou manifesto.

## Observações físicas confirmadas pelo usuário

1. A fila inicializou e ficou pronta no S25+; preview traseiro, GPS e modo manual permaneceram operacionais.
2. Um registro manual válido mostrou a mensagem **`Buraco salvo na fila local.`**, incrementou o contador de sessão e aumentou as pendências da fila. Não foi exibida a descrição residual que afirmava salvamento somente em memória.
3. O aplicativo sofreu `adb shell am force-stop` e foi reaberto sem limpar dados. As pendências foram recuperadas, o contador da nova sessão reiniciou e o cooldown bloqueou uma tentativa precoce sem criar pendência adicional; o registro voltou a ser permitido após o período normal.
4. A navegação Operação → Diagnóstico → Operação foi concluída sem crash, mantendo as pendências e restaurando preview, GPS, modo manual e fila local.

As confirmações acima foram fornecidas pelo usuário durante a sessão de validação. Nenhum UUID, coordenada, caminho de arquivo, conteúdo de imagem, API key ou log sensível foi registrado nesta evidência.

## Limitações preservadas

Esta revalidação não transforma em observação física os cenários anteriormente classificados como não executados: novo diálogo de localização, frame transitório do bootstrap, ordem visual transitória da persistência, reconstrução física granular sanitizada, ausência no MediaStore, responsividade durante estado transitório, backup/restauração e transferência entre dispositivos. As limitações permanecem explicitamente declaradas em `task-51.9-e2-scenario-classification.md`.

## Conclusão

O único cenário físico reprovado anteriormente foi **revalidado e aprovado** no APK identificado por este hash. A evidência física aplicável e a validação automatizada contemporânea estão reunidas para a decisão humana do Validation Gate E2. Este documento não é a aprovação do gate; ela depende de uma declaração explícita do usuário.