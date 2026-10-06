import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../mapa/navegacao_estacas_service.dart' show EstacaNavegavel;
import '../registro/models/grupo_atividade.dart' show formatarQuantidade;
import '../registro/vias_estaqueamento.dart';
import 'registros_equipe_service.dart';

// Mapa de avanço: onde cada serviço foi executado, a partir das estacas dos
// registros e das coordenadas do projeto. Nada aqui depende de tela.

// Estacas com coordenada por trecho ([chaveDoTrecho]), em ordem de número.
typedef EstacasPorTrecho = Map<String, List<EstacaNavegavel>>;

EstacasPorTrecho agruparEstacasPorTrecho(Iterable<EstacaNavegavel> estacas) {
  final porTrecho = <String, List<EstacaNavegavel>>{};
  for (final e in estacas) {
    porTrecho.putIfAbsent(chaveDoTrecho(e.trecho), () => []).add(e);
  }
  for (final lista in porTrecho.values) {
    lista.sort((a, b) => a.numero.compareTo(b.numero));
  }
  return porTrecho;
}

// Estacas do projeto cobertas pelo registro, em ordem. Vazio quando o
// registro não tem estaca (área de apoio) ou ela não tem coordenada.
List<EstacaNavegavel> estacasDoRegistro(
        RegistroDaEquipe r, EstacasPorTrecho estacas) =>
    estacasDoIntervalo(r.trecho, r.estacaInicial, r.estacaFinal, estacas);

// Estacas do [trecho] de [estacaInicial] a [estacaFinal], em ordem.
List<EstacaNavegavel> estacasDoIntervalo(String trecho, String estacaInicial,
    String estacaFinal, EstacasPorTrecho estacas) {
  final lista = estacas[chaveDoTrecho(trecho)];
  if (lista == null) return const [];
  final inicial = int.tryParse(numeroDaEstaca(estacaInicial));
  if (inicial == null) return const [];
  final fim = int.tryParse(numeroDaEstaca(estacaFinal)) ?? inicial;
  final de = min(inicial, fim);
  final ate = max(inicial, fim);
  return [for (final e in lista) if (e.numero >= de && e.numero <= ate) e];
}

// Cores dos serviços (ARGB). Mesma ordem no mapa do app e no do relatório.
// Ciano e magenta primeiro: o desenho do projeto é cheio de vermelho e azul,
// e a vegetação é verde.
const List<int> coresDeServico = [
  0xFF00E5FF, // ciano
  0xFFE040FB, // magenta
  0xFFFFEA00, // amarelo
  0xFFFF6D00, // laranja
  0xFF76FF03, // verde-limão
  0xFF2979FF, // azul
  0xFFFF1744, // vermelho
  0xFF1DE9B6, // turquesa
  0xFFF50057, // rosa
  0xFF8D6E63, // marrom
];

// Cor do serviço na lista [servicos] (ver [servicosPorFrequencia]).
int corDoServico(String servico, List<String> servicos) {
  final i = servicos.indexOf(servico);
  return coresDeServico[(i < 0 ? 0 : i) % coresDeServico.length];
}

// Serviços do mais ao menos frequente (empate: ordem alfabética). A posição
// define a cor.
List<String> servicosPorFrequencia(Iterable<String> servicos) {
  final contagem = <String, int>{};
  for (final s in servicos) {
    contagem.update(s, (n) => n + 1, ifAbsent: () => 1);
  }
  return contagem.keys.toList()
    ..sort((a, b) {
      final porContagem = contagem[b]!.compareTo(contagem[a]!);
      return porContagem != 0 ? porContagem : a.compareTo(b);
    });
}

// Se o registro é dos últimos [dias] dias (cor forte no mapa).
bool registroRecente(RegistroDaEquipe r, DateTime agora, {int dias = 7}) =>
    agora.difference(r.criadoEm) < Duration(days: dias);

// O que um serviço avançou num KM.
class AvancoDoKm {
  final String trecho;
  final String km;
  final Map<String, double> quantidades = {}; // unidade → soma
  final Set<String> estacas = {};
  int registros = 0;
  double metros = 0;

  AvancoDoKm(this.trecho, this.km);

  // Pontos das estacas deste KM, para enquadrar no mapa.
  final List<LatLng> pontos = [];
}

// O que um serviço avançou no período, com o detalhe por KM.
class AvancoDoServico {
  final String servico;
  final Map<String, double> quantidades = {};
  int registros = 0;
  double metros = 0;

  // Registros que não dá para desenhar: sem estaca ou sem coordenada.
  int foraDoMapa = 0;
  final List<AvancoDoKm> kms = [];

  AvancoDoServico(this.servico);
}

// Soma por serviço e KM. A extensão conta cada trecho entre duas estacas uma
// vez só por serviço e via, mesmo que vários registros passem por ele.
// Serviços do que tem mais registros ao que tem menos.
List<AvancoDoServico> resumirAvanco(
    List<RegistroDaEquipe> registros, EstacasPorTrecho estacas) {
  const distancia = Distance();
  final porServico = <String, AvancoDoServico>{};
  final porKm = <String, AvancoDoKm>{};
  final vaosContados = <String>{};

  for (final r in registros) {
    final servico = porServico.putIfAbsent(
        r.servicoNotavel, () => AvancoDoServico(r.servicoNotavel));
    final chaveKm = '${r.servicoNotavel}|${chaveDoTrecho(r.trecho)}|${r.km}';
    final km = porKm.putIfAbsent(chaveKm, () {
      final novo = AvancoDoKm(r.trecho, r.km);
      servico.kms.add(novo);
      return novo;
    });

    servico.registros++;
    km.registros++;
    if (r.quantidade != null && r.unidade.isNotEmpty) {
      servico.quantidades.update(r.unidade, (v) => v + r.quantidade!,
          ifAbsent: () => r.quantidade!);
      km.quantidades.update(r.unidade, (v) => v + r.quantidade!,
          ifAbsent: () => r.quantidade!);
    }

    final cobertas = estacasDoRegistro(r, estacas);
    if (cobertas.isEmpty) {
      servico.foraDoMapa++;
      continue;
    }
    for (final e in cobertas) {
      km.estacas.add('${e.numero}');
      km.pontos.add(e.ponto);
    }
    for (var i = 0; i + 1 < cobertas.length; i++) {
      final a = cobertas[i];
      final b = cobertas[i + 1];
      final vao = '${r.servicoNotavel}|${chaveDoTrecho(r.trecho)}|${r.via}|'
          '${a.numero}|${b.numero}';
      if (!vaosContados.add(vao)) continue;
      final metros = distancia.as(LengthUnit.Meter, a.ponto, b.ponto);
      servico.metros += metros;
      km.metros += metros;
    }
  }

  for (final s in porServico.values) {
    s.kms.sort((a, b) {
      final porTrecho = a.trecho.compareTo(b.trecho);
      if (porTrecho != 0) return porTrecho;
      final na = int.tryParse(a.km);
      final nb = int.tryParse(b.km);
      return na != null && nb != null ? na.compareTo(nb) : a.km.compareTo(b.km);
    });
  }
  return porServico.values.toList()
    ..sort((a, b) => b.registros.compareTo(a.registros));
}

// "1850 m³ + 20 m"; vazio sem medição.
String formatarQuantidades(Map<String, double> quantidades) => [
      for (final e in quantidades.entries) '${formatarQuantidade(e.value)} ${e.key}',
    ].join(' + ');

// "320 m" ou "1,2 km".
String formatarExtensao(double metros) => metros >= 1000
    ? '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
    : '${metros.round()} m';
