import 'package:flutter/material.dart';
import '../../../../core/localizacao_service.dart';
import '../../../auth/auth_service.dart';
import '../../../auth/models/usuario.dart';
import '../../../paralisacao/presentation/widgets/paralisacoes_do_dia.dart';
import '../../../sincronizacao/sincronizacao_service.dart';
import '../../clima_service.dart';
import '../../equipe_simova_service.dart';
import '../../models/relatorio_diario_info.dart';
import '../../relatorio_service.dart';
import '../../turno_noturno.dart';
import 'relatorio_pdf_preview_page.dart';

// Catálogos de funções e máquinas: o usuário só informa quantidades (zero não
// entra no relatório). A equipe também pode vir do apontamento.
const _funcoesEquipe = [
  'Armador',
  'Carpinteiro',
  'Greidista',
  'Meio Oficial Pedreiro',
  'Motorista Bomba Concreto',
  'Motorista De Carreta',
  'Motorista Operador',
  'Motorista T. C. Especiais',
  'Motorista Veic. Pesados',
  'Operador Maq. Pesadas',
  'Pedreiro',
  'Servente',
  'Sinaleiro',
];

const _tiposMaquinas = [
  'Basculante',
  'Betoneira',
  'Carroceria',
  'Comboio',
  'Espargidor',
  'Munck',
  'Pipa',
  'Pipa Abastecedor',
  'Bomba Lança',
  'Carregadeira de Pneus',
  'Cavalo Mecânico',
  'Escavadeira Hidráulica',
  'Escavadeira Hidráulica Rompedor',
  'Manipulador Telescópio',
  'Mini-Carregadeira',
  'Mini-Escavadeira',
  'Motoniveladora',
  'Retroescavadeira',
  'Rolo Compactador',
  'Trator Agrícola',
  'Trator Esteira',
  'Vibro-Acabadora',
];

// Formulário do RDO antes de gerar o PDF. Atividades e encarregado não são
// digitados: vêm dos registros e do usuário logado.
class RelatorioFormPage extends StatefulWidget {
  final Usuario usuario;
  final DateTime dia;

  const RelatorioFormPage({super.key, required this.usuario, required this.dia});

  @override
  State<RelatorioFormPage> createState() => _RelatorioFormPageState();
}

class _RelatorioFormPageState extends State<RelatorioFormPage> {
  final _ddsTemaController = TextEditingController();
  final _qtdEquipe = {for (final f in _funcoesEquipe) f: TextEditingController()};
  final _qtdMaquinas = {for (final m in _tiposMaquinas) m: TextEditingController()};
  TimeOfDay _horarioInicio = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _horarioFim = const TimeOfDay(hour: 17, minute: 0);
  // Condição do tempo escolhida por período (índice de periodosClima), ou null.
  final Map<String, String?> _clima = {for (final p in periodosClima) p: null};
  // Última sugestão do tempo da região (com a chuva estimada), se houve.
  Map<String, ClimaDoPeriodo>? _sugestaoClima;
  bool _buscandoClima = false;
  // Equipe vinda do apontamento; null = ainda não buscada neste dia.
  List<FuncaoEquipe>? _equipeSimova;
  // Origem da equipe escolhida pelo usuário: apontamento (padrão) ou digitada.
  bool _equipeManual = false;
  bool _buscandoEquipe = false;
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarInfoSalva();
  }

  @override
  void dispose() {
    _ddsTemaController.dispose();
    for (final c in _qtdEquipe.values) {
      c.dispose();
    }
    for (final c in _qtdMaquinas.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Pré-preenche com o que já foi salvo para o dia.
  Future<void> _carregarInfoSalva() async {
    final info = await RelatorioService.instancia.buscarInfoDoDia(widget.usuario.id!, widget.dia);
    if (!mounted) return;
    if (info != null) {
      _ddsTemaController.text = info.ddsTema;
      // Reabre no modo salvo (função fora do catálogo = veio do apontamento).
      final salva = _lerEquipeSalva(info.equipe);
      final doApontamento =
          salva.any((f) => !_funcoesEquipe.contains(f.funcao));
      if (doApontamento) {
        _equipeSimova = salva;
      } else if (salva.isNotEmpty) {
        _equipeManual = true;
        _aplicarQuantidadesSalvas(info.equipe, _qtdEquipe);
      }
      _aplicarQuantidadesSalvas(info.maquinasEquipamentos, _qtdMaquinas);
      _horarioInicio = _parseHorario(info.horarioInicio) ?? _horarioInicio;
      _horarioFim = _parseHorario(info.horarioFim) ?? _horarioFim;
      _clima['Manhã'] = info.climaManha.isEmpty ? null : info.climaManha;
      _clima['Tarde'] = info.climaTarde.isEmpty ? null : info.climaTarde;
      _clima['Noite'] = info.climaNoite.isEmpty ? null : info.climaNoite;
    }
    setState(() => _carregando = false);
    // Nada informado ainda: já traz a sugestão do tempo.
    if (_clima.values.every((c) => c == null)) _sugerirClima(automatico: true);
  }

  bool get _noturno => TurnoNoturnoService.instancia.ehNoturno(
      AuthService.instancia.usuarioLogado?.matricula ?? widget.usuario.matricula);

  // Preenche o clima pelo tempo da região. Automático, só completa o vazio e
  // não avisa falha; pelo botão, substitui e avisa.
  Future<void> _sugerirClima({bool automatico = false}) async {
    setState(() => _buscandoClima = true);
    try {
      // Onde a obra estava: as fotos do dia; sem elas, o GPS de agora.
      var posicao = await RelatorioService.instancia
          .posicaoDoDia(widget.usuario.id!, widget.dia, noturno: _noturno);
      if (posicao == null) {
        final gps = await LocalizacaoService.instancia
            .posicaoConfiavel(espera: const Duration(seconds: 3));
        if (gps != null) posicao = (latitude: gps.latitude, longitude: gps.longitude);
      }
      if (posicao == null) {
        if (!automatico) _avisar('Sem localização para buscar o tempo');
        return;
      }
      final sugestao = await ClimaService.instancia.sugerir(
        dia: widget.dia,
        latitude: posicao.latitude,
        longitude: posicao.longitude,
        incluirNoite: _noturno,
      );
      if (!mounted) return;
      if (sugestao == null || sugestao.isEmpty) {
        if (!automatico) _avisar('Não deu para buscar o tempo. Confira a internet.');
        return;
      }
      setState(() {
        _sugestaoClima = sugestao;
        for (final MapEntry(key: periodo, value: clima) in sugestao.entries) {
          if (!automatico || _clima[periodo] == null) _clima[periodo] = clima.condicao;
        }
      });
    } finally {
      if (mounted) setState(() => _buscandoClima = false);
    }
  }

  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  // Relê as linhas "44 - Motorista Veic. Pesados" salvas no dia.
  List<FuncaoEquipe> _lerEquipeSalva(String textoSalvo) {
    final itens = <FuncaoEquipe>[];
    for (final linha in textoSalvo.split('\n')) {
      final match = RegExp(r'^(\d+)\s*-\s*(.+)$').firstMatch(linha.trim());
      if (match == null) continue;
      itens.add(FuncaoEquipe(
        funcao: match.group(2)!.trim(),
        quantidade: int.parse(match.group(1)!),
      ));
    }
    return itens;
  }

  Future<void> _buscarEquipeDoApontamento() async {
    setState(() => _buscandoEquipe = true);
    // Relê a matrícula do servidor antes de buscar.
    final usuario = await AuthService.instancia.sincronizarPerfil();
    final resultado = await EquipeSimovaService.instancia.buscar(
      matricula: usuario?.matricula ?? widget.usuario.matricula,
      dia: widget.dia,
    );
    if (!mounted) return;
    setState(() {
      _buscandoEquipe = false;
      if (resultado.equipe != null) _equipeSimova = resultado.equipe;
    });

    if (resultado.equipe != null) return;

    // Dia sem apontamento ou matrícula que não bate: cada um com sua pista.
    final dias = resultado.diasComApontamento;
    final encarregados = resultado.encarregadosDoDia;
    var mensagem = resultado.erro!;
    if (dias.isNotEmpty) {
      mensagem += '.\nVocê tem apontamento em: ${dias.take(5).join(', ')}'
          '${dias.length > 5 ? '…' : ''}';
    } else if (encarregados.isNotEmpty) {
      mensagem += '.\nEncarregados com apontamento neste dia: '
          '${encarregados.take(5).join(', ')}'
          '${encarregados.length > 5 ? '…' : ''}';
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(
          seconds: dias.isEmpty && encarregados.isEmpty ? 4 : 10),
      content: Text(mensagem),
    ));
  }

  // Linhas "2 - Carpinteiro" de volta para os campos de quantidade.
  void _aplicarQuantidadesSalvas(String textoSalvo, Map<String, TextEditingController> quantidades) {
    for (final linha in textoSalvo.split('\n')) {
      final match = RegExp(r'^(\d+)\s*-\s*(.+)$').firstMatch(linha.trim());
      if (match == null) continue;
      final controller = quantidades[match.group(2)!.trim()];
      if (controller != null) controller.text = match.group(1)!;
    }
  }

  // "2 - Carpinteiro\n1 - Servente..." só com quantidade > 0.
  String _montarLista(List<String> catalogo, Map<String, TextEditingController> quantidades) {
    final linhas = <String>[];
    for (final nome in catalogo) {
      final qtd = int.tryParse(quantidades[nome]!.text.trim()) ?? 0;
      if (qtd > 0) linhas.add('$qtd - $nome');
    }
    return linhas.join('\n');
  }

  TimeOfDay? _parseHorario(String hhmm) {
    final partes = hhmm.split(':');
    if (partes.length != 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatarHorario(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _escolherHorario({required bool inicio}) async {
    final escolhido = await showTimePicker(
      context: context,
      initialTime: inicio ? _horarioInicio : _horarioFim,
    );
    if (escolhido != null) {
      setState(() => inicio ? _horarioInicio = escolhido : _horarioFim = escolhido);
    }
  }

  Future<void> _gerarPdf() async {
    setState(() => _salvando = true);
    try {
      final info = RelatorioDiarioInfo(
        usuarioId: widget.usuario.id!,
        data: '${widget.dia.year.toString().padLeft(4, '0')}-'
            '${widget.dia.month.toString().padLeft(2, '0')}-'
            '${widget.dia.day.toString().padLeft(2, '0')}',
        encarregado: widget.usuario.nome,
        equipe: _equipeManual
            ? _montarLista(_funcoesEquipe, _qtdEquipe)
            : (_equipeSimova ?? []).map((f) => f.linha).join('\n'),
        ddsTema: _ddsTemaController.text.trim(),
        horarioInicio: _formatarHorario(_horarioInicio),
        horarioFim: _formatarHorario(_horarioFim),
        maquinasEquipamentos: _montarLista(_tiposMaquinas, _qtdMaquinas),
        climaManha: _clima['Manhã'] ?? '',
        climaTarde: _clima['Tarde'] ?? '',
        climaNoite: _clima['Noite'] ?? '',
      );
      await RelatorioService.instancia.salvarInfoDoDia(info);
      // Leva o clima para o relatório do supervisor.
      SincronizacaoService.instancia.sincronizar();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RelatorioPdfPreviewPage(usuario: widget.usuario, dia: widget.dia, info: info),
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Informações do relatório')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Encarregado: ${widget.usuario.nome}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
            controller: _ddsTemaController,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'DDS/Ordem Unida - Tema',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _escolherHorario(inicio: true),
                  icon: const Icon(Icons.schedule),
                  label: Text('Início: ${_formatarHorario(_horarioInicio)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _escolherHorario(inicio: false),
                  icon: const Icon(Icons.schedule),
                  label: Text('Término: ${_formatarHorario(_horarioFim)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _construirClima(),
          const SizedBox(height: 16),
          // Lança ou corrige as paralisações deste dia antes de gerar.
          ParalisacoesDoDia(usuario: widget.usuario, dia: widget.dia),
          const SizedBox(height: 16),
          // Equipe na largura toda: os nomes de função são longos.
          _construirEquipe(),
          const SizedBox(height: 16),
          _construirColunaCatalogo(
              'Máquinas e Equipamentos', _tiposMaquinas, _qtdMaquinas),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _salvando ? null : _gerarPdf,
            icon: _salvando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
            label: Text(_salvando ? 'Gerando...' : 'Gerar PDF'),
          ),
        ],
      ),
    );
  }

  // Equipe do apontamento (precisa de internet) ou digitada (offline).
  Widget _construirEquipe() {
    final doApontamento = _equipeSimova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Equipe', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Do apontamento', style: TextStyle(fontSize: 12)),
              icon: Icon(Icons.cloud_download_outlined, size: 16),
            ),
            ButtonSegment(
              value: true,
              label: Text('Manual', style: TextStyle(fontSize: 12)),
              icon: Icon(Icons.edit_outlined, size: 16),
            ),
          ],
          selected: {_equipeManual},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (s) => setState(() => _equipeManual = s.first),
        ),
        const SizedBox(height: 8),
        if (_equipeManual)
          _construirGradeQuantidades(_funcoesEquipe, _qtdEquipe)
        else if (doApontamento == null) ...[
          const Text(
            'Traz a equipe do apontamento do dia, já contada por função.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _buscandoEquipe ? null : _buscarEquipeDoApontamento,
            icon: _buscandoEquipe
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.groups, size: 18),
            label: Text(
              _buscandoEquipe ? 'Buscando…' : 'Buscar equipe do dia',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ] else ...[
          for (final f in doApontamento)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${f.quantidade}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Text(f.funcao, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _buscandoEquipe ? null : _buscarEquipeDoApontamento,
              icon: _buscandoEquipe
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16),
              label: Text(_buscandoEquipe ? 'Buscando…' : 'Atualizar equipe',
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ],
    );
  }

  // Clima por período; tocar de novo no chip limpa.
  Widget _construirClima() {
    final sugestao = _sugestaoClima;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Condições climáticas',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _buscandoClima ? null : () => _sugerirClima(),
              icon: _buscandoClima
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_sync_outlined, size: 18),
              label: Text(_buscandoClima ? 'Buscando…' : 'Sugerir pelo tempo',
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final periodo in periodosClima)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(periodo, style: const TextStyle(fontSize: 12)),
                      // Chuva estimada: ajuda a decidir entre Chuvoso e Impraticável.
                      if ((sugestao?[periodo]?.chuvaMm ?? 0) > 0)
                        Text(
                          '${sugestao![periodo]!.chuvaMm.toStringAsFixed(1).replaceAll('.', ',')} mm',
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final condicao in condicoesClima)
                        ChoiceChip(
                          label: Text(condicao, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          selected: _clima[periodo] == condicao,
                          onSelected: (sel) => setState(() {
                            _clima[periodo] = sel ? condicao : null;
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (sugestao != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Sugerido pelo tempo da região. Confira: se não deu para '
              'trabalhar, marque "Impraticável".',
              style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  // Catálogo com título e a grade de quantidades embaixo.
  Widget _construirColunaCatalogo(
    String titulo,
    List<String> catalogo,
    Map<String, TextEditingController> quantidades,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        _construirGradeQuantidades(catalogo, quantidades),
      ],
    );
  }

  // Duas colunas: com 22 máquinas, uma só rolaria demais.
  Widget _construirGradeQuantidades(
    List<String> catalogo,
    Map<String, TextEditingController> quantidades,
  ) {
    final metade = (catalogo.length / 2).ceil();
    final esquerda = catalogo.take(metade).toList();
    final direita = catalogo.skip(metade).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              for (final nome in esquerda) _linhaQuantidade(nome, quantidades[nome]!),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              for (final nome in direita) _linhaQuantidade(nome, quantidades[nome]!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linhaQuantidade(String nome, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(nome, style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(),
                hintText: '0',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
