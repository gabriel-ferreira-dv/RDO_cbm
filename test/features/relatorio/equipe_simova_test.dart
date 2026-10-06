import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/relatorio/equipe_simova_service.dart';

// Na tabela `registro_diario` cada pessoa aparece em VÁRIAS linhas por dia
// (uma por operação/interferência apontada) — um encarregado chega a ter 1.400
// linhas para 55 pessoas. A contagem por função tem que deduplicar por
// funcionário, senão a equipe do RDO fica dezenas de vezes maior.
LinhaApontamento _linha(String funcionario, String funcao,
        {String encarregado = '051395::BALTAZAR COSME DA SILVA'}) =>
    LinhaApontamento(
      encarregado: encarregado,
      funcionario: funcionario,
      funcao: funcao,
    );

void main() {
  group('campos "matrícula::NOME"', () {
    test('separa nome e matrícula', () {
      expect(nomeDoCampo('051395::BALTAZAR COSME DA SILVA'),
          'BALTAZAR COSME DA SILVA');
      expect(matriculaDoCampo('051395::BALTAZAR COSME DA SILVA'), '051395');
    });

    test('campo sem separador vira o nome inteiro', () {
      expect(nomeDoCampo('FULANO DE TAL'), 'FULANO DE TAL');
      expect(matriculaDoCampo('FULANO DE TAL'), '');
    });
  });

  group('normalizarNome', () {
    test('ignora caixa, acento e espaço repetido', () {
      expect(normalizarNome('José  da Silva'), normalizarNome('JOSE DA SILVA'));
      expect(normalizarNome('051395::BALTAZAR COSME DA SILVA'),
          normalizarNome('Baltazar Cosme da Silva'));
    });

    test('nomes diferentes não colidem', () {
      expect(normalizarNome('JOAO ESMAEL'), isNot(normalizarNome('JOAO ESMERALDO')));
    });
  });

  group('formatarFuncao', () {
    test('converte caixa alta para caixa mista', () {
      expect(formatarFuncao('57005::MOTORISTA VEIC. PESADOS'),
          'Motorista Veic. Pesados');
      expect(formatarFuncao('MEIO OFICIAL PEDREIRO'), 'Meio Oficial Pedreiro');
    });

    test('preserva algarismo romano e número da função', () {
      expect(formatarFuncao('ENCARREGADO O. CIVIS III'), 'Encarregado O. Civis III');
      expect(formatarFuncao('OPERADOR MAQ. PESADAS 3'), 'Operador Maq. Pesadas 3');
      expect(formatarFuncao('ENCARREGADO TERRAPL. I'), 'Encarregado Terrapl. I');
    });
  });

  group('resumirEquipe', () {
    test('conta cada funcionário uma vez, mesmo com muitas linhas', () {
      // Caso real: a mesma pessoa apontada em 3 operações no dia.
      final linhas = [
        _linha('077560::ELIONALDO DOS SANTOS', '57005::MOTORISTA VEIC. PESADOS'),
        _linha('077560::ELIONALDO DOS SANTOS', '57005::MOTORISTA VEIC. PESADOS'),
        _linha('077560::ELIONALDO DOS SANTOS', '57005::MOTORISTA VEIC. PESADOS'),
        _linha('077603::OSCAR NOGUEIRA MORAIS', '57005::MOTORISTA VEIC. PESADOS'),
        _linha('078895::DANILO LUZ DO NASCIMENTO', '54007::PEDREIRO'),
      ];
      final equipe = resumirEquipe(linhas);

      expect(equipe, hasLength(2));
      expect(equipe.first.funcao, 'Motorista Veic. Pesados');
      expect(equipe.first.quantidade, 2); // e não 4
      expect(equipe.last.funcao, 'Pedreiro');
      expect(equipe.last.quantidade, 1);
    });

    test('ordena da maior equipe para a menor', () {
      final linhas = [
        _linha('1::A', 'PEDREIRO'),
        _linha('2::B', 'SERVENTE'),
        _linha('3::C', 'SERVENTE'),
        _linha('4::D', 'SERVENTE'),
        _linha('5::E', 'ARMADOR'),
        _linha('6::F', 'ARMADOR'),
      ];
      final equipe = resumirEquipe(linhas);
      expect(equipe.map((f) => f.funcao).toList(),
          ['Servente', 'Armador', 'Pedreiro']);
      expect(equipe.map((f) => f.quantidade).toList(), [3, 2, 1]);
    });

    test('ignora função vazia ou "-"', () {
      final linhas = [
        _linha('1::A', '-'),
        _linha('2::B', ''),
        _linha('3::C', 'PEDREIRO'),
      ];
      final equipe = resumirEquipe(linhas);
      expect(equipe, hasLength(1));
      expect(equipe.single.funcao, 'Pedreiro');
    });

    test('sem matrícula, usa o nome para não contar a pessoa duas vezes', () {
      final linhas = [
        _linha('JOAO DA SILVA', 'PEDREIRO'),
        _linha('João da Silva', 'PEDREIRO'),
      ];
      expect(resumirEquipe(linhas).single.quantidade, 1);
    });

    test('lista vazia devolve equipe vazia', () {
      expect(resumirEquipe([]), isEmpty);
    });

    test('a linha sai no formato que o RDO já usa', () {
      final equipe = resumirEquipe([_linha('1::A', 'PEDREIRO')]);
      expect(equipe.single.linha, '1 - Pedreiro');
    });
  });

  group('data do apontamento', () {
    test('dataBr e dataIso montam os dois prefixos possíveis', () {
      expect(dataBr(DateTime(2026, 7, 22)), '22/07/2026');
      expect(dataBr(DateTime(2026, 12, 5)), '05/12/2026');
      expect(dataIso(DateTime(2026, 7, 22)), '2026-07-22');
      expect(dataIso(DateTime(2026, 12, 5)), '2026-12-05');
    });

    test('mesmoDia aceita texto brasileiro e ISO', () {
      final dia = DateTime(2026, 7, 22);
      // Coluna de texto, como no export do sistema corporativo.
      expect(mesmoDia('22/07/2026 07:07', dia), isTrue);
      // Coluna de data/timestamp, que chega ao app em ISO — era o caso que
      // fazia a busca voltar vazia sem explicação.
      expect(mesmoDia('2026-07-22T07:07:00+00:00', dia), isTrue);
      expect(mesmoDia('2026-07-22 07:07:00', dia), isTrue);
    });

    test('mesmoDia rejeita outro dia nos dois formatos', () {
      final dia = DateTime(2026, 7, 22);
      expect(mesmoDia('23/07/2026 07:07', dia), isFalse);
      expect(mesmoDia('2026-07-23T07:07:00+00:00', dia), isFalse);
      // Dia e mês trocados não podem casar por acidente.
      expect(mesmoDia('07/22/2026', dia), isFalse);
    });

    test('diaDoValor normaliza os dois formatos para dd/MM/yyyy', () {
      expect(diaDoValor('22/07/2026 07:07'), '22/07/2026');
      expect(diaDoValor('2026-07-22T07:07:00+00:00'), '22/07/2026');
      expect(diaDoValor('formato desconhecido'), '');
    });
  });

  group('casamento do encarregado pela matrícula', () {
    // É a matrícula que liga o usuário do app ao apontamento — ela é única e
    // não sofre com abreviação, apelido nem erro de digitação no nome.
    const campo = '051395::BALTAZAR COSME DA SILVA';

    test('a matrícula é extraída do campo do apontamento', () {
      expect(matriculaDoCampo(campo), '051395');
    });

    test('matrículas parecidas não se confundem', () {
      expect(matriculaDoCampo('051395::A'), isNot(matriculaDoCampo('05139::B')));
      expect(matriculaDoCampo('077560::A'), isNot(matriculaDoCampo('077603::B')));
    });

    test('zero à esquerda faz parte da matrícula', () {
      // "051395" não pode virar 51395 — a comparação é textual de propósito.
      expect(matriculaDoCampo(campo), '051395');
      expect(matriculaDoCampo(campo), isNot('51395'));
    });

    test('nome abreviado, que quebraria o casamento por nome, não afeta a matrícula', () {
      const abreviado = '051395::BALTAZAR C. DA SILVA';
      expect(matriculaDoCampo(abreviado), matriculaDoCampo(campo));
      expect(normalizarNome(abreviado), isNot(normalizarNome(campo)));
    });
  });
}
