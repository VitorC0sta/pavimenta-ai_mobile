# Evidência — Tarefa 36.1: compatibilidade das dependências candidatas E2

## Resultado

**SUCESSO para o escopo da tarefa 36.1.** Foram preservados os seis pins diretos aprovados da E1 e confirmados os seguintes candidatos exatos para a futura fixação da E2:

- `sqflite: 2.4.1` como dependência principal;
- `crypto: 3.0.7` como dependência principal;
- `glados: 1.1.7` como dependência de desenvolvimento.

Esta tarefa realizou somente inspeção e validação de compatibilidade. Não adicionou os candidatos ao `pubspec.yaml`, não atualizou o lockfile, não selecionou adaptador SQLite de host e não executou as tarefas 36.2–36.5.

## Baseline preservado

A execução foi feita no baseline aprovado:

- Flutter `3.24.3`, canal stable;
- Dart `3.5.3`;
- projeto Android com AGP `8.5.1`;
- constraint resolvida atual: Dart `>=3.5.3 <4.0.0` e Flutter `>=3.24.0`.

Os seis pins diretos E1 permaneceram exatamente:

| Dependência | Pin preservado |
|---|---:|
| `camera` | `0.11.0+2` |
| `geolocator` | `13.0.2` |
| `image` | `4.2.0` |
| `uuid` | `4.6.0` |
| `wakelock_plus` | `1.2.8` |
| `path_provider` | `2.1.4` |

`flutter pub deps --style=compact` confirmou esses seis pacotes como dependências principais já resolvidas. O grafo também já contém `crypto 3.0.7` transitivamente por `uuid`/`archive`, de modo que sua promoção futura a dependência direta não exige troca de versão.

O `git status --short` já apresentava `pubspec.yaml` e `pubspec.lock` modificados pelo baseline E1 antes desta tarefa. Todos os comandos de candidato foram executados com `flutter pub add --dry-run`; a inspeção posterior confirmou que nenhum candidato foi escrito nesses arquivos e que o diff continuou limitado às alterações E1 preexistentes.

## Compatibilidade de `sqflite 2.4.1`

O resolvedor da toolchain selecionou `sqflite 2.4.1` como a versão mais alta compatível com o baseline ao executar:

```powershell
flutter pub add --dry-run sqflite
```

Resultado: exit code `0`, com resolução de:

- `sqflite 2.4.1`;
- `sqflite_android 2.4.0`;
- `sqflite_common 2.5.4+6`;
- `sqflite_platform_interface 2.4.0`;
- `sqflite_darwin 2.4.1+1`;
- `synchronized 3.3.0+3`.

Os metadados oficiais de [`sqflite 2.4.1`](https://pub.dev/api/packages/sqflite/versions/2.4.1) exigem Dart `^3.5.0` e Flutter `>=3.7.0`, ambos satisfeitos por Dart 3.5.3/Flutter 3.24.3, e declaram Android entre as plataformas. O backend Android resolvido, [`sqflite_android 2.4.0`](https://pub.dev/api/packages/sqflite_android/versions/2.4.0), possui os mesmos mínimos de SDK Flutter/Dart e declara plugin Android.

A inspeção do artefato resolvido em cache confirmou `compileSdk 34`, `minSdk 19`, Java 11 e plugin Android de biblioteca. Isso é compatível com o projeto atual baseado em AGP 8.5.1 e valores Android fornecidos pelo Flutter 3.24.3. A validação definitiva do build após a fixação pertence às tarefas posteriores da 36 e não foi antecipada aqui.

A versão atual publicada `2.4.5` não foi escolhida porque o próprio resolvedor a classificou como incompatível com as constraints vigentes. Assim, o candidato exato tecnicamente justificável para este baseline é `2.4.1`, não a versão publicada mais nova.

## Compatibilidade de `crypto 3.0.7`

Comando:

```powershell
flutter pub add --dry-run crypto:3.0.7
```

Resultado: exit code `0`; a única mudança projetada seria promover `crypto 3.0.7` de transitiva para direta, sem alterar sua versão nem o restante do grafo.

Os metadados oficiais de [`crypto 3.0.7`](https://pub.dev/api/packages/crypto/versions/3.0.7) exigem Dart `^3.4.0`, satisfeito por Dart 3.5.3. É pacote Dart puro, sem requisito Android ou Flutter adicional. Um probe isolado importou a biblioteca e executou SHA-256; a chamada produziu um digest válido. A asserção do probe usou inicialmente um valor esperado digitado incorretamente, portanto esse erro não caracteriza incompatibilidade do pacote e o probe não foi incorporado à suíte do repositório.

## Compatibilidade de `glados 1.1.7`

Comando:

```powershell
flutter pub add --dev --dry-run glados:1.1.7
```

Resultado: exit code `0`. O resolvedor preservou `test_api 0.7.2` do Flutter 3.24.3 e selecionou `test 1.25.7`, `analyzer 6.7.0` e os demais transitivos compatíveis.

Os metadados oficiais de [`glados 1.1.7`](https://pub.dev/api/packages/glados/versions/1.1.7) ainda publicam a constraint legada `>=2.12.0 <3.0.0`. Por isso, a compatibilidade com Dart 3.5.3 não foi inferida apenas desse metadado. Ela foi verificada diretamente com o resolvedor do Flutter 3.24.3 e em sandbox isolado com constraint Dart `>=3.5.3 <3.6.0`, os seis pins E1 e os três candidatos exatos. `flutter pub get` resolveu `glados 1.1.7`, e `flutter test` compilou/importou o pacote e aprovou a instanciação de `Glados<int>`, `any.int` e `ExploreConfig`.

A ressalva é documental: o pacote não declara formalmente Dart 3 em seu pubspec, embora a toolchain-alvo resolva e compile sua API. Para este projeto fixado em Dart 3.5.3, a evidência prática sustenta o pin `1.1.7`; uma atualização futura de toolchain deverá revalidá-lo em vez de presumir compatibilidade.

## Probe isolado e fronteira da tarefa 36.2

Foi criado fora do repositório um sandbox temporário com Flutter SDK, os seis pins E1 e:

```yaml
sqflite: 2.4.1
crypto: 3.0.7
glados: 1.1.7
```

`flutter pub get` resolveu o conjunto completo. O teste compilou os três imports e confirmou a API Glados sob Dart 3.5.3. Ao acessar `databaseFactory` no host Windows, `sqflite` informou corretamente que o factory global não é inicializado fora da plataforma plugin sem backend host. Essa observação não invalida o plugin Android nem o pin `2.4.1`; ela é precisamente a questão reservada à tarefa 36.2 sobre eventual adaptador para testes SQLite reais no host. Nenhum adaptador foi escolhido ou adicionado nesta tarefa.

O probe não foi promovido à suíte porque continha duas asserções exploratórias inadequadas ao escopo: um digest esperado digitado incorretamente e acesso ao factory Android em execução host. Nenhuma falha de resolução, importação ou compilação foi observada.

## Verificações executadas

1. leitura integral de `requirements.md`, `design.md` e do trecho aplicável de `tasks.md`;
2. confirmação de que não existe `.config` no diretório da spec, conforme já registrado na tarefa 35.2; trata-se de feature, não bugfix;
3. inspeção de `pubspec.yaml`, `pubspec.lock`, `.metadata`, Gradle Android e evidências 35.2/35.3;
4. `git status --short`, `flutter --version`, `dart --version` e `flutter pub deps --style=compact`;
5. resolução dry-run separada de `sqflite`, `crypto 3.0.7` e `glados 1.1.7`;
6. confronto dos metadados oficiais e da implementação Android resolvida;
7. resolução e compilação isoladas do conjunto exato sem modificar o repositório;
8. reinspeção de `pubspec.yaml` e `pubspec.lock` após os dry-runs.

## Limites preservados

- nenhum pin E1 foi alterado;
- nenhum pacote E2 foi fixado ainda;
- nenhum adaptador host foi selecionado;
- nenhuma dependência E3–E5 foi adicionada;
- nenhum código Dart, Android, teste do repositório, evidência E0/E1 ou status de tarefa foi modificado;
- nenhum cliente de ocorrência, configuração, segredo, worker, rede, ORM, Hive, gerador, DI, mocks ou visão computacional foi introduzido.

Conteúdo de metadados externos foi reescrito para conformidade com restrições de licenciamento.
