import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/models/foto_com_contexto.dart';
import 'package:namer_app/features/registro/models/grupo_atividade.dart';

// A medição (quantidade + unidade) por registro é somada por grupo, mas só
// quando as unidades batem — somar m³ com m² seria um número sem sentido.
FotoComContexto _foto({
  required int registroId,
  required int fotoId,
  double? quantidade,
  String unidade = '',
}) =>
    FotoComContexto(
      fotoId: fotoId,
      caminhoArquivo: '/x/$fotoId.jpg',
      fotoCriadoEm: '2026-07-29T12:00:00Z',
      registroId: registroId,
      trecho: 'C1',
      km: '225',
      via: 'Via 02 Norte',
      atividade: 'TERRAPLENAGEM',
      estacaInicial: 'EST. 1115',
      estacaFinal: 'EST. 1120',
      servicoNotavel: 'COMPACTAÇÃO DE ATERRO',
      quantidade: quantidade,
      unidade: unidade,
      descricao: '',
      registroCriadoEm: '2026-07-29T12:00:00Z',
    );

void main() {
  group('formatarQuantidade', () {
    test('remove zeros à direita e usa vírgula decimal', () {
      expect(formatarQuantidade(120), '120');
      expect(formatarQuantidade(12.5), '12,5');
      expect(formatarQuantidade(12.50), '12,5');
      expect(formatarQuantidade(0.25), '0,25');
    });
  });

  group('quantidadeTotal do grupo', () {
    test('soma as quantidades quando a unidade é a mesma', () {
      final grupos = agruparPorAtividade([
        _foto(registroId: 1, fotoId: 1, quantidade: 100, unidade: 'm³'),
        _foto(registroId: 2, fotoId: 2, quantidade: 50.5, unidade: 'm³'),
      ]);
      expect(grupos, hasLength(1));
      final total = grupos.single.quantidadeTotal;
      expect(total, isNotNull);
      expect(total!.total, closeTo(150.5, 0.001));
      expect(total.unidade, 'm³');
    });

    test('não soma quando as unidades divergem', () {
      final grupos = agruparPorAtividade([
        _foto(registroId: 1, fotoId: 1, quantidade: 100, unidade: 'm³'),
        _foto(registroId: 2, fotoId: 2, quantidade: 20, unidade: 'm²'),
      ]);
      expect(grupos.single.quantidadeTotal, isNull);
    });

    test('sem quantidade nenhuma devolve null', () {
      final grupos = agruparPorAtividade([
        _foto(registroId: 1, fotoId: 1),
      ]);
      expect(grupos.single.quantidadeTotal, isNull);
    });

    test('ignora sessões sem quantidade ao somar', () {
      final grupos = agruparPorAtividade([
        _foto(registroId: 1, fotoId: 1, quantidade: 80, unidade: 'm³'),
        _foto(registroId: 2, fotoId: 2), // sem medição
      ]);
      final total = grupos.single.quantidadeTotal;
      expect(total, isNotNull);
      expect(total!.total, closeTo(80, 0.001));
    });
  });
}
