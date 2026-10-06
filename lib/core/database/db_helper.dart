import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// Acesso único ao SQLite local (uma conexão só).
class DbHelper {
  DbHelper._interno();
  static final DbHelper instancia = DbHelper._interno();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _abrirBanco();
    return _db!;
  }

  Future<Database> _abrirBanco() async {
    final caminho = join(await getDatabasesPath(), 'registro_diario.db');
    debugPrint('[DB] Banco SQLite em: $caminho');
    return openDatabase(
      caminho,
      version: 14,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE usuarios (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            senha_hash TEXT NOT NULL,
            matricula TEXT NOT NULL DEFAULT '',
            perfil TEXT NOT NULL DEFAULT '',
            criado_em TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE registros (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            usuario_id INTEGER NOT NULL,
            trecho TEXT NOT NULL,
            km TEXT NOT NULL,
            km_final TEXT NOT NULL DEFAULT '',
            via TEXT NOT NULL,
            atividade TEXT NOT NULL,
            estaca_inicial TEXT NOT NULL,
            estaca_final TEXT NOT NULL,
            servico_notavel TEXT NOT NULL,
            servico_notavel_detalhe TEXT NOT NULL DEFAULT '',
            quantidade REAL,
            unidade TEXT NOT NULL DEFAULT '',
            em_nome_de_matricula TEXT NOT NULL DEFAULT '',
            em_nome_de_nome TEXT NOT NULL DEFAULT '',
            registrado_por_nome TEXT NOT NULL DEFAULT '',
            origem_dispositivo TEXT NOT NULL DEFAULT '',
            origem_id_local INTEGER,
            descricao TEXT,
            criado_em TEXT NOT NULL,
            sincronizado INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
          )
        ''');

        await db.execute('''
          CREATE TABLE fotos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            registro_id INTEGER NOT NULL,
            caminho_arquivo TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            criado_em TEXT NOT NULL,
            sincronizado INTEGER NOT NULL DEFAULT 0,
            origem_dispositivo TEXT NOT NULL DEFAULT '',
            origem_id_local INTEGER,
            FOREIGN KEY (registro_id) REFERENCES registros (id)
          )
        ''');

        await db.execute(_criarTabelaRelatorioDiarioInfo);
        await db.execute(_criarTabelaAvisos);
        await db.execute(_indiceOrigemRegistros);
        await db.execute(_indiceOrigemFotos);
        await _migrarV14(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(_criarTabelaRelatorioDiarioInfo);
        }
        if (oldVersion < 3) {
          // 0 = pendente de envio ao Supabase.
          await db.execute(
              'ALTER TABLE registros ADD COLUMN sincronizado INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE fotos ADD COLUMN sincronizado INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 4) {
          await db.execute(_criarTabelaAvisos);
        }
        if (oldVersion < 5) {
          // Passo do serviço (vazio nos registros antigos).
          await db.execute(
              "ALTER TABLE registros ADD COLUMN servico_notavel_detalhe TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 6) {
          // Medição: quantidade (opcional, pode ser nula) e sua unidade.
          await db.execute('ALTER TABLE registros ADD COLUMN quantidade REAL');
          await db.execute(
              "ALTER TABLE registros ADD COLUMN unidade TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 7) {
          // Clima do RDO por período (manhã/tarde/noite).
          for (final col in ['clima_manha', 'clima_tarde', 'clima_noite']) {
            await db.execute(
                "ALTER TABLE relatorio_diario_info ADD COLUMN $col TEXT NOT NULL DEFAULT ''");
          }
        }
        if (oldVersion < 8) {
          // Matrícula, para achar o encarregado no apontamento.
          await db.execute(
              "ALTER TABLE usuarios ADD COLUMN matricula TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 9) {
          // Perfil do usuário ('supervisor' libera a gestão de equipe).
          await db.execute(
              "ALTER TABLE usuarios ADD COLUMN perfil TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 10) {
          // Lançado pelo supervisor em nome de alguém (vazio = próprio).
          for (final col in ['em_nome_de_matricula', 'em_nome_de_nome']) {
            await db.execute(
                "ALTER TABLE registros ADD COLUMN $col TEXT NOT NULL DEFAULT ''");
          }
        }
        if (oldVersion < 11) {
          // Origem no servidor dos registros baixados de outro aparelho:
          // impede baixar duas vezes e reenviar.
          await db.execute(
              "ALTER TABLE registros ADD COLUMN origem_dispositivo TEXT NOT NULL DEFAULT ''");
          await db.execute(
              'ALTER TABLE registros ADD COLUMN origem_id_local INTEGER');
          await db.execute(
              "ALTER TABLE registros ADD COLUMN registrado_por_nome TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE fotos ADD COLUMN origem_dispositivo TEXT NOT NULL DEFAULT ''");
          await db.execute(
              'ALTER TABLE fotos ADD COLUMN origem_id_local INTEGER');
          await db.execute(_indiceOrigemRegistros);
          await db.execute(_indiceOrigemFotos);
        }
        if (oldVersion < 13) {
          // KM da estaca final, quando o serviço atravessa o KM.
          await db.execute(
              "ALTER TABLE registros ADD COLUMN km_final TEXT NOT NULL DEFAULT ''");
        }
        // A v12 não tem migração: a limpeza que ela fazia foi removida.
        if (oldVersion < 14) await _migrarV14(db);
      },
    );
  }
}

// Paralisações com fotos, e o clima do RDO passa a subir para o servidor.
Future<void> _migrarV14(Database db) async {
  await db.execute(
      'ALTER TABLE relatorio_diario_info ADD COLUMN sincronizado INTEGER NOT NULL DEFAULT 0');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS paralisacoes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      motivo TEXT NOT NULL,
      observacao TEXT NOT NULL DEFAULT '',
      trecho TEXT NOT NULL DEFAULT '',
      km TEXT NOT NULL DEFAULT '',
      inicio TEXT NOT NULL,
      fim TEXT,
      excluida INTEGER NOT NULL DEFAULT 0,
      criado_em TEXT NOT NULL,
      sincronizado INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS fotos_paralisacao (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      paralisacao_id INTEGER NOT NULL,
      caminho_arquivo TEXT NOT NULL,
      latitude REAL,
      longitude REAL,
      criado_em TEXT NOT NULL,
      sincronizado INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (paralisacao_id) REFERENCES paralisacoes (id)
    )
  ''');
}

// Origem única: uma nova sincronização não duplica o que já foi baixado.
const _indiceOrigemRegistros = '''
  CREATE UNIQUE INDEX IF NOT EXISTS idx_registros_origem
    ON registros (origem_dispositivo, origem_id_local)
    WHERE origem_dispositivo <> ''
''';

const _indiceOrigemFotos = '''
  CREATE UNIQUE INDEX IF NOT EXISTS idx_fotos_origem
    ON fotos (origem_dispositivo, origem_id_local)
    WHERE origem_dispositivo <> ''
''';

// Histórico de atualizações de mapas e dados (tela de Atualizações).
const _criarTabelaAvisos = '''
  CREATE TABLE IF NOT EXISTS avisos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    titulo TEXT NOT NULL,
    corpo TEXT NOT NULL,
    criado_em TEXT NOT NULL
  )
''';

// Infos do RDO: uma linha por usuário e dia.
const _criarTabelaRelatorioDiarioInfo = '''
  CREATE TABLE IF NOT EXISTS relatorio_diario_info (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    usuario_id INTEGER NOT NULL,
    data TEXT NOT NULL,
    encarregado TEXT,
    equipe TEXT,
    dds_tema TEXT,
    horario_inicio TEXT,
    horario_fim TEXT,
    maquinas_equipamentos TEXT,
    clima_manha TEXT NOT NULL DEFAULT '',
    clima_tarde TEXT NOT NULL DEFAULT '',
    clima_noite TEXT NOT NULL DEFAULT '',
    atualizado_em TEXT NOT NULL,
    UNIQUE (usuario_id, data),
    FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
  )
''';
