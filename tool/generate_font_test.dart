// Script de geração de fontes: cria assets/fonts/custom_pt_<tamanho>.zip a
// partir da fonte Arial do sistema, incluindo caracteres acentuados (pt-BR),
// para cada tamanho de 10 a 24.
// Fica em tool/ (não em test/) para não ser executado pelo `flutter test`
// padrão. Roda como teste porque dart:ui (Canvas/PictureRecorder) só
// funciona dentro do binding de testes do Flutter. Execute manualmente
// sempre que precisar trocar a fonte/charset com:
//   flutter test tool/generate_font_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const String fontFamily = 'GeneratedFont';
const int minFontSize = 10;
const int maxFontSize = 24;

String _buildCharset() {
  final buffer = StringBuffer();
  for (var c = 33; c <= 126; c++) {
    buffer.writeCharCode(c);
  }
  buffer.write(' ');
  buffer.write('áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÜÇñÑ');
  return buffer.toString();
}

class _Glyph {
  final int code;
  final int width;
  final Uint8List pixels;
  _Glyph(this.code, this.width, this.pixels);
}

Future<void> _gerarFonte(int fontSize, List<int> chars) async {
  // Passo 1: mede a largura de cada caractere e a altura de linha comum.
  final widths = <int, double>{};
  var lineHeight = 0.0;
  for (final code in chars) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(code),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize.toDouble(),
          color: const Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    widths[code] = tp.width;
    if (tp.height > lineHeight) lineHeight = tp.height;
  }
  final rowHeight = lineHeight.ceil();

  // Passo 2: renderiza cada caractere num canvas com a altura de linha fixa.
  final glyphs = <_Glyph>[];
  for (final code in chars) {
    final w = widths[code]!.ceil().clamp(1, 999);
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(code),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize.toDouble(),
          color: const Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    tp.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(w, rowHeight);
    final byteData =
        await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    glyphs.add(_Glyph(code, w, byteData!.buffer.asUint8List()));
  }

  // Monta o atlas (uma única linha) e o atlas .fnt (formato AngelCode).
  const gap = 1;
  final atlasWidth =
      glyphs.fold<int>(0, (sum, g) => sum + g.width + gap) - gap;
  final atlas = img.Image(
    width: atlasWidth,
    height: rowHeight,
    numChannels: 4,
  );

  final fnt = StringBuffer()
    ..writeln(
        'info face="$fontFamily" size=$fontSize bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 antialias=1 padding=0,0,0,0 spacing=0,0 outline=0')
    ..writeln(
        'common lineHeight=$rowHeight base=$rowHeight scaleW=$atlasWidth scaleH=$rowHeight pages=1 packed=0')
    ..writeln('page id=0 file="custom_pt_$fontSize.png"')
    ..writeln('chars count=${glyphs.length}');

  var cursorX = 0;
  for (final g in glyphs) {
    for (var y = 0; y < rowHeight; y++) {
      for (var x = 0; x < g.width; x++) {
        final i = (y * g.width + x) * 4;
        atlas.setPixelRgba(
          cursorX + x,
          y,
          g.pixels[i],
          g.pixels[i + 1],
          g.pixels[i + 2],
          g.pixels[i + 3],
        );
      }
    }
    fnt.writeln(
        'char id=${g.code} x=$cursorX y=0 width=${g.width} height=$rowHeight xoffset=0 yoffset=0 xadvance=${g.width} page=0 chnl=15');
    cursorX += g.width + gap;
  }

  final pngBytes = img.encodePng(atlas);

  final archive = Archive()
    ..addFile(
        ArchiveFile('custom_pt_$fontSize.png', pngBytes.length, pngBytes))
    ..addFile(ArchiveFile(
        'custom_pt_$fontSize.fnt', fnt.length, fnt.toString().codeUnits));

  final zipBytes = ZipEncoder().encode(archive);

  final outFile = File('assets/fonts/custom_pt_$fontSize.zip');
  outFile.writeAsBytesSync(zipBytes);

  // Sanidade: a fonte gerada deve conter os caracteres acentuados.
  final reloaded = img.readFontZip(outFile.readAsBytesSync());
  expect(reloaded.characters.containsKey('ç'.codeUnitAt(0)), isTrue);
  expect(reloaded.characters.containsKey('ã'.codeUnitAt(0)), isTrue);

  // ignore: avoid_print
  print('Fonte gerada em ${outFile.absolute.path} (${glyphs.length} chars, ${zipBytes.length} bytes)');
}

void main() {
  test('gera fontes bitmap com acentos para tamanhos 10 a 24', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final fontBytes = File(r'C:\Windows\Fonts\arial.ttf').readAsBytesSync();
    final loader = FontLoader(fontFamily)
      ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
    await loader.load();

    final chars = _buildCharset().runes.toSet().toList()..sort();

    for (var fontSize = minFontSize; fontSize <= maxFontSize; fontSize++) {
      await _gerarFonte(fontSize, chars);
    }
  });
}
