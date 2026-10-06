import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/models/foto_com_contexto.dart';
import 'package:namer_app/features/registro/models/grupo_atividade.dart';

FotoComContexto _foto({
  required int fotoId,
  required int registroId,
  String trecho = 'Trecho A',
  String km = '10',
  String atividade = 'Terraplenagem',
  String servicoNotavel = 'Corte',
}) {
  return FotoComContexto(
    fotoId: fotoId,
    caminhoArquivo: '/fotos/$fotoId.jpg',
    fotoCriadoEm: '2024-01-01T10:00:00.000Z',
    registroId: registroId,
    trecho: trecho,
    km: km,
    via: 'Via 01 Sul',
    atividade: atividade,
    estacaInicial: '0',
    estacaFinal: '100',
    servicoNotavel: servicoNotavel,
    descricao: '',
    registroCriadoEm: '2024-01-01T09:00:00.000Z',
  );
}

void main() {
  test('agrupa fotos do mesmo trecho/km/atividade/serviço num único grupo', () {
    final fotos = [
      _foto(fotoId: 1, registroId: 100),
      _foto(fotoId: 2, registroId: 100),
      _foto(fotoId: 3, registroId: 200),
    ];

    final grupos = agruparPorAtividade(fotos);

    expect(grupos, hasLength(1));
    expect(grupos.first.totalFotos, 3);
    expect(grupos.first.registros, hasLength(2));
  });

  test('separa em grupos diferentes quando trecho/km/atividade/serviço diverge', () {
    final fotos = [
      _foto(fotoId: 1, registroId: 100, trecho: 'Trecho A'),
      _foto(fotoId: 2, registroId: 200, trecho: 'Trecho B'),
    ];

    final grupos = agruparPorAtividade(fotos);

    expect(grupos, hasLength(2));
  });
}
