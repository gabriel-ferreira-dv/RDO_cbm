import 'package:flutter/material.dart';
import '../../../auth/auth_service.dart';
import '../../../auth/models/usuario.dart';
import '../../../paralisacao/paralisacao_service.dart';
import '../../../supervisor/presentation/pages/mapa_avanco_page.dart';
import '../../relatorio_service.dart';
import '../../turno_noturno.dart';
import 'relatorio_form_page.dart';

class RelatorioPage extends StatefulWidget {
  final Usuario usuario;

  const RelatorioPage({super.key, required this.usuario});

  @override
  State<RelatorioPage> createState() => _RelatorioPageState();
}

class _RelatorioPageState extends State<RelatorioPage> {
  // No turno da noite, o relatório gerado de madrugada já abre no dia em que
  // o turno começou.
  late DateTime _diaSelecionado = diaDoTurno(DateTime.now(), noturno: _noturno);
  bool _verificando = false;

  bool get _noturno => TurnoNoturnoService.instancia.ehNoturno(
      AuthService.instancia.usuarioLogado?.matricula ?? widget.usuario.matricula);

  String get _dataFormatada {
    final d = _diaSelecionado;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _selecionarData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _diaSelecionado,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (escolhida != null) {
      setState(() => _diaSelecionado = escolhida);
    }
  }

  Future<void> _gerarRelatorio() async {
    setState(() => _verificando = true);
    try {
      final grupos = await RelatorioService.instancia.buscarGruposDoDia(
          widget.usuario.id!, _diaSelecionado,
          noturno: _noturno);
      // Dia só de chuva: sem foto de serviço, mas com paralisação.
      final paradas = grupos.isNotEmpty
          ? const []
          : await ParalisacaoService.instancia.listarDoDia(
              widget.usuario.id!, _diaSelecionado,
              noturno: _noturno);
      if (!mounted) return;
      if (grupos.isEmpty && paradas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nenhuma foto nem paralisação encontrada para o '
                  'dia selecionado')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RelatorioFormPage(usuario: widget.usuario, dia: _diaSelecionado),
        ),
      );
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 64),
            const SizedBox(height: 16),
            const Text('Gerar relatório em PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _verificando ? null : _selecionarData,
              icon: const Icon(Icons.calendar_today),
              label: Text(_dataFormatada),
            ),
            if (_noturno)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Turno da noite: o que foi registrado até as 11:59 conta '
                  'para o dia anterior.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            // O mesmo mapa entra no PDF.
            OutlinedButton.icon(
              onPressed: _verificando
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MapaAvancoPage.doEncarregado(
                          usuario: widget.usuario,
                          dia: _diaSelecionado,
                        ),
                      )),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Ver mapa do dia'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _verificando ? null : _gerarRelatorio,
              icon: _verificando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_verificando ? 'Verificando...' : 'Gerar relatório'),
            ),
          ],
        ),
      ),
    );
  }
}
