import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../mapa/mapa_estatico.dart';
import '../mapa/navegacao_estacas_service.dart';
import '../mapa/presentation/pages/map_page.dart' show pecasDoProjetoEm;
import '../registro/vias_estaqueamento.dart' show chaveDoTrecho;
import '../supervisor/avanco.dart';
import 'texto_pdf.dart';

// Uma atividade para o mapa do relatório.
typedef AtividadeNoMapa = ({
  String trecho,
  String estacaInicial,
  String estacaFinal,
  String servico,
});

// Mapa das atividades pronto para o PDF.
class MapaNoPdf {
  final Uint8List imagem;
  final int largura;
  final int altura;
  final bool comSatelite;

  // Serviços desenhados, com a cor (ARGB) de cada um.
  final List<({String servico, int cor})> legenda;

  const MapaNoPdf({
    required this.imagem,
    required this.largura,
    required this.altura,
    required this.comSatelite,
    required this.legenda,
  });
}

// Imagem do mapa com as [atividades] pintadas sobre as estacas, nas mesmas
// cores do mapa de avanço. Null quando nenhuma tem estaca com coordenada (ou
// algo falha: o relatório sai sem o mapa).
Future<MapaNoPdf?> montarMapaDasAtividades(List<AtividadeNoMapa> atividades) async {
  if (atividades.isEmpty) return null;
  try {
    final estacas =
        agruparEstacasPorTrecho(await NavegacaoEstacasService.instancia.todas());
    final servicos = servicosPorFrequencia(atividades.map((a) => a.servico));
    final tracos = <TracoNoMapa>[];
    final desenhados = <String>{};
    final trechos = <String>{};
    final rotulos = <String, RotuloNoMapa>{};

    for (final a in atividades) {
      final cobertas =
          estacasDoIntervalo(a.trecho, a.estacaInicial, a.estacaFinal, estacas);
      if (cobertas.isEmpty) continue;
      tracos.add(TracoNoMapa(
          [for (final e in cobertas) e.ponto], corDoServico(a.servico, servicos)));
      desenhados.add(a.servico);
      final trecho = chaveDoTrecho(a.trecho);
      trechos.add(trecho);
      // Um "KM 225" por KM, para quem lê o papel se localizar.
      final inicio = cobertas.first;
      rotulos.putIfAbsent(
          '$trecho|${inicio.km}', () => RotuloNoMapa(inicio.ponto, 'KM ${inicio.km}'));
    }
    if (tracos.isEmpty) return null;

    // Eixo das pistas com atividade, de referência.
    final porPista = <String, List<LatLng>>{};
    for (final trecho in trechos) {
      for (final e in estacas[trecho] ?? const <EstacaNavegavel>[]) {
        porPista.putIfAbsent('$trecho|${e.via}', () => []).add(e.ponto);
      }
    }

    const largura = 1200;
    const altura = 700;
    final mapa = await gerarMapaEstatico(
      tracos: tracos,
      eixos: [for (final l in porPista.values) if (l.length > 1) l],
      rotulos: rotulos.values.toList(),
      // A ortofoto e o desenho do projeto, os mesmos da aba Mapa.
      pecasDoProjeto: pecasDoProjetoEm,
      largura: largura,
      altura: altura,
    );
    if (mapa == null) return null;
    return MapaNoPdf(
      imagem: mapa.imagem,
      largura: largura,
      altura: altura,
      comSatelite: mapa.comSatelite,
      legenda: [
        for (final s in servicos)
          if (desenhados.contains(s)) (servico: s, cor: corDoServico(s, servicos)),
      ],
    );
  } catch (e) {
    debugPrint('Mapa do relatório falhou (sai sem o mapa): $e');
    return null;
  }
}

// Título, imagem, legenda e crédito juntos: não se separam na quebra de
// página.
pw.Widget mapaNoPdf(MapaNoPdf mapa,
    {required pw.Widget titulo, required double largura}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      titulo,
      pw.SizedBox(height: 6),
      pw.Image(
        pw.MemoryImage(mapa.imagem),
        width: largura,
        height: largura * mapa.altura / mapa.largura,
        fit: pw.BoxFit.contain,
      ),
      pw.SizedBox(height: 4),
      pw.Wrap(
        spacing: 12,
        runSpacing: 3,
        children: [
          for (final l in mapa.legenda)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(width: 16, height: 5, color: PdfColor.fromInt(l.cor)),
                pw.SizedBox(width: 4),
                pw.Text(textoParaPdf(l.servico), style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
        ],
      ),
      if (mapa.comSatelite)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text('Imagem de satélite: Esri World Imagery',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ),
    ],
  );
}
