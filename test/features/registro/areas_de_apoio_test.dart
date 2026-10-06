import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/vias_estaqueamento.dart';

// Canteiro Industrial e Pátio de Vigas são áreas de apoio: não têm via nem
// estaca de projeto, e o formulário não pergunta nenhuma das duas.
void main() {
  test('áreas de apoio não pedem via nem estaca', () {
    for (final trecho in ['CANTEIRO INDUSTRIAL', 'PÁTIO DE VIGAS']) {
      expect(trechoTemVia(trecho), isFalse, reason: trecho);
      expect(trechoTemEstaca(trecho), isFalse, reason: trecho);
    }
  });

  test('o nome é comparado sem acento nem caixa', () {
    expect(trechoTemEstaca('Pátio de Vigas'), isFalse);
    expect(trechoTemEstaca('PATIO DE VIGAS'), isFalse);
  });

  test('os trechos da obra continuam pedindo estaca', () {
    for (final trecho in ['D2', 'C1', 'CONTORNO DE FUNDÃO', 'CONTORNO DE IBIRAÇU']) {
      expect(trechoTemEstaca(trecho), isTrue, reason: trecho);
    }
    expect(trechoTemEstaca(null), isTrue);
  });
}
