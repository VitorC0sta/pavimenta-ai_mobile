# Evidência da tarefa 60.1 — Atualização preservadora E3 no Galaxy S25+

## Escopo executado

- Tarefa: **60.1 — Instalar o APK E3 como atualização preservadora, registrar dispositivo/hash e confirmar preservação de pendências E2, preview, GPS e modo manual.**
- Repositório: `C:\Users\vitor\Documents\tcc\pavimenta-ai_mobile`.
- Spec consultada: `requirements.md`, `design.md` e `tasks.md` de `mvp-app-flutter`.
- A pasta da spec não contém `.config` nem `.config.kiro`; a spec é regular, não um bugfix.
- Limite: esta execução não abriu Configurações, não alterou parâmetros ou credencial, não acionou `Registrar buraco`, não limpou dados, não removeu o pacote, não executou as tarefas 60.2–60.7 e não aprovou o Gate E3.

## Artefato E3 e dispositivo

| Campo | Valor sanitizado |
|---|---|
| APK instalado | `build\app\outputs\flutter-apk\app-debug.apk` |
| Variante | debug |
| Pacote | `com.vitor.pavimenta_ai_mobile` |
| Versão | `1.0.0` (código `1`) |
| Tamanho | `125953496` bytes |
| SHA-256 recalculado | `2FAC8A62713157F23739FBB726CDD589E70E4691455BB84113FF731608C1D23E` |
| Correspondência | Coincide com o artefato E3 registrado em `task-59.3-e3-debug-apk-and-manifests.md`. |
| Ambiente executor | Windows, ADB local do Android SDK |
| Dispositivo | Samsung `SM-S936B` (Galaxy S25+) |
| Serial ADB | `RQGL701ZV7Z` |
| Estado ADB | `device` |
| Android | `17` (API `37`) |

## Atualização preservadora

Antes da atualização, o pacote existente tinha `versionName=1.0.0`, `versionCode=1`, `firstInstallTime=2026-10-24 18:33:58` e `lastUpdateTime=2026-10-26 09:34:27`.

O APK E3 foi aplicado ao mesmo pacote com:

```text
adb -s RQGL701ZV7Z install -r build\app\outputs\flutter-apk\app-debug.apk
```

O resultado foi `Success`. Não foram usados `adb uninstall`, `pm clear`, limpeza de dados, remoção de arquivos ou instalação com novo identificador de pacote.

Após a instalação, o pacote continuou com `versionName=1.0.0` e `versionCode=1`; `firstInstallTime` permaneceu `2026-10-24 18:33:58`, enquanto `lastUpdateTime` passou a `2026-10-28 01:03:52`. A preservação do primeiro instante de instalação, em conjunto com o uso exclusivo de `install -r`, confirma que o Android substituiu a aplicação existente sem criar uma instalação limpa.

## Validação no aparelho físico

O aplicativo foi aberto no Galaxy S25+ atualizado. A atividade `com.vitor.pavimenta_ai_mobile/.MainActivity` ficou em foco. A inspeção da interface efetivamente renderizada no aparelho, com valores de localização redigidos e sem screenshots persistidos, confirmou:

| Verificação exigida pela tarefa | Resultado observado |
|---|---|
| Pendências E2 | A fila local informou estado **Pronta** e exibiu **4 pendências** após a atualização. A presença dos registros não vazios, somada à atualização sem limpeza, confirma a preservação da fila E2. |
| Preview traseiro | Estado **Câmera traseira pronta** e semântica de preview disponível foram observados no aplicativo atualizado. |
| GPS | Estado **GPS pronto/disponível** foi observado. Latitude, longitude, precisão e velocidade foram renderizadas pelo aparelho, mas seus valores não foram registrados. |
| Modo manual | O banner semântico declarou modo de registro manual com detecção automática indisponível. O controle **Registrar buraco por confirmação manual** estava presente. |

A tela foi somente rolada para observar a fila e o controle manual. O botão de registro não foi acionado, evitando criar uma nova ocorrência ou alterar a contagem E2 durante uma tarefa dedicada apenas à preservação.

## Resultado

**SUCESSO no escopo da tarefa 60.1.** O APK E3 de hash rastreável foi instalado no Samsung Galaxy S25+ como atualização preservadora. A aplicação manteve o pacote existente e carregou quatro pendências E2, preview traseiro pronto, GPS pronto e a interface de modo manual. Nenhum dado de localização, imagem, UUID, caminho interno, URL ou credencial foi incluído nesta evidência.

As validações de parâmetros, URL, credencial, ausência de configuração, force-stop, permissões e classificação consolidada continuam exclusivamente nas tarefas 60.2–60.7.
