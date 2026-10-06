import 'package:flutter/material.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/filtro_dia_dropdown.dart';
import '../../../../core/widgets/info_chip.dart';
import '../../../auth/models/usuario.dart';
import '../../models/registro.dart';
import '../../registro_service.dart';
import '../../vias_estaqueamento.dart' show faixaDeKm;

// Lista os registros anteriores do usuário para servir de modelo a um novo
// registro. Ao tocar num item, a página é fechada devolvendo o Registro
// escolhido para quem a abriu (Navigator.pop(registro)).
class ImportarAtividadePage extends StatefulWidget {
  final Usuario usuario;

  const ImportarAtividadePage({super.key, required this.usuario});

  @override
  State<ImportarAtividadePage> createState() => _ImportarAtividadePageState();
}

class _ImportarAtividadePageState extends State<ImportarAtividadePage> {
  late Future<List<Registro>> _registrosFuture;
  DateTime? _diaFiltro;

  List<DateTime> _diasDisponiveis(List<Registro> registros) {
    final dias = <DateTime>{
      for (final r in registros)
        if (diaLocalDe(r.criadoEm) != null) diaLocalDe(r.criadoEm)!,
    };
    return dias.toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  void initState() {
    super.initState();
    _registrosFuture = RegistroService.instancia.listarRegistros(widget.usuario.id!);
  }

  Widget _cardRegistro(Registro r) {
    final theme = Theme.of(context);
    final descricao = r.descricao.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${r.trecho} • KM ${faixaDeKm(r.km, r.kmFinal)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    formatarData(r.criadoEm),
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(r.atividade, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Sem via em trecho de pista simples — o chip vazio some.
                  if (r.via.trim().isNotEmpty)
                    InfoChip(icone: Icons.swap_horiz, texto: r.via),
                  if (r.estacaInicial.isNotEmpty)
                    InfoChip(
                      icone: Icons.straighten,
                      texto: 'Estaca ${r.estacaInicial} – ${r.estacaFinal}',
                    ),
                  InfoChip(icone: Icons.handyman_outlined, texto: r.servicoNotavel),
                  if (r.servicoNotavelDetalhe.isNotEmpty)
                    InfoChip(
                      icone: Icons.checklist_rtl,
                      texto: r.servicoNotavelDetalhe,
                    ),
                ],
              ),
              if (descricao.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  descricao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Importar atividade anterior')),
      body: FutureBuilder<List<Registro>>(
        future: _registrosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final registros = snapshot.data ?? [];
          if (registros.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 56,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  const Text('Nenhum registro anterior encontrado'),
                ],
              ),
            );
          }
          final dias = _diasDisponiveis(registros);
          final filtrados = _diaFiltro == null
              ? registros
              : registros
                  .where((r) => diaLocalDe(r.criadoEm) == _diaFiltro)
                  .toList();
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            // +1 para o cabeçalho (instrução + filtro por dia).
            itemCount: filtrados.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Toque numa atividade para reaproveitar os campos dela num novo registro.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      FiltroDiaDropdown(
                        dias: dias,
                        selecionado: _diaFiltro,
                        onSelected: (dia) => setState(() => _diaFiltro = dia),
                      ),
                    ],
                  ),
                );
              }
              return _cardRegistro(filtrados[index - 1]);
            },
          );
        },
      ),
    );
  }
}
