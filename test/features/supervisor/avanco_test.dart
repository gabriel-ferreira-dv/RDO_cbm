import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:namer_app/features/mapa/navegacao_estacas_service.dart';
import 'package:namer_app/features/supervisor/avanco.dart';
import 'package:namer_app/features/supervisor/registros_equipe_service.dart';

// 20 m de latitude, o espaçamento das estacas.
const double _passo = 20 / 111195;

// Estacas 1100 a 1150 do C1 (norte) e 2100 a 2150 (sul), a cada 20 m, e o
// Contorno de Fundão com acento no nome.
final _estacas = agruparEstacasPorTrecho([
  for (var n = 1100; n <= 1150; n++)
    EstacaNavegavel(
      trecho: 'C1',
      km: n < 1125 ? '225' : '226',
      rotulo: '$n',
      numero: n,
      ponto: LatLng(-19.9 + (n - 1100) * _passo, -40.4),
      via: 'Via 02 Norte',
    ),
  for (var n = 2100; n <= 2150; n++)
    EstacaNavegavel(
      trecho: 'C1',
      km: n < 2125 ? '225' : '226',
      rotulo: '$n',
      numero: n,
      ponto: LatLng(-19.9 + (n - 2100) * _passo, -40.3998),
      via: 'Via 01 Sul',
    ),
  for (var n = 1; n <= 10; n++)
    EstacaNavegavel(
      trecho: 'CONTORNO DE FUNDÃO',
      km: '203',
      rotulo: '$n',
      numero: n,
      ponto: LatLng(-19.95 + n * _passo, -40.40),
    ),
]);

RegistroDaEquipe _r({
  String trecho = 'C1',
  String km = '225',
  String via = 'Via 02 Norte',
  String de = '1110',
  String ate = '1110',
  String servico = 'COMPACTAÇÃO DE ATERRO',
  double? quantidade,
  String unidade = '',
  DateTime? quando,
}) =>
    RegistroDaEquipe(
      dispositivoId: 'a',
      idLocal: 1,
      usuarioNome: 'João',
      usuarioMatricula: '045020',
      trecho: trecho,
      km: km,
      via: via,
      atividade: 'TERRAPLENAGEM',
      estacaInicial: de,
      estacaFinal: ate,
      servicoNotavel: servico,
      servicoNotavelDetalhe: '',
      quantidade: quantidade,
      unidade: unidade,
      descricao: '',
      criadoEm: quando ?? DateTime(2026, 9, 20, 10),
    );

void main() {
  group('estacasDoRegistro', () {
    test('pega o intervalo, em ordem, mesmo com as pontas trocadas', () {
      final estacas = estacasDoRegistro(_r(de: '1115', ate: '1112'), _estacas);
      expect(estacas.map((e) => e.numero), [1112, 1113, 1114, 1115]);
    });

    test('lê a estaca escrita como "EST. 1115"', () {
      expect(estacasDoRegistro(_r(de: 'EST. 1115', ate: 'EST. 1116'), _estacas),
          hasLength(2));
    });

    test('casa o trecho sem ligar para acento', () {
      final estacas = estacasDoRegistro(
          _r(trecho: 'Contorno de Fundao', via: '', de: '2', ate: '4'), _estacas);
      expect(estacas, hasLength(3));
    });

    // A série sul (2xxx) fica na outra pista: não se mistura com a norte.
    test('a série sul só pega estacas da pista sul', () {
      final estacas = estacasDoRegistro(
          _r(via: 'Via 01 Sul', de: '2110', ate: '2112'), _estacas);
      expect(estacas.map((e) => e.via).toSet(), {'Via 01 Sul'});
    });

    test('sem estaca ou trecho desconhecido: nada no mapa', () {
      expect(estacasDoRegistro(_r(de: '', ate: ''), _estacas), isEmpty);
      expect(estacasDoRegistro(_r(trecho: 'PÁTIO DE VIGAS'), _estacas), isEmpty);
    });
  });

  group('resumirAvanco', () {
    test('soma a medição por serviço e por KM', () {
      final resumo = resumirAvanco([
        _r(quantidade: 100, unidade: 'm³'),
        _r(quantidade: 50.5, unidade: 'm³'),
        _r(km: '226', de: '1130', ate: '1130', quantidade: 30, unidade: 'm³'),
      ], _estacas);
      final servico = resumo.single;
      expect(servico.quantidades, {'m³': 180.5});
      expect(servico.registros, 3);
      expect(servico.kms.map((k) => k.km), ['225', '226']);
      expect(servico.kms.first.quantidades, {'m³': 150.5});
    });

    test('a extensão vem das estacas: 5 estacas são 80 m', () {
      final resumo = resumirAvanco([_r(de: '1110', ate: '1114')], _estacas);
      expect(resumo.single.metros, closeTo(80, 0.5));
    });

    // Dois lançamentos no mesmo pedaço (uma leva de fotos em cada) não
    // dobram a extensão.
    test('trecho repetido conta uma vez só', () {
      final resumo = resumirAvanco([
        _r(de: '1110', ate: '1114'),
        _r(de: '1112', ate: '1116'),
      ], _estacas);
      expect(resumo.single.metros, closeTo(120, 0.5));
    });

    test('pista sul e norte somam separadas', () {
      final resumo = resumirAvanco([
        _r(de: '1110', ate: '1111'),
        _r(via: 'Via 01 Sul', de: '2110', ate: '2111'),
      ], _estacas);
      expect(resumo.single.metros, closeTo(40, 0.5));
    });

    test('registro sem estaca conta na medição, mas fica fora do mapa', () {
      final resumo = resumirAvanco([
        _r(trecho: 'CANTEIRO INDUSTRIAL', km: '203', de: '', ate: '',
            quantidade: 10, unidade: 'm³'),
      ], _estacas);
      expect(resumo.single.foraDoMapa, 1);
      expect(resumo.single.quantidades, {'m³': 10});
      expect(resumo.single.metros, 0);
    });

    test('o serviço com mais registros vem primeiro', () {
      final resumo = resumirAvanco([
        _r(servico: 'DRENAGEM'),
        _r(servico: 'ESCAVAÇÃO'),
        _r(servico: 'ESCAVAÇÃO'),
      ], _estacas);
      expect(resumo.map((s) => s.servico), ['ESCAVAÇÃO', 'DRENAGEM']);
    });

    test('KM em ordem numérica, não de texto', () {
      final resumo = resumirAvanco([
        _r(km: '99', de: '', ate: ''),
        _r(km: '100', de: '', ate: ''),
      ], _estacas);
      expect(resumo.single.kms.map((k) => k.km), ['99', '100']);
    });
  });

  group('cores dos serviços', () {
    test('o mais frequente vem primeiro; empate em ordem alfabética', () {
      expect(
        servicosPorFrequencia(['DRENAGEM', 'ESCAVAÇÃO', 'ESCAVAÇÃO', 'ATERRO']),
        ['ESCAVAÇÃO', 'ATERRO', 'DRENAGEM'],
      );
    });

    // O mapa do app e o do PDF usam a mesma função: mesma cor nos dois.
    test('a cor segue a posição e dá a volta na paleta', () {
      final servicos = [for (var i = 0; i < coresDeServico.length + 1; i++) 'S$i'];
      expect(corDoServico('S0', servicos), coresDeServico[0]);
      expect(corDoServico('S1', servicos), coresDeServico[1]);
      expect(corDoServico('S${coresDeServico.length}', servicos), coresDeServico[0]);
    });
  });

  test('estacasDoIntervalo serve ao relatório sem precisar do registro', () {
    expect(estacasDoIntervalo('C1', '1110', '1112', _estacas).map((e) => e.numero),
        [1110, 1111, 1112]);
  });

  test('registroRecente: últimos 7 dias', () {
    final agora = DateTime(2026, 9, 24, 12);
    expect(registroRecente(_r(quando: DateTime(2026, 9, 20)), agora), isTrue);
    expect(registroRecente(_r(quando: DateTime(2026, 9, 10)), agora), isFalse);
  });

  test('formatação do resumo', () {
    expect(formatarQuantidades({'m³': 1850, 'm': 20.5}), '1850 m³ + 20,5 m');
    expect(formatarQuantidades({}), isEmpty);
    expect(formatarExtensao(320.4), '320 m');
    expect(formatarExtensao(1234), '1,2 km');
  });
}
