import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/historico/resumo_historico.dart';
import 'package:namer_app/features/registro/models/grupo_atividade.dart';

// Data fixa para os testes: 15/07/2026 ao meio-dia (local).
final _agora = DateTime(2026, 7, 15, 12);

FotoAgrupada _foto(int id) => FotoAgrupada(
      fotoId: id,
      caminhoArquivo: 'foto_$id.jpg',
      criadoEm: _agora.toUtc().toIso8601String(),
    );

RegistroAgrupado _registro(int id, DateTime criadoEm, int fotos) =>
    RegistroAgrupado(
      registroId: id,
      via: 'Via 01 Sul',
      estacaInicial: '57',
      estacaFinal: '60',
      descricao: '',
      criadoEm: criadoEm.toUtc().toIso8601String(),
      fotos: [for (var i = 0; i < fotos; i++) _foto(id * 100 + i)],
    );

GrupoAtividade _grupo(String atividade, List<RegistroAgrupado> registros) =>
    GrupoAtividade(
      trecho: 'D2',
      km: 'KM 231',
      atividade: atividade,
      servicoNotavel: 'SERVIÇO X',
      registros: registros,
    );

void main() {
  test('conta registros e fotos de hoje e dos últimos 7 dias', () {
    final grupos = [
      _grupo('TERRAPLENAGEM', [
        _registro(1, _agora, 3), // hoje
        _registro(2, _agora.subtract(const Duration(days: 3)), 2), // na semana
        _registro(3, _agora.subtract(const Duration(days: 10)), 5), // fora
      ]),
    ];

    final resumo = calcularResumo(grupos, _agora);
    expect(resumo.registrosHoje, 1);
    expect(resumo.fotosHoje, 3);
    expect(resumo.registrosSemana, 2);
    expect(resumo.fotosSemana, 5);
  });

  test('dia 6 dias atrás ainda conta na semana; 7 dias atrás não', () {
    final grupos = [
      _grupo('TERRAPLENAGEM', [
        _registro(1, _agora.subtract(const Duration(days: 6)), 1),
        _registro(2, _agora.subtract(const Duration(days: 7)), 1),
      ]),
    ];

    final resumo = calcularResumo(grupos, _agora);
    expect(resumo.registrosSemana, 1);
  });

  test('aponta a atividade mais frequente da semana', () {
    final grupos = [
      _grupo('TERRAPLENAGEM', [
        _registro(1, _agora, 1),
        _registro(2, _agora.subtract(const Duration(days: 1)), 1),
      ]),
      _grupo('DRENAGEM', [
        _registro(3, _agora, 1),
      ]),
    ];

    final resumo = calcularResumo(grupos, _agora);
    expect(resumo.atividadeMaisFrequente, 'TERRAPLENAGEM');
  });

  test('sem registros na semana, não sugere atividade', () {
    final grupos = [
      _grupo('TERRAPLENAGEM', [
        _registro(1, _agora.subtract(const Duration(days: 30)), 2),
      ]),
    ];

    final resumo = calcularResumo(grupos, _agora);
    expect(resumo.registrosSemana, 0);
    expect(resumo.atividadeMaisFrequente, isNull);
  });

  test('lista vazia devolve tudo zerado', () {
    final resumo = calcularResumo([], _agora);
    expect(resumo.registrosHoje, 0);
    expect(resumo.fotosHoje, 0);
    expect(resumo.registrosSemana, 0);
    expect(resumo.fotosSemana, 0);
    expect(resumo.atividadeMaisFrequente, isNull);
  });
}
