import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/core/utils/utm.dart';
import 'package:namer_app/features/registro/sugestao_gps_service.dart';

void main() {
  // Necessário para carregar os CSVs de assets via rootBundle nos testes.
  TestWidgetsFlutterBinding.ensureInitialized();
  // Coordenadas sintéticas: estacas a cada 20 m no eixo N, como no projeto.
  final estacas = [
    EstacaCoordenada(trecho: 'D2', estaca: 'EST. 57', e: 1000, n: 2000),
    EstacaCoordenada(trecho: 'D2', estaca: 'EST. 58', e: 1000, n: 2020),
    EstacaCoordenada(trecho: 'D3', estaca: 'EST. 10', e: 5000, n: 9000),
  ];

  test('encontra a estaca mais próxima e calcula a distância no plano UTM', () {
    final resultado = estacaMaisProxima(1003, 2018, estacas)!;
    expect(resultado.estaca.estaca, 'EST. 58');
    expect(resultado.estaca.trecho, 'D2');
    // sqrt(3² + 2²) ≈ 3,61 m
    expect(resultado.distanciaMetros, closeTo(3.61, 0.01));
  });

  test('considera estacas de outros trechos na busca', () {
    final resultado = estacaMaisProxima(5010, 9005, estacas)!;
    expect(resultado.estaca.estaca, 'EST. 10');
    expect(resultado.estaca.trecho, 'D3');
  });

  test('retorna null quando não há estacas cadastradas', () {
    expect(estacaMaisProxima(0, 0, []), isNull);
  });

  test('formatarDistanciaMetros usa metros abaixo de 1 km e km acima', () {
    expect(formatarDistanciaMetros(35.4), '35 m');
    expect(formatarDistanciaMetros(1500), '1.5 km');
  });

  test('numeroDaEstaca casa formatos diferentes de estaca', () {
    expect(numeroDaEstaca('EST. 57'), '57');
    expect(numeroDaEstaca('57'), '57');
    expect(numeroDaEstaca('sem número'), '');
  });

  test('parseCoordenada aceita os formatos produzidos pelo Excel pt-BR', () {
    expect(parseCoordenada('352584.4440'), closeTo(352584.444, 0.0001));
    expect(parseCoordenada('352584,4440'), closeTo(352584.444, 0.0001));
    expect(parseCoordenada('1.234.567,89'), closeTo(1234567.89, 0.0001));
    // Excel "engoliu" a casa decimal e deixou só pontos de milhar.
    expect(parseCoordenada('3.525.844.440'), closeTo(3525844440, 0.1));
    expect(parseCoordenada('não é número'), isNull);
  });

  test('corrigirEscalaUtm recupera coordenada que perdeu a casa decimal', () {
    // Easting UTM é sempre < 1.000.000; northing < 10.000.000.
    expect(corrigirEscalaUtm(3525844440, 1000000), closeTo(352584.444, 0.001));
    expect(corrigirEscalaUtm(77931694423, 10000000), closeTo(7793169.4423, 0.001));
    // Valores já corretos passam intactos.
    expect(corrigirEscalaUtm(352584.444, 1000000), 352584.444);
  });

  test('sugere estaca com rótulo e KM do KMxEst a partir dos CSVs reais', () async {
    // Coordenada UTM da estaca 60 (D2) do assets/estacas_coords.csv.
    final posicao = utmParaLatLng(352610.3231, 7793072.8977);
    final resultado =
        await SugestaoGpsService.instancia.sugerirParaPosicao(posicao);

    expect(resultado.erro, isNull);
    final s = resultado.sugestao!;
    expect(s.trecho, 'D2');
    // A sugestão devolve o rótulo como está no KMxEst (é o formato que os
    // dropdowns usam); comparamos pelo número para não acoplar o teste ao
    // formato do rótulo ("60" vs "EST. 60").
    expect(numeroDaEstaca(s.estaca), '60');
    // Comparação por dígitos para não acoplar ao formato do rótulo no CSV
    // ("231" vs "KM 231") — o serviço devolve o texto como está no KMxEst.
    expect(numeroDaEstaca(s.km), '231');
    expect(s.distanciaMetros, lessThan(1));
  });
}
