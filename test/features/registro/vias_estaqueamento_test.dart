import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/csv_dados_datasource.dart';
import 'package:namer_app/features/registro/vias_estaqueamento.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('trechoTemVia', () {
    test('Contorno não pede via; C1 e D2 pedem', () {
      expect(trechoTemVia('CONTORNO DE FUNDÃO'), isFalse);
      expect(trechoTemVia('CONTORNO DE IBIRAÇU'), isFalse);
      // O D2 tem uma série só de estacas e ainda assim é pista dupla: o
      // sentido vem da escolha do encarregado, não da numeração.
      expect(trechoTemVia('D2'), isTrue);
      expect(trechoTemVia('C1'), isTrue);
    });

    test('sem trecho escolhido, o padrão é perguntar', () {
      expect(trechoTemVia(null), isTrue);
    });

    test('acento, caixa e espaço a mais não trazem o campo de volta', () {
      expect(trechoTemVia('contorno de fundao'), isFalse);
      expect(trechoTemVia('  Contorno  de   Ibiraçu '), isFalse);
      // "Ç" decomposto (C + cedilha combinante), como sai de alguns editores.
      // Escrito com escape de propósito: salvo como texto literal, um editor
      // poderia normalizar o arquivo e o caso deixaria de ser testado.
      expect(trechoTemVia('CONTORNO DE IBIRAÇU'), isFalse);
    });
  });

  // O nome do trecho vem das planilhas. Se ele mudar lá — um acento, um
  // "CONTORNO FUNDÃO" sem o "DE" — a lista de trechosSemVia deixa de casar e o
  // campo da via volta a aparecer no Contorno, sem erro nenhum. Este teste lê o
  // CSV real e cobra isso.
  test('todo Contorno das planilhas cai na regra de pista simples', () async {
    final nomes = <String>{};
    for (final caminho in [caminhoCSVkm, caminhoCSVdados]) {
      final linhas = await lerDadosCsv(caminho);
      for (final linha in linhas) {
        // Trecho é a coluna 0 no KMxEst e a última no SevNotaveis.
        for (final indice in [0, colTrecho]) {
          if (linha.length <= indice) continue;
          final valor = linha[indice].toString().trim();
          if (chaveDoTrecho(valor).startsWith('CONTORNO')) nomes.add(valor);
        }
      }
    }

    expect(nomes, isNotEmpty,
        reason: 'nenhum Contorno encontrado nas planilhas — o teste ficaria vazio');
    for (final nome in nomes) {
      expect(trechoTemVia(nome), isFalse,
          reason: '"$nome" está nas planilhas mas ainda pediria a via');
    }
  });
}
