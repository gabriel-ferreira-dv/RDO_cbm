import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/relatorio/texto_pdf.dart';

void main() {
  group('textoParaPdf', () {
    // Acento é a maior parte do texto do relatório e cabe no Latin-1: se a
    // limpeza mexesse nele, estragaria todo RDO para consertar um travessão.
    test('acento e símbolo dentro do Latin-1 passam intactos', () {
      const original = 'COMPACTAÇÃO DE ATERRO, 120,5 m³, 3º turno · São Mateus';
      expect(textoParaPdf(original), original);
    });

    test('travessão vira hífen', () {
      expect(textoParaPdf('estaca 32 — 200 m'), 'estaca 32 - 200 m');
      expect(textoParaPdf('estaca 32 – 200 m'), 'estaca 32 - 200 m');
    });

    // O teclado do Android troca aspas retas por curvas sozinho enquanto o
    // encarregado digita a descrição — ele não tem como evitar isso.
    test('aspas curvas e reticências viram o equivalente reto', () {
      expect(textoParaPdf('“bueiro” do ‘lado’'), '"bueiro" do \'lado\'');
      expect(textoParaPdf('aguardando…'), 'aguardando...');
    });

    test('marcador de lista e seta viram ASCII', () {
      expect(textoParaPdf('• limpeza'), '- limpeza');
      expect(textoParaPdf('estaca 10 → 20'), 'estaca 10 -> 20');
    });

    test('emoji some em vez de virar quadradinho', () {
      expect(textoParaPdf('servico concluido 👍'), 'servico concluido ');
    });

    test('texto vazio e texto já limpo não são alterados', () {
      expect(textoParaPdf(''), '');
      expect(textoParaPdf('BUEIRO CELULAR'), 'BUEIRO CELULAR');
    });

    // A garantia que interessa: o que sai daqui a fonte do PDF consegue
    // desenhar. O dart_pdf codifica com latin1.encode, que lança acima de
    // U+00FF — se algo escapasse, o relatório sairia com quadradinho.
    test('o resultado sempre cabe no Latin-1', () {
      const entradas = [
        'estaca 32 — 200 m',
        '“teste” … • → ≤ ≥ 👍 ✅ ℃',
        'COMPACTAÇÃO 120,5 m³',
        'nome com espaço duro e​invisível',
      ];
      for (final entrada in entradas) {
        expect(() => latin1.encode(textoParaPdf(entrada)), returnsNormally,
            reason: 'não caberia no PDF: $entrada');
      }
    });
  });

  group('linhasParaPdf', () {
    test('limpa cada linha e descarta o que ficou vazio', () {
      expect(
        linhasParaPdf(['• Motorista', '👍', '  ', 'Servente — 2']),
        ['- Motorista', 'Servente - 2'],
      );
    });
  });
}
