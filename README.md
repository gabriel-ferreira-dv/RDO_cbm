# RDO cbm

App que eu desenvolvi para os encarregados registrarem no celular o que foi feito na obra durante o dia (foto, local e serviço) e, no fim do dia, gerarem o RDO em PDF.

## Por que eu fiz

Antes do app, as fotos e os avisos de serviço chegavam pelo grupo do WhatsApp, cada um de um jeito. Muitas vezes não dava para saber em que KM ou estaca a foto tinha sido tirada, e montar o RDO, a medição e o avanço da obra virava um trabalho de garimpo.

A ideia é que o registro já saia padronizado do campo. O encarregado escolhe o trecho, o KM, a estaca e o serviço, tira as fotos, e cada foto sai carimbada com essas informações, data, hora, coordenada, o logo e um minimapa do local.

## O que tem no app

O app é dividido em abas:

- **Registro**: escolhe trecho, KM e estaca, ou toca em "Preencher pela minha localização" e o GPS sugere a estaca mais perto. Depois vem a atividade, o serviço e o passo. Quando o serviço é medido, dá para informar quantidade e unidade, e a descrição pode ser ditada. No fim abre a câmera.
- **Paradas**: registro de paralisação, com motivo, hora de início e fim e fotos.
- **Histórico**: tudo o que já foi registrado, agrupado por atividade.
- **Mapa**: satélite com o desenho do projeto por cima e a posição atual. Cada usuário vê os mapas do grupo dele (CBM ou subcontratada).
- **Relatório**: gera o RDO do dia em PDF, com os registros, as fotos, as paralisações, o clima, o efetivo que vem do SIMOVA e um mapa das atividades.
- **Equipe** (só para supervisor): o supervisor monta a equipe dele, acompanha os registros dos encarregados, gera o relatório consolidado e o mapa de avanço. Também consegue lançar um registro em nome de um encarregado.

Além disso, o app avisa às 16:30, de segunda a sábado, para ninguém esquecer de registrar, e mostra as mensagens que o gestor manda pelo Supabase.

## Como funciona por dentro

O mais importante: **o app funciona sem internet**. Tudo é gravado primeiro no celular, num banco SQLite, e quando tem sinal ele envia sozinho para o Supabase. Se a internet cai no meio do envio, o que faltou fica pendente e sobe na próxima vez. Para não duplicar nada no servidor, cada linha é identificada pelo aparelho e pelo id que ela tem no celular (`dispositivo_id` + `id_local`).

No Supabase eu uso:

- **Auth** para o login com e-mail e senha. Sem internet, o app aceita a última senha que funcionou online.
- **Postgres com RLS**: o encarregado só vê o que é dele, o supervisor vê também a equipe dele e o gestor do painel vê tudo. Quem é supervisor fica na tabela `perfis_app`, que o app não consegue alterar.
- **Storage**: o bucket `fotos` (privado) e o bucket `dados` (público), onde ficam os CSVs, os mapas e o APK novo.
- **Edge Function** que puxa o relatório "Equipe Apontada" do SIMOVA, para o RDO já sair com o efetivo do dia.

Os CSVs do projeto (`KMxEst.csv`, `estacas_coords.csv` e `SevNotaveis.csv`) vêm junto com o APK. Se eu subo uma versão nova no Supabase, o app baixa sozinho, sem precisar lançar outra versão. Os mapas funcionam do mesmo jeito, só que não vêm no APK: são sempre baixados do Supabase. Quem controla isso é a tabela `versoes_dados`.

As coordenadas das estacas estão em UTM (SIRGAS 2000, fuso 24S), igual ao CAD do projeto. O app converte para latitude e longitude com o `proj4dart` para comparar com o GPS e encaixar os mapas.

O painel web que os gestores usam fica em outro repositório (`painel`) e lê o mesmo Supabase.

## Organização do código

Separei por funcionalidade. Cada pasta em `lib/features/` tem as telas em `presentation/` e um `*_service.dart` com as regras e o acesso aos dados. A tela chama o serviço direto, sem camadas no meio. Para o tamanho do app, isso deixa mais fácil achar as coisas.

```
lib/
  main.dart
  core/            banco local, tema, configuração do Supabase e widgets comuns
  features/
    auth/          login e sessão
    registro/      formulário, CSVs, estacas e sugestão pelo GPS
    camera/        câmera e carimbo da foto
    paralisacao/   aba Paradas
    historico/
    mapa/          mapa, tiles do projeto e permissão por grupo
    relatorio/     RDO em PDF, clima, efetivo do SIMOVA e turno da noite
    sincronizacao/ envio para o Supabase e atualização dos dados e do app
    supervisor/    equipe, registros da equipe, consolidado e mapa de avanço
    notificacoes/  lembrete diário, mensagens do gestor e avisos de atualização
    tutorial/
supabase/          scripts SQL que eu rodo no SQL Editor
tool/              scripts de apoio: fontes do carimbo, ícone e preparação dos mapas
scripts/           pull_db.ps1, para copiar o banco de um celular para o PC
test/
```

## Banco no celular

O SQLite fica no arquivo `registro_diario.db`, na pasta de dados do app (não fica dentro do projeto). As tabelas são criadas e atualizadas em `lib/core/database/db_helper.dart`, e hoje o banco está na versão 14. Quando eu acrescento um campo, coloco a migração no `onUpgrade`, assim quem atualiza o app não perde nada.

As tabelas são `usuarios`, `registros`, `fotos`, `paralisacoes`, `fotos_paralisacao`, `relatorio_diario_info` (os dados do RDO de cada dia) e `avisos`. As que sobem para o Supabase têm a coluna `sincronizado`: 0 enquanto falta enviar, 1 depois que o servidor confirmou.

Para olhar o banco de um celular conectado no PC, eu rodo `.\scripts\pull_db.ps1`.

## Scripts do Supabase

Os arquivos da pasta `supabase/` eu rodo à mão no SQL Editor. Cada um explica no começo o que faz e se pode rodar mais de uma vez.

Um cuidado: quando o app passa a mandar uma coluna nova, eu rodo o script que cria essa coluna no Supabase **antes** de lançar a versão. Senão o servidor recusa os registros que chegam com a coluna desconhecida.

## Como rodar

```bash
flutter pub get
flutter run
```

Os testes:

```bash
flutter test
```

Para ver os widgets sem abrir o app inteiro, uso o Widget Preview (os exemplos estão em `lib/core/widgets/previews.dart`):

```bash
flutter widget-preview start
```

A URL e a chave pública do Supabase ficam em `lib/core/supabase_config.dart`. Essa chave é pública mesmo, porque vai dentro do APK. Quem protege os dados são as regras de RLS.

Para gerar o APK e instalar nos celulares, escrevi o passo a passo no [README-build.md](README-build.md).

## Testes

Os testes ficam em `test/`, separados do mesmo jeito que as features. Eles cobrem principalmente as partes de lógica: o carimbo da foto, as estacas e o KM final, a sugestão pelo GPS, a leitura dos CSVs, o texto e as fotos do PDF, o clima e o efetivo do RDO, a sincronização, o relatório consolidado e o mapa de avanço.

O que depende de câmera, GPS ou do Supabase de verdade eu testo no celular.

## O que ainda falta

- O `applicationId` ainda é `com.example.flutter_application_1`. Trocar exige que todo mundo desinstale e instale de novo, então faz sentido trocar junto com a assinatura.
- Os APKs ainda são assinados com a chave de debug do meu computador. O README-build.md explica o porquê e o que fazer na hora de trocar.
