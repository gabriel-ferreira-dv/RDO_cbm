import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import '../../core/dados_remotos.dart';

// SevNotaveis.csv — uma linha por passo de serviço, com as colunas:
//   Atividade;Servico notavel;SERVIÇO CORRELATO (PASSO);Trecho
const String caminhoCSVdados = 'assets/SevNotaveis.csv';
const String caminhoCSVkm = 'assets/KMxEst.csv';
const String caminhoCSVestacasCoords = 'assets/estacas_coords.csv';
const String caminhoSerN = caminhoCSVdados;

// Índices das colunas de SevNotaveis.csv.
const int colAtividade = 0;
const int colServicoNotavel = 1;
const int colPasso = 2;
const int colTrecho = 3;

// Lê o CSV em UTF-8 e, se falhar, em Latin-1 (o Excel pt-BR salva em
// Windows-1252).
@visibleForTesting
String decodificarCsv(List<int> bytes) {
  try {
    return utf8.decode(bytes); // rejeita bytes inválidos (allowMalformed: false)
  } on FormatException {
    return latin1.decode(bytes);
  }
}

// Usa a cópia baixada do servidor; sem ela, a do APK.
Future<String> _conteudoCsv(String assetPath) async {
  final remoto = arquivoRemotoOuNull(assetPath.split('/').last);
  if (remoto != null) return decodificarCsv(await remoto.readAsBytes());
  final dados = await rootBundle.load(assetPath);
  return decodificarCsv(dados.buffer.asUint8List());
}

Future<List<List<dynamic>>> lerDadosCsv(String data) async {
  try {
    final rawData = await _conteudoCsv(data);
    final dados = Csv().decode(rawData);
    return dados.isEmpty ? [] : dados.skip(1).toList();
  } catch (e) {
    print('Erro ao ler CSV: $e');
    return [];
  }
}

// Valores distintos e ordenados de [alvo], nas linhas que casam com [filtros].
Future<List<String>> _valoresDistintos(
  String caminho,
  int alvo,
  Map<int, String> filtros,
) async {
  final dados = await lerDadosCsv(caminho);
  final valores = dados
      .where((linha) =>
          linha.length > alvo &&
          filtros.entries.every((f) =>
              linha.length > f.key &&
              linha[f.key].toString().trim() == f.value.trim()))
      .map((linha) => linha[alvo].toString().trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return valores;
}

Future<List<String>> carregarColuna(int indice) =>
    _valoresDistintos(caminhoCSVdados, indice, const {});

Future<List<String>> carregarKmEst(int indice, int indice2, String servNot) async {
  final dados = await lerDadosCsv(caminhoCSVkm);
  final valores = dados
      .where((linha) => linha.length > indice && linha[indice2].toString() == servNot)
      .map((linha) => linha[indice].toString())
      .toSet()
      .toList();
  return valores;
}

Future<List<String>> carregarTrechos() => carregarColuna(colTrecho);

// Atividades disponíveis no trecho.
Future<List<String>> carregarAtividades(String trecho) =>
    _valoresDistintos(caminhoCSVdados, colAtividade, {colTrecho: trecho});

// Serviços notáveis da atividade dentro do trecho.
Future<List<String>> carregarServicosNotaveis(String trecho, String atividade) =>
    _valoresDistintos(caminhoCSVdados, colServicoNotavel, {
      colTrecho: trecho,
      colAtividade: atividade,
    });

// Passos do serviço, filtrados também pela atividade (o serviço se repete).
Future<List<String>> carregarPassosDoServico(
  String trecho,
  String atividade,
  String servicoNotavel,
) =>
    _valoresDistintos(caminhoCSVdados, colPasso, {
      colTrecho: trecho,
      colAtividade: atividade,
      colServicoNotavel: servicoNotavel,
    });
