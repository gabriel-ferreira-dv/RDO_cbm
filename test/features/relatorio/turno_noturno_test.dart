import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/relatorio/turno_noturno.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  DateTime dia(int d, [int m = 9]) => DateTime(2026, m, d);

  group('diaDoTurno', () {
    test('turno do dia segue o calendário', () {
      expect(diaDoTurno(DateTime(2026, 9, 24, 1, 30), noturno: false), dia(24));
      expect(diaDoTurno(DateTime(2026, 9, 24, 17), noturno: false), dia(24));
    });

    // O caso que motivou a regra: 17h às 2h, relatório gerado às 2h.
    test('turno da noite fica inteiro no dia em que começou', () {
      expect(diaDoTurno(DateTime(2026, 9, 23, 17), noturno: true), dia(23));
      expect(diaDoTurno(DateTime(2026, 9, 23, 23, 59), noturno: true), dia(23));
      expect(diaDoTurno(DateTime(2026, 9, 24, 0, 10), noturno: true), dia(23));
      expect(diaDoTurno(DateTime(2026, 9, 24, 2), noturno: true), dia(23));
    });

    test('a virada é ao meio-dia', () {
      expect(diaDoTurno(DateTime(2026, 9, 24, 11, 59), noturno: true), dia(23));
      expect(diaDoTurno(DateTime(2026, 9, 24, 12), noturno: true), dia(24));
    });

    test('madrugada do dia 1º volta para o fim do mês anterior', () {
      expect(diaDoTurno(DateTime(2026, 10, 1, 1), noturno: true), dia(30, 9));
    });
  });

  group('TurnoNoturnoService', () {
    test('reconhece a matrícula guardada no aparelho', () async {
      SharedPreferences.setMockInitialValues({
        'matriculas_turno_noturno': ['051395'],
      });
      final servico = TurnoNoturnoService.instancia;
      await servico.carregarDoAparelho();

      expect(servico.ehNoturno('051395'), isTrue);
      expect(servico.ehNoturno(' 051395 '), isTrue);
      expect(servico.ehNoturno('051396'), isFalse);
      expect(servico.ehNoturno(''), isFalse);
    });
  });
}
