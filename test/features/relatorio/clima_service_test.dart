import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/relatorio/clima_service.dart';

final _dia = DateTime(2026, 9, 24);

// Série horária de dois dias (48 h) no formato do Open-Meteo. [chuva] e
// [nuvens] recebem a hora contada do 0h do [_dia] (a noite passa de 24).
Map<String, dynamic> _serie({
  double Function(int hora)? chuva,
  int Function(int hora)? nuvens,
  int Function(int hora)? codigo,
}) {
  String dois(int n) => n.toString().padLeft(2, '0');
  final horas = List.generate(48, (h) => h);
  return {
    'time': [
      for (final h in horas)
        () {
          final d = _dia.add(Duration(hours: h));
          return '${d.year}-${dois(d.month)}-${dois(d.day)}T${dois(d.hour)}:00';
        }(),
    ],
    'precipitation': [for (final h in horas) chuva?.call(h) ?? 0.0],
    'cloud_cover': [for (final h in horas) nuvens?.call(h) ?? 10],
    'weather_code': [for (final h in horas) codigo?.call(h) ?? 0],
  };
}

void main() {
  final fimDoDia = DateTime(2026, 9, 25, 7);

  test('chuva à tarde: manhã boa, tarde chuvosa com os milímetros', () {
    final clima = classificarClima(
      horario: _serie(chuva: (h) => h >= 13 && h < 16 ? 0.5 : 0),
      dia: _dia,
      agora: fimDoDia,
    );
    expect(clima['Manhã']!.condicao, 'Bom');
    expect(clima['Tarde']!.condicao, 'Chuvoso');
    expect(clima['Tarde']!.chuvaMm, closeTo(1.5, 0.001));
  });

  test('céu fechado sem chuva é nublado', () {
    final clima = classificarClima(
      horario: _serie(nuvens: (_) => 90),
      dia: _dia,
      agora: fimDoDia,
    );
    expect(clima['Manhã']!.condicao, 'Nublado');
  });

  // Garoa de menos de 1 mm no período não faz o dia chuvoso.
  test('garoa fraca não conta como chuva', () {
    final clima = classificarClima(
      horario: _serie(chuva: (h) => h == 8 ? 0.4 : 0),
      dia: _dia,
      agora: fimDoDia,
    );
    expect(clima['Manhã']!.condicao, 'Bom');
  });

  test('trovoada conta como chuva mesmo com pouca água', () {
    final clima = classificarClima(
      horario: _serie(chuva: (h) => h == 14 ? 0.2 : 0, codigo: (h) => h == 14 ? 95 : 0),
      dia: _dia,
      agora: fimDoDia,
    );
    expect(clima['Tarde']!.condicao, 'Chuvoso');
  });

  test('período que ainda não começou fica de fora', () {
    final clima = classificarClima(
      horario: _serie(),
      dia: _dia,
      agora: DateTime(2026, 9, 24, 10),
    );
    expect(clima.keys, ['Manhã']);
  });

  // A noite só entra para o turno da noite, e vai até as 6h do dia seguinte.
  test('noite só quando pedida, contando a madrugada seguinte', () {
    final serie = _serie(chuva: (h) => h == 26 ? 3.0 : 0); // 2h do dia 25
    expect(
      classificarClima(horario: serie, dia: _dia, agora: fimDoDia).containsKey('Noite'),
      isFalse,
    );
    final noite = classificarClima(
        horario: serie, dia: _dia, agora: fimDoDia, incluirNoite: true)['Noite']!;
    expect(noite.condicao, 'Chuvoso');
    expect(noite.chuvaMm, 3.0);
  });

  test('nunca sugere Impraticável: isso é decisão do encarregado', () {
    final clima = classificarClima(
      horario: _serie(chuva: (_) => 20, nuvens: (_) => 100, codigo: (_) => 99),
      dia: _dia,
      agora: fimDoDia,
      incluirNoite: true,
    );
    expect(clima.values.map((c) => c.condicao), everyElement('Chuvoso'));
  });
}
