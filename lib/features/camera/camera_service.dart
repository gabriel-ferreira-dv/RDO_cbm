import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;

import '../../core/localizacao_service.dart';

// ── Localização ──────────────────────────────────────────────────────────────

// Posição do carimbo: a mesma filtrada do mapa (ver LocalizacaoService).
Future<PosicaoGps> pegarLocalizacao() async {
  bool ativo = await Geolocator.isLocationServiceEnabled();
  if (!ativo) throw Exception('Serviço de localização desativado');

  LocationPermission permissao = await Geolocator.checkPermission();
  if (permissao == LocationPermission.denied) {
    permissao = await Geolocator.requestPermission();
    if (permissao == LocationPermission.denied) throw Exception('Permissão negada');
  }

  final posicao = await LocalizacaoService.instancia.posicaoConfiavel();
  if (posicao == null) throw Exception('Não foi possível obter a localização');
  return posicao;
}



// Textos do carimbo em ordem de leitura. Campo vazio não vira linha: a foto
// de paralisação pode não ter KM, e a descrição é opcional.
List<String> blocosDoCarimbo({
  required String trecho,
  required String kmtrecho,
  required String via,
  required String estacaInicial,
  required String estacaFinal,
  required String servNotavel,
  required String servNotavelDetalhe,
  required String descricao,
  required String dataHora,
  required double lat,
  required double lon,
}) {
  final km = kmtrecho.trim();
  final sentido = via.trim();
  return [
    trecho,
    // Sem via, sem o traço.
    if (km.isNotEmpty) sentido.isEmpty ? 'KM $km' : 'KM $km - $sentido'
    else if (sentido.isNotEmpty) sentido,
    // Área de apoio não tem estaca.
    if (estacaInicial.isNotEmpty) 'Est. $estacaInicial - $estacaFinal',
    servNotavel,
    servNotavelDetalhe,
    if (descricao.trim().isNotEmpty) 'Descrição: ${descricao.trim()}',
    dataHora,
    'Lat: ${lat.toStringAsFixed(4)} Lon: ${lon.toStringAsFixed(4)}',
  ].where((b) => b.trim().isNotEmpty).toList();
}

class EditarParams {
  final String imagePath;
  final Uint8List logoBytes;
  final Uint8List fontBytes;
  final double lat;
  final double lon;
  final String trecho;
  final String kmtrecho;
  final String estacaInicial;
  final String estacaFinal;
  final String via;
  final String descricao;
  final String servNotavel;
  final String servNotavelDetalhe;
  final String dataHora;
  final int fontSize;
  final Uint8List? minimapBytes;

  final TransferableTypedData? fotoRaw;
  final int? fotoW;
  final int? fotoH;

  EditarParams(this.imagePath, this.logoBytes, this.fontBytes, this.lat, this.lon,
      this.trecho, this.kmtrecho, this.estacaInicial, this.estacaFinal, this.via,
      this.descricao, this.servNotavel, this.servNotavelDetalhe, this.dataHora, this.fontSize,
      {this.minimapBytes, this.fotoRaw, this.fotoW, this.fotoH});
}


img.Image? _logoCache;
final Map<int, img.BitmapFont> _fontCache = {};

final Map<int, img.Image> _logoResizedCache = {};


void _desenharTextoComContorno(img.Image dst, String texto, {
  required img.BitmapFont font,
  required int x,
  required int y,
  bool rightJustify = false,
  bool wrap = false,
}) {
  final preto = img.ColorRgb8(0, 0, 0);
  final branco = img.ColorRgb8(255, 255, 255);

  // Contorno preto, mais largo que o preenchimento branco.
  const contornoOffsetsX = [-1, 1, 0, 0];
  const contornoOffsetsY = [0, 0, -1, 1];
  for (var i = 0; i < contornoOffsetsX.length; i++) {
    img.drawString(dst, texto, font: font, x: x + contornoOffsetsX[i], y: y + contornoOffsetsY[i],
        color: preto, rightJustify: rightJustify, wrap: wrap);
  }

  // Negrito falso: a fonte bitmap não tem bold, então desenha deslocado 1px.
  const negritoOffsetsX = [0, 0, 1];
  const negritoOffsetsY = [0, 0, 0];
  for (var i = 0; i < negritoOffsetsX.length; i++) {
    img.drawString(dst, texto, font: font, x: x + negritoOffsetsX[i], y: y + negritoOffsetsY[i],
        color: branco, rightJustify: rightJustify, wrap: wrap);
  }
}


int _larguraTexto(img.BitmapFont font, String texto) {
  var largura = 0;
  for (final ch in texto.split('')) {
    largura += font.characterXAdvance(ch);
  }
  return largura;
}

// Quebra [texto] em linhas de até [larguraMax] pixels (o wrap do drawString
// só respeita a borda da imagem). Palavra longa demais é cortada.
List<String> _quebrarEmLinhas(img.BitmapFont font, String texto, int larguraMax) {
  final linhas = <String>[];
  var atual = '';

  void fechar() {
    if (atual.isNotEmpty) {
      linhas.add(atual);
      atual = '';
    }
  }

  for (final palavra in texto.split(RegExp(r'\s+')).where((p) => p.isNotEmpty)) {
    final candidata = atual.isEmpty ? palavra : '$atual $palavra';
    if (_larguraTexto(font, candidata) <= larguraMax) {
      atual = candidata;
      continue;
    }
    fechar();

    if (_larguraTexto(font, palavra) <= larguraMax) {
      atual = palavra;
      continue;
    }
    // Palavra sozinha não cabe: quebra caractere a caractere.
    for (final ch in palavra.split('')) {
      if (atual.isNotEmpty && _larguraTexto(font, atual + ch) > larguraMax) {
        fechar();
      }
      atual += ch;
    }
  }
  fechar();
  return linhas;
}

// Expostos só para os testes de quebra de linha do carimbo.
@visibleForTesting
int larguraTextoParaTeste(img.BitmapFont font, String texto) =>
    _larguraTexto(font, texto);

// Carimbo completo fora do isolate, para teste.
@visibleForTesting
void editarImagemParaTeste(EditarParams params) => _editarImagem(params);

@visibleForTesting
List<String> quebrarEmLinhasParaTeste(
        img.BitmapFont font, String texto, int larguraMax) =>
    _quebrarEmLinhas(font, texto, larguraMax);

class _Bbox {
  final int left, top, right, bottom;
  _Bbox(this.left, this.top, this.right, this.bottom);
}

_Bbox? _bboxAlfaTocado(img.Image image) {
  var left = image.width, top = image.height, right = -1, bottom = -1;
  for (final px in image) {
    if (px.a != 0) {
      if (px.x < left) left = px.x;
      if (px.x > right) right = px.x;
      if (px.y < top) top = px.y;
      if (px.y > bottom) bottom = px.y;
    }
  }
  return right < 0 ? null : _Bbox(left, top, right, bottom);
}

void _editarImagem(EditarParams p) {
  final sw = Stopwatch()..start();
  img.Image foto;
  if (p.fotoRaw != null) {

    final bytes = p.fotoRaw!.materialize().asUint8List();
    foto = img.Image.fromBytes(
      width: p.fotoW!,
      height: p.fotoH!,
      bytes: bytes.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    debugPrint('[timing] isolate: foto de raw nativo (${foto.width}x${foto.height}) = ${sw.elapsedMilliseconds}ms');
  } else {
    foto = img.decodeImage(File(p.imagePath).readAsBytesSync())!;
    debugPrint('[timing] isolate: decode foto (${foto.width}x${foto.height}) = ${sw.elapsedMilliseconds}ms');
    sw.reset();

    foto = img.bakeOrientation(foto);
    debugPrint('[timing] isolate: bakeOrientation = ${sw.elapsedMilliseconds}ms');
  }
  sw.reset();

  final W = foto.width;
  final H = foto.height;
  final menor = min(W, H);
  final margemFull = (menor * 0.015).round();
  final branco = img.ColorRgb8(255, 255, 255);


  final logoLargFull = (W * 0.20).round();
  final logoOrig = _logoCache ??= img.decodeImage(p.logoBytes)!;
  final logoFull = _logoResizedCache[logoLargFull] ??= img.copyResize(logoOrig,
      width: logoLargFull, interpolation: img.Interpolation.average);
  img.compositeImage(foto, logoFull, dstX: margemFull, dstY: margemFull);
  debugPrint('[timing] isolate: logo = ${sw.elapsedMilliseconds}ms');
  sw.reset();

  const targetFrac = 0.040;
  final workScale  = (p.fontSize / (menor * targetFrac)).clamp(0.01, 1.0);
  final workW      = (W * workScale).round().clamp(1, W);
  final workH      = (H * workScale).round().clamp(1, H);
  final workMenor  = min(workW, workH);

  final overlay = img.Image(width: workW, height: workH, numChannels: 4);
  img.fill(overlay, color: img.ColorRgba8(255, 255, 255, 0));

  final margem  = (workMenor * 0.015).round();
  final lineH   = (p.fontSize * 1.3).round();

  // Calculado aqui porque o texto precisa saber onde o minimapa termina.
  final mapaSize     = (menor * 0.36).round();
  final bordaPreta   = (mapaSize * 0.01).round().clamp(1, 6);
  final bordaBranca  = (mapaSize * 0.015).round().clamp(2, 10);
  final frameSizeFull = mapaSize + (bordaPreta + bordaBranca) * 2;

  final font = _fontCache[p.fontSize] ??= img.readFontZip(p.fontBytes);
  debugPrint('[timing] isolate: readFontZip = ${sw.elapsedMilliseconds}ms');
  sw.reset();

  // Textos no canto inferior direito, de baixo para cima.
  final xDir = workW - margem;

  // Largura do texto: a menor entre a distância de xDir até o meio da foto e
  // até a borda do minimapa.
  final minimapaDireitaWork = p.minimapBytes == null
      ? 0
      : ((margemFull + frameSizeFull) * workScale).round();
  final larguraMax = min(
    xDir - (workW / 2).round(),
    xDir - minimapaDireitaWork - margem,
  ).clamp(font.size * 4, workW);

  // Item longo quebra em várias linhas.
  final blocos = blocosDoCarimbo(
    trecho: p.trecho,
    kmtrecho: p.kmtrecho,
    via: p.via,
    estacaInicial: p.estacaInicial,
    estacaFinal: p.estacaFinal,
    servNotavel: p.servNotavel,
    servNotavelDetalhe: p.servNotavelDetalhe,
    descricao: p.descricao,
    dataHora: p.dataHora,
    lat: p.lat,
    lon: p.lon,
  );
  final linhas = [
    for (final bloco in blocos) ..._quebrarEmLinhas(font, bloco, larguraMax),
  ];

  var y = workH - margem - lineH;
  for (final linha in linhas.reversed) {
    _desenharTextoComContorno(overlay, linha,
        font: font, x: xDir, y: y, rightJustify: true);
    y -= lineH;
  }

  debugPrint('[timing] isolate: drawString (${linhas.length}x) = ${sw.elapsedMilliseconds}ms');
  sw.reset();

  final bbox = _bboxAlfaTocado(overlay);
  if (bbox != null) {
    const pad = 2; // folga contra antialiasing na borda do bbox
    final left   = (bbox.left   - pad).clamp(0, workW - 1);
    final top    = (bbox.top    - pad).clamp(0, workH - 1);
    final right  = (bbox.right  + pad).clamp(0, workW - 1);
    final bottom = (bbox.bottom + pad).clamp(0, workH - 1);
    final cropW  = right - left + 1;
    final cropH  = bottom - top + 1;
    final overlayCrop = img.copyCrop(overlay, x: left, y: top, width: cropW, height: cropH);

    if (workScale < 0.99) {
      final scaleX = W / workW;
      final scaleY = H / workH;
      final dstX = (left * scaleX).floor().clamp(0, W - 1);
      final dstY = (top * scaleY).floor().clamp(0, H - 1);
      final destW = (cropW * scaleX).ceil().clamp(1, W - dstX);
      final destH = (cropH * scaleY).ceil().clamp(1, H - dstY);
      final overlayFull = img.copyResize(overlayCrop, width: destW, height: destH,
          interpolation: img.Interpolation.linear);
      img.compositeImage(foto, overlayFull, dstX: dstX, dstY: dstY);
    } else {
      img.compositeImage(foto, overlayCrop, dstX: left, dstY: top);
    }
  }
  debugPrint('[timing] isolate: resize+composite overlay texto = ${sw.elapsedMilliseconds}ms');
  sw.reset();

  // Minimapa no canto inferior esquerdo.
  if (p.minimapBytes != null) {                                                        
    final miniImg = img.decodePng(p.minimapBytes!);
    if (miniImg != null) {
      final mapa = img.copyResize(miniImg, width: mapaSize, height: mapaSize,
          interpolation: img.Interpolation.average);
      // Borda preta e branca: visível em fundo claro ou escuro.
      final frameSize = frameSizeFull;
      final frame     = img.Image(width: frameSize, height: frameSize);
      img.fill(frame, color: img.ColorRgb8(0, 0, 0));
      img.fillRect(frame,
          x1: bordaPreta, y1: bordaPreta,
          x2: frameSize - bordaPreta, y2: frameSize - bordaPreta,
          color: branco);
      img.compositeImage(frame, mapa, dstX: bordaPreta + bordaBranca, dstY: bordaPreta + bordaBranca);
      img.compositeImage(foto, frame,
          dstX: margemFull, dstY: H - margemFull - frameSize);
    }
  }
  debugPrint('[timing] isolate: minimap composite = ${sw.elapsedMilliseconds}ms');
  sw.reset();


  File(p.imagePath).writeAsBytesSync(
      img.encodeJpg(foto, quality: 75, chroma: img.JpegChroma.yuv420));
  debugPrint('[timing] isolate: encodeJpg+write = ${sw.elapsedMilliseconds}ms');
}

class _AquecerParams {
  final int fotoWidth;
  final Uint8List logoBytes;
  final Uint8List fontBytes;
  final int fontSize;

  _AquecerParams(this.fotoWidth, this.logoBytes, this.fontBytes, this.fontSize);
}

void _aquecerCaches(_AquecerParams p) {
  final logoOrig = _logoCache ??= img.decodeImage(p.logoBytes)!;
  final logoLarg = (p.fotoWidth * 0.20).round();
  _logoResizedCache[logoLarg] ??= img.copyResize(logoOrig,
      width: logoLarg, interpolation: img.Interpolation.average);
  _fontCache[p.fontSize] ??= img.readFontZip(p.fontBytes);
}


class _FotoWorker {
  static Future<_FotoWorker>? _instanciaFutura;

  final SendPort _commandPort;

  _FotoWorker._(this._commandPort);

  static Future<_FotoWorker> instancia() {
    return _instanciaFutura ??= _criar();
  }

  static Future<_FotoWorker> _criar() async {
    final readyPort = ReceivePort();
    await Isolate.spawn(_workerMain, readyPort.sendPort);
    final commandPort = await readyPort.first as SendPort;
    return _FotoWorker._(commandPort);
  }

  Future<void> processar(EditarParams params) => _enviar(params);

  Future<void> aquecer(_AquecerParams params) => _enviar(params);

  Future<void> _enviar(Object params) async {
    final replyPort = ReceivePort();
    _commandPort.send([params, replyPort.sendPort]);
    final resultado = await replyPort.first;
    replyPort.close();
    if (resultado is String) {
      throw Exception(resultado);
    }
  }
}

void _workerMain(SendPort mainPort) {
  final commandPort = ReceivePort();
  mainPort.send(commandPort.sendPort);
  commandPort.listen((message) {
    final params = message[0];
    final replyPort = message[1] as SendPort;
    try {
      if (params is _AquecerParams) {
        _aquecerCaches(params);
      } else {
        _editarImagem(params as EditarParams);
      }
      replyPort.send(true);
    } catch (e) {
      replyPort.send(e.toString());
    }
  });
}


Future<void> aquecerProcessadorFoto() async {
  await Future.wait([
    _FotoWorker.instancia(),
    _carregarLogo(),
  ]);
}

const int fontSizeMin = 10;
const int fontSizeMax = 24;

Future<List<int>> dimensoesImagem(String path) async {
  try {
    final raf = await File(path).open();
    final buffer = Uint8List(65536);
    final lido = await raf.readInto(buffer);
    await raf.close();
    final dados = buffer.sublist(0, lido);
    final info = img.findDecoderForData(dados)?.startDecode(dados);
    if (info != null && info.width > 0) return [info.width, info.height];
  } catch (_) {}
  return [4000, 3000]; // Padrão seguro para fotos de alta resolução.
}

Uint8List? _logoBytesCache;
final Map<int, Uint8List> _fontBytesCache = {};

Future<Uint8List> _carregarLogo() async {
  if (_logoBytesCache != null) return _logoBytesCache!;
  final data = await rootBundle.load('assets/logo.png');
  return _logoBytesCache = data.buffer.asUint8List();
}

Future<Uint8List> _carregarFonte(int fontSize) async {
  final cacheado = _fontBytesCache[fontSize];
  if (cacheado != null) return cacheado;
  final data = await rootBundle.load('assets/fonts/custom_pt_$fontSize.zip');
  final bytes = data.buffer.asUint8List();
  _fontBytesCache[fontSize] = bytes;
  return bytes;
}

Future<void> processarFoto(String imagePath, double lat, double lon,
    String trecho, String kmtrecho, String estacaInicial, String estacaFinal,
    String via, String descricao, String servNotavel, String servNotavelDetalhes,
    {Uint8List? minimapBytes, List<int>? dimsConhecidas}) async {
  final sw = Stopwatch()..start();
  final dims = dimsConhecidas ?? await dimensoesImagem(imagePath);
  final fontSize = (min(dims[0], dims[1]) * 0.50).round().clamp(fontSizeMin, fontSizeMax);
  debugPrint('[timing] dimensoesImagem = ${sw.elapsedMilliseconds}ms');
  sw.reset();

  final logoBytes = await _carregarLogo();
  final fontBytes = await _carregarFonte(fontSize);
  debugPrint('[timing] carregar assets (logo+fonte) = ${sw.elapsedMilliseconds}ms');
  sw.reset();

  final worker = await _FotoWorker.instancia();
  debugPrint('[timing] worker pronto (spawn só na 1ª foto) = ${sw.elapsedMilliseconds}ms');
  sw.reset();

  TransferableTypedData? fotoRaw;
  int? fotoW;
  int? fotoH;
  try {
    final bytesJpg = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytesJpg);
    final frame = await codec.getNextFrame();
    final dados = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (dados != null) {
      fotoW = frame.image.width;
      fotoH = frame.image.height;
      fotoRaw = TransferableTypedData.fromList([dados.buffer.asUint8List()]);
    }
    frame.image.dispose();
    codec.dispose();
  } catch (e) {
    debugPrint('Decode nativo falhou (usando fallback em Dart puro): $e');
  }
  debugPrint('[timing] decode nativo (Skia) = ${sw.elapsedMilliseconds}ms');
  sw.reset();

  // Data e hora da captura, para o carimbo.
  String dois(int n) => n.toString().padLeft(2, '0');
  final agora = DateTime.now();
  final dataHora = '${dois(agora.day)}/${dois(agora.month)}/${agora.year} '
      '${dois(agora.hour)}:${dois(agora.minute)}';

  await worker.processar(EditarParams(
    imagePath, logoBytes, fontBytes, lat, lon,
    trecho, kmtrecho, estacaInicial, estacaFinal, via, descricao, servNotavel, servNotavelDetalhes, dataHora, fontSize,
    minimapBytes: minimapBytes,
    fotoRaw: fotoRaw,
    fotoW: fotoW,
    fotoH: fotoH,
  ));
  debugPrint('[timing] processar (isolate persistente) = ${sw.elapsedMilliseconds}ms');
}


Future<void> aquecerCachesParaFoto(List<int> dims) async {
  final fontSize = (min(dims[0], dims[1]) * 0.60).round().clamp(fontSizeMin, fontSizeMax);
  final logoBytes = await _carregarLogo();
  final fontBytes = await _carregarFonte(fontSize);
  final worker = await _FotoWorker.instancia();
  await worker.aquecer(_AquecerParams(dims[0], logoBytes, fontBytes, fontSize));
}
