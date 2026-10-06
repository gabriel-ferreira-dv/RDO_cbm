import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/csv_dados_datasource.dart';

// Roda contra o SevNotaveis.csv real do projeto: garante que a cascata
// trecho → atividade → serviço notável → passo continua batendo com a
// planilha depois de qualquer atualização dela.
void main() {
  // Necessário para carregar os CSVs de assets via rootBundle nos testes.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('carregarTrechos lê a coluna Trecho (a 4ª) e não a de passo', () async {
    final trechos = await carregarTrechos();
    expect(trechos, contains('D2'));
    expect(trechos, contains('C1'));
    // Se o índice estivesse errado, viriam passos de serviço na lista.
    expect(trechos.length, lessThan(20));
  });

  test('atividades vêm filtradas pelo trecho e sem repetir', () async {
    final atividades = await carregarAtividades('D2');
    expect(atividades, contains('Terraplanagem'));
    expect(atividades.toSet().length, atividades.length);
  });

  test('serviços notáveis dependem do trecho e da atividade', () async {
    final servicos =
        await carregarServicosNotaveis('D2', 'Terraplanagem');
    expect(servicos, contains('REMOÇÃO DE TUBOS DE CONCRETO'));
    // Serviço de outra atividade não pode vazar para esta lista.
    expect(servicos, isNot(contains('BUEIRO CELULAR')));
  });

  test('passos vêm do serviço escolhido e nunca vazios', () async {
    final passos = await carregarPassosDoServico(
        'C1', 'Drenagem', 'BUEIRO CELULAR');
    expect(passos, contains('Locação topográfica'));
    expect(passos.length, greaterThanOrEqualTo(3));
    expect(passos.any((p) => p.trim().isEmpty), isFalse);
  });

  test('passos respeitam a atividade, não só o serviço', () async {
    // Alguns serviços se repetem em atividades diferentes (COMPACTAÇÃO DE
    // ATERRO está em Terraplanagem no D2). Pedir os passos sob uma atividade
    // onde o serviço não existe tem que vir vazio — é isso que impede a lista
    // de puxar passos de outra atividade caso a planilha passe a divergir.
    final naAtividadeCerta = await carregarPassosDoServico(
        'D2', 'Terraplanagem', 'COMPACTAÇÃO DE ATERRO');
    final naAtividadeErrada = await carregarPassosDoServico(
        'D2', 'Drenagem', 'COMPACTAÇÃO DE ATERRO');

    expect(naAtividadeCerta, isNotEmpty);
    expect(naAtividadeErrada, isEmpty);
  });

  test('passos respeitam o trecho', () async {
    // DESTOCAMENTO DE ÁRVORES, em Terraplanagem, está no Contorno de Fundão e
    // não no D2. (Até a revisão da planilha o exemplo era COMPACTAÇÃO DE
    // ATERRO em Civil, que passou a existir em todos os trechos.)
    const servico = 'DESTOCAMENTO DE ÁRVORES MAIOR QUE Ø30';
    final contorno = await carregarPassosDoServico(
        'CONTORNO DE FUNDÃO', 'Terraplanagem', servico);
    final d2 = await carregarPassosDoServico('D2', 'Terraplanagem', servico);

    expect(contorno, isNotEmpty);
    expect(d2, isEmpty);
  });

  test('combinação inexistente devolve lista vazia em vez de erro', () async {
    final passos = await carregarPassosDoServico(
        'TRECHO QUE NÃO EXISTE', 'DRENAGEM', 'BUEIRO CELULAR');
    expect(passos, isEmpty);
  });
}
