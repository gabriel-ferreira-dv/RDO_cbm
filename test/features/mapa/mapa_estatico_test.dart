import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:namer_app/features/mapa/mapa_estatico.dart';

void main() {
  group('pixelNoMundo', () {
    test('no zoom 0 o mundo inteiro cabe num tile de 256', () {
      final canto = pixelNoMundo(const LatLng(0, -180), 0);
      expect(canto.x, closeTo(0, 1e-9));
      expect(canto.y, closeTo(128, 1e-9));
      final meio = pixelNoMundo(const LatLng(0, 0), 0);
      expect(meio.x, closeTo(128, 1e-9));
    });

    test('cada zoom dobra a escala', () {
      const p = LatLng(-19.9, -40.4);
      expect(pixelNoMundo(p, 15).x * 2, closeTo(pixelNoMundo(p, 16).x, 1e-6));
    });
  });

  group('enquadrarMapa', () {
    // Uns 400 m de pista, como um dia de serviço.
    final pista = [
      const LatLng(-19.9000, -40.4000),
      const LatLng(-19.9036, -40.4000),
    ];

    test('os pontos ficam dentro da imagem, com margem', () {
      final q = enquadrarMapa(pista, largura: 1200, altura: 700);
      for (final p in pista) {
        final px = pixelNoMundo(p, q.zoom);
        expect(px.x - q.x, inInclusiveRange(60, 1140));
        expect(px.y - q.y, inInclusiveRange(60, 640));
      }
    });

    test('usa o maior zoom em que cabe', () {
      final q = enquadrarMapa(pista, largura: 1200, altura: 700);
      final maisPerto = enquadrarMapa(pista, largura: 1200, altura: 700,
          zoomMaximo: q.zoom + 1, zoomMinimo: q.zoom + 1);
      // No zoom seguinte já não caberia: a altura em pixels passaria da imagem.
      final a = pixelNoMundo(pista.first, maisPerto.zoom);
      final b = pixelNoMundo(pista.last, maisPerto.zoom);
      expect((b.y - a.y).abs(), greaterThan(700 - 120));
    });

    test('um ponto só abre no zoom máximo, centralizado', () {
      final q = enquadrarMapa([pista.first], largura: 1200, altura: 700);
      expect(q.zoom, 18);
      final px = pixelNoMundo(pista.first, 18);
      expect(px.x - q.x, closeTo(600, 1e-6));
      expect(px.y - q.y, closeTo(350, 1e-6));
    });

    test('obra espalhada para no zoom mínimo', () {
      final q = enquadrarMapa(
          [const LatLng(-19.0, -41.0), const LatLng(-21.0, -39.0)],
          largura: 1200,
          altura: 700);
      expect(q.zoom, 10);
    });
  });

  test('latLngDoPixel desfaz o pixelNoMundo', () {
    const p = LatLng(-19.9123, -40.4056);
    final px = pixelNoMundo(p, 17);
    final volta = latLngDoPixel(px.x, px.y, 17);
    expect(volta.latitude, closeTo(p.latitude, 1e-9));
    expect(volta.longitude, closeTo(p.longitude, 1e-9));
  });

  group('tile do projeto', () {
    // Tile 10×10 de uma cor só.
    PecaDecodificada peca(int r, int g, int b, int a,
            {double topoX = 100, double topoY = 50, double baseY = 150, double dirX = 300}) =>
        (
          rgba: Uint8List.fromList([for (var i = 0; i < 100; i++) ...[r, g, b, a]]),
          largura: 10,
          altura: 10,
          topoX: topoX,
          topoY: topoY,
          baseEsqX: topoX,
          baseEsqY: baseY,
          baseDirX: dirX,
          baseDirY: baseY,
        );

    test('entra no lugar dos cantos, com a opacidade da aba Mapa', () {
      final jpeg = desenharMapaEstatico(DesenhoDoMapa(
        largura: 400,
        altura: 200,
        pecas: [peca(255, 0, 0, 255)],
      ));
      final imagem = img.decodeJpg(jpeg)!;
      final dentro = imagem.getPixel(200, 100);
      // 80% vermelho sobre o fundo cinza (236).
      expect(dentro.r, greaterThan(235));
      expect(dentro.g, inInclusiveRange(25, 75));
      final fora = imagem.getPixel(50, 100);
      expect(fora.g, greaterThan(220));
    });

    // Tile vazio (transparente) não pode apagar o satélite.
    test('parte transparente deixa ver o que está embaixo', () {
      final jpeg = desenharMapaEstatico(DesenhoDoMapa(
        largura: 400,
        altura: 200,
        pecas: [peca(255, 0, 0, 0)],
      ));
      final pixel = img.decodeJpg(jpeg)!.getPixel(200, 100);
      expect(pixel.g, greaterThan(220));
    });

    // A grade é UTM: o tile vem levemente girado e tem que seguir os cantos.
    test('tile girado segue o paralelogramo', () {
      final jpeg = desenharMapaEstatico(DesenhoDoMapa(
        largura: 400,
        altura: 200,
        pecas: [
          (
            rgba: Uint8List.fromList([for (var i = 0; i < 100; i++) ...[0, 0, 255, 255]]),
            largura: 10,
            altura: 10,
            topoX: 100,
            topoY: 40,
            baseEsqX: 80,
            baseEsqY: 160,
            baseDirX: 280,
            baseDirY: 180,
          ),
        ],
      ));
      final imagem = img.decodeJpg(jpeg)!;
      expect(imagem.getPixel(190, 110).b, greaterThan(200), reason: 'meio do tile');
      expect(imagem.getPixel(90, 45).b, lessThan(240), reason: 'fora, à esquerda do topo');
      expect(imagem.getPixel(90, 45).r, greaterThan(200));
    });
  });

  // Sem internet o relatório sai com as linhas sobre fundo claro.
  test('desenha a linha na cor do serviço, sem satélite', () {
    final jpeg = desenharMapaEstatico(const DesenhoDoMapa(
      largura: 400,
      altura: 200,
      eixos: [
        [0, 150, 400, 150],
      ],
      tracos: [
        (xy: [50, 100, 350, 100], cor: 0xFFE53935),
        (xy: [200, 50], cor: 0xFF1E88E5),
      ],
      rotulos: [(x: 60, y: 30, texto: 'KM 225')],
    ));
    final imagem = img.decodeJpg(jpeg)!;
    expect(imagem.width, 400);
    expect(imagem.height, 200);

    final naLinha = imagem.getPixel(200, 100);
    expect(naLinha.r, greaterThan(180), reason: 'vermelho do serviço');
    expect(naLinha.b, lessThan(110));

    final noPonto = imagem.getPixel(200, 50);
    expect(noPonto.b, greaterThan(160), reason: 'azul do ponto');

    final fundo = imagem.getPixel(380, 20);
    expect(fundo.r, greaterThan(200), reason: 'fundo claro sem satélite');
  });
}
