import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Mensagem escrita pelo gestor na tabela `mensagens` do Supabase.
class MensagemDoGestor {
  final int id;
  final String titulo;
  final String corpo;

  const MensagemDoGestor({required this.id, required this.titulo, required this.corpo});
}

// Mensagens do gestor pela tabela `mensagens` (destinatário vazio = todos),
// buscadas ao abrir o app.
class MensagensService {
  MensagensService._interno();
  static final MensagensService instancia = MensagensService._interno();

  static const _chaveUltimaLida = 'ultima_mensagem_lida';

  // Mensagens ainda não vistas neste aparelho; vazio sem internet.
  Future<List<MensagemDoGestor>> buscarNovas(String emailUsuario) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ultimaLida = prefs.getInt(_chaveUltimaLida) ?? 0;

      final linhas = await Supabase.instance.client
          .from('mensagens')
          .select()
          .gt('id', ultimaLida)
          .order('id', ascending: true);

      final minhas = <MensagemDoGestor>[];
      var maiorId = ultimaLida;
      for (final linha in linhas) {
        final id = linha['id'] as int;
        if (id > maiorId) maiorId = id;
        final destinatario = (linha['destinatario_email'] as String?)?.trim() ?? '';
        if (destinatario.isNotEmpty &&
            destinatario.toLowerCase() != emailUsuario.toLowerCase()) {
          continue; // endereçada a outro encarregado
        }
        minhas.add(MensagemDoGestor(
          id: id,
          titulo: (linha['titulo'] as String?)?.trim() ?? 'Mensagem',
          corpo: (linha['corpo'] as String?)?.trim() ?? '',
        ));
      }

      // Marca tudo como visto, para não reprocessar.
      if (maiorId > ultimaLida) await prefs.setInt(_chaveUltimaLida, maiorId);
      return minhas;
    } catch (e) {
      debugPrint('Busca de mensagens falhou: $e');
      return const [];
    }
  }
}
