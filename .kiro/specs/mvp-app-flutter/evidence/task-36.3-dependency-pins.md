# Evidência — Tarefa 36.3: fixação das dependências E2

## Resultado

**SUCESSO para o escopo da tarefa 36.3.** As dependências aprovadas para a E2 foram fixadas com versões exatas no `pubspec.yaml`, e o `pubspec.lock` foi atualizado por resolução normal com Flutter 3.24.3/Dart 3.5.3.

## Pins registrados

### Dependências principais

- `sqflite: 2.4.1`
- `crypto: 3.0.7`

### Dependências de desenvolvimento

- `glados: 1.1.7`
- `sqflite_common_ffi: 2.3.4+4`

Os seis pins E1 foram preservados sem alteração: `camera 0.11.0+2`, `geolocator 13.0.2`, `image 4.2.0`, `uuid 4.6.0`, `wakelock_plus 1.2.8` e `path_provider 2.1.4`.

## Justificativas

- **`sqflite 2.4.1`:** é a versão exata mais alta que o resolvedor da toolchain aprovada aceita para o projeto. Exige Dart `^3.5.0` e Flutter `>=3.7.0`, atendidos por Dart 3.5.3 e Flutter 3.24.3. Fornece o SQLite Android escolhido no design para constraints, unicidade, transações, versão de schema e ordenação determinística.
- **`crypto 3.0.7`:** exige Dart `^3.4.0`, é compatível com Dart 3.5.3 e já estava resolvido transitivamente na mesma versão. O pin direto explicita o uso E2 de SHA-256 por streaming sem introduzir segredo ou criptografia de banco.
- **`glados 1.1.7`:** é o pin aprovado para as propriedades 13–20. Embora seus metadados mantenham constraint legada anterior ao Dart 3, a tarefa 36.1 comprovou resolução e compilação reais com Flutter 3.24.3/Dart 3.5.3, preservando `test_api 0.7.2` e resolvendo `test 1.25.7`/`analyzer 6.7.0` compatíveis. A compatibilidade deverá ser reavaliada se a toolchain mudar.
- **`sqflite_common_ffi 2.3.4+4`:** o adaptador host é realmente necessário porque `sqflite` sozinho depende do plugin da plataforma e não inicializa `databaseFactory` em testes host Windows. O design exige testes com SQLite temporário real; este é o único adaptador de desenvolvimento adicionado. Ele exige Dart `^3.5.0`, declara suporte a Windows e aceita `sqflite_common >=2.5.4+2 <4.0.0`; a resolução conjunta usa `sqflite_common 2.5.4+6`, também compartilhado por `sqflite 2.4.1`.

Nenhum pin usa `^`, intervalo aberto ou resolução flutuante para os quatro pacotes desta tarefa. `sqflite_common_ffi` permanece em `dev_dependencies` e não integra o aplicativo de produção.

## Resolução e validação

Comandos executados na raiz do repositório:

```powershell
flutter pub get
flutter pub deps --style=compact
```

Resultados:

- `flutter pub get`: exit code `0`; lockfile atualizado normalmente.
- `flutter pub deps --style=compact`: exit code `0`.
- Grafo principal confirmado: `sqflite 2.4.1` e `crypto 3.0.7` como dependências diretas.
- Grafo de desenvolvimento confirmado: `glados 1.1.7` e `sqflite_common_ffi 2.3.4+4` como dependências diretas.
- Backend compartilhado confirmado: `sqflite_common 2.5.4+6`; backend host confirmado: `sqlite3 2.9.4`; backend Android confirmado: `sqflite_android 2.4.0`.
- O resolvedor informou versões mais novas incompatíveis com as constraints, sem erro de resolução e sem atualização global de Flutter, Dart, Android SDK, Gradle ou Java.

Uma primeira tentativa de encadear os comandos com `&&` não foi aceita pela versão do PowerShell disponível e não executou o resolvedor. Os mesmos comandos foram então executados sequencialmente com verificação explícita do exit code; essa execução concluiu com sucesso.

## Limites preservados

- nenhum código de fila, schema, persistência, imagem durável ou teste PBT foi implementado;
- nenhuma dependência de E3–E5 foi adicionada;
- nenhum pacote de rede de ocorrências, secure storage, worker, estado, DI, mocks, ORM, Hive ou visão computacional foi adicionado;
- nenhuma evidência histórica E0/E1 nem status de tarefa foi alterado;
- as tarefas 36.4 e posteriores não foram executadas.
