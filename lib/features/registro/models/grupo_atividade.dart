import 'foto_com_contexto.dart';

// Uma foto pronta para exibir, com hora e coordenadas.
class FotoAgrupada {
  final int fotoId;
  final String caminhoArquivo;
  final double? latitude;
  final double? longitude;
  final String criadoEm;

  FotoAgrupada({
    required this.fotoId,
    required this.caminhoArquivo,
    this.latitude,
    this.longitude,
    required this.criadoEm,
  });
}

// Um registro do grupo (via, estacas e descrição variam por registro).
class RegistroAgrupado {
  final int registroId;
  final String via;
  final String estacaInicial;
  final String estacaFinal;
  final double? quantidade;
  final String unidade;

  // Encarregado em nome de quem o registro foi lançado; vazio no caso comum.
  final String emNomeDeNome;

  // Quem lançou este registro por mim; vazio quando fui eu mesmo.
  final String registradoPorNome;

  final String descricao;
  final String criadoEm;
  final List<FotoAgrupada> fotos;

  RegistroAgrupado({
    required this.registroId,
    required this.via,
    required this.estacaInicial,
    required this.estacaFinal,
    this.quantidade,
    this.unidade = '',
    this.emNomeDeNome = '',
    this.registradoPorNome = '',
    required this.descricao,
    required this.criadoEm,
    required this.fotos,
  });
}

// Registros com o mesmo trecho, KM, atividade, serviço e passo.
class GrupoAtividade {
  final String trecho;
  final String km;

  // KM da estaca final quando o serviço atravessa o KM; vazio quando não.
  final String kmFinal;

  final String atividade;
  final String servicoNotavel;
  final String servicoNotavelDetalhe;
  final List<RegistroAgrupado> registros;

  GrupoAtividade({
    required this.trecho,
    required this.km,
    this.kmFinal = '',
    required this.atividade,
    required this.servicoNotavel,
    this.servicoNotavelDetalhe = '',
    required this.registros,
  });

  int get totalFotos => registros.fold(0, (soma, r) => soma + r.fotos.length);

  // Soma das quantidades, só quando todas usam a mesma unidade; senão null.
  ({double total, String unidade})? get quantidadeTotal {
    final comQuantidade =
        registros.where((r) => r.quantidade != null && r.unidade.isNotEmpty);
    if (comQuantidade.isEmpty) return null;
    final unidades = comQuantidade.map((r) => r.unidade).toSet();
    if (unidades.length != 1) return null;
    final total = comQuantidade.fold(0.0, (s, r) => s + r.quantidade!);
    return (total: total, unidade: unidades.first);
  }
}

// 120 → "120"; 12.5 → "12,5".
String formatarQuantidade(double valor) {
  final texto = valor.toStringAsFixed(2);
  return texto
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

// Agrupa as fotos por trecho, KM, atividade, serviço e passo, mantendo a ordem.
List<GrupoAtividade> agruparPorAtividade(List<FotoComContexto> fotos) {
  final gruposPorChave = <String, List<FotoComContexto>>{};
  for (final f in fotos) {
    final chave = '${f.trecho}|${f.km}|${f.kmFinal}|${f.atividade}'
        '|${f.servicoNotavel}|${f.servicoNotavelDetalhe}';
    gruposPorChave.putIfAbsent(chave, () => []).add(f);
  }

  final grupos = <GrupoAtividade>[];
  for (final fotosDoGrupo in gruposPorChave.values) {
    final registrosPorId = <int, RegistroAgrupado>{};
    for (final f in fotosDoGrupo) {
      final registro = registrosPorId.putIfAbsent(
        f.registroId,
        () => RegistroAgrupado(
          registroId: f.registroId,
          via: f.via,
          estacaInicial: f.estacaInicial,
          estacaFinal: f.estacaFinal,
          quantidade: f.quantidade,
          unidade: f.unidade,
          emNomeDeNome: f.emNomeDeNome,
          registradoPorNome: f.registradoPorNome,
          descricao: f.descricao,
          criadoEm: f.registroCriadoEm,
          fotos: [],
        ),
      );
      registro.fotos.add(FotoAgrupada(
        fotoId: f.fotoId,
        caminhoArquivo: f.caminhoArquivo,
        latitude: f.latitude,
        longitude: f.longitude,
        criadoEm: f.fotoCriadoEm,
      ));
    }

    final primeira = fotosDoGrupo.first;
    grupos.add(GrupoAtividade(
      trecho: primeira.trecho,
      km: primeira.km,
      kmFinal: primeira.kmFinal,
      atividade: primeira.atividade,
      servicoNotavel: primeira.servicoNotavel,
      servicoNotavelDetalhe: primeira.servicoNotavelDetalhe,
      registros: registrosPorId.values.toList(),
    ));
  }
  return grupos;
}
