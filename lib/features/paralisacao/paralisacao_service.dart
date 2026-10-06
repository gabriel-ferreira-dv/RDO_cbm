import '../../core/database/db_helper.dart';
import '../relatorio/turno_noturno.dart';
import 'models/paralisacao.dart';

// Foto de uma paralisação, guardada no aparelho.
class FotoParalisacao {
  final int id;
  final String caminhoArquivo;
  final String criadoEm;

  const FotoParalisacao({
    required this.id,
    required this.caminhoArquivo,
    required this.criadoEm,
  });
}

// Grava as paralisações no aparelho. Toda mudança marca a linha como pendente
// de envio; excluir só marca (o servidor precisa saber que ela saiu).
class ParalisacaoService {
  ParalisacaoService._interno();
  static final ParalisacaoService instancia = ParalisacaoService._interno();

  Future<int> salvar(Paralisacao p) async {
    final db = await DbHelper.instancia.database;
    final dados = p.toMap()
      ..remove('id')
      ..['sincronizado'] = 0;
    if (p.id == null) return db.insert('paralisacoes', dados);
    await db.update('paralisacoes', dados, where: 'id = ?', whereArgs: [p.id]);
    return p.id!;
  }

  // Retoma o serviço: fecha a paralisação agora.
  Future<void> encerrar(int id, {DateTime? quando}) async {
    final db = await DbHelper.instancia.database;
    await db.update(
      'paralisacoes',
      {
        'fim': (quando ?? DateTime.now()).toUtc().toIso8601String(),
        'sincronizado': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> excluir(int id) async {
    final db = await DbHelper.instancia.database;
    await db.update('paralisacoes', {'excluida': 1, 'sincronizado': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  // Paralisações do dia de trabalho [dia], na ordem do dia.
  Future<List<Paralisacao>> listarDoDia(int usuarioId, DateTime dia,
      {bool noturno = false}) async {
    final db = await DbHelper.instancia.database;
    final alvo = DateTime(dia.year, dia.month, dia.day);
    // Janela larga (até o meio-dia seguinte, por causa do turno da noite);
    // o dia exato é conferido abaixo.
    final de = alvo.toUtc().toIso8601String();
    final ate = DateTime(alvo.year, alvo.month, alvo.day + 1, horaViradaTurnoNoturno)
        .toUtc()
        .toIso8601String();
    final linhas = await db.query(
      'paralisacoes',
      where: 'usuario_id = ? AND excluida = 0 AND inicio >= ? AND inicio < ?',
      whereArgs: [usuarioId, de, ate],
      orderBy: 'inicio',
    );
    return [
      for (final l in linhas)
        if (Paralisacao.fromMap(l).diaDeTrabalho(noturno: noturno) == alvo)
          Paralisacao.fromMap(l),
    ];
  }

  // Se há paralisação aberta no dia de trabalho atual (o ponto vermelho da aba).
  Future<bool> paradoAgora(int usuarioId, {bool noturno = false}) async {
    final hoje = await listarDoDia(
        usuarioId, diaDoTurno(DateTime.now(), noturno: noturno),
        noturno: noturno);
    return hoje.any((p) => p.emAndamento);
  }

  Future<void> adicionarFoto({
    required int paralisacaoId,
    required String caminhoArquivo,
    double? latitude,
    double? longitude,
  }) async {
    final db = await DbHelper.instancia.database;
    await db.insert('fotos_paralisacao', {
      'paralisacao_id': paralisacaoId,
      'caminho_arquivo': caminhoArquivo,
      'latitude': latitude,
      'longitude': longitude,
      'criado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<FotoParalisacao>> fotosDe(int paralisacaoId) async {
    final db = await DbHelper.instancia.database;
    final linhas = await db.query('fotos_paralisacao',
        where: 'paralisacao_id = ?', whereArgs: [paralisacaoId], orderBy: 'id');
    return [
      for (final l in linhas)
        FotoParalisacao(
          id: l['id'] as int,
          caminhoArquivo: l['caminho_arquivo'] as String,
          criadoEm: l['criado_em'] as String,
        ),
    ];
  }

  // Quantas fotos tem cada paralisação de [ids].
  Future<Map<int, int>> contarFotos(List<int> ids) async {
    if (ids.isEmpty) return {};
    final db = await DbHelper.instancia.database;
    final linhas = await db.rawQuery(
      'SELECT paralisacao_id, COUNT(*) AS n FROM fotos_paralisacao '
      'WHERE paralisacao_id IN (${List.filled(ids.length, '?').join(',')}) '
      'GROUP BY paralisacao_id',
      ids,
    );
    return {
      for (final l in linhas) l['paralisacao_id'] as int: (l['n'] as num).toInt(),
    };
  }

  // Trecho e KM do último registro do dia: sugestão para a paralisação.
  Future<({String trecho, String km})?> ultimoLocalDoDia(int usuarioId) async {
    final db = await DbHelper.instancia.database;
    final hoje = DateTime.now();
    final inicioDoDia =
        DateTime(hoje.year, hoje.month, hoje.day).toUtc().toIso8601String();
    final linhas = await db.query(
      'registros',
      columns: ['trecho', 'km'],
      where: 'usuario_id = ? AND criado_em >= ?',
      whereArgs: [usuarioId, inicioDoDia],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    return (
      trecho: (linhas.first['trecho'] as String?) ?? '',
      km: (linhas.first['km'] as String?) ?? '',
    );
  }
}
