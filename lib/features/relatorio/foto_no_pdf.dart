import 'package:pdf/widgets.dart' as pw;

// Proporção padrão (4:3) quando não dá para ler a da foto.
const double proporcaoPadraoDaFoto = 0.75;

// Limites da altura em relação à largura (foto em retrato não toma a página).
const double _alturaMinima = 0.5;
const double _alturaMaxima = 1.35;

// Altura da caixa da foto no PDF, na proporção real da imagem, para não
// cortar o carimbo das bordas. Use com `BoxFit.contain`.
double alturaDaFotoNoPdf(pw.MemoryImage imagem, double largura) {
  final larguraOriginal = imagem.width;
  final alturaOriginal = imagem.height;
  if (larguraOriginal == null ||
      alturaOriginal == null ||
      larguraOriginal <= 0 ||
      alturaOriginal <= 0) {
    return largura * proporcaoPadraoDaFoto;
  }
  final proporcao =
      (alturaOriginal / larguraOriginal).clamp(_alturaMinima, _alturaMaxima);
  return largura * proporcao;
}
