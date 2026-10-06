import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/camera/camera_service.dart';

List<String> _blocos({
  String trecho = 'C1',
  String km = '225',
  String via = 'Via 02 Norte',
  String estacaInicial = '1115',
  String estacaFinal = '1120',
  String servico = 'COMPACTAÇÃO DE ATERRO',
  String passo = '',
  String descricao = '',
}) =>
    blocosDoCarimbo(
      trecho: trecho,
      kmtrecho: km,
      via: via,
      estacaInicial: estacaInicial,
      estacaFinal: estacaFinal,
      servNotavel: servico,
      servNotavelDetalhe: passo,
      descricao: descricao,
      dataHora: '24/09/2026 13:10',
      lat: -19.9,
      lon: -40.4,
    );

void main() {
  test('registro comum: trecho, KM com via, estacas e serviço', () {
    final blocos = _blocos(descricao: 'aterro na saia');
    expect(blocos, containsAllInOrder([
      'C1',
      'KM 225 - Via 02 Norte',
      'Est. 1115 - 1120',
      'COMPACTAÇÃO DE ATERRO',
      'Descrição: aterro na saia',
      '24/09/2026 13:10',
    ]));
  });

  // Saía "Descrição:" sozinho na foto quando o campo ficava em branco.
  test('sem descrição não sai a linha "Descrição:"', () {
    expect(_blocos(descricao: '  ').where((b) => b.startsWith('Descrição')), isEmpty);
  });

  // Foto de paralisação sem local: não pode sair um "KM" solto.
  test('sem KM não sai a linha de KM', () {
    final blocos = _blocos(
      trecho: '',
      km: '',
      via: '',
      estacaInicial: '',
      estacaFinal: '',
      servico: 'PARALISAÇÃO - Chuva',
      passo: 'Parado desde 13:10',
    );
    expect(blocos.first, 'PARALISAÇÃO - Chuva');
    expect(blocos.where((b) => b.startsWith('KM')), isEmpty);
    expect(blocos, contains('Parado desde 13:10'));
  });

  test('trecho sem via mostra só o KM', () {
    expect(_blocos(via: ''), contains('KM 225'));
  });
}
