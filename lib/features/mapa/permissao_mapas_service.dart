import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mapas_config.dart';

// Grupos de mapa do usuário, da tabela `mapas_usuario` do Supabase. Fica
// guardado no aparelho (o mapa funciona sem sinal). Sem linha nenhuma, vale CBM.
class PermissaoMapasService {
  PermissaoMapasService._interno();
  static final PermissaoMapasService instancia =
      PermissaoMapasService._interno();

  static const String tabela = 'mapas_usuario';
  static const String _chavePrefs = 'grupos_de_mapa';

  // Notifier: a permissão pode chegar com a tela do mapa já aberta.
  final ValueNotifier<Set<String>> grupos = ValueNotifier({grupoCbm});

  // true se o mapa [nome] pertence a um grupo deste usuário.
  bool podeVerMapa(String nome) => grupos.value.contains(grupoDoMapa(nome));

  // Lê a permissão guardada no aparelho (no boot).
  Future<void> carregarDoAparelho() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salvos = prefs.getStringList(_chavePrefs);
      if (salvos != null && salvos.isNotEmpty) grupos.value = salvos.toSet();
    } catch (e) {
      debugPrint('Permissão de mapas: falha ao ler do aparelho: $e');
    }
  }

  // Busca no servidor e guarda no aparelho; sem rede, vale a guardada.
  Future<void> sincronizar() async {
    try {
      final usuario = Supabase.instance.client.auth.currentUser;
      if (usuario == null) return;
      final linhas = await Supabase.instance.client
          .from(tabela)
          .select('grupo')
          .eq('user_id', usuario.id);

      final doServidor = {
        for (final linha in linhas)
          ((linha['grupo'] as String?) ?? '').trim(),
      }..removeWhere((g) => g.isEmpty);

      final novos = doServidor.isEmpty ? {grupoCbm} : doServidor;
      if (setEquals(novos, grupos.value)) return;
      grupos.value = novos;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_chavePrefs, novos.toList());
    } catch (e) {
      debugPrint('Permissão de mapas: falha ao sincronizar: $e');
    }
  }
}
