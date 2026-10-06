import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/filtro_dia_dropdown.dart';
import '../../../../core/widgets/galeria_imagens_page.dart';
import '../../../auth/models/usuario.dart';
import '../../../registro/models/grupo_atividade.dart';
import '../../../registro/vias_estaqueamento.dart' show faixaDeKm;
import '../../../registro/registro_service.dart';
import '../../resumo_historico.dart';

// Registros do usuário, agrupados; tocar num registro abre as fotos dele.
class HistoricoPage extends StatefulWidget {
  final Usuario usuario;

  const HistoricoPage({super.key, required this.usuario});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  late Future<List<GrupoAtividade>> _gruposFuture;
  DateTime? _diaFiltro;

  // Dias (locais) que têm registro, do mais recente para o mais antigo.
  List<DateTime> _diasDisponiveis(List<GrupoAtividade> grupos) {
    final dias = <DateTime>{
      for (final g in grupos)
        for (final r in g.registros)
          if (diaLocalDe(r.criadoEm) != null) diaLocalDe(r.criadoEm)!,
    };
    return dias.toList()..sort((a, b) => b.compareTo(a));
  }

  // Mantém só as sessões do dia filtrado; grupos que ficarem vazios somem.
  List<GrupoAtividade> _filtrarPorDia(List<GrupoAtividade> grupos) {
    final dia = _diaFiltro;
    if (dia == null) return grupos;
    return [
      for (final g in grupos)
        if (g.registros.any((r) => diaLocalDe(r.criadoEm) == dia))
          GrupoAtividade(
            trecho: g.trecho,
            km: g.km,
            kmFinal: g.kmFinal,
            atividade: g.atividade,
            servicoNotavel: g.servicoNotavel,
            servicoNotavelDetalhe: g.servicoNotavelDetalhe,
            registros: g.registros
                .where((r) => diaLocalDe(r.criadoEm) == dia)
                .toList(),
          ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _gruposFuture = RegistroService.instancia
        .listarFotosComContexto(widget.usuario.id!)
        .then(agruparPorAtividade);
  }

  Future<void> _recarregar() async {
    setState(() {
      _gruposFuture = RegistroService.instancia
          .listarFotosComContexto(widget.usuario.id!)
          .then(agruparPorAtividade);
    });
    await _gruposFuture;
  }

  void _abrirFotos(RegistroAgrupado registro) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GaleriaImagensPage(
          fotos: registro.fotos.map((f) => f.caminhoArquivo).toList(),
          descricao: registro.descricao,
        ),
      ),
    );
  }

  String _plural(int n, String singular) => '$n $singular${n == 1 ? '' : 's'}';

  Widget _tileResumo(String titulo, int registros, int fotos) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            titulo,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            '$registros',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            registros == 1 ? 'registro' : 'registros',
            style: theme.textTheme.labelSmall,
          ),
          Text(
            _plural(fotos, 'foto'),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // Produção de hoje e da semana.
  Widget _painelResumo(List<GrupoAtividade> grupos) {
    final theme = Theme.of(context);
    final resumo = calcularResumo(grupos, DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Resumo',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _tileResumo('Hoje', resumo.registrosHoje, resumo.fotosHoje),
                Container(
                  width: 1,
                  height: 48,
                  color: theme.colorScheme.outlineVariant,
                ),
                _tileResumo(
                  'Últimos 7 dias',
                  resumo.registrosSemana,
                  resumo.fotosSemana,
                ),
              ],
            ),
            if (resumo.atividadeMaisFrequente != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mais frequente na semana: ${resumo.atividadeMaisFrequente}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Miniatura da primeira foto (ou um ícone, se o arquivo sumiu).
  Widget _miniaturaSessao(RegistroAgrupado r) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: 52,
      height: 52,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: r.fotos.isEmpty
          ? placeholder
          : Image.file(
              File(r.fotos.first.caminhoArquivo),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              // Decodifica pequeno: é só uma miniatura.
              cacheWidth: 156,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }

  Widget _sessaoTile(RegistroAgrupado r) {
    final theme = Theme.of(context);
    final descricao = r.descricao.trim();

    return ListTile(
      leading: _miniaturaSessao(r),
      title: Text(
        // Via e estaca só quando existem (área de apoio não tem nenhuma).
        [
          if (r.via.trim().isNotEmpty) r.via,
          if (r.estacaInicial.isNotEmpty)
            'Estaca ${r.estacaInicial} – ${r.estacaFinal}'
          else
            'Sem estaca',
          if (r.quantidade != null && r.unidade.isNotEmpty)
            '${formatarQuantidade(r.quantidade!)} ${r.unidade}',
        ].join(' • '),
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.emNomeDeNome.isNotEmpty)
            Text(
              'Em nome de ${r.emNomeDeNome}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            )
          else if (r.registradoPorNome.isNotEmpty)
            Text(
              'Lançado por ${r.registradoPorNome}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          if (descricao.isNotEmpty)
            Text(
              descricao,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          Text(
            '${formatarDataHora(r.criadoEm)} • ${_plural(r.fotos.length, 'foto')}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _abrirFotos(r),
    );
  }

  Widget _cardGrupo(GrupoAtividade g) {
    final theme = Theme.of(context);
    final sessoes = g.registros.length == 1
        ? '1 sessão'
        : '${g.registros.length} sessões';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        // Sem shape: tira as linhas que o ExpansionTile desenha ao expandir.
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.construction,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          '${g.trecho} • KM ${faixaDeKm(g.km, g.kmFinal)}',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${g.atividade} — ${g.servicoNotavel}'
              '${g.servicoNotavelDetalhe.isNotEmpty ? ' (${g.servicoNotavelDetalhe})' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '$sessoes • ${_plural(g.totalFotos, 'foto')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (g.quantidadeTotal != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Medido: ${formatarQuantidade(g.quantidadeTotal!.total)} '
                  '${g.quantidadeTotal!.unidade}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        children: g.registros.map(_sessaoTile).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _recarregar,
      child: FutureBuilder<List<GrupoAtividade>>(
        future: _gruposFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final grupos = snapshot.data ?? [];
          if (grupos.isEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        const Text('Nenhum registro ainda'),
                        const SizedBox(height: 4),
                        Text(
                          'Os registros que você fizer aparecerão aqui',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          final dias = _diasDisponiveis(grupos);
          final filtrados = _filtrarPorDia(grupos);
          // +2: o resumo (de todos os grupos) e o filtro por dia.
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: filtrados.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) return _painelResumo(grupos);
              if (index == 1) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FiltroDiaDropdown(
                    dias: dias,
                    selecionado: _diaFiltro,
                    onSelected: (dia) => setState(() => _diaFiltro = dia),
                  ),
                );
              }
              return _cardGrupo(filtrados[index - 2]);
            },
          );
        },
      ),
    );
  }
}
