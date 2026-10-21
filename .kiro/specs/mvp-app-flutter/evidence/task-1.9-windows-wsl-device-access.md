# Evidência — Tarefa 1.9: comparação de acesso ao aparelho entre Windows e WSL

## Resultado

**Status: comparação executada com bloqueio de acesso ao aparelho.** O ambiente Windows possui o ADB do Android SDK e conseguiu executar a enumeração, mas não listou nenhum dispositivo Android. O WSL está instalado e possui a distribuição Ubuntu 24.04 em WSL2, porém essa distribuição não possui um comando `adb` disponível; por isso, não foi possível enumerar nem confirmar acesso ao Samsung Galaxy S25+ a partir do WSL.

O resultado confirma a separação exigida pelo design: **o reconhecimento de um aparelho pelo ADB do Windows não implica reconhecimento pelo ADB do WSL**. Cada ambiente usa sua própria disponibilidade e conexão de ADB e precisa ser validado diretamente. Nesta execução, não houve reconhecimento no Windows e não havia ADB nativo disponível no WSL para realizar a enumeração.

## Momento e ambientes verificados

- Data e hora da verificação: `2026-10-19T23:34:22.6321036-03:00`.
- Windows: Microsoft Windows NT `10.0.26300.0`.
- ADB Windows: `C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe`.
- WSL: `wsl.exe` disponível em `C:\WINDOWS\system32\wsl.exe`.
- Distribuição inspecionada: `Ubuntu-24.04`, WSL versão 2.
- Kernel observado na distribuição: `6.18.54.1-microsoft-standard-WSL2`.

## Verificação no Windows

Comando executado:

```text
C:\Users\vitor\AppData\Local\Android\sdk\platform-tools\adb.exe devices -l
```

Saída relevante:

```text
ADBExecutableExists=True
List of devices attached
WindowsADBDevicesExitCode=0
```

O comando terminou normalmente, mas não houve linha de dispositivo após o cabeçalho. Assim, nenhum serial foi observado com estado `device`, `unauthorized` ou `offline`, e o Galaxy S25+ não estava acessível pelo ADB Windows no momento da comparação.

## Verificação no WSL

A disponibilidade do WSL foi verificada sem instalar ou alterar componentes:

```text
Default Distribution: docker-desktop-data
Default Version: 2

NAME                   STATE           VERSION
* docker-desktop-data  Stopped         2
docker-desktop         Stopped         2
Ubuntu-24.04           Stopped         2
```

Na distribuição `Ubuntu-24.04`, foram consultados o ambiente e a presença de ADB e Flutter. Saída relevante:

```text
Linux DESKTOP-V1T0RC0F3 6.18.54.1-microsoft-standard-WSL2 #1 SMP PREEMPT_DYNAMIC Tue Oct  6 19:13:07 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux
WSLADB=not-found
WSLADBDevices=not-executed
/mnt/c/dev/flutter/bin/flutter
WSLFlutterFound=true
WSLInvocationExitCode=0
```

O caminho de Flutter encontrado sob `/mnt/c` aponta para o SDK armazenado no volume Windows. Essa descoberta não comprova uma toolchain Linux/WSL independente e, principalmente, não substitui a ausência de um ADB disponível dentro da distribuição. Como `adb` não foi encontrado, `adb devices -l` não foi executado no WSL e nenhum acesso WSL ao aparelho pode ser afirmado.

## Comparação e conclusão

| Ambiente | ADB disponível no próprio ambiente | Enumeração executada | Galaxy S25+ reconhecido |
|---|---:|---:|---:|
| Windows | Sim | Sim; código de saída `0` | Não; lista vazia |
| Ubuntu 24.04 / WSL2 | Não | Não; bloqueada pela ausência de `adb` | Não comprovado |

O ambiente executor já registrado para Flutter na tarefa 1.7 é o Windows. Nesse ambiente, o acesso ao aparelho permanece bloqueado pela lista vazia, de forma consistente com a evidência da tarefa 1.8. O WSL não oferece evidência alternativa de acesso porque não dispõe de ADB nativo nesta distribuição.

Mesmo que uma execução futura passe a listar o Galaxy pelo ADB Windows, será obrigatório executar uma verificação separada dentro do WSL antes de afirmar que comandos Flutter/ADB executados no WSL conseguem acessar o aparelho. Da mesma forma, uma enumeração WSL não deve ser inferida a partir de saída do processo Windows.

## Bloqueios e etapa manual

- **Windows:** conectar e autorizar manualmente o Galaxy S25+ e repetir a enumeração no mesmo ambiente Windows que executará Flutter, conforme já descrito na evidência da tarefa 1.8.
- **WSL:** acesso não verificável enquanto não houver uma estratégia de ADB para WSL explicitamente autorizada e validada. Nenhuma instalação ou reconfiguração deve ser feita automaticamente.
- Para a continuidade no ambiente atualmente escolhido, a evidência necessária é o serial do Galaxy com estado `device` no ADB Windows e o destino Android correspondente no Flutter Windows; não é necessário usar WSL.

Nenhuma instalação, atualização, inicialização/reinicialização manual de servidor ADB, aceite de licença ou reconfiguração de Flutter, Android SDK, Gradle, Java, ADB, drivers USB ou WSL foi executada. Nenhum projeto Flutter, funcionalidade ou teste automatizado foi criado, e nenhuma outra tarefa da especificação foi executada.
