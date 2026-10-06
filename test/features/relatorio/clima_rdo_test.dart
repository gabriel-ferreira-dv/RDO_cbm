import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/relatorio/models/relatorio_diario_info.dart';

// O clima do RDO é por período; só os períodos preenchidos entram no PDF, na
// ordem manhã → tarde → noite.
RelatorioDiarioInfo _info({
  String manha = '',
  String tarde = '',
  String noite = '',
}) =>
    RelatorioDiarioInfo(
      usuarioId: 1,
      data: '2026-07-29',
      encarregado: 'Fulano',
      equipe: '',
      ddsTema: '',
      horarioInicio: '07:00',
      horarioFim: '17:00',
      maquinasEquipamentos: '',
      climaManha: manha,
      climaTarde: tarde,
      climaNoite: noite,
    );

void main() {
  test('lista só os períodos preenchidos, na ordem certa', () {
    final clima = _info(manha: 'Bom', noite: 'Chuvoso').climaPorPeriodo;
    expect(clima.map((c) => c.periodo).toList(), ['Manhã', 'Noite']);
    expect(clima.first.condicao, 'Bom');
    expect(clima.last.condicao, 'Chuvoso');
  });

  test('sem clima informado devolve lista vazia', () {
    expect(_info().climaPorPeriodo, isEmpty);
  });

  test('sobrevive ao ida-e-volta pelo toMap/fromMap', () {
    final original = _info(manha: 'Nublado', tarde: 'Impraticável');
    // fromMap lê linhas do banco, onde o id sempre existe.
    final mapa = original.toMap()..['id'] = 1;
    final volta = RelatorioDiarioInfo.fromMap(mapa);
    expect(volta.climaManha, 'Nublado');
    expect(volta.climaTarde, 'Impraticável');
    expect(volta.climaNoite, '');
  });

  test('as condições oferecidas cobrem tempo bom e paralisação', () {
    expect(condicoesClima, contains('Bom'));
    expect(condicoesClima, contains('Impraticável'));
  });
}
