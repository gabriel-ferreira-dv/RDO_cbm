import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Condição sugerida para um período, com a chuva estimada.
class ClimaDoPeriodo {
  final String condicao; // 'Bom', 'Nublado' ou 'Chuvoso'
  final double chuvaMm;

  const ClimaDoPeriodo(this.condicao, this.chuvaMm);
}

// Horas de cada período: [início, fim), contando do 0h do dia. A noite vai
// até as 6h do dia seguinte, o que cobre o turno da noite.
const Map<String, (int, int)> horasDosPeriodos = {
  'Manhã': (6, 12),
  'Tarde': (12, 18),
  'Noite': (18, 30),
};

// Chuva (mm) a partir da qual o período conta como chuvoso.
const double chuvaMinimaMm = 1.0;

// Nuvens (% média) a partir das quais o período conta como nublado.
const int nuvensMinimasPct = 70;

// Classifica cada período de [dia] pela série horária do Open-Meteo. Período
// que ainda não começou ([agora]) fica de fora, assim como a noite quando
// [incluirNoite] é falso. Nunca sugere "Impraticável": isso é o encarregado
// quem decide.
Map<String, ClimaDoPeriodo> classificarClima({
  required Map<String, dynamic> horario,
  required DateTime dia,
  required DateTime agora,
  bool incluirNoite = false,
}) {
  final horas = (horario['time'] as List).cast<String>();
  final chuva = (horario['precipitation'] as List?) ?? const [];
  final nuvens = (horario['cloud_cover'] as List?) ?? const [];
  final codigos = (horario['weather_code'] as List?) ?? const [];
  final zero = DateTime(dia.year, dia.month, dia.day);

  final resultado = <String, ClimaDoPeriodo>{};
  for (final MapEntry(key: periodo, value: (de, ate)) in horasDosPeriodos.entries) {
    if (periodo == 'Noite' && !incluirNoite) continue;
    final inicio = zero.add(Duration(hours: de));
    if (inicio.isAfter(agora)) continue;
    final fim = zero.add(Duration(hours: ate));

    var somaChuva = 0.0;
    var somaNuvens = 0.0;
    var amostras = 0;
    var trovoada = false;
    for (var i = 0; i < horas.length; i++) {
      // Horas locais, sem fuso ("2026-09-24T13:00"), como pedido na consulta.
      final hora = DateTime.tryParse(horas[i]);
      if (hora == null || hora.isBefore(inicio) || !hora.isBefore(fim)) continue;
      somaChuva += (i < chuva.length ? chuva[i] as num? : null)?.toDouble() ?? 0;
      somaNuvens += (i < nuvens.length ? nuvens[i] as num? : null)?.toDouble() ?? 0;
      final codigo = (i < codigos.length ? codigos[i] as num? : null)?.toInt() ?? 0;
      if (codigo >= 95) trovoada = true;
      amostras++;
    }
    if (amostras == 0) continue;

    final condicao = somaChuva >= chuvaMinimaMm || trovoada
        ? 'Chuvoso'
        : somaNuvens / amostras >= nuvensMinimasPct
            ? 'Nublado'
            : 'Bom';
    resultado[periodo] = ClimaDoPeriodo(condicao, somaChuva);
  }
  return resultado;
}

// Tempo hora a hora do Open-Meteo, para sugerir o clima do RDO. É modelo
// meteorológico, não estação: serve de ponto de partida, o encarregado confere.
// ATENÇÃO: a API gratuita do Open-Meteo é para uso não comercial. Para uso na
// empresa, contrate uma chave e troque [_host] por customer-api.open-meteo.com
// com &apikey=... (ver open-meteo.com/en/pricing).
class ClimaService {
  ClimaService._interno();
  static final ClimaService instancia = ClimaService._interno();

  static const String _host = 'api.open-meteo.com';

  // Sugestão por período para [dia] em ([latitude], [longitude]); null sem
  // internet ou se a consulta falhar.
  Future<Map<String, ClimaDoPeriodo>?> sugerir({
    required DateTime dia,
    required double latitude,
    required double longitude,
    bool incluirNoite = false,
  }) async {
    String data(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final uri = Uri.https(_host, '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(3),
      'longitude': longitude.toStringAsFixed(3),
      'hourly': 'precipitation,cloud_cover,weather_code',
      // Horas no fuso da obra, sem sufixo: comparáveis com o dia local.
      'timezone': 'America/Sao_Paulo',
      'start_date': data(dia),
      // O dia seguinte entra pela noite (até as 6h).
      'end_date': data(DateTime(dia.year, dia.month, dia.day + 1)),
    });

    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final pedido = await cliente.getUrl(uri);
      final resposta = await pedido.close().timeout(const Duration(seconds: 10));
      final corpo = await resposta.transform(utf8.decoder).join();
      if (resposta.statusCode != 200) {
        debugPrint('Clima: Open-Meteo respondeu ${resposta.statusCode}: $corpo');
        return null;
      }
      final json = jsonDecode(corpo) as Map<String, dynamic>;
      return classificarClima(
        horario: json['hourly'] as Map<String, dynamic>,
        dia: dia,
        agora: DateTime.now(),
        incluirNoite: incluirNoite,
      );
    } catch (e) {
      debugPrint('Clima: consulta falhou: $e');
      return null;
    } finally {
      cliente.close();
    }
  }
}
