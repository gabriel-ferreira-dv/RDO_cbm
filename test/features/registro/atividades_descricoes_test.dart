import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/atividades_descricoes.dart';
import 'package:namer_app/features/registro/csv_dados_datasource.dart';

// As descrições são encontradas pelo nome EXATO da atividade. Se um nome no
// mapa não bater com o CSV (um acento, um espaço), a descrição nunca apareceria
// — este teste pega isso contra o SevNotaveis.csv real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toda descrição corresponde a uma atividade existente no CSV', () async {
    final linhas = await lerDadosCsv(caminhoCSVdados);
    final atividadesDoCsv =
        linhas.map((l) => l[colAtividade].toString().trim()).toSet();

    for (final nome in descricoesAtividades.keys) {
      expect(atividadesDoCsv, contains(nome),
          reason: 'descrição para "$nome" não casa com nenhuma atividade do CSV');
    }
  });

  test('descricaoDaAtividade devolve o texto certo e null quando não há', () {
    expect(descricaoDaAtividade('Drenagem'), contains('águas pluviais'));
    // O nome antigo, em caixa alta, não pode mais casar: a planilha trocou a
    // taxonomia e a busca é pelo texto exato.
    expect(descricaoDaAtividade('DRENAGEM'), isNull);
    expect(descricaoDaAtividade(null), isNull);
    expect(descricaoDaAtividade('ATIVIDADE INEXISTENTE'), isNull);
  });
}
