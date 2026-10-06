import 'dart:math';

import 'csv_dados_datasource.dart';
import 'vias_estaqueamento.dart';

// Se [km] está entre [kmDe] e [kmAte], inclusive e em qualquer ordem. KM que
// não é número só casa com as pontas.
bool kmNoIntervalo(String km, String kmDe, String kmAte) {
  final n = int.tryParse(km.trim());
  final de = int.tryParse(kmDe.trim());
  final ate = int.tryParse(kmAte.trim());
  if (n == null || de == null || ate == null) return km == kmDe || km == kmAte;
  return n >= min(de, ate) && n <= max(de, ate);
}

// Quantos KMs de cada lado entram nas listas de estaca, para o serviço poder
// atravessar o KM.
const int kmsVizinhos = 2;


// Uma estaca do projeto: número, KM a que pertence e, em pista dupla, a via.
class EstacaDoProjeto {
  final String trecho;
  final int numero;

  // Como a estaca é escrita nas planilhas ("1115", "57").
  final String rotulo;
  final String km;

  // null em trecho de pista simples, onde a numeração não indica sentido.
  final String? via;

  // true quando o KM veio da estaca gêmea da outra pista.
  final bool kmDerivado;

  const EstacaDoProjeto({
    required this.trecho,
    required this.numero,
    required this.rotulo,
    required this.km,
    required this.via,
    this.kmDerivado = false,
  });
}

// Rótulo na lista da estaca final: com o KM ao lado quando é de outro KM.
String rotuloComKm(EstacaDoProjeto estaca, String kmSelecionado) =>
    estaca.km == kmSelecionado
        ? estaca.rotulo
        : '${estaca.rotulo} (KM ${estaca.km})';

// Estacas do projeto por trecho/KM/via, do KMxEst.csv. A série sul do C1
// (2xxx) não está nele: é derivada da norte, com o mesmo KM.
class EstaqueamentoService {
  EstaqueamentoService._interno();
  static final EstaqueamentoService instancia = EstaqueamentoService._interno();

  List<EstacaDoProjeto>? _cache;

  void limparCache() => _cache = null;

  Future<List<EstacaDoProjeto>> todas() async {
    if (_cache != null) return _cache!;

    final linhas = await lerDadosCsv(caminhoCSVkm);
    // Só trecho e estaca do CSV de coordenadas.
    final coordenadas = await lerDadosCsv(caminhoCSVestacasCoords);

    // Pista dupla = trecho com estacas da série sul.
    final pistaDupla = <String>{
      for (final linha in coordenadas)
        if (linha.length > 1 &&
            estacaDaSerieSul(
                int.tryParse(numeroDaEstaca(linha[1].toString())) ?? 0))
          linha[0].toString().trim(),
    };

    final daPlanilha = <EstacaDoProjeto>[];
    final chavesConhecidas = <String>{};
    for (final linha in linhas) {
      if (linha.length <= 3) continue;
      final trecho = linha[0].toString().trim();
      final rotulo = linha[1].toString().trim();
      final numero = int.tryParse(numeroDaEstaca(rotulo));
      if (numero == null) continue;
      if (!chavesConhecidas.add('$trecho|$numero')) continue;
      daPlanilha.add(EstacaDoProjeto(
        trecho: trecho,
        numero: numero,
        rotulo: rotulo,
        km: linha[3].toString().trim(),
        via: viaDaEstaca(numero, pistaDupla: pistaDupla.contains(trecho)),
      ));
    }

    final derivadas = <EstacaDoProjeto>[];
    for (final estaca in daPlanilha) {
      if (!pistaDupla.contains(estaca.trecho)) continue;
      if (estacaDaSerieSul(estaca.numero)) continue;
      final numeroSul = gemeaNaSerieSul(estaca.numero);
      if (chavesConhecidas.contains('${estaca.trecho}|$numeroSul')) continue;
      derivadas.add(EstacaDoProjeto(
        trecho: estaca.trecho,
        numero: numeroSul,
        rotulo: '$numeroSul',
        km: estaca.km,
        via: viaSul,
        kmDerivado: true,
      ));
    }

    _cache = [...daPlanilha, ...derivadas];
    return _cache!;
  }

  // Estacas de um KM, filtradas pela via (null = as duas séries).
  Future<List<String>> rotulosDoKm(String trecho, String km, {String? via}) async {
    final todas = await this.todas();
    final lista = todas
        .where((e) =>
            e.trecho == trecho &&
            e.km == km &&
            (via == null || e.via == null || e.via == via))
        .toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));
    return lista.map((e) => e.rotulo).toList();
  }

  // Estacas do [km] e dos [kmsVizinhos] KMs de cada lado, filtradas pela via,
  // em ordem de estaca.
  Future<List<EstacaDoProjeto>> doKmEVizinhos(String trecho, String km,
      {String? via}) {
    final n = int.tryParse(km.trim());
    final de = n == null ? km : '${n - kmsVizinhos}';
    final ate = n == null ? km : '${n + kmsVizinhos}';
    return doIntervalo(trecho, de, ate, via: via);
  }

  // Estacas do KM [kmDe] ao [kmAte], filtradas pela via.
  Future<List<EstacaDoProjeto>> doIntervalo(
      String trecho, String kmDe, String kmAte,
      {String? via}) async {
    final todas = await this.todas();
    return todas
        .where((e) =>
            e.trecho == trecho &&
            (via == null || e.via == null || e.via == via) &&
            kmNoIntervalo(e.km, kmDe, kmAte))
        .toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));
  }

  // Índice "trecho|numero" → estaca.
  Future<Map<String, EstacaDoProjeto>> porNumero() async {
    final todas = await this.todas();
    return {for (final e in todas) '${e.trecho}|${e.numero}': e};
  }
}
