import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/estaqueamento.dart';
import 'package:namer_app/features/registro/vias_estaqueamento.dart';

// Serviço que começa num KM e termina no seguinte: o encarregado escolhe o
// intervalo de KMs e as listas de estaca mostram as estacas de todo ele.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('faixaDeKm', () {
    test('serviço que começa e acaba no mesmo KM mostra um KM só', () {
      expect(faixaDeKm('231', ''), '231');
      expect(faixaDeKm('231', '231'), '231');
    });

    test('serviço que atravessa mostra o intervalo', () {
      expect(faixaDeKm('231', '232'), '231 a 232');
    });

    test('só espaço conta como vazio', () {
      expect(faixaDeKm('231', '   '), '231');
    });
  });

  group('rotuloComKm', () {
    const estaca = EstacaDoProjeto(
        trecho: 'D2', numero: 62, rotulo: '62', km: '232', via: null);

    test('estaca do KM escolhido aparece só com o número', () {
      expect(rotuloComKm(estaca, '232'), '62');
    });

    test('estaca de outro KM avisa em qual está', () {
      expect(rotuloComKm(estaca, '231'), '62 (KM 232)');
    });
  });

  group('intervalo de KMs', () {
    test('kmNoIntervalo inclui as pontas, em qualquer ordem', () {
      expect(kmNoIntervalo('231', '231', '232'), isTrue);
      expect(kmNoIntervalo('232', '231', '232'), isTrue);
      expect(kmNoIntervalo('233', '231', '232'), isFalse);
      expect(kmNoIntervalo('231', '232', '231'), isTrue);
    });

    test('o KM escolhido vem com dois KMs de cada lado, em ordem numérica',
        () async {
      final estacas =
          await EstaqueamentoService.instancia.doKmEVizinhos('D2', '233');
      expect(estacas.map((e) => e.km).toSet(),
          {'231', '232', '233', '234', '235'});
      final numeros = estacas.map((e) => e.numero).toList();
      expect(numeros, orderedEquals([...numeros]..sort()));
    });

    test('um KM só traz as mesmas estacas do KM', () async {
      final servico = EstaqueamentoService.instancia;
      final doKm = await servico.rotulosDoKm('D2', '231');
      final intervalo = await servico.doIntervalo('D2', '231', '231');
      expect(intervalo.map((e) => e.rotulo), doKm);
    });

    test('dois KMs trazem as estacas dos dois, e só deles', () async {
      final estacas =
          await EstaqueamentoService.instancia.doIntervalo('D2', '231', '232');
      expect(estacas.map((e) => e.km).toSet(), {'231', '232'});
      final numeros = estacas.map((e) => e.numero).toList();
      expect(numeros, orderedEquals([...numeros]..sort()));
    });

    test('em pista dupla a via continua filtrando', () async {
      final servico = EstaqueamentoService.instancia;
      final km = (await servico.todas()).firstWhere((e) => e.trecho == 'C1').km;
      final norte = await servico.doIntervalo('C1', km, km, via: viaNorte);
      expect(norte, isNotEmpty);
      expect(norte.every((e) => e.via == viaNorte || e.via == null), isTrue);
    });
  });
}
