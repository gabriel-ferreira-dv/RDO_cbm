// Linha achatada do JOIN entre fotos e registros: uma foto com os dados do
// registro ao qual ela pertence. Somente leitura — nunca é inserida no banco.
class FotoComContexto {
  final int fotoId;
  final String caminhoArquivo;
  final double? latitude;
  final double? longitude;
  final String fotoCriadoEm;

  final int registroId;
  final String trecho;
  final String km;

  // KM da estaca final quando o serviço atravessa o KM; vazio quando não.
  final String kmFinal;

  final String via;
  final String atividade;
  final String estacaInicial;
  final String estacaFinal;
  final String servicoNotavel;
  final String servicoNotavelDetalhe;
  final double? quantidade;
  final String unidade;
  final String emNomeDeNome;

  // Quem lançou, quando o registro veio de outro aparelho (o supervisor
  // apontando em nome deste encarregado). Vazio no registro próprio.
  final String registradoPorNome;

  final String descricao;
  final String registroCriadoEm;

  FotoComContexto({
    required this.fotoId,
    required this.caminhoArquivo,
    this.latitude,
    this.longitude,
    required this.fotoCriadoEm,
    required this.registroId,
    required this.trecho,
    required this.km,
    this.kmFinal = '',
    required this.via,
    required this.atividade,
    required this.estacaInicial,
    required this.estacaFinal,
    required this.servicoNotavel,
    this.servicoNotavelDetalhe = '',
    this.quantidade,
    this.unidade = '',
    this.emNomeDeNome = '',
    this.registradoPorNome = '',
    required this.descricao,
    required this.registroCriadoEm,
  });

  factory FotoComContexto.fromMap(Map<String, dynamic> m) => FotoComContexto(
        fotoId: m['foto_id'] as int,
        caminhoArquivo: m['caminho_arquivo'] as String,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        fotoCriadoEm: m['foto_criado_em'] as String,
        registroId: m['registro_id'] as int,
        trecho: m['trecho'] as String,
        km: m['km'] as String,
        kmFinal: (m['km_final'] as String?) ?? '',
        via: m['via'] as String,
        atividade: m['atividade'] as String,
        estacaInicial: m['estaca_inicial'] as String,
        estacaFinal: m['estaca_final'] as String,
        servicoNotavel: m['servico_notavel'] as String,
        servicoNotavelDetalhe: (m['servico_notavel_detalhe'] as String?) ?? '',
        quantidade: (m['quantidade'] as num?)?.toDouble(),
        unidade: (m['unidade'] as String?) ?? '',
        emNomeDeNome: (m['em_nome_de_nome'] as String?) ?? '',
        registradoPorNome: (m['registrado_por_nome'] as String?) ?? '',
        descricao: (m['descricao'] as String?) ?? '',
        registroCriadoEm: m['registro_criado_em'] as String,
      );
}
