import '../../core/database/db_helper.dart';

// Um aviso de atualização registrado no aparelho (mapa/dados baixados).
class Aviso {
  final int id;
  final String titulo;
  final String corpo;
  final String criadoEm;

  const Aviso({
    required this.id,
    required this.titulo,
    required this.corpo,
    required this.criadoEm,
  });
}

// Histórico local dos avisos de atualização exibido na AvisosPage. Guarda
// SÓ atualizações concluídas de mapa/dados do projeto — lembretes diários e
// mensagens do gestor não entram aqui.
class AvisosService {
  AvisosService._interno();
  static final AvisosService instancia = AvisosService._interno();

  Future<void> registrar(String titulo, String corpo) async {
    final db = await DbHelper.instancia.database;
    await db.insert('avisos', {
      'titulo': titulo,
      'corpo': corpo,
      'criado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // Todos os avisos, do mais recente para o mais antigo.
  Future<List<Aviso>> listar() async {
    final db = await DbHelper.instancia.database;
    final linhas = await db.query('avisos', orderBy: 'id DESC');
    return [
      for (final l in linhas)
        Aviso(
          id: l['id'] as int,
          titulo: l['titulo'] as String,
          corpo: l['corpo'] as String,
          criadoEm: l['criado_em'] as String,
        ),
    ];
  }
}
