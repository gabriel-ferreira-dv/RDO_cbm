import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Um encarregado que faz parte da equipe de um supervisor.
class EncarregadoDaEquipe {
  final String matricula;
  final String nome;

  const EncarregadoDaEquipe({required this.matricula, required this.nome});

  @override
  bool operator ==(Object other) =>
      other is EncarregadoDaEquipe && other.matricula == matricula;

  @override
  int get hashCode => matricula.hashCode;
}

// Equipe do supervisor, no Supabase: vale em qualquer celular e o RLS a usa.
class EquipeSupervisorService {
  EquipeSupervisorService._interno();
  static final EquipeSupervisorService instancia =
      EquipeSupervisorService._interno();

  static const String tabela = 'equipes_supervisor';

  Future<List<EncarregadoDaEquipe>> carregar(String supervisorMatricula) async {
    if (supervisorMatricula.trim().isEmpty) return [];
    try {
      final linhas = await Supabase.instance.client
          .from(tabela)
          .select('encarregado_matricula, encarregado_nome')
          .eq('supervisor_matricula', supervisorMatricula.trim())
          .order('encarregado_nome', ascending: true); // o padrão é Z→A

      return [
        for (final l in linhas)
          EncarregadoDaEquipe(
            matricula: (l['encarregado_matricula'] as String?) ?? '',
            nome: (l['encarregado_nome'] as String?) ?? '',
          ),
      ];
    } catch (e) {
      debugPrint('Carregar equipe do supervisor falhou: $e');
      return [];
    }
  }

  // Troca a equipe inteira pela lista escolhida. null = sucesso; senão, o erro.
  Future<String?> salvar(
    String supervisorMatricula,
    List<EncarregadoDaEquipe> equipe,
  ) async {
    final matricula = supervisorMatricula.trim();
    if (matricula.isEmpty) return 'Supervisor sem matrícula cadastrada';
    try {
      final client = Supabase.instance.client;
      await client.from(tabela).delete().eq('supervisor_matricula', matricula);
      if (equipe.isNotEmpty) {
        await client.from(tabela).insert([
          for (final e in equipe)
            {
              'supervisor_matricula': matricula,
              'encarregado_matricula': e.matricula,
              'encarregado_nome': e.nome,
            },
        ]);
      }
      return null;
    } catch (e) {
      debugPrint('Salvar equipe do supervisor falhou: $e');
      return 'Não foi possível salvar a equipe — verifique a conexão';
    }
  }
}
