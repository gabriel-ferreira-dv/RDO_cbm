import 'package:flutter/material.dart';

import '../../../auth/auth_service.dart';
import '../../../auth/models/usuario.dart';
import '../../../relatorio/turno_noturno.dart';
import '../widgets/paralisacoes_do_dia.dart';

// Aba "Paradas": as paralisações de um dia, com registrar e retomar.
class ParalisacoesPage extends StatefulWidget {
  final Usuario usuario;

  // Avisa a Home quando algo muda (o ponto vermelho da aba).
  final VoidCallback? aoMudar;

  const ParalisacoesPage({super.key, required this.usuario, this.aoMudar});

  @override
  State<ParalisacoesPage> createState() => _ParalisacoesPageState();
}

class _ParalisacoesPageState extends State<ParalisacoesPage> {
  bool get _noturno => TurnoNoturnoService.instancia.ehNoturno(
      AuthService.instancia.usuarioLogado?.matricula ?? widget.usuario.matricula);

  DateTime get _hoje {
    final d = diaDoTurno(DateTime.now(), noturno: _noturno);
    return DateTime(d.year, d.month, d.day);
  }

  late DateTime _dia = _hoje;

  void _mudarDia(DateTime dia) =>
      setState(() => _dia = DateTime(dia.year, dia.month, dia.day));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ehHoje = _dia == _hoje;
    final data = '${_dia.day.toString().padLeft(2, '0')}/'
        '${_dia.month.toString().padLeft(2, '0')}/${_dia.year}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Dia anterior',
              onPressed: () => _mudarDia(DateTime(_dia.year, _dia.month, _dia.day - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () async {
                  final escolhido = await showDatePicker(
                    context: context,
                    initialDate: _dia,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (escolhido != null) _mudarDia(escolhido);
                },
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(ehHoje ? 'Hoje, $data' : data),
              ),
            ),
            IconButton(
              tooltip: 'Dia seguinte',
              onPressed: ehHoje
                  ? null
                  : () => _mudarDia(DateTime(_dia.year, _dia.month, _dia.day + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // A chave recria o painel ao trocar de dia.
        ParalisacoesDoDia(
          key: ValueKey(_dia),
          usuario: widget.usuario,
          dia: _dia,
          aoMudar: widget.aoMudar,
        ),
        const SizedBox(height: 16),
        Text(
          'Registre toda vez que o serviço parar: chuva, falta de material, '
          'máquina quebrada, interferência. O horário, o motivo e as fotos vão '
          'para o RDO e para o relatório do supervisor, e provam que a parada '
          'não foi culpa da obra.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
