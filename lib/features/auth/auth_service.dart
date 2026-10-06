import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/database/db_helper.dart';
import 'models/usuario.dart';

// Login online pelo Supabase (a recusa do servidor nunca cai para o local) e,
// sem rede, pela cópia local da última senha que valeu online. Conta antiga
// só-local é criada no servidor no primeiro login online.
class AuthService {
  AuthService._interno();
  static final AuthService instancia = AuthService._interno();

  static const _chaveSessao = 'usuario_logado_id';

  Usuario? usuarioLogado;

  // O servidor não reconhece mais a sessão: matrícula e perfil param de
  // atualizar, e a tela pede novo login.
  bool sessaoPrecisaRenovar = false;

  String _hashSenha(String senha) {
    return sha256.convert(utf8.encode(senha)).toString();
  }

  // Cliente Supabase; null se o initialize falhou (o app segue local).
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> _salvarSessao(int usuarioId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chaveSessao, usuarioId);
  }

  // Atualiza a cópia local do usuário mantendo o id (os registros apontam para ele).
  Future<Usuario> _salvarUsuarioLocal(String nome, String email, String senha,
      {String matricula = '', String perfil = ''}) async {
    final db = await DbHelper.instancia.database;
    final hash = _hashSenha(senha);
    final existente = await db.query('usuarios', where: 'email = ?', whereArgs: [email]);
    if (existente.isNotEmpty) {
      final atual = Usuario.fromMap(existente.first);
      // Matrícula vazia do servidor não apaga a local; o perfil sempre é
      // sobrescrito, para a revogação valer.
      final matriculaFinal = matricula.isNotEmpty ? matricula : atual.matricula;
      await db.update(
        'usuarios',
        {
          'nome': nome,
          'senha_hash': hash,
          'matricula': matriculaFinal,
          'perfil': perfil,
        },
        where: 'id = ?',
        whereArgs: [atual.id],
      );
      return Usuario(
        id: atual.id,
        nome: nome,
        email: email,
        senhaHash: hash,
        matricula: matriculaFinal,
        perfil: perfil,
        criadoEm: atual.criadoEm,
      );
    }

    final criadoEm = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('usuarios', {
      'nome': nome,
      'email': email,
      'senha_hash': hash,
      'matricula': matricula,
      'perfil': perfil,
      'criado_em': criadoEm,
    });
    return Usuario(
      id: id,
      nome: nome,
      email: email,
      senhaHash: hash,
      matricula: matricula,
      perfil: perfil,
      criadoEm: criadoEm,
    );
  }

  // Relê matrícula e perfil do servidor e renova o token (o RLS lê a
  // matrícula de dentro dele). Sem rede, devolve o que está no aparelho.
  Future<Usuario?> sincronizarPerfil() async {
    final atual = usuarioLogado;
    final supabase = _supabase;
    if (supabase == null || atual?.id == null) return atual;
    try {
      final resposta = await supabase.auth.refreshSession();
      final metadata = resposta.user?.userMetadata;
      if (metadata == null) return atual;

      final matricula = (metadata['matricula'] as String?)?.trim() ?? '';
      final perfil = (metadata['perfil'] as String?)?.trim() ?? '';
      final matriculaFinal = matricula.isNotEmpty ? matricula : atual!.matricula;
      if (matriculaFinal == atual!.matricula && perfil == atual.perfil) {
        return atual;
      }

      final db = await DbHelper.instancia.database;
      await db.update('usuarios', {'matricula': matriculaFinal, 'perfil': perfil},
          where: 'id = ?', whereArgs: [atual.id]);
      usuarioLogado = Usuario(
        id: atual.id,
        nome: atual.nome,
        email: atual.email,
        senhaHash: atual.senhaHash,
        matricula: matriculaFinal,
        perfil: perfil,
        criadoEm: atual.criadoEm,
      );
      sessaoPrecisaRenovar = false;
      return usuarioLogado;
    } on AuthException catch (e) {
      // Sem rede: vale o perfil do aparelho.
      if (e is AuthRetryableFetchException) return atual;

      // O servidor recusou a sessão: marca para a tela pedir novo login.
      sessaoPrecisaRenovar = true;
      debugPrint('Sessão não reconhecida pelo servidor (${e.message}); '
          'perfil congelado no último login online');
      return atual;
    } catch (e) {
      debugPrint('Sincronização do perfil falhou: $e');
      return atual;
    }
  }

  // Restaura a sessão salva; null se não há ou o usuário não existe mais.
  Future<Usuario?> restaurarSessao() async {
    final prefs = await SharedPreferences.getInstance();
    final usuarioId = prefs.getInt(_chaveSessao);
    if (usuarioId == null) return null;

    final db = await DbHelper.instancia.database;
    final resultado =
        await db.query('usuarios', where: 'id = ?', whereArgs: [usuarioId]);
    if (resultado.isEmpty) {
      // Usuário não existe mais: descarta a sessão.
      await prefs.remove(_chaveSessao);
      return null;
    }

    usuarioLogado = Usuario.fromMap(resultado.first);
    return usuarioLogado;
  }

  // Cadastro no servidor (exige internet). null = sucesso; senão, o erro.
  Future<String?> cadastrar(String nome, String email, String senha,
      {String matricula = ''}) async {
    final supabase = _supabase;
    if (supabase == null) {
      return 'Cadastro requer internet — tente novamente conectado';
    }
    try {
      await supabase.auth.signUp(
        email: email,
        password: senha,
        data: {'nome': nome, 'matricula': matricula},
      );
    } on AuthException catch (e) {
      if (e is AuthRetryableFetchException) {
        return 'Cadastro requer internet — tente novamente conectado';
      }
      return _mensagemDeAuth(e, cadastro: true);
    } catch (e) {
      debugPrint('Cadastro online falhou: $e');
      return 'Cadastro requer internet — tente novamente conectado';
    }

    usuarioLogado =
        await _salvarUsuarioLocal(nome, email, senha, matricula: matricula);
    await _salvarSessao(usuarioLogado!.id!);
    return null;
  }

  // null = sucesso; senão, a mensagem de erro.
  Future<String?> login(String email, String senha) async {
    final supabase = _supabase;
    // Motivo da falha online, para a mensagem final.
    String? motivoOnline;
    if (supabase != null) {
      try {
        final resposta = await supabase.auth
            .signInWithPassword(email: email, password: senha);
        final nomeMetadata =
            (resposta.user?.userMetadata?['nome'] as String?)?.trim();
        final nome = (nomeMetadata != null && nomeMetadata.isNotEmpty)
            ? nomeMetadata
            : email.split('@').first;
        // Cada login online traz a matrícula mais recente.
        final matricula =
            (resposta.user?.userMetadata?['matricula'] as String?)?.trim() ?? '';
        final perfil =
            (resposta.user?.userMetadata?['perfil'] as String?)?.trim() ?? '';
        usuarioLogado = await _salvarUsuarioLocal(nome, email, senha,
            matricula: matricula, perfil: perfil);
        await _salvarSessao(usuarioLogado!.id!);
        sessaoPrecisaRenovar = false;
        return null;
      } on AuthException catch (e) {
        if (e is! AuthRetryableFetchException) {
          if (e.code == 'invalid_credentials') {
            return _migrarContaLocal(supabase, email, senha);
          }
          // Recusa do servidor nunca cai para o login local.
          return _mensagemDeAuth(e, cadastro: false);
        }
        // Sem rede: segue para o fallback local abaixo.
        motivoOnline = 'servidor não respondeu';
      } catch (e) {
        debugPrint('Login online falhou (rede?): $e');
        motivoOnline = _descreverFalhaDeRede(e);
      }
    } else {
      motivoOnline = 'app iniciou sem conexão com o servidor';
    }
    return _loginLocal(email, senha, motivoOnline: motivoOnline);
  }

  // Motivo curto da falha de rede, para a mensagem de login.
  String _descreverFalhaDeRede(Object e) {
    final texto = e.toString().toLowerCase();
    if (texto.contains('failed host lookup') || texto.contains('nodename')) {
      return 'servidor não encontrado — DNS ou rede bloqueando';
    }
    if (texto.contains('timed out') || texto.contains('timeout')) {
      return 'tempo esgotado';
    }
    if (texto.contains('socketexception') || texto.contains('connection')) {
      return 'sem acesso à rede';
    }
    return 'falha de conexão';
  }

  // Credenciais recusadas: se batem com uma conta só-local, cria no servidor.
  Future<String?> _migrarContaLocal(
      SupabaseClient supabase, String email, String senha) async {
    final erroLocal = await _loginLocal(email, senha);
    if (erroLocal != null) return 'E-mail ou senha incorretos';
    try {
      await supabase.auth.signUp(
        email: email,
        password: senha,
        data: {
          'nome': usuarioLogado!.nome,
          'matricula': usuarioLogado!.matricula,
        },
      );
    } catch (e) {
      // A migração fica para o próximo login online.
      debugPrint('Migração da conta local falhou: $e');
    }
    return null;
  }

  Future<String?> _loginLocal(String email, String senha,
      {String? motivoOnline}) async {
    final db = await DbHelper.instancia.database;
    final resultado = await db.query('usuarios', where: 'email = ?', whereArgs: [email]);
    if (resultado.isEmpty) {
      // Aparelho novo sem acesso ao servidor: explica o motivo.
      if (motivoOnline != null) {
        return 'Não foi possível entrar: $motivoOnline. Primeiro acesso neste '
            'aparelho precisa de internet.';
      }
      return 'Usuário não encontrado neste aparelho — conecte à internet para entrar';
    }

    final usuario = Usuario.fromMap(resultado.first);
    if (usuario.senhaHash != _hashSenha(senha)) return 'Senha incorreta';

    usuarioLogado = usuario;
    await _salvarSessao(usuario.id!);
    return null;
  }

  String _mensagemDeAuth(AuthException e, {required bool cadastro}) {
    switch (e.code) {
      case 'user_already_exists':
      case 'email_exists':
        return 'Já existe uma conta com este e-mail';
      case 'weak_password':
        return 'Senha muito fraca — use pelo menos 6 caracteres';
      case 'user_banned':
        return 'Usuário desativado pelo administrador';
      case 'email_not_confirmed':
        return 'E-mail ainda não confirmado — verifique sua caixa de entrada';
      case 'validation_failed':
        return 'E-mail inválido';
      default:
        return '${cadastro ? 'Cadastro' : 'Login'} falhou: ${e.message}';
    }
  }

  Future<void> logout() async {
    usuarioLogado = null;
    sessaoPrecisaRenovar = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveSessao);
    try {
      await _supabase?.auth.signOut();
    } catch (e) {
      // Sem rede o signOut remoto falha; a sessão local já foi encerrada.
      debugPrint('signOut remoto falhou: $e');
    }
  }
}
