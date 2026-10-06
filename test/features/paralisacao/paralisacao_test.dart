import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/paralisacao/models/paralisacao.dart';

void main() {
  group('descreverParalisacao', () {
    test('encerrada: horário, duração, motivo, local e observação', () {
      expect(
        descreverParalisacao(
          inicio: DateTime(2026, 9, 24, 13, 10),
          fim: DateTime(2026, 9, 24, 15, 40),
          motivo: 'Chuva',
          trecho: 'C1',
          km: '225',
          observacao: 'pista alagada',
        ),
        '13:10 às 15:40 (2h30) - Chuva - C1 / KM 225 - pista alagada',
      );
    });

    test('ainda parado: sem término', () {
      expect(
        descreverParalisacao(
            inicio: DateTime(2026, 9, 24, 13, 10), motivo: 'Falta de material'),
        '13:10 - sem término - Falta de material',
      );
    });

    // Local e observação são opcionais: não pode sobrar separador.
    test('sem local nem observação não deixa traço solto', () {
      expect(
        descreverParalisacao(
          inicio: DateTime(2026, 9, 24, 8),
          fim: DateTime(2026, 9, 24, 8, 45),
          motivo: 'Chuva',
          trecho: ' ',
          observacao: '',
        ),
        '08:00 às 08:45 (45 min) - Chuva',
      );
    });

    test('turno da noite: atravessa a meia-noite', () {
      expect(
        descreverParalisacao(
          inicio: DateTime(2026, 9, 24, 22, 30),
          fim: DateTime(2026, 9, 25, 1),
          motivo: 'Chuva',
        ),
        startsWith('22:30 às 01:00 (2h30)'),
      );
    });

    // A fonte do PDF só desenha Latin-1: travessão ou "•" virariam quadradinho.
    test('cabe no Latin-1 do PDF', () {
      final texto = descreverParalisacao(
        inicio: DateTime(2026, 9, 24, 13, 10),
        fim: DateTime(2026, 9, 24, 15, 40),
        motivo: 'Equipamento quebrado',
        trecho: 'CONTORNO DE FUNDÃO',
        km: '203',
      );
      expect(texto.runes.where((r) => r > 0xFF), isEmpty, reason: texto);
    });
  });

  test('formatarDuracao', () {
    expect(formatarDuracao(const Duration(minutes: 45)), '45 min');
    expect(formatarDuracao(const Duration(hours: 2)), '2h');
    expect(formatarDuracao(const Duration(hours: 2, minutes: 5)), '2h05');
  });

  test('tempoParado soma só as encerradas', () {
    final total = tempoParado([
      (inicio: DateTime(2026, 9, 24, 8), fim: DateTime(2026, 9, 24, 9)),
      (inicio: DateTime(2026, 9, 24, 13), fim: DateTime(2026, 9, 24, 13, 30)),
      (inicio: DateTime(2026, 9, 24, 16), fim: null),
    ]);
    expect(total, const Duration(hours: 1, minutes: 30));
  });

  group('Paralisacao', () {
    final base = Paralisacao(
      id: 3,
      usuarioId: 1,
      motivo: 'Chuva',
      observacao: 'forte',
      trecho: 'D2',
      km: '231',
      inicio: DateTime.utc(2026, 9, 24, 16, 10),
      criadoEm: '2026-09-24T16:10:00.000Z',
    );

    test('ida e volta pelo banco, ainda parada', () {
      final volta = Paralisacao.fromMap(base.toMap());
      expect(volta.motivo, 'Chuva');
      expect(volta.km, '231');
      expect(volta.inicio, base.inicio);
      expect(volta.fim, isNull);
      expect(volta.emAndamento, isTrue);
    });

    test('ida e volta pelo banco, encerrada', () {
      final encerrada = Paralisacao.fromMap({
        ...base.toMap(),
        'fim': DateTime.utc(2026, 9, 24, 18).toIso8601String(),
      });
      expect(encerrada.fim, DateTime.utc(2026, 9, 24, 18));
      expect(encerrada.emAndamento, isFalse);
    });

    // Quem é da noite: a parada da madrugada conta no dia em que o turno começou.
    test('madrugada do turno da noite fica no dia anterior', () {
      final madrugada = Paralisacao(
        usuarioId: 1,
        motivo: 'Chuva',
        inicio: DateTime(2026, 9, 25, 1, 30).toUtc(),
        criadoEm: '',
      );
      expect(madrugada.diaDeTrabalho(noturno: true), DateTime(2026, 9, 24));
      expect(madrugada.diaDeTrabalho(noturno: false), DateTime(2026, 9, 25));
    });
  });

  test('os motivos cobrem chuva e o "Outro"', () {
    expect(motivosParalisacao.first, 'Chuva');
    expect(motivosParalisacao, contains('Outro'));
  });
}
