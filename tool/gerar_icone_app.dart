// Gera as imagens do ícone do app a partir do assets/logo.png (logo branco
// da empresa, 2099x633, fundo transparente):
//   - assets/icone_app.png: quadrado 1024px, fundo asfalto escuro (#1F2933)
//     com o logo centralizado — ícone "legado" do Android.
//   - assets/icone_app_foreground.png: logo em canvas transparente com
//     margem extra — foreground do adaptive icon (o Android corta ~25% das
//     bordas em ícones adaptativos, por isso a folga maior).
//
// Rode com: dart run tool/gerar_icone_app.dart
// Depois: dart run flutter_launcher_icons (config no pubspec.yaml).
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final logo = img.decodeImage(File('assets/logo.png').readAsBytesSync())!;
  const tamanho = 1024;

  // Em tamanho de launcher (48px) o texto "CONSTRUTORA BARBOSA MELLO" fica
  // ilegível — o ícone usa só o símbolo, que ocupa o terço esquerdo do
  // logo. O trim remove as bordas transparentes do recorte.
  final simbolo = img.trim(
    img.copyCrop(logo,
        x: 0, y: 0, width: (logo.width * 0.38).round(), height: logo.height),
    mode: img.TrimMode.transparent,
  );

  img.Image logoAjustado(double fracaoMaxima) {
    final maxLado = (tamanho * fracaoMaxima).round();
    final escala = [maxLado / simbolo.width, maxLado / simbolo.height]
        .reduce((a, b) => a < b ? a : b);
    return img.copyResize(
      simbolo,
      width: (simbolo.width * escala).round(),
      interpolation: img.Interpolation.average,
    );
  }

  void compor(img.Image destino, img.Image conteudo) {
    img.compositeImage(
      destino,
      conteudo,
      dstX: ((tamanho - conteudo.width) / 2).round(),
      dstY: ((tamanho - conteudo.height) / 2).round(),
    );
  }

  // Ícone legado: fundo escuro + símbolo em 62% do lado.
  final icone = img.Image(width: tamanho, height: tamanho, numChannels: 4);
  img.fill(icone, color: img.ColorRgba8(31, 41, 51, 255)); // #1F2933
  compor(icone, logoAjustado(0.62));
  File('assets/icone_app.png').writeAsBytesSync(img.encodePng(icone));

  // Foreground adaptativo: transparente + símbolo menor (folga p/ o corte).
  final foreground = img.Image(width: tamanho, height: tamanho, numChannels: 4);
  img.fill(foreground, color: img.ColorRgba8(0, 0, 0, 0));
  compor(foreground, logoAjustado(0.44));
  File('assets/icone_app_foreground.png')
      .writeAsBytesSync(img.encodePng(foreground));

  stdout.writeln('OK: assets/icone_app.png e assets/icone_app_foreground.png');
}
