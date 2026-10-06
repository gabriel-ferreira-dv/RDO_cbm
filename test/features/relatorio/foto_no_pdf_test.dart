import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:namer_app/features/relatorio/foto_no_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// JPEG de verdade nas dimensões pedidas — o MemoryImage lê o cabeçalho para
// descobrir a proporção, então não dá para simular com bytes quaisquer.
pw.MemoryImage foto(int largura, int altura) {
  final imagem = img.Image(width: largura, height: altura);
  img.fill(imagem, color: img.ColorRgb8(120, 120, 120));
  return pw.MemoryImage(Uint8List.fromList(img.encodeJpg(imagem, quality: 70)));
}

void main() {
  const larguraNoPdf = 200.0;

  // O carimbo (logo, trecho, KM, estaca, data, minimapa) fica nas bordas da
  // foto. Se a caixa não acompanhar a proporção, é exatamente ele que some.
  test('a caixa acompanha a proporção da foto, seja qual for a câmera', () {
    // 4:3 — o que a caixa fixa já assumia.
    expect(alturaDaFotoNoPdf(foto(1600, 1200), larguraNoPdf),
        closeTo(larguraNoPdf * 0.75, 0.01));
    // 16:9 — aqui a caixa fixa cortava as laterais.
    expect(alturaDaFotoNoPdf(foto(1920, 1080), larguraNoPdf),
        closeTo(larguraNoPdf * 0.5625, 0.01));
    // 1:1 — cortava em cima e embaixo.
    expect(alturaDaFotoNoPdf(foto(1000, 1000), larguraNoPdf),
        closeTo(larguraNoPdf, 0.01));
    // 3:4 em retrato.
    expect(alturaDaFotoNoPdf(foto(1200, 1600), larguraNoPdf),
        closeTo(larguraNoPdf * 4 / 3, 0.01));
  });

  test('foto muito alongada para de crescer, para não tomar a página', () {
    // 9:16 daria 1.78x a largura; o teto segura em 1.35 e o resto vira faixa
    // branca — nada da foto se perde, porque o desenho usa BoxFit.contain.
    expect(alturaDaFotoNoPdf(foto(1080, 1920), larguraNoPdf),
        closeTo(larguraNoPdf * 1.35, 0.01));
    // Panorâmica extrema, no outro extremo.
    expect(alturaDaFotoNoPdf(foto(3000, 800), larguraNoPdf),
        closeTo(larguraNoPdf * 0.5, 0.01));
  });

  test('a altura nunca é zero nem negativa', () {
    for (final imagem in [foto(4, 3), foto(1, 1), foto(3, 4)]) {
      expect(alturaDaFotoNoPdf(imagem, larguraNoPdf), greaterThan(0));
    }
  });
}
