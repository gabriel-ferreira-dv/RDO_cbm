import 'package:latlong2/latlong.dart';

import '../../core/utils/utm.dart';
import '../registro/estaqueamento.dart';
import '../registro/sugestao_gps_service.dart';

// Estaca navegável: tem coordenada e KM.
class EstacaNavegavel {
  final String trecho;
  final String km;

  // Rótulo oficial do KMxEst ("EST. 1245"), o mesmo que aparece no formulário.
  final String rotulo;

  // Só os dígitos — usado para ordenar a lista na ordem do projeto.
  final int numero;
  final LatLng ponto;

  // Sentido da pista em trecho de pista dupla; null em pista simples.
  final String? via;

  const EstacaNavegavel({
    required this.trecho,
    required this.km,
    required this.rotulo,
    required this.numero,
    required this.ponto,
    this.via,
  });

  // "EST. 2115 • Via 01 Sul" (em pista dupla a via identifica a estaca).
  String get descricao => via == null ? rotulo : '$rotulo • $via';
}

// Navegação do mapa (trecho → KM → estaca): só estacas com coordenada e KM.
class NavegacaoEstacasService {
  NavegacaoEstacasService._interno();
  static final NavegacaoEstacasService instancia =
      NavegacaoEstacasService._interno();

  List<EstacaNavegavel>? _cache;

  // Descarta a lista (chamar quando os CSVs forem atualizados).
  void limparCache() => _cache = null;

  Future<List<EstacaNavegavel>> _todas() async {
    if (_cache != null) return _cache!;

    final coordenadas = await SugestaoGpsService.instancia.carregarCoordenadas();
    final kmPorEstaca = await EstaqueamentoService.instancia.porNumero();

    final navegaveis = <EstacaNavegavel>[];
    for (final coord in coordenadas) {
      final numero = numeroDaEstaca(coord.estaca);
      if (numero.isEmpty) continue;
      final info = kmPorEstaca['${coord.trecho}|$numero'];
      if (info == null) continue; // sem KM: fora da escolha em cascata
      navegaveis.add(EstacaNavegavel(
        trecho: coord.trecho,
        km: info.km,
        rotulo: info.rotulo,
        numero: int.parse(numero),
        ponto: utmParaLatLng(coord.e, coord.n),
        via: info.via,
      ));
    }
    _cache = navegaveis;
    return navegaveis;
  }

  // Todas as estacas com coordenada e KM (mapa de avanço).
  Future<List<EstacaNavegavel>> todas() => _todas();

  Future<List<String>> trechos() async {
    final todas = await _todas();
    return todas.map((e) => e.trecho).toSet().toList()..sort();
  }

  // KMs do trecho em ordem numérica.
  Future<List<String>> kms(String trecho) async {
    final todas = await _todas();
    final valores = todas
        .where((e) => e.trecho == trecho)
        .map((e) => e.km)
        .toSet()
        .toList();
    valores.sort((a, b) {
      final na = int.tryParse(a);
      final nb = int.tryParse(b);
      if (na != null && nb != null) return na.compareTo(nb);
      return a.compareTo(b);
    });
    return valores;
  }

  // Estacas navegáveis do KM, na ordem crescente do estaqueamento.
  Future<List<EstacaNavegavel>> estacas(String trecho, String km) async {
    final todas = await _todas();
    final lista = todas.where((e) => e.trecho == trecho && e.km == km).toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));
    return lista;
  }
}
