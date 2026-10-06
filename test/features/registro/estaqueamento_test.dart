import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/estaqueamento.dart';
import 'package:namer_app/features/registro/vias_estaqueamento.dart';

// C1 é pista dupla: a série 1000 é a Via 02 Norte e a série 2000 é a Via 01
// Sul, com a estaca 2115 ao lado da 1115. D2 é pista simples e usa uma série
// só. Estes testes rodam contra o KMxEst.csv e o estacas_coords.csv reais.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final servico = EstaqueamentoService.instancia;

  group('regras de numeração', () {
    test('série sul começa na estaca 2000', () {
      expect(estacaDaSerieSul(1999), isFalse);
      expect(estacaDaSerieSul(2000), isTrue);
      expect(estacaDaSerieSul(2115), isTrue);
    });

    test('gêmeas são deslocadas de 1000', () {
      expect(gemeaNaSerieSul(1115), 2115);
      expect(gemeaNaSerieNorte(2115), 1115);
      expect(gemeaNaSerieNorte(1115), isNull);
    });

    test('via só é deduzida em pista dupla', () {
      expect(viaDaEstaca(2115, pistaDupla: true), viaSul);
      expect(viaDaEstaca(1115, pistaDupla: true), viaNorte);
      expect(viaDaEstaca(115, pistaDupla: false), isNull);
    });
  });

  group('estacas do projeto', () {
    test('C1 ganha a série sul derivada das gêmeas do norte', () async {
      final todas = await servico.todas();
      final c1 = todas.where((e) => e.trecho == 'C1');
      final norte = c1.where((e) => e.via == viaNorte).toList();
      final sul = c1.where((e) => e.via == viaSul).toList();

      expect(norte, isNotEmpty);
      // Toda estaca do norte tem a correspondente no sul, com o mesmo KM.
      expect(sul.length, norte.length);
      final kmSulPorNumero = {for (final e in sul) e.numero: e.km};
      for (final e in norte) {
        expect(kmSulPorNumero[gemeaNaSerieSul(e.numero)], e.km,
            reason: 'estaca ${e.numero} e sua gêmea deveriam ter o mesmo KM');
      }
    });

    test('D2 é pista simples: nenhuma estaca recebe via', () async {
      final todas = await servico.todas();
      final d2 = todas.where((e) => e.trecho == 'D2');
      expect(d2, isNotEmpty);
      expect(d2.every((e) => e.via == null), isTrue);
    });

    test('no C1 a via filtra a lista de estacas do KM', () async {
      final norte = await servico.rotulosDoKm('C1', '225', via: viaNorte);
      final sul = await servico.rotulosDoKm('C1', '225', via: viaSul);

      expect(norte, isNotEmpty);
      expect(sul, isNotEmpty);
      // Nenhuma estaca aparece nas duas listas — era exatamente o problema:
      // a 1115 e a 2115 são pontos diferentes, em pistas diferentes.
      expect(norte.toSet().intersection(sul.toSet()), isEmpty);
      expect(norte.every((r) => int.parse(r) < inicioSerieSul), isTrue);
      expect(sul.every((r) => int.parse(r) >= inicioSerieSul), isTrue);
    });

    test('no D2 a via não muda a lista (pista simples)', () async {
      final norte = await servico.rotulosDoKm('D2', '235', via: viaNorte);
      final sul = await servico.rotulosDoKm('D2', '235', via: viaSul);
      expect(norte, isNotEmpty);
      expect(sul, equals(norte));
    });

    test('estacas saem em ordem crescente', () async {
      final sul = await servico.rotulosDoKm('C1', '225', via: viaSul);
      final numeros = sul.map(int.parse).toList();
      expect(numeros, equals([...numeros]..sort()));
    });

    test('KM inexistente devolve lista vazia', () async {
      expect(await servico.rotulosDoKm('C1', '99999', via: viaSul), isEmpty);
    });
  });
}
