// Datas ISO em UTC (como no banco) para exibir no horário local.

// dd/mm/aaaa local; devolve [iso] se não for válido.
String formatarData(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final dia = d.day.toString().padLeft(2, '0');
  final mes = d.month.toString().padLeft(2, '0');
  return '$dia/$mes/${d.year}';
}

// "dd/mm/aaaa às hh:mm" local; devolve [iso] se não for válido.
String formatarDataHora(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final dia = d.day.toString().padLeft(2, '0');
  final mes = d.month.toString().padLeft(2, '0');
  final hora = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dia/$mes/${d.year} às $hora:$min';
}

// Dia local (sem hora) de um ISO em UTC, comparável com ==; null se inválido.
DateTime? diaLocalDe(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

// hh:mm local; vazio se [iso] não for válido.
String formatarHora(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
