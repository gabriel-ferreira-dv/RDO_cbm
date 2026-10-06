// Clima do RDO por período (justifica paralisação por chuva).
const List<String> periodosClima = ['Manhã', 'Tarde', 'Noite'];
const List<String> condicoesClima = ['Bom', 'Nublado', 'Chuvoso', 'Impraticável'];

// Infos do RDO de um usuário num dia (as atividades vêm dos registros).
class RelatorioDiarioInfo {
  final int? id;
  final int usuarioId;
  final String data; // yyyy-MM-dd, local
  final String encarregado;
  final String equipe;
  final String ddsTema;
  final String horarioInicio;
  final String horarioFim;
  final String maquinasEquipamentos;

  // Condição do tempo por período; vazio quando não informado.
  final String climaManha;
  final String climaTarde;
  final String climaNoite;

  RelatorioDiarioInfo({
    this.id,
    required this.usuarioId,
    required this.data,
    required this.encarregado,
    required this.equipe,
    required this.ddsTema,
    required this.horarioInicio,
    required this.horarioFim,
    required this.maquinasEquipamentos,
    this.climaManha = '',
    this.climaTarde = '',
    this.climaNoite = '',
  });

  // Clima por período, na ordem de [periodosClima], só com os preenchidos.
  List<({String periodo, String condicao})> get climaPorPeriodo => [
        for (final (i, p) in periodosClima.indexed)
          if ([climaManha, climaTarde, climaNoite][i].isNotEmpty)
            (periodo: p, condicao: [climaManha, climaTarde, climaNoite][i]),
      ];

  Map<String, dynamic> toMap() => {
        'id': id,
        'usuario_id': usuarioId,
        'data': data,
        'encarregado': encarregado,
        'equipe': equipe,
        'dds_tema': ddsTema,
        'horario_inicio': horarioInicio,
        'horario_fim': horarioFim,
        'maquinas_equipamentos': maquinasEquipamentos,
        'clima_manha': climaManha,
        'clima_tarde': climaTarde,
        'clima_noite': climaNoite,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      };

  factory RelatorioDiarioInfo.fromMap(Map<String, dynamic> m) => RelatorioDiarioInfo(
        id: m['id'] as int,
        usuarioId: m['usuario_id'] as int,
        data: m['data'] as String,
        encarregado: (m['encarregado'] as String?) ?? '',
        equipe: (m['equipe'] as String?) ?? '',
        ddsTema: (m['dds_tema'] as String?) ?? '',
        horarioInicio: (m['horario_inicio'] as String?) ?? '',
        horarioFim: (m['horario_fim'] as String?) ?? '',
        maquinasEquipamentos: (m['maquinas_equipamentos'] as String?) ?? '',
        climaManha: (m['clima_manha'] as String?) ?? '',
        climaTarde: (m['clima_tarde'] as String?) ?? '',
        climaNoite: (m['clima_noite'] as String?) ?? '',
      );
}
