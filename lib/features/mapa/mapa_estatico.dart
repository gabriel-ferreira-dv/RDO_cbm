import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

// Mapa em imagem para o PDF: satélite (se houver internet), o mapa do projeto
// (ortofoto e desenho, dos tiles .webp baixados) e as linhas por cima. Não
// usa widget: o desenho roda no isolate.

// Um tile do mapa do projeto e onde ele fica: os mesmos três cantos que o
// mapa do app usa para encaixar a imagem.
class PecaDoProjeto {
  final String arquivo;
  final LatLng topoEsquerda;
  final LatLng baseEsquerda;
  final LatLng baseDireita;

  const PecaDoProjeto({
    required this.arquivo,
    required this.topoEsquerda,
    required this.baseEsquerda,
    required this.baseDireita,
  });
}

// Zoom a partir do qual o mapa do projeto entra na imagem. De longe seriam
// centenas de tiles para quase nada de detalhe.
const int zoomMinimoDoProjeto = 16;

// Teto de tiles do projeto por imagem, pelo mesmo motivo.
const int maximoDePecas = 200;

// Opacidade do mapa do projeto sobre o satélite, a mesma da aba Mapa.
const double opacidadeDoProjeto = 0.8;

// Linha no mapa (ou ponto, com um vértice só). Cor ARGB.
class TracoNoMapa {
  final List<LatLng> pontos;
  final int cor;

  const TracoNoMapa(this.pontos, this.cor);
}

// Etiqueta no mapa. Só ASCII: a fonte do desenho não tem acento.
class RotuloNoMapa {
  final LatLng ponto;
  final String texto;

  const RotuloNoMapa(this.ponto, this.texto);
}

const int tamanhoDoTile = 256;

const String _urlDosTiles =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile';

// Posição em pixels no mundo inteiro (Web Mercator) no [zoom].
({double x, double y}) pixelNoMundo(LatLng p, int zoom) {
  final escala = tamanhoDoTile * pow(2, zoom).toDouble();
  final lat = p.latitude.clamp(-85.05112878, 85.05112878) * pi / 180;
  return (
    x: (p.longitude + 180) / 360 * escala,
    y: (1 - log(tan(lat) + 1 / cos(lat)) / pi) / 2 * escala,
  );
}

// Inverso de [pixelNoMundo].
LatLng latLngDoPixel(double x, double y, int zoom) {
  final escala = tamanhoDoTile * pow(2, zoom).toDouble();
  final n = pi * (1 - 2 * y / escala);
  return LatLng(
    atan((exp(n) - exp(-n)) / 2) * 180 / pi,
    x / escala * 360 - 180,
  );
}

// Maior zoom em que [pontos] cabem em [largura]×[altura] com [margem] de
// cada lado, e o canto superior esquerdo da imagem (pixels no mundo).
({int zoom, double x, double y}) enquadrarMapa(
  List<LatLng> pontos, {
  required int largura,
  required int altura,
  int margem = 60,
  int zoomMinimo = 10,
  int zoomMaximo = 18,
}) {
  for (var z = zoomMaximo;; z--) {
    final px = [for (final p in pontos) pixelNoMundo(p, z)];
    final minX = px.map((p) => p.x).reduce(min);
    final maxX = px.map((p) => p.x).reduce(max);
    final minY = px.map((p) => p.y).reduce(min);
    final maxY = px.map((p) => p.y).reduce(max);
    final cabe = maxX - minX <= largura - 2 * margem &&
        maxY - minY <= altura - 2 * margem;
    if (cabe || z <= zoomMinimo) {
      return (
        zoom: z,
        x: (minX + maxX) / 2 - largura / 2,
        y: (minY + maxY) / 2 - altura / 2,
      );
    }
  }
}

// Tudo o que o desenho precisa, já em pixels da imagem. Linhas são listas
// planas [x0, y0, x1, y1, ...]: atravessam o isolate sem conversão.
class DesenhoDoMapa {
  final int largura;
  final int altura;
  final List<({Uint8List bytes, int x, int y})> tiles;

  // Tiles do projeto já decodificados (RGBA sem pré-multiplicar), no tamanho
  // em que aparecem, e os cantos na imagem: topo-esquerda, base-esquerda e
  // base-direita.
  final List<PecaDecodificada> pecas;
  final List<List<int>> eixos;
  final List<({List<int> xy, int cor})> tracos;
  final List<({int x, int y, String texto})> rotulos;

  const DesenhoDoMapa({
    required this.largura,
    required this.altura,
    this.tiles = const [],
    this.pecas = const [],
    this.eixos = const [],
    this.tracos = const [],
    this.rotulos = const [],
  });
}

typedef PecaDecodificada = ({
  Uint8List rgba,
  int largura,
  int altura,
  double topoX,
  double topoY,
  double baseEsqX,
  double baseEsqY,
  double baseDirX,
  double baseDirY,
});

// Monta a imagem (JPEG). Síncrono: roda no isolate.
Uint8List desenharMapaEstatico(DesenhoDoMapa d) {
  final imagem = img.Image(width: d.largura, height: d.altura);
  img.fill(imagem, color: img.ColorRgb8(236, 236, 236));
  for (final t in d.tiles) {
    final tile = img.decodeImage(t.bytes);
    if (tile != null) _colar(imagem, tile, t.x, t.y);
  }
  for (final p in d.pecas) {
    _encaixar(imagem, p);
  }

  // O desenho do projeto já traz o eixo: o nosso só entra sem ele. Sem
  // satélite, o fundo é claro e o eixo vira cinza.
  if (d.pecas.isEmpty) {
    final corEixo = d.tiles.isEmpty
        ? img.ColorRgb8(150, 150, 150)
        : img.ColorRgba8(255, 255, 255, 140);
    for (final eixo in d.eixos) {
      _linha(imagem, eixo, corEixo, 2);
    }
  }

  final branco = img.ColorRgb8(255, 255, 255);
  for (final t in d.tracos) {
    final cor = _cor(t.cor);
    if (t.xy.length == 2) {
      img.fillCircle(imagem, x: t.xy[0], y: t.xy[1], radius: 10, color: branco, antialias: true);
      img.fillCircle(imagem, x: t.xy[0], y: t.xy[1], radius: 7, color: cor, antialias: true);
    } else {
      _linha(imagem, t.xy, branco, 11);
      _linha(imagem, t.xy, cor, 7);
    }
  }

  final fonte = img.arial24;
  for (final r in d.rotulos) {
    final largura = r.texto.split('').fold(0, (s, c) => s + fonte.characterXAdvance(c));
    final x = r.x + 12;
    final y = r.y - fonte.lineHeight ~/ 2;
    img.fillRect(imagem,
        x1: x - 6,
        y1: y - 3,
        x2: x + largura + 6,
        y2: y + fonte.lineHeight + 3,
        color: img.ColorRgba8(0, 0, 0, 170),
        radius: 4);
    img.drawString(imagem, r.texto, font: fonte, x: x, y: y, color: branco);
  }

  return Uint8List.fromList(img.encodeJpg(imagem, quality: 85));
}

img.Color _cor(int argb) => img.ColorRgba8(
    (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, (argb >> 24) & 0xFF);

// Linha fina pelo drawLine; grossa, com um círculo a cada pixel do caminho.
// O drawLine grosso sai mais fino que a junta e a linha ficava "em contas".
void _linha(img.Image imagem, List<int> xy, img.Color cor, int espessura) {
  if (espessura < 4) {
    for (var i = 0; i + 3 < xy.length; i += 2) {
      img.drawLine(imagem,
          x1: xy[i],
          y1: xy[i + 1],
          x2: xy[i + 2],
          y2: xy[i + 3],
          color: cor,
          thickness: espessura,
          antialias: true);
    }
    return;
  }
  final raio = espessura ~/ 2;
  void carimbar(int x, int y) {
    // Fora da imagem não tem o que pintar.
    if (x < -raio || y < -raio || x > imagem.width + raio || y > imagem.height + raio) {
      return;
    }
    img.fillCircle(imagem, x: x, y: y, radius: raio, color: cor, antialias: true);
  }

  for (var i = 0; i + 3 < xy.length; i += 2) {
    final x0 = xy[i], y0 = xy[i + 1], x1 = xy[i + 2], y1 = xy[i + 3];
    final passos = max((x1 - x0).abs(), (y1 - y0).abs());
    for (var s = 0; s < passos; s++) {
      carimbar(x0 + ((x1 - x0) * s / passos).round(),
          y0 + ((y1 - y0) * s / passos).round());
    }
  }
  if (xy.length >= 2) carimbar(xy[xy.length - 2], xy[xy.length - 1]);
}

// Pinta o tile do projeto no paralelogramo dos três cantos (o tile tem uma
// leve rotação: a grade é UTM). Para cada pixel da imagem, acha o ponto
// correspondente do tile e mistura com [opacidadeDoProjeto] e o alfa dele.
void _encaixar(img.Image imagem, PecaDecodificada p) {
  final ax = p.baseDirX - p.baseEsqX; // topo → topo-direita
  final ay = p.baseDirY - p.baseEsqY;
  final bx = p.baseEsqX - p.topoX; // topo → base
  final by = p.baseEsqY - p.topoY;
  final det = ax * by - ay * bx;
  if (det.abs() < 1e-9) return;

  final xs = [p.topoX, p.topoX + ax, p.baseEsqX, p.baseDirX];
  final ys = [p.topoY, p.topoY + ay, p.baseEsqY, p.baseDirY];
  final x0 = max(0, xs.reduce(min).floor());
  final x1 = min(imagem.width - 1, xs.reduce(max).ceil());
  final y0 = max(0, ys.reduce(min).floor());
  final y1 = min(imagem.height - 1, ys.reduce(max).ceil());

  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final dx = x + 0.5 - p.topoX;
      final dy = y + 0.5 - p.topoY;
      final u = (dx * by - dy * bx) / det;
      final v = (ax * dy - ay * dx) / det;
      if (u < 0 || u >= 1 || v < 0 || v >= 1) continue;
      final i = ((v * p.altura).floor() * p.largura + (u * p.largura).floor()) * 4;
      final alfa = p.rgba[i + 3] / 255 * opacidadeDoProjeto;
      if (alfa <= 0) continue;
      final pixel = imagem.getPixel(x, y);
      pixel
        ..r = pixel.r + (p.rgba[i] - pixel.r) * alfa
        ..g = pixel.g + (p.rgba[i + 1] - pixel.g) * alfa
        ..b = pixel.b + (p.rgba[i + 2] - pixel.b) * alfa;
    }
  }
}

// Cola o tile na posição (x, y), cortando o que sai da imagem.
void _colar(img.Image destino, img.Image tile, int x, int y) {
  final x0 = max(0, x);
  final y0 = max(0, y);
  final x1 = min(destino.width, x + tile.width);
  final y1 = min(destino.height, y + tile.height);
  if (x1 <= x0 || y1 <= y0) return;
  img.compositeImage(destino, tile,
      dstX: x0,
      dstY: y0,
      dstW: x1 - x0,
      dstH: y1 - y0,
      srcX: x0 - x,
      srcY: y0 - y,
      srcW: x1 - x0,
      srcH: y1 - y0,
      blend: img.BlendMode.direct);
}

// Imagem do mapa com [tracos] enquadrados, ou null sem nada para desenhar.
// [pecasDoProjeto] dá os tiles do mapa do projeto numa área (de perto, eles
// entram por cima do satélite). Sem internet sai sem o satélite.
Future<({Uint8List imagem, bool comSatelite, bool comProjeto})?> gerarMapaEstatico({
  required List<TracoNoMapa> tracos,
  List<List<LatLng>> eixos = const [],
  List<RotuloNoMapa> rotulos = const [],
  List<PecaDoProjeto> Function(LatLngBounds area)? pecasDoProjeto,
  int largura = 1200,
  int altura = 700,
}) async {
  final todos = [for (final t in tracos) ...t.pontos];
  if (todos.isEmpty) return null;
  final quadro = enquadrarMapa(todos, largura: largura, altura: altura);
  final z = quadro.zoom;

  ({double x, double y}) naTela(LatLng p) {
    final px = pixelNoMundo(p, z);
    return (x: px.x - quadro.x, y: px.y - quadro.y);
  }

  List<int> naImagem(List<LatLng> pontos) {
    final xy = <int>[];
    for (final p in pontos) {
      final px = naTela(p);
      xy
        ..add(px.x.round())
        ..add(px.y.round());
    }
    return xy;
  }

  final tiles = await _baixarTiles(z, quadro.x, quadro.y, largura, altura);

  final pecas = <PecaDecodificada>[];
  if (pecasDoProjeto != null && z >= zoomMinimoDoProjeto) {
    final area = LatLngBounds(
      latLngDoPixel(quadro.x, quadro.y + altura, z),
      latLngDoPixel(quadro.x + largura, quadro.y, z),
    );
    final lista = pecasDoProjeto(area);
    if (lista.length <= maximoDePecas) {
      for (final peca in lista) {
        final decodificada = await _decodificarPeca(peca, naTela);
        if (decodificada != null) pecas.add(decodificada);
      }
    } else {
      debugPrint('Mapa do relatório: ${lista.length} tiles do projeto, '
          'acima de $maximoDePecas — sai só com o satélite');
    }
  }

  final desenho = DesenhoDoMapa(
    largura: largura,
    altura: altura,
    tiles: tiles,
    pecas: pecas,
    eixos: [for (final e in eixos) naImagem(e)],
    tracos: [for (final t in tracos) (xy: naImagem(t.pontos), cor: t.cor)],
    rotulos: [
      for (final r in rotulos)
        (x: naImagem([r.ponto])[0], y: naImagem([r.ponto])[1], texto: r.texto),
    ],
  );
  final imagem = await compute(desenharMapaEstatico, desenho);
  return (imagem: imagem, comSatelite: tiles.isNotEmpty, comProjeto: pecas.isNotEmpty);
}

// Lê o tile do projeto e decodifica já no tamanho em que ele aparece
// (decodificador nativo: o .webp inteiro em Dart puro levaria segundos).
Future<PecaDecodificada?> _decodificarPeca(
    PecaDoProjeto peca, ({double x, double y}) Function(LatLng) naTela) async {
  final topo = naTela(peca.topoEsquerda);
  final baseEsq = naTela(peca.baseEsquerda);
  final baseDir = naTela(peca.baseDireita);
  final largura = sqrt(pow(baseDir.x - baseEsq.x, 2) + pow(baseDir.y - baseEsq.y, 2)).ceil();
  final altura = sqrt(pow(baseEsq.x - topo.x, 2) + pow(baseEsq.y - topo.y, 2)).ceil();
  if (largura < 2 || altura < 2) return null;
  try {
    final bytes = await File(peca.arquivo).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: largura, targetHeight: altura);
    final quadro = await codec.getNextFrame();
    final dados =
        await quadro.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final w = quadro.image.width;
    final h = quadro.image.height;
    quadro.image.dispose();
    codec.dispose();
    if (dados == null) return null;
    return (
      rgba: dados.buffer.asUint8List(),
      largura: w,
      altura: h,
      topoX: topo.x,
      topoY: topo.y,
      baseEsqX: baseEsq.x,
      baseEsqY: baseEsq.y,
      baseDirX: baseDir.x,
      baseDirY: baseDir.y,
    );
  } catch (e) {
    debugPrint('Mapa do relatório: tile do projeto ${peca.arquivo} falhou: $e');
    return null;
  }
}

// Tiles de satélite que cobrem a imagem. Tenta o do meio primeiro: se falhar,
// está sem internet e não perde tempo com o resto.
Future<List<({Uint8List bytes, int x, int y})>> _baixarTiles(
    int z, double origemX, double origemY, int largura, int altura) async {
  final pedidos = [
    for (var ty = (origemY / tamanhoDoTile).floor();
        ty <= ((origemY + altura - 1) / tamanhoDoTile).floor();
        ty++)
      for (var tx = (origemX / tamanhoDoTile).floor();
          tx <= ((origemX + largura - 1) / tamanhoDoTile).floor();
          tx++)
        (tx: tx, ty: ty),
  ];
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  final baixados = <({Uint8List bytes, int x, int y})>[];

  Future<void> baixar(({int tx, int ty}) p) async {
    final bytes = await _baixarTile(cliente, z, p.tx, p.ty);
    if (bytes == null) return;
    baixados.add((
      bytes: bytes,
      x: (p.tx * tamanhoDoTile - origemX).round(),
      y: (p.ty * tamanhoDoTile - origemY).round(),
    ));
  }

  try {
    final meio = pedidos[pedidos.length ~/ 2];
    await baixar(meio);
    if (baixados.isEmpty) return baixados;
    final resto = [...pedidos]..remove(meio);
    for (var i = 0; i < resto.length; i += 8) {
      await Future.wait([for (final p in resto.skip(i).take(8)) baixar(p)]);
    }
  } finally {
    cliente.close(force: true);
  }
  return baixados;
}

Future<Uint8List?> _baixarTile(HttpClient cliente, int z, int x, int y) async {
  try {
    final pedido = await cliente
        .getUrl(Uri.parse('$_urlDosTiles/$z/$y/$x'))
        .timeout(const Duration(seconds: 8));
    pedido.headers.set(HttpHeaders.userAgentHeader, 'RDO cbm');
    final resposta = await pedido.close().timeout(const Duration(seconds: 8));
    if (resposta.statusCode != 200) {
      await resposta.drain<void>();
      return null;
    }
    return await consolidateHttpClientResponseBytes(resposta)
        .timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Mapa do relatório: tile $z/$y/$x falhou: $e');
    return null;
  }
}
