import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/core/utils/date_formatter.dart';

void main() {
  group('formatarData', () {
    test('converte ISO para dd/mm/aaaa', () {
      expect(formatarData('2024-03-05T10:00:00.000Z'), matches(RegExp(r'^\d{2}/\d{2}/2024$')));
    });

    test('retorna a string original quando não é um ISO válido', () {
      expect(formatarData('não é uma data'), 'não é uma data');
    });
  });

  group('diaLocalDe', () {
    test('dois horários do mesmo dia local viram o mesmo DateTime', () {
      // Mesmo dia no fuso local (horas diferentes) → mesma chave de filtro.
      final a = diaLocalDe(DateTime(2024, 3, 5, 8).toUtc().toIso8601String());
      final b = diaLocalDe(DateTime(2024, 3, 5, 17).toUtc().toIso8601String());
      expect(a, isNotNull);
      expect(a, b);
      expect(a!.hour, 0);
    });

    test('retorna null quando não é um ISO válido', () {
      expect(diaLocalDe('não é uma data'), isNull);
    });
  });

  group('formatarDataHora', () {
    test('inclui "às hh:mm" além da data', () {
      expect(formatarDataHora('2024-03-05T10:00:00.000Z'), matches(RegExp(r'^\d{2}/\d{2}/2024 às \d{2}:\d{2}$')));
    });

    test('retorna a string original quando não é um ISO válido', () {
      expect(formatarDataHora('não é uma data'), 'não é uma data');
    });
  });

  group('formatarHora', () {
    test('retorna só hh:mm', () {
      expect(formatarHora('2024-03-05T10:00:00.000Z'), matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('retorna string vazia quando não é um ISO válido', () {
      expect(formatarHora('não é uma data'), '');
    });
  });
}
