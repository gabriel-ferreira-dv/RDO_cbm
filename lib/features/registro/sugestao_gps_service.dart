import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/localizacao_service.dart';
import '../../core/utils/utm.dart';
import 'csv_dados_datasource.dart';
import 'estaqueamento.dart';
import 'vias_estaqueamento.dart';

// Coordenadas das estacas em UTM SIRGAS2000/24S (Trecho;Estaca;E;N). O
// casamento com o KMxEst.csv é pelo número da estaca.

// Reexportado para quem já importava as regras de numeração daqui.
export 'vias_estaqueamento.dart' show numeroDaEstaca, viaSul, viaNorte;

class EstacaCoordenada {
  final String trecho;
  final String estaca;
  final double e;
  final double n;

  EstacaCoordenada({
    required this.trecho,
    required this.estaca,
    required this.e,
    required this.n,
  });
}

// Valores prontos para preencher o formulário da Home.
class SugestaoGps {
  final String trecho;
  final String km;
  final String estaca;
  final double distanciaMetros;

  // Via pela série da estaca (pista dupla); null em pista simples.
  final String? via;

  SugestaoGps({
    required this.trecho,
    required this.km,
    required this.estaca,
    required this.distanciaMetros,
    this.via,
  });
}

// Uma sugestão ou uma mensagem de erro para o usuário.
class ResultadoSugestaoGps {
  final SugestaoGps? sugestao;
  final String? erro;

  ResultadoSugestaoGps.ok(SugestaoGps this.sugestao) : erro = null;
  ResultadoSugestaoGps.falha(String this.erro) : sugestao = null;
}

String formatarDistanciaMetros(double metros) {
  if (metros >= 1000) return '${(metros / 1000).toStringAsFixed(1)} km';
  return '${metros.round()} m';
}

// Estacas ordenadas da mais próxima à mais distante do ponto (e, n) no plano UTM. 
List<({EstacaCoordenada estaca, double distanciaMetros})> estacasPorDistancia(
  double e,
  double n,
  List<EstacaCoordenada> estacas,
) {
  final resultado = estacas.map((est) {
    final dx = est.e - e;
    final dy = est.n - n;
    return (estaca: est, distanciaMetros: sqrt(dx * dx + dy * dy));
  }).toList();
  resultado.sort((a, b) => a.distanciaMetros.compareTo(b.distanciaMetros));
  return resultado;
}

({EstacaCoordenada estaca, double distanciaMetros})? estacaMaisProxima(
  double e,
  double n,
  List<EstacaCoordenada> estacas,
) {
  final ordenadas = estacasPorDistancia(e, n, estacas);
  return ordenadas.isEmpty ? null : ordenadas.first;
}

double? parseCoordenada(dynamic valor) {
  if (valor is num) return valor.toDouble();
  var s = valor.toString().trim();
  final temPonto = s.contains('.');
  final temVirgula = s.contains(',');
  if (temPonto && temVirgula) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (temVirgula) {
    s = s.replaceAll(',', '.');
  } else if ('.'.allMatches(s).length > 1) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s);
}


double corrigirEscalaUtm(double valor, double maximoExclusivo) {
  var v = valor;
  while (v >= maximoExclusivo) {
    v /= 10;
  }
  return v;
}

class SugestaoGpsService {
  SugestaoGpsService._interno();
  static final SugestaoGpsService instancia = SugestaoGpsService._interno();

  static const double distanciaMaximaMetros = 500;

  List<EstacaCoordenada>? _cacheCoordenadas;


  void limparCache() {
    _cacheCoordenadas = null;
    EstaqueamentoService.instancia.limparCache();
  }

  Future<List<EstacaCoordenada>> carregarCoordenadas() async {
    if (_cacheCoordenadas != null) return _cacheCoordenadas!;
    final linhas = await lerDadosCsv(caminhoCSVestacasCoords);
    final estacas = <EstacaCoordenada>[];
    for (final linha in linhas) {
      if (linha.length < 4) continue;
      final e = parseCoordenada(linha[2]);
      final n = parseCoordenada(linha[3]);
      if (e == null || n == null) continue;
      estacas.add(EstacaCoordenada(
        trecho: linha[0].toString().trim(),
        estaca: linha[1].toString().trim(),
        e: corrigirEscalaUtm(e, 1000000),
        n: corrigirEscalaUtm(n, 10000000),
      ));
    }
    _cacheCoordenadas = estacas;
    return estacas;
  }

  // Mesma posição filtrada do mapa e do carimbo.
  Future<PosicaoGps?> _obterPosicao() => LocalizacaoService.instancia
      .posicaoConfiavel(espera: const Duration(seconds: 10));


  Future<ResultadoSugestaoGps> sugerir() async {
    final estacas = await carregarCoordenadas();
    if (estacas.isEmpty) {
      return ResultadoSugestaoGps.falha(
        'Sem coordenadas de estacas cadastradas (assets/estacas_coords.csv)',
      );
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      return ResultadoSugestaoGps.falha('Ative a localização (GPS) do aparelho');
    }
    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (permissao == LocationPermission.denied ||
        permissao == LocationPermission.deniedForever) {
      return ResultadoSugestaoGps.falha('Permissão de localização negada');
    }

    final posicao = await _obterPosicao();
    if (posicao == null) {
      return ResultadoSugestaoGps.falha('Não foi possível obter sua localização');
    }

    return sugerirParaPosicao(LatLng(posicao.latitude, posicao.longitude));
    // return sugerirParaPosicao(LatLng(-19.989739, -40.413614));
  }


  Future<ResultadoSugestaoGps> sugerirParaPosicao(LatLng posicao) async {
    final estacas = await carregarCoordenadas(); 
    if (estacas.isEmpty) {
      return ResultadoSugestaoGps.falha(
        'Sem coordenadas de estacas cadastradas (assets/estacas_coords.csv)',
      );
    }

    final utm = latLngParaUtm(posicao);
    final candidatas = estacasPorDistancia(utm.x, utm.y, estacas);
    if (candidatas.first.distanciaMetros > distanciaMaximaMetros) {
      return ResultadoSugestaoGps.falha(
        'Você está a ${formatarDistanciaMetros(candidatas.first.distanciaMetros)} '
        'da estaca mais próxima do projeto',
      );
    }

    // No C1 a via sai da série da estaca.
    final pistaDupla = <String>{
      for (final e in estacas)
        if (estacaDaSerieSul(int.tryParse(numeroDaEstaca(e.estaca)) ?? 0))
          e.trecho,
    };

    // A mais próxima pode não estar no KMxEst: tenta as seguintes no raio.
    final tabela = await EstaqueamentoService.instancia.porNumero();
    for (final candidata in candidatas) {
      if (candidata.distanciaMetros > distanciaMaximaMetros) break;
      final numero = numeroDaEstaca(candidata.estaca.estaca);
      final chave = '${candidata.estaca.trecho}|$numero';
      final info = tabela[chave];
      if (info == null) continue;
      return ResultadoSugestaoGps.ok(SugestaoGps(
        trecho: candidata.estaca.trecho,
        km: info.km,
        estaca: info.rotulo,
        distanciaMetros: candidata.distanciaMetros,
        via: info.via ??
            viaDaEstaca(
              int.tryParse(numero) ?? 0,
              pistaDupla: pistaDupla.contains(candidata.estaca.trecho),
            ),
      ));
    }

    return ResultadoSugestaoGps.falha(
      'Nenhuma estaca próxima encontrada na tabela KM x Estaca',
    );
  }
}
