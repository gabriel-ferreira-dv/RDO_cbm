// Um registro: os campos escolhidos na Home antes da câmera.
class Registro {
  final int? id;
  final int usuarioId;
  final String trecho;
  final String km;

  // KM da estaca final, quando o serviço atravessa o KM; senão vazio.
  final String kmFinal;

  final String via;
  final String atividade;
  final String estacaInicial;
  final String estacaFinal;
  final String servicoNotavel;
  // Passo do serviço; vazio nos registros antigos.
  final String servicoNotavelDetalhe;

  // Quantidade medida do serviço (medição), ou null quando não informada.
  final double? quantidade;

  // Unidade da quantidade ('m³', 'm²', 'm', ...); vazio quando não informada.
  final String unidade;

  // Encarregado em nome de quem o supervisor lançou; vazio no registro comum.
  // O dono passa a ser o encarregado, mas o autor continua registrado.
  final String emNomeDeMatricula;
  final String emNomeDeNome;

  bool get lancadoPorTerceiro => emNomeDeMatricula.isNotEmpty;

  final String descricao;
  final String criadoEm;

  Registro({
    this.id,
    required this.usuarioId,
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
    this.emNomeDeMatricula = '',
    this.emNomeDeNome = '',
    required this.descricao,
    required this.criadoEm,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'usuario_id': usuarioId,
        'trecho': trecho,
        'km': km,
        'km_final': kmFinal,
        'via': via,
        'atividade': atividade,
        'estaca_inicial': estacaInicial,
        'estaca_final': estacaFinal,
        'servico_notavel': servicoNotavel,
        'servico_notavel_detalhe': servicoNotavelDetalhe,
        'quantidade': quantidade,
        'unidade': unidade,
        'em_nome_de_matricula': emNomeDeMatricula,
        'em_nome_de_nome': emNomeDeNome,
        'descricao': descricao,
        'criado_em': criadoEm,
      };

  factory Registro.fromMap(Map<String, dynamic> m) => Registro(
        id: m['id'] as int,
        usuarioId: m['usuario_id'] as int,
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
        emNomeDeMatricula: (m['em_nome_de_matricula'] as String?) ?? '',
        emNomeDeNome: (m['em_nome_de_nome'] as String?) ?? '',
        descricao: (m['descricao'] as String?) ?? '',
        criadoEm: m['criado_em'] as String,
      );
}
