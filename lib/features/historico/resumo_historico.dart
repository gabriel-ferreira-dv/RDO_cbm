import '../registro/models/grupo_atividade.dart';

// Contadores exibidos no painel de resumo do Histórico. "Semana" = hoje e os
// 6 dias anteriores, para o encarregado conferir a produção recente.
class ResumoHistorico {
  final int registrosHoje;
  final int fotosHoje;
  final int registrosSemana;
  final int fotosSemana;

  // Atividade com mais registros na semana; `null` quando não houve nenhum.
  final String? atividadeMaisFrequente;

  const ResumoHistorico({
    required this.registrosHoje,
    required this.fotosHoje,
    required this.registrosSemana,
    required this.fotosSemana,
    this.atividadeMaisFrequente,
  });
}

// Calcula o resumo a partir dos grupos já carregados pelo Histórico.
// [agora] vem de fora (em vez de DateTime.now()) para os testes fixarem a
// data. As datas dos registros são gravadas em UTC — a comparação é feita
// no fuso local, que é o "dia" que faz sentido para quem está na obra.
ResumoHistorico calcularResumo(List<GrupoAtividade> grupos, DateTime agora) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final inicioSemana = hoje.subtract(const Duration(days: 6));

  var registrosHoje = 0;
  var fotosHoje = 0;
  var registrosSemana = 0;
  var fotosSemana = 0;
  final registrosPorAtividade = <String, int>{};

  for (final grupo in grupos) {
    for (final registro in grupo.registros) {
      final criado = DateTime.tryParse(registro.criadoEm)?.toLocal();
      if (criado == null) continue;
      final dia = DateTime(criado.year, criado.month, criado.day);
      if (dia.isBefore(inicioSemana) || dia.isAfter(hoje)) continue;

      registrosSemana++;
      fotosSemana += registro.fotos.length;
      registrosPorAtividade[grupo.atividade] =
          (registrosPorAtividade[grupo.atividade] ?? 0) + 1;

      if (dia == hoje) {
        registrosHoje++;
        fotosHoje += registro.fotos.length;
      }
    }
  }

  String? atividadeMaisFrequente;
  var maior = 0;
  registrosPorAtividade.forEach((atividade, quantidade) {
    if (quantidade > maior) {
      maior = quantidade;
      atividadeMaisFrequente = atividade;
    }
  });

  return ResumoHistorico(
    registrosHoje: registrosHoje,
    fotosHoje: fotosHoje,
    registrosSemana: registrosSemana,
    fotosSemana: fotosSemana,
    atividadeMaisFrequente: atividadeMaisFrequente,
  );
}
