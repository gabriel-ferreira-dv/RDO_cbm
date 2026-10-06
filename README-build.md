
## 1. Gerar o APK

```powershell
flutter build apk --release
```

O arquivo sai em:

```
build\app\outputs\flutter-apk\app-release.apk
```

Esse APK já é instalável em qualquer Android. Se ainda não existir a chave de
assinatura (passo 2), ele é assinado com a chave de debug — funciona para
testar, mas use a chave própria para distribuir de verdade.

## 2. Criar a chave de assinatura (uma vez só)

> **Atenção antes de criar:** os APKs distribuídos até a versão 1.0.0+2 foram
> assinados com a chave de debug deste computador
> (`C:\Users\064925\.android\debug.keystore`). Criar a chave agora faz os
> celulares recusarem as próximas atualizações — todo mundo teria que
> desinstalar e instalar de novo. Enquanto não trocar, gere os APKs sempre
> neste computador e mantenha um backup desse arquivo.

A chave é o "carimbo" que identifica o app como seu. **Sem ela, não é possível
lançar atualizações por cima de uma versão já instalada** — o Android recusa a
instalação se a assinatura mudar.

No PowerShell, dentro da pasta do projeto:

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v `
  -keystore android\app\upload-keystore.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias rdocbm
```

Ele vai pedir uma senha (escolha uma e **guarde bem**) e alguns dados
(nome, organização, cidade...). Pode responder o que fizer sentido; nada disso
aparece para o usuário do app.

Depois crie o arquivo `android\key.properties` com o conteúdo abaixo,
trocando `SUA_SENHA` pela senha que você digitou:

```properties
storePassword=SUA_SENHA
keyPassword=SUA_SENHA
keyAlias=rdocbm
storeFile=upload-keystore.jks
```

Pronto: a partir daí `flutter build apk --release` usa a chave real
automaticamente.

> **Importante:** `key.properties` e o `.jks` estão no `.gitignore` (não vão
> para o repositório). Faça um backup dos dois num lugar seguro — perder o
> `.jks` significa nunca mais conseguir atualizar o app já instalado nos
> celulares da equipe.

## 3. Instalar em outro celular

1. Envie o `app-release.apk` para o celular (cabo USB, Google Drive, OneDrive
   ou pen drive — o arquivo é grande demais para WhatsApp/e-mail, ver seção 4).
2. No celular, abra o arquivo pelo gerenciador de arquivos.
3. O Android vai avisar que a instalação vem de "fonte desconhecida" —
   toque em **Configurações** → permita a instalação para aquele app
   (gerenciador de arquivos ou navegador) → volte e confirme.
4. Na primeira abertura, o app pede as permissões de câmera, localização,
   microfone e notificações. Todas são necessárias para o registro.

Alternativa por cabo (mais rápido, com o celular em modo desenvolvedor):

```powershell
flutter install --release
```

## 4. Tamanho do APK

Desde a versão 1.0.0+2 os mapas **não vão no APK** (eram uns 200 dos 254 MB).
Cada celular baixa os mapas pela tela de Atualizações, do bucket `dados` do
Supabase — então todo mapa de `mapas_config.dart` precisa estar lá, com a
linha dele em `versoes_dados`. Sem isso, o mapa mostra só o satélite.

Ele já era 791 MB: os tiles dos mapas eram PNG (~725 MB) e foram convertidos
para **WebP** (~130 MB), sem diferença visível. Os tiles são fotos aéreas com
transparência: PNG é ótimo para desenho e péssimo para foto; JPEG não serve
(não tem transparência); WebP resolve os dois lados e é lido nativamente pelo
Flutter.

### Se os tiles forem regerados

Depois de gerar tiles novos em PNG (`tool/split_overlay.dart`), converta:

```powershell
npm install sharp             # uma vez só
node tool\converter_tiles_webp.js --mover
```

Os PNGs originais vão para `_tiles_png_backup/` (fora dos assets, fora do
git). O app procura **`.webp`** — PNG solto nas pastas de overlay só ocupa
espaço no APK sem ser usado.

### Atualização de mapa pelo Supabase

O `.zip` de cada mapa enviado ao bucket `dados` deve conter os arquivos
**`.webp`**. Se subir PNGs, o app baixa mas não acha os tiles.

## 5. Publicar uma atualização pelo próprio app

O passo a passo está no topo de `supabase/versao_app.sql`. Em resumo:
aumentar o número depois do `+` em `version:` no `pubspec.yaml`, gerar o APK
**neste computador**, subir no bucket `dados` com nome novo (`RDO-cbm-3.apk`)
e atualizar a linha de `versao_app`. Só chega a quem já tem a 1.0.0+2 ou
mais nova; a primeira versão com o recurso ainda vai pelo grupo.
