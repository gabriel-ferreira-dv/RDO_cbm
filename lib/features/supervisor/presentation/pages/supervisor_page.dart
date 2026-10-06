import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../auth/auth_service.dart';
import '../../../auth/models/usuario.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../paralisacao/models/paralisacao.dart';
import '../../equipe_supervisor_service.dart';
import '../../registros_equipe_service.dart';
import '../../../relatorio/mapa_do_relatorio.dart';
import '../../../relatorio/texto_pdf.dart';
import '../../../relatorio/turno_noturno.dart';
import '../../relatorio_consolidado_service.dart';
import 'mapa_avanco_page.dart';
import 'montar_equipe_page.dart';

// Painel do supervisor: o dia de cada encarregado e o relatório consolidado.
class SupervisorPage extends StatefulWidget {
  final Usuario usuario;

  const SupervisorPage({super.key, required this.usuario});

  @override
  State<SupervisorPage> createState() => _SupervisorPageState();
}

class _SupervisorPageState extends State<SupervisorPage> {
  DateTime _dia = DateTime.now();
  List<EncarregadoDaEquipe> _equipe = [];
  List<ResumoDoEncarregado> _resumos = [];
  bool _carregando = true;
  bool _incluirFotos = false;
  bool _gerando = false;
  // Progresso do download das fotos.
  int _fotosBaixadas = 0;
  int _fotosTotal = 0;

  String get _matricula =>
      AuthService.instancia.usuarioLogado?.matricula ?? widget.usuario.matricula;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    // Renova o token antes: o RLS lê a matrícula de dentro dele.
    await AuthService.instancia.sincronizarPerfil();
    // Quem da equipe é do turno da noite muda o dia de cada um.
    await TurnoNoturnoService.instancia.sincronizar();
    final equipe = await EquipeSupervisorService.instancia.carregar(_matricula);
    final resumos = await RegistrosEquipeService.instancia
        .buscarDoDia(equipe: equipe, dia: _dia);
    if (!mounted) return;
    setState(() {
      _equipe = equipe;
      _resumos = resumos;
      _carregando = false;
    });
  }

  Future<void> _escolherDia() async {
    final escolhido = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (escolhido == null) return;
    setState(() => _dia = escolhido);
    _carregar();
  }

  Future<void> _montarEquipe() async {
    if (_matricula.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Seu usuário está sem matrícula. Cadastre no Supabase '
            'e entre no app novamente'),
      ));
      return;
    }
    final nova = await Navigator.of(context).push<List<EncarregadoDaEquipe>>(
      MaterialPageRoute(
        builder: (_) => MontarEquipePage(
          supervisorMatricula: _matricula,
          equipeAtual: _equipe,
        ),
      ),
    );
    if (nova != null) _carregar();
  }

  void _abrirMapaDeAvanco() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MapaAvancoPage.daEquipe(matriculas: [
        for (final e in _equipe) e.matricula,
        // O que o próprio supervisor registrou também entra.
        if (_matricula.isNotEmpty) _matricula,
      ]),
    ));
  }

  Future<void> _gerarConsolidado() async {
    setState(() {
      _gerando = true;
      _fotosBaixadas = 0;
      _fotosTotal = 0;
    });
    // Cópia: um refresh no meio da geração trocaria _resumos.
    final resumos = _resumos;
    try {
      final fotos = _incluirFotos
          ? await _baixarFotos(resumos)
          : [for (final _ in resumos) const <FotoConsolidada>[]];
      final blocos = <BlocoEncarregado>[];
      for (var i = 0; i < resumos.length; i++) {
        final resumo = resumos[i];
        // Texto do SIMOVA: limpa para o PDF.
        blocos.add(BlocoEncarregado(
          nome: textoParaPdf(resumo.encarregado.nome),
          matricula: textoParaPdf(resumo.encarregado.matricula),
          efetivo: linhasParaPdf([for (final f in resumo.efetivo) f.linha]),
          totalPessoas: resumo.totalPessoas,
          atividades: listarAtividades(resumo.registros),
          fotos: fotos[i],
          clima: textoParaPdf(resumo.clima?.linha ?? ''),
          paralisacoes:
              linhasParaPdf([for (final p in resumo.paralisacoes) p.descricao]),
          tempoParado: resumo.totalParado > Duration.zero
              ? formatarDuracao(resumo.totalParado)
              : '',
        ));
      }

      final dataFormatada = '${_dia.day.toString().padLeft(2, '0')}/'
          '${_dia.month.toString().padLeft(2, '0')}/${_dia.year}';
      // Onde a equipe trabalhou no dia, nas cores do mapa de avanço.
      final mapa = await montarMapaDasAtividades([
        for (final resumo in resumos)
          for (final r in resumo.registros)
            (
              trecho: r.trecho,
              estacaInicial: r.estacaInicial,
              estacaFinal: r.estacaFinal,
              servico: r.servicoNotavel,
            ),
      ]);
      final bytes = await RelatorioConsolidadoService.instancia.gerar(
        blocos: blocos,
        supervisor: textoParaPdf(widget.usuario.nome),
        dataFormatada: dataFormatada,
        mapa: mapa,
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Equipe — $dataFormatada')),
          body: PdfPreview(
            build: (_) async => bytes,
            allowSharing: true,
            allowPrinting: true,
            canChangePageFormat: false,
            pdfFileName: 'equipe_${_dia.year}'
                '${_dia.month.toString().padLeft(2, '0')}'
                '${_dia.day.toString().padLeft(2, '0')}.pdf',
          ),
        ),
      ));
    } catch (e) {
      // Mostra a falha ao usuário.
      debugPrint('Relatório da equipe falhou: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível gerar o relatório. Tente de novo; '
              'se continuar, gere sem as fotos e me avise.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  // Fotos de cada encarregado (na ordem de [resumos]), baixadas em paralelo.
  Future<List<List<FotoConsolidada>>> _baixarFotos(
      List<ResumoDoEncarregado> resumos) async {
    final servico = RegistrosEquipeService.instancia;
    final pendentes = <_FotoPendente>[];
    for (var i = 0; i < resumos.length; i++) {
      final registros = resumos[i].registros;
      if (registros.isNotEmpty) {
        final caminhos = await servico.caminhosDasFotos(registros);
        for (final registro in registros) {
          for (final caminho in caminhos[registro.chave] ?? const <String>[]) {
            pendentes.add(_FotoPendente(
              encarregado: i,
              caminho: caminho,
              legenda: textoParaPdf(registro.estacaInicial.isEmpty
                  ? registro.servicoNotavel
                  : '${registro.servicoNotavel} - estaca ${registro.estacaInicial}'),
            ));
          }
        }
      }
      // Fotos das paralisações vêm depois das do serviço.
      final paradas = resumos[i].paralisacoes;
      if (paradas.isEmpty) continue;
      final caminhosParadas = await servico.caminhosDasFotosDeParalisacao(paradas);
      for (final p in paradas) {
        for (final caminho
            in caminhosParadas['${p.dispositivoId}|${p.idLocal}'] ?? const <String>[]) {
          pendentes.add(_FotoPendente(
            encarregado: i,
            caminho: caminho,
            legenda: textoParaPdf('Paralisação - ${p.motivo} - '
                '${formatarHora(p.inicio.toUtc().toIso8601String())}'),
          ));
        }
      }
    }
    if (mounted) setState(() => _fotosTotal = pendentes.length);

    final fotos = [for (final _ in resumos) <FotoConsolidada>[]];
    const simultaneas = 6;
    for (var inicio = 0; inicio < pendentes.length; inicio += simultaneas) {
      final lote = pendentes.skip(inicio).take(simultaneas).toList();
      final baixadas =
          await Future.wait([for (final p in lote) servico.baixarFoto(p.caminho)]);
      for (var j = 0; j < lote.length; j++) {
        final bytes = baixadas[j];
        if (bytes == null) continue;
        fotos[lote[j].encarregado]
            .add(FotoConsolidada(bytes: bytes, legenda: lote[j].legenda));
      }
      if (mounted) setState(() => _fotosBaixadas = inicio + lote.length);
    }
    return fotos;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dataFormatada = '${_dia.day.toString().padLeft(2, '0')}/'
        '${_dia.month.toString().padLeft(2, '0')}/${_dia.year}';

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _escolherDia,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(dataFormatada),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _montarEquipe,
                icon: const Icon(Icons.group_add, size: 18),
                label: const Text('Equipe'),
              ),
            ],
          ),
          if (_equipe.isNotEmpty) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _abrirMapaDeAvanco,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Mapa de avanço da equipe'),
            ),
          ],
          const SizedBox(height: 12),
          if (_carregando)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_equipe.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.groups_outlined,
                      size: 56, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text(
                    'Sua equipe ainda está vazia. Toque em "Equipe" para '
                    'escolher os encarregados que você supervisiona.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else ...[
            for (final resumo in _resumos) _cartaoEncarregado(resumo),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _incluirFotos,
              onChanged: (v) => setState(() => _incluirFotos = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir fotos no relatório',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Deixa o PDF bem maior e mais lento de gerar — precisa baixar '
                'todas as fotos do dia.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _gerando ? null : _gerarConsolidado,
              icon: _gerando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf),
              label: Text(!_gerando
                  ? 'Gerar relatório da equipe'
                  : _fotosBaixadas < _fotosTotal
                      ? 'Baixando fotos $_fotosBaixadas de $_fotosTotal…'
                      : 'Gerando…'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cartaoEncarregado(ResumoDoEncarregado resumo) {
    final theme = Theme.of(context);
    final atividades = listarAtividades(resumo.registros);
    final paradas = resumo.paralisacoes;
    final parado = resumo.totalParado;
    final aindaParado = paradas.any((p) => p.fim == null);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(resumo.encarregado.nome,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          [
            '${resumo.totalPessoas} no efetivo',
            '${atividades.length} atividade(s)',
            if (aindaParado)
              'PARADO AGORA'
            else if (paradas.isNotEmpty)
              '${formatarDuracao(parado)} parado',
          ].join(' · '),
          style: theme.textTheme.labelSmall?.copyWith(
              color: aindaParado ? theme.colorScheme.error : null),
        ),
        children: [
          if ((resumo.clima?.linha ?? '').isNotEmpty)
            _secao('Clima', [resumo.clima!.linha]),
          if (resumo.efetivo.isNotEmpty)
            _secao('Efetivo', [for (final f in resumo.efetivo) f.linha]),
          _secao(
            'Atividades',
            atividades,
            vazio: 'Nenhuma atividade registrada no app neste dia',
          ),
          if (paradas.isNotEmpty)
            _secao('Paralisações', [for (final p in paradas) p.descricao]),
          if (resumo.registros.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Último registro às '
                  '${formatarHora(resumo.registros.last.criadoEm.toIso8601String())}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _secao(String titulo, List<String> itens, {String? vazio}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 2),
          if (itens.isEmpty && vazio != null)
            Text(vazio,
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))
          else
            for (final item in itens)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $item', style: const TextStyle(fontSize: 12)),
              ),
        ],
      ),
    );
  }
}

// Foto por baixar e o índice do encarregado dono dela.
class _FotoPendente {
  final int encarregado;
  final String caminho;
  final String legenda;

  const _FotoPendente({
    required this.encarregado,
    required this.caminho,
    required this.legenda,
  });
}
