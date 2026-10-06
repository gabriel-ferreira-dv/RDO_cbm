import 'package:flutter/material.dart';

import '../../../auth/auth_service.dart';
import '../../../auth/models/usuario.dart';
import '../../../relatorio/turno_noturno.dart';
import '../../../sincronizacao/sincronizacao_service.dart';
import '../../models/paralisacao.dart';
import '../../paralisacao_service.dart';
import '../pages/paralisacao_form_page.dart';

// Paralisações de um dia de trabalho, com o botão de registrar e o de
// retomar o serviço. Vai no Início (dia atual) e no formulário do RDO.
class ParalisacoesDoDia extends StatefulWidget {
  final Usuario usuario;

  // Dia de trabalho; null = o de agora (respeita o turno da noite).
  final DateTime? dia;

  // Chamado depois de registrar, editar ou retomar.
  final VoidCallback? aoMudar;

  const ParalisacoesDoDia({super.key, required this.usuario, this.dia, this.aoMudar});

  @override
  State<ParalisacoesDoDia> createState() => _ParalisacoesDoDiaState();
}

class _ParalisacoesDoDiaState extends State<ParalisacoesDoDia> {
  List<Paralisacao> _lista = [];
  Map<int, int> _fotos = {};
  bool _carregando = true;

  bool get _noturno => TurnoNoturnoService.instancia.ehNoturno(
      AuthService.instancia.usuarioLogado?.matricula ?? widget.usuario.matricula);

  DateTime get _dia => widget.dia ?? diaDoTurno(DateTime.now(), noturno: _noturno);

  bool get _ehHoje => widget.dia == null ||
      _dia == diaDoTurno(DateTime.now(), noturno: _noturno);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final lista = await ParalisacaoService.instancia
        .listarDoDia(widget.usuario.id!, _dia, noturno: _noturno);
    final fotos = await ParalisacaoService.instancia
        .contarFotos([for (final p in lista) p.id!]);
    if (!mounted) return;
    setState(() {
      _lista = lista;
      _fotos = fotos;
      _carregando = false;
    });
  }

  Future<void> _abrir([Paralisacao? paralisacao]) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ParalisacaoFormPage(
        usuario: widget.usuario,
        dia: _dia,
        noturno: _noturno,
        paralisacao: paralisacao,
      ),
    ));
    // Sempre recarrega: a foto pode ter entrado mesmo saindo pelo voltar.
    await _carregar();
    widget.aoMudar?.call();
    // O supervisor vê a paralisação assim que houver rede.
    SincronizacaoService.instancia.sincronizar();
  }

  Future<void> _retomar(Paralisacao p) async {
    await ParalisacaoService.instancia.encerrar(p.id!);
    SincronizacaoService.instancia.sincronizar();
    await _carregar();
    widget.aoMudar?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Serviço retomado. Parado por '
          '${formatarDuracao(DateTime.now().difference(p.inicio.toLocal()))}.'),
    ));
  }

  String _hhmm(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emAndamento = _lista.where((p) => p.emAndamento).toList();
    final total = tempoParado([for (final p in _lista) (inicio: p.inicio, fim: p.fim)]);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.pause_circle_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ehHoje ? 'Paralisações de hoje' : 'Paralisações do dia',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (total > Duration.zero)
                  Text('${formatarDuracao(total)} parado',
                      style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (_carregando)
              const Center(child: CircularProgressIndicator())
            else ...[
              for (final p in emAndamento) _emAndamento(theme, p),
              if (_lista.isEmpty)
                Text(
                  _ehHoje
                      ? 'Se o serviço parar (chuva, falta de material, máquina '
                          'quebrada…), registre aqui. Vai para o RDO e para o '
                          'relatório do supervisor.'
                      : 'Nenhuma paralisação registrada neste dia.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              for (final p in _lista.where((p) => !p.emAndamento))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_toggle_off),
                  title: Text(p.descricao),
                  trailing: (_fotos[p.id] ?? 0) > 0
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_camera_outlined, size: 16),
                            Text(' ${_fotos[p.id]}'),
                          ],
                        )
                      : null,
                  onTap: () => _abrir(p),
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => _abrir(),
                icon: const Icon(Icons.add),
                label: const Text('Registrar paralisação'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emAndamento(ThemeData theme, Paralisacao p) {
    final cores = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cores.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Serviço parado desde ${_hhmm(p.inicio)} · ${p.motivo}',
            style: theme.textTheme.titleSmall?.copyWith(
                color: cores.onErrorContainer, fontWeight: FontWeight.bold),
          ),
          if (p.trecho.isNotEmpty || p.observacao.isNotEmpty)
            Text(
              [
                if (p.trecho.isNotEmpty)
                  p.km.isEmpty ? p.trecho : '${p.trecho} / KM ${p.km}',
                if (p.observacao.isNotEmpty) p.observacao,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: cores.onErrorContainer),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _retomar(p),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Retomar serviço'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Editar ou fotografar',
                onPressed: () => _abrir(p),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
