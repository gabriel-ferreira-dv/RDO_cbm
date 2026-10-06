import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/mapa/navegacao_estacas_service.dart';

// Roda contra o KMxEst.csv e o estacas_coords.csv reais: garante que a
// cascata trecho → KM → estaca do mapa continua consistente com as planilhas.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final servico = NavegacaoEstacasService.instancia;

  test('trechos navegáveis são os que têm mapa embutido', () async {
    final trechos = await servico.trechos();
    expect(trechos, containsAll(['C1', 'D2']));
  });

  test('KMs vêm em ordem numérica, não alfabética', () async {
    final kms = await servico.kms('D2');
    expect(kms, isNotEmpty);
    final numeros = kms.map(int.parse).toList();
    final ordenados = [...numeros]..sort();
    expect(numeros, equals(ordenados));
  });

  test('estacas do KM vêm ordenadas e dentro do trecho', () async {
    final kms = await servico.kms('D2');
    final estacas = await servico.estacas('D2', kms.first);

    expect(estacas, isNotEmpty);
    for (final e in estacas) {
      expect(e.trecho, 'D2');
      expect(e.km, kms.first);
      expect(e.rotulo, isNotEmpty);
    }
    final numeros = estacas.map((e) => e.numero).toList();
    final ordenados = [...numeros]..sort();
    expect(numeros, equals(ordenados));
  });

  test('coordenadas caem na região da obra (Espírito Santo)', () async {
    for (final trecho in await servico.trechos()) {
      final kms = await servico.kms(trecho);
      final estacas = await servico.estacas(trecho, kms.first);
      for (final e in estacas) {
        // Se a conversão UTM→WGS84 ou a escala do CSV estivesse errada, o
        // ponto cairia longe daqui e a navegação levaria o usuário ao nada.
        expect(e.ponto.latitude, inInclusiveRange(-21.5, -18.0),
            reason: '${e.rotulo} do $trecho fora da faixa esperada');
        expect(e.ponto.longitude, inInclusiveRange(-41.5, -39.0),
            reason: '${e.rotulo} do $trecho fora da faixa esperada');
      }
    }
  });

  test('KM inexistente devolve lista vazia em vez de erro', () async {
    expect(await servico.estacas('D2', '99999'), isEmpty);
    expect(await servico.kms('TRECHO QUE NÃO EXISTE'), isEmpty);
  });
}
