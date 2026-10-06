import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../paralisacao/models/paralisacao.dart';
import '../relatorio/equipe_simova_service.dart';
import '../relatorio/turno_noturno.dart';
import 'equipe_supervisor_service.dart';

// Um registro feito por um encarregado, lido de volta do servidor.
class RegistroDaEquipe {
  final String dispositivoId;
  final int idLocal;
  final String usuarioNome;
  final String usuarioMatricula;
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

  // Quem lançou, quando foi o supervisor; vazio no registro comum.
  final String registradoPorNome;

  final String descricao;
  final DateTime criadoEm;

  const RegistroDaEquipe({
    required this.dispositivoId,
    required this.idLocal,
    required this.usuarioNome,
    required this.usuarioMatricula,
    required this.trecho,
    required this.km,
    this.kmFinal = '',
    required this.via,
    required this.atividade,
    required this.estacaInicial,
    required this.estacaFinal,
    required this.servicoNotavel,
    required this.servicoNotavelDetalhe,
    this.quantidade,
    required this.unidade,
    this.registradoPorNome = '',
    required this.descricao,
    required this.criadoEm,
  });

  factory RegistroDaEquipe.fromMap(Map<String, dynamic> m) => RegistroDaEquipe(
        dispositivoId: (m['dispositivo_id'] as String?) ?? '',
        idLocal: (m['id_local'] as num?)?.toInt() ?? 0,
        usuarioNome: (m['usuario_nome'] as String?) ?? '',
        usuarioMatricula: (m['usuario_matricula'] as String?) ?? '',
        trecho: (m['trecho'] as String?) ?? '',
        km: (m['km'] as String?) ?? '',
        kmFinal: (m['km_final'] as String?) ?? '',
        via: (m['via'] as String?) ?? '',
        atividade: (m['atividade'] as String?) ?? '',
        estacaInicial: (m['estaca_inicial'] as String?) ?? '',
        estacaFinal: (m['estaca_final'] as String?) ?? '',
        servicoNotavel: (m['servico_notavel'] as String?) ?? '',
        servicoNotavelDetalhe: (m['servico_notavel_detalhe'] as String?) ?? '',
        quantidade: (m['quantidade'] as num?)?.toDouble(),
        unidade: (m['unidade'] as String?) ?? '',
        registradoPorNome: (m['registrado_por_nome'] as String?) ?? '',
        descricao: (m['descricao'] as String?) ?? '',
        criadoEm:
            DateTime.tryParse((m['criado_em'] as String?) ?? '')?.toLocal() ??
                DateTime.now(),
      );

  // Chave do registro no servidor — as fotos apontam para ela.
  String get chave => '$dispositivoId|$idLocal';
}

// Uma paralisação de um encarregado, lida do servidor.
class ParalisacaoDaEquipe {
  final String dispositivoId;
  final int idLocal;
  final String usuarioMatricula;
  final String motivo;
  final String observacao;
  final String trecho;
  final String km;
  final DateTime inicio; // local
  final DateTime? fim; // local; null = ainda parado

  const ParalisacaoDaEquipe({
    required this.dispositivoId,
    required this.idLocal,
    required this.usuarioMatricula,
    required this.motivo,
    this.observacao = '',
    this.trecho = '',
    this.km = '',
    required this.inicio,
    this.fim,
  });

  factory ParalisacaoDaEquipe.fromMap(Map<String, dynamic> m) => ParalisacaoDaEquipe(
        dispositivoId: (m['dispositivo_id'] as String?) ?? '',
        idLocal: (m['id_local'] as num?)?.toInt() ?? 0,
        usuarioMatricula: (m['usuario_matricula'] as String?) ?? '',
        motivo: (m['motivo'] as String?) ?? '',
        observacao: (m['observacao'] as String?) ?? '',
        trecho: (m['trecho'] as String?) ?? '',
        km: (m['km'] as String?) ?? '',
        inicio: DateTime.tryParse((m['inicio'] as String?) ?? '')?.toLocal() ??
            DateTime.now(),
        fim: DateTime.tryParse((m['fim'] as String?) ?? '')?.toLocal(),
      );

  String get descricao => descreverParalisacao(
        inicio: inicio,
        fim: fim,
        motivo: motivo,
        trecho: trecho,
        km: km,
        observacao: observacao,
      );
}

// Clima que o encarregado informou no RDO do dia.
class ClimaDaEquipe {
  final String manha;
  final String tarde;
  final String noite;

  const ClimaDaEquipe({this.manha = '', this.tarde = '', this.noite = ''});

  factory ClimaDaEquipe.fromMap(Map<String, dynamic> m) => ClimaDaEquipe(
        manha: (m['clima_manha'] as String?) ?? '',
        tarde: (m['clima_tarde'] as String?) ?? '',
        noite: (m['clima_noite'] as String?) ?? '',
      );

  // "Manhã: Bom  Tarde: Chuvoso"; vazio se nada foi informado.
  String get linha => [
        if (manha.isNotEmpty) 'Manhã: $manha',
        if (tarde.isNotEmpty) 'Tarde: $tarde',
        if (noite.isNotEmpty) 'Noite: $noite',
      ].join('  ');
}

// O dia de um encarregado: registros do app e efetivo apontado.
class ResumoDoEncarregado {
  final EncarregadoDaEquipe encarregado;
  final List<RegistroDaEquipe> registros;
  final List<FuncaoEquipe> efetivo;
  final List<ParalisacaoDaEquipe> paralisacoes;
  final ClimaDaEquipe? clima;

  const ResumoDoEncarregado({
    required this.encarregado,
    required this.registros,
    required this.efetivo,
    this.paralisacoes = const [],
    this.clima,
  });

  int get totalPessoas =>
      efetivo.fold(0, (soma, f) => soma + f.quantidade);

  // Tempo parado nas paralisações encerradas.
  Duration get totalParado =>
      tempoParado([for (final p in paralisacoes) (inicio: p.inicio, fim: p.fim)]);
}

// Lê do servidor o que a equipe do supervisor produziu num dia.
class RegistrosEquipeService {
  RegistrosEquipeService._interno();
  static final RegistrosEquipeService instancia =
      RegistrosEquipeService._interno();

  static const String tabelaRegistros = 'registros_app';
  static const String tabelaFotos = 'fotos_app';
  static const String tabelaParalisacoes = 'paralisacoes_app';
  static const String tabelaFotosParalisacao = 'paralisacao_fotos_app';
  static const String tabelaClima = 'clima_dia_app';
  static const String bucketFotos = 'fotos';

  // Registros e efetivo de cada encarregado no [dia] (quem não apontou também entra).
  Future<List<ResumoDoEncarregado>> buscarDoDia({
    required List<EncarregadoDaEquipe> equipe,
    required DateTime dia,
  }) async {
    if (equipe.isEmpty) return [];

    final registrosPorMatricula = await _registrosDoDia(equipe, dia);
    final paralisacoesPorMatricula = await _paralisacoesDoDia(equipe, dia);
    final climaPorMatricula = await _climaDoDia(equipe, dia);

    final resumos = <ResumoDoEncarregado>[];
    for (final enc in equipe) {
      final resultado = await EquipeSimovaService.instancia
          .buscar(matricula: enc.matricula, dia: dia);
      resumos.add(ResumoDoEncarregado(
        encarregado: enc,
        registros: registrosPorMatricula[enc.matricula] ?? const [],
        efetivo: resultado.equipe ?? const [],
        paralisacoes: paralisacoesPorMatricula[enc.matricula] ?? const [],
        clima: climaPorMatricula[enc.matricula],
      ));
    }
    return resumos;
  }

  // Registros das [matriculas] desde [desde] (null = tudo), do mais antigo
  // ao mais novo; null se a busca falhar. Vem em páginas de 1000, o teto de
  // linhas por consulta do Supabase.
  Future<List<RegistroDaEquipe>?> registrosDoPeriodo(List<String> matriculas,
      {DateTime? desde}) async {
    if (matriculas.isEmpty) return [];
    const pagina = 1000;
    final todos = <RegistroDaEquipe>[];
    try {
      for (var inicio = 0;; inicio += pagina) {
        var consulta = Supabase.instance.client
            .from(tabelaRegistros)
            .select()
            .inFilter('usuario_matricula', matriculas);
        if (desde != null) {
          consulta = consulta.gte('criado_em', desde.toUtc().toIso8601String());
        }
        final linhas = await consulta
            .order('criado_em', ascending: true)
            // Desempate estável: sem ele, uma página repetiria linhas da outra.
            .order('id', ascending: true)
            .range(inicio, inicio + pagina - 1);
        todos.addAll(linhas.map(RegistroDaEquipe.fromMap));
        if (linhas.length < pagina) return todos;
      }
    } catch (e) {
      debugPrint('Busca dos registros do período falhou: $e');
      return null;
    }
  }

  // Paralisações do dia de cada encarregado (turno da noite incluso). Sem a
  // tabela no servidor (SQL não rodado), volta vazio.
  Future<Map<String, List<ParalisacaoDaEquipe>>> _paralisacoesDoDia(
    List<EncarregadoDaEquipe> equipe,
    DateTime dia,
  ) async {
    final alvo = DateTime(dia.year, dia.month, dia.day);
    final fim =
        DateTime(dia.year, dia.month, dia.day + 1, horaViradaTurnoNoturno).toUtc();
    try {
      final linhas = await Supabase.instance.client
          .from(tabelaParalisacoes)
          .select()
          .inFilter('usuario_matricula', [for (final e in equipe) e.matricula])
          .eq('excluida', false)
          .gte('inicio', alvo.toUtc().toIso8601String())
          .lt('inicio', fim.toIso8601String())
          .order('inicio', ascending: true);
      final porMatricula = <String, List<ParalisacaoDaEquipe>>{};
      for (final l in linhas) {
        final p = ParalisacaoDaEquipe.fromMap(l);
        final noturno = TurnoNoturnoService.instancia.ehNoturno(p.usuarioMatricula);
        if (diaDoTurno(p.inicio, noturno: noturno) != alvo) continue;
        porMatricula.putIfAbsent(p.usuarioMatricula, () => []).add(p);
      }
      return porMatricula;
    } catch (e) {
      debugPrint('Busca das paralisações da equipe falhou: $e');
      return {};
    }
  }

  // Clima que cada encarregado informou no RDO do dia.
  Future<Map<String, ClimaDaEquipe>> _climaDoDia(
    List<EncarregadoDaEquipe> equipe,
    DateTime dia,
  ) async {
    final data = '${dia.year.toString().padLeft(4, '0')}-'
        '${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
    try {
      final linhas = await Supabase.instance.client
          .from(tabelaClima)
          .select()
          .inFilter('usuario_matricula', [for (final e in equipe) e.matricula])
          .eq('data', data);
      return {
        for (final l in linhas)
          (l['usuario_matricula'] as String?) ?? '': ClimaDaEquipe.fromMap(l),
      };
    } catch (e) {
      debugPrint('Busca do clima da equipe falhou: $e');
      return {};
    }
  }

  // Caminhos das fotos das paralisações no Storage, por paralisação
  // ("dispositivo|id_local").
  Future<Map<String, List<String>>> caminhosDasFotosDeParalisacao(
      List<ParalisacaoDaEquipe> paralisacoes) async {
    if (paralisacoes.isEmpty) return {};
    try {
      final linhas = await Supabase.instance.client
          .from(tabelaFotosParalisacao)
          .select('dispositivo_id, paralisacao_id_local, caminho_storage')
          .inFilter('dispositivo_id', {for (final p in paralisacoes) p.dispositivoId}.toList())
          .inFilter('paralisacao_id_local', {for (final p in paralisacoes) p.idLocal}.toList())
          .order('id', ascending: true);
      final desejadas = {for (final p in paralisacoes) '${p.dispositivoId}|${p.idLocal}'};
      final porParalisacao = <String, List<String>>{};
      for (final l in linhas) {
        final chave =
            '${l['dispositivo_id']}|${(l['paralisacao_id_local'] as num).toInt()}';
        final caminho = (l['caminho_storage'] as String?) ?? '';
        if (!desejadas.contains(chave) || caminho.isEmpty) continue;
        porParalisacao.putIfAbsent(chave, () => []).add(caminho);
      }
      return porParalisacao;
    } catch (e) {
      debugPrint('Busca das fotos das paralisações falhou: $e');
      return {};
    }
  }

  Future<Map<String, List<RegistroDaEquipe>>> _registrosDoDia(
    List<EncarregadoDaEquipe> equipe,
    DateTime dia,
  ) async {
    // Busca até o meio-dia seguinte, para pegar o turno da noite inteiro; cada
    // registro é conferido abaixo pelo turno do seu encarregado. criado_em
    // está em UTC e o dia é local: converte as bordas.
    final alvo = DateTime(dia.year, dia.month, dia.day);
    final inicio = alvo.toUtc();
    final fim =
        DateTime(dia.year, dia.month, dia.day + 1, horaViradaTurnoNoturno).toUtc();

    try {
      final linhas = await Supabase.instance.client
          .from(tabelaRegistros)
          .select()
          .inFilter('usuario_matricula', [for (final e in equipe) e.matricula])
          .gte('criado_em', inicio.toIso8601String())
          .lt('criado_em', fim.toIso8601String())
          // O padrão do order() é decrescente.
          .order('criado_em', ascending: true);

      final porMatricula = <String, List<RegistroDaEquipe>>{};
      for (final l in linhas) {
        final registro = RegistroDaEquipe.fromMap(l);
        final noturno = TurnoNoturnoService.instancia
            .ehNoturno(registro.usuarioMatricula);
        if (diaDoTurno(registro.criadoEm, noturno: noturno) != alvo) continue;
        porMatricula
            .putIfAbsent(registro.usuarioMatricula, () => [])
            .add(registro);
      }
      return porMatricula;
    } catch (e) {
      debugPrint('Busca de registros da equipe falhou: $e');
      return {};
    }
  }

  // Caminhos das fotos no Storage, por registro ("dispositivo|id_local").
  Future<Map<String, List<String>>> caminhosDasFotos(
      List<RegistroDaEquipe> registros) async {
    if (registros.isEmpty) return {};
    try {
      final dispositivos = {for (final r in registros) r.dispositivoId}.toList();
      final idsLocais = {for (final r in registros) r.idLocal}.toList();
      // Filtra pelo registro também: o limite de 1000 linhas cortava as do dia.
      final linhas = await Supabase.instance.client
          .from(tabelaFotos)
          .select('dispositivo_id, registro_id_local, caminho_storage')
          .inFilter('dispositivo_id', dispositivos)
          .inFilter('registro_id_local', idsLocais)
          .order('id', ascending: true);

      // Só os registros pedidos.
      final desejados = {for (final r in registros) r.chave};
      final porRegistro = <String, List<String>>{};
      for (final l in linhas) {
        final chave =
            '${l['dispositivo_id']}|${(l['registro_id_local'] as num).toInt()}';
        if (!desejados.contains(chave)) continue;
        final caminho = (l['caminho_storage'] as String?) ?? '';
        if (caminho.isEmpty) continue;
        porRegistro.putIfAbsent(chave, () => []).add(caminho);
      }
      return porRegistro;
    } catch (e) {
      debugPrint('Busca dos caminhos das fotos falhou: $e');
      return {};
    }
  }

  // Baixa uma foto do bucket; null se falhar (o relatório sai assim mesmo).
  Future<Uint8List?> baixarFoto(String caminhoStorage) async {
    try {
      return await Supabase.instance.client.storage
          .from(bucketFotos)
          .download(caminhoStorage);
    } catch (e) {
      debugPrint('Download da foto "$caminhoStorage" falhou: $e');
      return null;
    }
  }
}
