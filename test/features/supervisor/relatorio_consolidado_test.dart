import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:namer_app/features/relatorio/mapa_do_relatorio.dart';
import 'package:namer_app/features/supervisor/equipe_supervisor_service.dart';
import 'package:namer_app/features/supervisor/registros_equipe_service.dart';
import 'package:namer_app/features/supervisor/relatorio_consolidado_service.dart';

RegistroDaEquipe _registro({
  String servico = 'COMPACTAÇÃO DE ATERRO',
  String passo = '',
  String estacaInicial = 'EST. 1115',
  String estacaFinal = 'EST. 1115',
  String via = 'Via 02 Norte',
  String kmFinal = '',
  double? quantidade,
  String unidade = '',
  int idLocal = 1,
  int hora = 9,
  int minuto = 0,
  String registradoPor = '',
}) =>
    RegistroDaEquipe(
      dispositivoId: 'aparelho-1',
      idLocal: idLocal,
      usuarioNome: 'João',
      usuarioMatricula: '045020',
      trecho: 'C1',
      km: '225',
      kmFinal: kmFinal,
      via: via,
      atividade: 'TERRAPLENAGEM',
      estacaInicial: estacaInicial,
      estacaFinal: estacaFinal,
      servicoNotavel: servico,
      servicoNotavelDetalhe: passo,
      quantidade: quantidade,
      unidade: unidade,
      registradoPorNome: registradoPor,
      descricao: '',
      criadoEm: DateTime(2026, 7, 31, hora, minuto),
    );

void main() {
  group('descreverAtividade', () {
    test('monta a linha com trecho, km, estaca e via', () {
      final texto = descreverAtividade(_registro());
      expect(texto, contains('COMPACTAÇÃO DE ATERRO'));
      expect(texto, contains('C1 / KM 225'));
      expect(texto, contains('estaca EST. 1115'));
      expect(texto, contains('via Via 02 Norte'));
    });

    // Serviço que atravessa o KM: a estaca final está no KM seguinte, e quem
    // lê a medição precisa ver os dois.
    test('serviço que atravessa o KM mostra o intervalo de KM', () {
      expect(descreverAtividade(_registro(kmFinal: '226')),
          contains('C1 / KM 225 a 226'));
      expect(descreverAtividade(_registro()), contains('C1 / KM 225,'));
    });

    // Área de apoio (Canteiro Industrial, Pátio de Vigas) não tem estaca.
    test('registro sem estaca não deixa "estaca" solta na linha', () {
      final texto = descreverAtividade(
          _registro(estacaInicial: '', estacaFinal: '', via: ''));
      expect(texto, isNot(contains('estaca')));
      expect(texto, endsWith('C1 / KM 225.'));
    });

    test('estacas diferentes viram um intervalo', () {
      final texto = descreverAtividade(
          _registro(estacaInicial: 'EST. 1115', estacaFinal: 'EST. 1120'));
      expect(texto, contains('EST. 1115 a EST. 1120'));
    });

    test('inclui o passo e a medição quando existem', () {
      final texto = descreverAtividade(_registro(
          passo: 'Compactação (rolo)', quantidade: 120.5, unidade: 'm³'));
      expect(texto, contains('(Compactação (rolo))'));
      expect(texto, contains('120,5 m³'));
    });

    test('sem medição não deixa sobra de traço na linha', () {
      expect(descreverAtividade(_registro()), endsWith('via Via 02 Norte.'));
    });

    // Trecho de pista simples (o Contorno) grava a via em branco. Sem cuidado,
    // o lugar da via vira um separador solto: "estaca 3 a 32- 200 m".
    test('sem via não sobra separador antes da medida', () {
      expect(descreverAtividade(_registro(via: '')), endsWith('EST. 1115.'));
      expect(
          descreverAtividade(_registro(via: '', quantidade: 200, unidade: 'm')),
          endsWith('EST. 1115 - 200 m.'));
    });

    // A fonte padrão do PDF é Type1 e só codifica Latin-1: um caractere fora
    // dela (o travessão "—", "•", "…", aspas curvas) não é desenhado, vira um
    // quadradinho no relatório impresso. Acentos estão dentro do Latin-1 e
    // passam bem — o problema é só o que passa de U+00FF.
    test('a linha inteira cabe no Latin-1 que a fonte do PDF codifica', () {
      final texto = descreverAtividade(_registro(
        passo: 'Compactação (rolo)',
        quantidade: 120.5,
        unidade: 'm³',
        registradoPor: 'Vagner (supervisor)',
      ));
      final foraDoLatin1 =
          texto.runes.where((r) => r > 0xFF).map((r) => String.fromCharCode(r));
      expect(foraDoLatin1, isEmpty,
          reason: 'sairia como quadradinho no PDF: $texto');
    });

    test('marca o registro lançado pela supervisão', () {
      // A rastreabilidade é o que separa, numa auditoria, o apontamento da
      // própria frente do que a supervisão lançou por ela.
      final texto =
          descreverAtividade(_registro(registradoPor: 'Vagner (supervisor)'));
      expect(texto, contains('lançado por Vagner (supervisor)'));
    });

    test('registro do próprio encarregado não ganha marcação', () {
      expect(descreverAtividade(_registro()), isNot(contains('lançado por')));
    });
  });

  group('listarAtividades', () {
    // O encarregado lança de novo o mesmo serviço a cada leva de fotos, e o
    // relatório repetia a linha inteira só com a hora trocada.
    test('lançamentos iguais viram uma linha só, com o intervalo de horário', () {
      final itens = listarAtividades([
        _registro(idLocal: 1, hora: 15, minuto: 2),
        _registro(idLocal: 2, hora: 15, minuto: 3),
        _registro(idLocal: 3, hora: 15, minuto: 23),
      ]);
      expect(itens, hasLength(1));
      expect(itens.single, startsWith('15:02 a 15:23  COMPACTAÇÃO DE ATERRO'));
    });

    test('lançamento único mostra só a hora', () {
      final itens = listarAtividades([_registro(hora: 7, minuto: 5)]);
      expect(itens.single, startsWith('07:05  COMPACTAÇÃO DE ATERRO'));
    });

    test('o intervalo sai certo com os registros fora de ordem', () {
      final itens = listarAtividades([
        _registro(idLocal: 1, hora: 15, minuto: 23),
        _registro(idLocal: 2, hora: 13, minuto: 15),
      ]);
      expect(itens.single, startsWith('13:15 a 15:23'));
    });

    test('estaca, passo, via ou medição diferente não junta', () {
      final base = _registro(idLocal: 1);
      for (final outro in [
        _registro(idLocal: 2, estacaFinal: 'EST. 1120'),
        _registro(idLocal: 2, passo: 'Espalhamento do material em camadas'),
        _registro(idLocal: 2, via: 'Via 01 Sul'),
        _registro(idLocal: 2, quantidade: 50, unidade: 'm³'),
      ]) {
        expect(listarAtividades([base, outro]), hasLength(2),
            reason: descreverAtividade(outro));
      }
    });

    test('o que a supervisão lançou não se mistura ao do encarregado', () {
      final itens = listarAtividades([
        _registro(idLocal: 1),
        _registro(idLocal: 2, registradoPor: 'João Carlos (supervisor)'),
      ]);
      expect(itens, hasLength(2));
    });

    test('serviços diferentes aparecem separados', () {
      final itens = listarAtividades([
        _registro(idLocal: 1),
        _registro(idLocal: 2, servico: 'ESCAVAÇÃO 3ª CATEGORIA'),
      ]);
      expect(itens, hasLength(2));
      expect(itens.last, contains('ESCAVAÇÃO 3ª CATEGORIA'));
    });

    test('preserva a ordem de chegada dos registros', () {
      final itens = listarAtividades([
        _registro(idLocal: 1, servico: 'PRIMEIRO'),
        _registro(idLocal: 2, servico: 'SEGUNDO'),
      ]);
      expect(itens.first, contains('PRIMEIRO'));
      expect(itens.last, contains('SEGUNDO'));
    });

    test('lista vazia devolve vazio', () {
      expect(listarAtividades([]), isEmpty);
    });
  });

  group('paralisações e clima da equipe', () {
    test('a paralisação lida do servidor vira linha de relatório', () {
      final p = ParalisacaoDaEquipe.fromMap({
        'dispositivo_id': 'aparelho-1',
        'id_local': 4,
        'usuario_matricula': '045020',
        'motivo': 'Chuva',
        'trecho': 'C1',
        'km': '225',
        'observacao': '',
        'inicio': DateTime(2026, 7, 31, 13, 10).toUtc().toIso8601String(),
        'fim': DateTime(2026, 7, 31, 15, 40).toUtc().toIso8601String(),
      });
      expect(p.descricao, '13:10 às 15:40 (2h30) - Chuva - C1 / KM 225');
    });

    test('sem término no servidor = ainda parado', () {
      final p = ParalisacaoDaEquipe.fromMap({
        'motivo': 'Falta de material',
        'inicio': DateTime(2026, 7, 31, 9).toUtc().toIso8601String(),
        'fim': null,
      });
      expect(p.fim, isNull);
      expect(p.descricao, '09:00 - sem término - Falta de material');
    });

    test('o clima só lista os períodos informados', () {
      expect(const ClimaDaEquipe(manha: 'Bom', noite: 'Chuvoso').linha,
          'Manhã: Bom  Noite: Chuvoso');
      expect(const ClimaDaEquipe().linha, isEmpty);
    });

    test('o total parado ignora a que ainda está aberta', () {
      final resumo = ResumoDoEncarregado(
        encarregado: const EncarregadoDaEquipe(matricula: '045020', nome: 'João'),
        registros: const [],
        efetivo: const [],
        paralisacoes: [
          ParalisacaoDaEquipe(
            dispositivoId: 'a',
            idLocal: 1,
            usuarioMatricula: '045020',
            motivo: 'Chuva',
            inicio: DateTime(2026, 7, 31, 8),
            fim: DateTime(2026, 7, 31, 9, 15),
          ),
          ParalisacaoDaEquipe(
            dispositivoId: 'a',
            idLocal: 2,
            usuarioMatricula: '045020',
            motivo: 'Chuva',
            inicio: DateTime(2026, 7, 31, 16),
          ),
        ],
      );
      expect(resumo.totalParado, const Duration(hours: 1, minutes: 15));
    });

    test('gera o PDF com o mapa das atividades da equipe', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final imagem = img.Image(width: 120, height: 70);
      img.fill(imagem, color: img.ColorRgb8(200, 200, 200));
      final bytes = await RelatorioConsolidadoService.instancia.gerar(
        blocos: [
          BlocoEncarregado(
            nome: 'JOÃO',
            matricula: '045020',
            efetivo: const [],
            totalPessoas: 0,
            atividades: listarAtividades([_registro()]),
          ),
        ],
        supervisor: 'Supervisor',
        dataFormatada: '31/07/2026',
        mapa: MapaNoPdf(
          imagem: Uint8List.fromList(img.encodeJpg(imagem)),
          largura: 120,
          altura: 70,
          comSatelite: true,
          legenda: const [(servico: 'COMPACTAÇÃO DE ATERRO', cor: 0xFFE53935)],
        ),
      );
      expect(bytes, isNotEmpty);
    });

    test('gera o PDF com clima e paralisação, mesmo sem atividade', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await RelatorioConsolidadoService.instancia.gerar(
        blocos: const [
          BlocoEncarregado(
            nome: 'ENCARREGADO NA CHUVA',
            matricula: '045020',
            efetivo: [],
            totalPessoas: 0,
            atividades: [],
            clima: 'Manhã: Chuvoso  Tarde: Impraticável',
            paralisacoes: ['07:00 às 12:00 (5h) - Chuva - C1 / KM 225'],
            tempoParado: '5h',
          ),
        ],
        supervisor: 'Supervisor',
        dataFormatada: '31/07/2026',
      );
      expect(bytes, isNotEmpty);
    });
  });

  test('a chave do registro casa foto com registro', () {
    final r = _registro(idLocal: 7);
    expect(r.chave, 'aparelho-1|7');
  });

  // Com mais de 6 fotos (3 linhas), as fotos de um encarregado já não cabem
  // numa página só. Presas dentro de uma Column, travavam a paginação: em
  // debug estourava o limite de páginas, em release gerava páginas em branco
  // sem fim.
  test('gera o PDF quando as fotos de um encarregado ocupam várias páginas',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final imagem = img.Image(width: 1600, height: 1200);
    img.fill(imagem, color: img.ColorRgb8(120, 120, 120));
    final jpeg = Uint8List.fromList(img.encodeJpg(imagem, quality: 70));

    final bytes = await RelatorioConsolidadoService.instancia.gerar(
      blocos: [
        BlocoEncarregado(
          nome: 'ENCARREGADO COM MUITAS FOTOS',
          matricula: '012345',
          efetivo: const ['11 - Servente'],
          totalPessoas: 11,
          // Estacas diferentes: iguais, as 18 virariam uma linha só.
          atividades: listarAtividades([
            for (var i = 1; i <= 18; i++)
              _registro(
                  idLocal: i,
                  estacaInicial: 'EST. ${1100 + i}',
                  estacaFinal: 'EST. ${1100 + i}'),
          ]),
          fotos: [
            for (var i = 1; i <= 60; i++)
              FotoConsolidada(bytes: jpeg, legenda: 'Foto $i'),
          ],
        ),
        const BlocoEncarregado(
          nome: 'ENCARREGADO SEM NADA',
          matricula: '054321',
          efetivo: [],
          totalPessoas: 0,
          atividades: [],
        ),
      ],
      supervisor: 'Supervisor',
      dataFormatada: '31/07/2026',
    );

    expect(bytes, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
