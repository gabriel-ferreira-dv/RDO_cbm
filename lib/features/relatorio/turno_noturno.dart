import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Até esta hora, quem é do turno da noite ainda está no dia anterior: o turno
// das 17h às 2h fica inteiro no dia em que começou.
const int horaViradaTurnoNoturno = 12;

// Dia de trabalho a que [momento] (hora local) pertence.
DateTime diaDoTurno(DateTime momento, {required bool noturno}) {
  final dia = DateTime(momento.year, momento.month, momento.day);
  return noturno && momento.hour < horaViradaTurnoNoturno
      ? DateTime(dia.year, dia.month, dia.day - 1)
      : dia;
}

// Matrículas do turno da noite (tabela turno_noturno do Supabase). Fica
// guardado no aparelho, para o relatório sair certo sem sinal.
class TurnoNoturnoService {
  TurnoNoturnoService._interno();
  static final TurnoNoturnoService instancia = TurnoNoturnoService._interno();

  static const String tabela = 'turno_noturno';
  static const String _chavePrefs = 'matriculas_turno_noturno';

  Set<String> _matriculas = {};

  bool ehNoturno(String matricula) {
    final m = matricula.trim();
    return m.isNotEmpty && _matriculas.contains(m);
  }

  // Lê a lista guardada no aparelho (no boot).
  Future<void> carregarDoAparelho() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _matriculas = (prefs.getStringList(_chavePrefs) ?? const []).toSet();
    } catch (e) {
      debugPrint('Turno noturno: falha ao ler do aparelho: $e');
    }
  }

  // Busca no servidor e guarda no aparelho; sem rede, vale a guardada.
  Future<void> sincronizar() async {
    try {
      final linhas =
          await Supabase.instance.client.from(tabela).select('matricula');
      final matriculas = {
        for (final linha in linhas) ((linha['matricula'] as String?) ?? '').trim(),
      }..removeWhere((m) => m.isEmpty);
      _matriculas = matriculas;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_chavePrefs, matriculas.toList());
    } catch (e) {
      debugPrint('Turno noturno: falha ao sincronizar: $e');
    }
  }
}
