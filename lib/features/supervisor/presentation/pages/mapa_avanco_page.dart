import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/utils/date_formatter.dart';
import '../../../auth/auth_service.dart';
import '../../../auth/models/usuario.dart';
import '../../../mapa/navegacao_estacas_service.dart';
import '../../../mapa/presentation/pages/map_page.dart' show camadasDoProjeto;
import '../../../registro/models/grupo_atividade.dart' show formatarQuantidade;
import '../../../registro/models/registro.dart';
import '../../../registro/registro_service.dart';
import '../../../registro/vias_estaqueamento.dart' show faixaDeKm;
import '../../../relatorio/turno_noturno.dart';
import '../../avanco.dart';
import '../../registros_equipe_service.dart';

// Janela de tempo do mapa da equipe.
enum _Periodo {
  hoje(1, 'Hoje'),
  semana(7, '7 dias'),
  mes(30, '30 dias'),
  trimestre(90, '90 dias'),
  tudo(null, 'Tudo');

  final int? dias;
  final String rotulo;
  const _Periodo(this.dias, this.rotulo);
}

// Registro do aparelho no formato do mapa.
RegistroDaEquipe _doAparelho(Registro r, Usuario usuario) => RegistroDaEquipe(
      dispositivoId: '',
      idLocal: r.id ?? 0,
      usuarioNome: usuario.nome,
      usuarioMatricula: usuario.matricula,
      trecho: r.trecho,
      km: r.km,
      kmFinal: r.kmFinal,
      via: r.via,
      atividade: r.atividade,
      estacaInicial: r.estacaInicial,
      estacaFinal: r.estacaFinal,
      servicoNotavel: r.servicoNotavel,
      servicoNotavelDetalhe: r.servicoNotavelDetalhe,
      quantidade: r.quantidade,
      unidade: r.unidade,
      descricao: r.descricao,
      criadoEm: DateTime.tryParse(r.criadoEm)?.toLocal() ?? DateTime.now(),
    );

// Onde cada serviço foi executado, pintado sobre as estacas do projeto, com
// o acumulado por serviço e KM. Duas versões: a da equipe (supervisor, do
// servidor, por período) e a do encarregado (só o dele, dia a dia).
class MapaAvancoPage extends StatefulWidget {
  // Matrículas da equipe (e a do próprio supervisor).
  final List<String> matriculas;

  // Encarregado vendo o próprio dia; null no mapa da equipe.
  final Usuario? usuario;

  // Dia em que o mapa do encarregado abre.
  final DateTime? dia;

  const MapaAvancoPage.daEquipe({super.key, required this.matriculas})
      : usuario = null,
        dia = null;

  const MapaAvancoPage.doEncarregado({super.key, required Usuario this.usuario, this.dia})
      : matriculas = const [];

  @override
  State<MapaAvancoPage> createState() => _MapaAvancoPageState();
}

class _MapaAvancoPageState extends State<MapaAvancoPage> {
  final _mapa = MapController();
  final LayerHitNotifier<RegistroDaEquipe> _toque = ValueNotifier(null);
  bool _mapaPronto = false;

  bool get _doEncarregadoLogado => widget.usuario != null;

  bool get _noturno => TurnoNoturnoService.instancia.ehNoturno(
      AuthService.instancia.usuarioLogado?.matricula ?? widget.usuario?.matricula ?? '');

  // Dia de trabalho no mapa do encarregado.
  late DateTime _dia = () {
    final d = widget.dia ?? diaDoTurno(DateTime.now(), noturno: _noturno);
    return DateTime(d.year, d.month, d.day);
  }();

  _Periodo _periodo = _Periodo.mes;
  String? _servico; // null = todos
  String? _encarregado; // matrícula; null = todos

  EstacasPorTrecho _estacas = {};

  // Eixo do projeto, uma linha por trecho e pista (no C1 as séries 1000 e
  // 2000 não se ligam).
  List<List<LatLng>> _eixos = [];
  List<RegistroDaEquipe> _registros = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _mapa.dispose();
    _toque.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    if (_estacas.isEmpty) {
      _estacas = agruparEstacasPorTrecho(
          await NavegacaoEstacasService.instancia.todas());
      final porPista = <String, List<LatLng>>{};
      for (final lista in _estacas.values) {
        for (final e in lista) {
          porPista.putIfAbsent('${e.trecho}|${e.via}', () => []).add(e.ponto);
        }
      }
      _eixos = [for (final l in porPista.values) if (l.length > 1) l];
    }
    final registros = _doEncarregadoLogado
        ? await _registrosDoDia()
        : await RegistrosEquipeService.instancia.registrosDoPeriodo(
            widget.matriculas,
            desde: _inicioDoPeriodo(),
          );
    if (!mounted) return;
    setState(() {
      _carregando = false;
      if (registros == null) {
        _erro = 'Não foi possível buscar os registros. Confira a internet.';
        return;
      }
      _registros = registros;
      // Filtro que sumiu do período volta para "todos".
      if (_servico != null && !registros.any((r) => r.servicoNotavel == _servico)) {
        _servico = null;
      }
      if (_encarregado != null &&
          !registros.any((r) => r.usuarioMatricula == _encarregado)) {
        _encarregado = null;
      }
    });
    _enquadrar();
  }

  DateTime? _inicioDoPeriodo() {
    final dias = _periodo.dias;
    if (dias == null) return null;
    final hoje = DateTime.now();
    return DateTime(hoje.year, hoje.month, hoje.day - dias + 1);
  }

  // Registros do encarregado no dia de trabalho [_dia], do aparelho (vale
  // sem internet). O que ele lançou em nome de outro não é dele.
  Future<List<RegistroDaEquipe>> _registrosDoDia() async {
    final usuario = widget.usuario!;
    final todos = await RegistroService.instancia.listarRegistros(usuario.id!);
    final doDia = [
      for (final r in todos)
        if (!r.lancadoPorTerceiro &&
            diaLocalDe(r.criadoEm) != null &&
            diaDoTurno(DateTime.parse(r.criadoEm).toLocal(), noturno: _noturno) == _dia)
          _doAparelho(r, usuario),
    ];
    // A lista vem do mais novo; o mapa desenha do mais antigo.
    return doDia..sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
  }

  Future<void> _mudarDia(DateTime dia) async {
    setState(() => _dia = DateTime(dia.year, dia.month, dia.day));
    await _carregar();
  }

  List<RegistroDaEquipe> get _doEncarregado => _encarregado == null
      ? _registros
      : _registros.where((r) => r.usuarioMatricula == _encarregado).toList();

  List<RegistroDaEquipe> get _filtrados => _servico == null
      ? _doEncarregado
      : _doEncarregado.where((r) => r.servicoNotavel == _servico).toList();

  // Serviços do período (com o filtro de encarregado), do mais ao menos
  // registrado; a posição dá a cor, a mesma do mapa no relatório.
  List<String> get _servicos =>
      servicosPorFrequencia(_doEncarregado.map((r) => r.servicoNotavel));

  Color _corDe(String servico, List<String> servicos) =>
      Color(corDoServico(servico, servicos));

  // Enquadra os pontos (ou tudo o que está filtrado).
  void _enquadrar([List<LatLng>? pontos]) {
    if (!_mapaPronto) return;
    final alvo = pontos ??
        [
          for (final r in _filtrados)
            for (final e in estacasDoRegistro(r, _estacas)) e.ponto,
        ];
    if (alvo.isEmpty) return;
    if (alvo.length == 1) {
      _mapa.move(alvo.first, 17);
      return;
    }
    _mapa.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(alvo),
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 220),
      maxZoom: 18,
    ));
  }

  void _mostrarDetalhes(List<RegistroDaEquipe> registros) {
    if (registros.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final r in registros.reversed) _detalhe(r),
        ],
      ),
    );
  }

  Widget _detalhe(RegistroDaEquipe r) {
    final estacas = r.estacaInicial == r.estacaFinal || r.estacaFinal.isEmpty
        ? r.estacaInicial
        : '${r.estacaInicial} a ${r.estacaFinal}';
    final medicao = r.quantidade != null && r.unidade.isNotEmpty
        ? '${formatarQuantidade(r.quantidade!)} ${r.unidade}'
        : '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        r.servicoNotavelDetalhe.isEmpty
            ? r.servicoNotavel
            : '${r.servicoNotavel} (${r.servicoNotavelDetalhe})',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text([
        [
          '${r.trecho} / KM ${faixaDeKm(r.km, r.kmFinal)}',
          if (estacas.isNotEmpty) 'Est. $estacas',
          if (r.via.isNotEmpty) r.via,
        ].join(' · '),
        [
          r.usuarioNome,
          formatarDataHora(r.criadoEm.toUtc().toIso8601String()),
          if (medicao.isNotEmpty) medicao,
        ].join(' · '),
      ].join('\n')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_doEncarregadoLogado ? 'Mapa do dia' : 'Mapa de avanço')),
      body: Column(
        children: [
          _filtros(),
          Expanded(
            child: _carregando && _registros.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _erro != null
                    ? _mensagem(Icons.cloud_off, _erro!, acao: _carregar)
                    : Stack(
                        children: [
                          _mapaDoAvanco(),
                          if (_carregando)
                            const LinearProgressIndicator(minHeight: 3),
                          _resumo(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _mensagem(IconData icone, String texto, {VoidCallback? acao}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
            if (acao != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: acao, child: const Text('Tentar de novo')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    final servicos = _servicos;
    final encarregados = <String, String>{
      for (final r in _registros) r.usuarioMatricula: r.usuarioNome,
    };
    final nomes = encarregados.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            if (_doEncarregadoLogado)
              _seletorDeDia()
            else
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_Periodo>(
                  segments: [
                    for (final p in _Periodo.values)
                      ButtonSegment(
                        value: p,
                        label: Text(p.rotulo, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                  selected: {_periodo},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (s) {
                    setState(() => _periodo = s.first);
                    _carregar();
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('servico_${_servico}_${servicos.length}'),
                    initialValue: _servico,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Serviço', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      for (final s in servicos)
                        DropdownMenuItem(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (s) {
                      setState(() => _servico = s);
                      _enquadrar();
                    },
                  ),
                ),
                if (!_doEncarregadoLogado) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('enc_${_encarregado}_${nomes.length}'),
                    initialValue: _encarregado,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Encarregado', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      for (final e in nomes)
                        DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (m) {
                      setState(() {
                        _encarregado = m;
                        // O serviço escolhido pode não existir para ele.
                        if (_servico != null &&
                            !_doEncarregado.any((r) => r.servicoNotavel == _servico)) {
                          _servico = null;
                        }
                      });
                      _enquadrar();
                    },
                  ),
                ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ‹ 24/09/2026 › — o dia de trabalho do encarregado.
  Widget _seletorDeDia() {
    final hoje = diaDoTurno(DateTime.now(), noturno: _noturno);
    final ehHoje = _dia == DateTime(hoje.year, hoje.month, hoje.day);
    final data = '${_dia.day.toString().padLeft(2, '0')}/'
        '${_dia.month.toString().padLeft(2, '0')}/${_dia.year}';
    return Row(
      children: [
        IconButton(
          tooltip: 'Dia anterior',
          onPressed: _carregando
              ? null
              : () => _mudarDia(DateTime(_dia.year, _dia.month, _dia.day - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton.icon(
            onPressed: _carregando
                ? null
                : () async {
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
          onPressed: _carregando || ehHoje
              ? null
              : () => _mudarDia(DateTime(_dia.year, _dia.month, _dia.day + 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _mapaDoAvanco() {
    final servicos = _servicos;
    final agora = DateTime.now();
    final linhas = <Polyline<RegistroDaEquipe>>[];
    final pontos = <Marker>[];
    // Do mais antigo ao mais novo: o recente fica por cima.
    for (final r in _filtrados) {
      final estacas = estacasDoRegistro(r, _estacas);
      if (estacas.isEmpty) continue;
      final cor = _corDe(r.servicoNotavel, servicos);
      final recente = registroRecente(r, agora);
      if (estacas.length == 1) {
        pontos.add(Marker(
          point: estacas.first.ponto,
          width: 18,
          height: 18,
          child: GestureDetector(
            onTap: () => _mostrarDetalhes([r]),
            child: Container(
              decoration: BoxDecoration(
                color: recente ? cor : cor.withValues(alpha: 0.55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ));
        continue;
      }
      linhas.add(Polyline(
        points: [for (final e in estacas) e.ponto],
        color: recente ? cor : cor.withValues(alpha: 0.55),
        strokeWidth: recente ? 7 : 5,
        borderColor: Colors.white.withValues(alpha: recente ? 0.9 : 0.5),
        borderStrokeWidth: 1.5,
        strokeCap: StrokeCap.round,
        hitValue: r,
      ));
    }

    // Sem nada filtrado: mostra a obra inteira.
    final inicio = linhas.isNotEmpty || pontos.isNotEmpty
        ? [
            for (final l in linhas) ...l.points,
            for (final p in pontos) p.point,
          ]
        : [for (final eixo in _eixos) ...eixo];

    return FlutterMap(
      mapController: _mapa,
      options: MapOptions(
        initialCameraFit: inicio.length > 1
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(inicio),
                padding: const EdgeInsets.fromLTRB(40, 40, 40, 220),
                maxZoom: 18,
              )
            : null,
        initialCenter: inicio.isEmpty ? const LatLng(-19.95, -40.40) : inicio.first,
        initialZoom: 14,
        minZoom: 10,
        maxZoom: 20,
        onMapReady: () => _mapaPronto = true,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
              'World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.example.namer_app',
          maxNativeZoom: 18,
        ),
        // Ortofoto e desenho do projeto, os da aba Mapa. Só de perto: de
        // longe seriam centenas de tiles de uma vez.
        ...camadasDoProjeto(zoomMinimo: 17),
        // O eixo do projeto, fino, para dar referência onde nada foi feito.
        PolylineLayer(
          polylines: [
            for (final eixo in _eixos)
              Polyline(
                points: eixo,
                color: Colors.white.withValues(alpha: 0.35),
                strokeWidth: 2,
              ),
          ],
        ),
        GestureDetector(
          onTap: () => _mostrarDetalhes(_toque.value?.hitValues ?? const []),
          child: PolylineLayer<RegistroDaEquipe>(
            hitNotifier: _toque,
            polylines: linhas,
          ),
        ),
        MarkerLayer(markers: pontos),
      ],
    );
  }

  Widget _resumo() {
    final theme = Theme.of(context);
    final servicos = _servicos;
    final filtrados = _filtrados;
    final resumo = resumirAvanco(filtrados, _estacas);
    final foraDoMapa = resumo.fold(0, (soma, s) => soma + s.foraDoMapa);

    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.1,
      maxChildSize: 0.85,
      builder: (context, rolagem) => Material(
        elevation: 8,
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: ListView(
          controller: rolagem,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              filtrados.isEmpty
                  ? _doEncarregadoLogado
                      ? 'Nenhum registro neste dia'
                      : 'Nenhum registro no período'
                  : '${filtrados.length} registro(s) · ${resumo.length} serviço(s)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              '${_doEncarregadoLogado ? '' : 'Linha forte: últimos 7 dias. '}'
              'Toque numa linha para ver o registro.'
              '${foraDoMapa > 0 ? '\n$foraDoMapa registro(s) sem estaca no mapa '
                  '(área de apoio ou estaca sem coordenada).' : ''}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final s in resumo) _cartaoServico(theme, s, _corDe(s.servico, servicos)),
          ],
        ),
      ),
    );
  }

  Widget _cartaoServico(ThemeData theme, AvancoDoServico s, Color cor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(radius: 8, backgroundColor: cor),
        title: Text(s.servico,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(_numeros(s.quantidades, s.metros, s.registros),
            style: theme.textTheme.bodySmall),
        children: [
          for (final km in s.kms)
            ListTile(
              dense: true,
              title: Text('${km.trecho} · KM ${km.km}'),
              subtitle: Text(_numeros(km.quantidades, km.metros, km.registros)),
              trailing: km.pontos.isEmpty
                  ? null
                  : const Icon(Icons.center_focus_strong_outlined, size: 20),
              // Leva o mapa até o KM.
              onTap: km.pontos.isEmpty ? null : () => _enquadrar(km.pontos),
            ),
        ],
      ),
    );
  }

  String _numeros(Map<String, double> quantidades, double metros, int registros) => [
        if (quantidades.isNotEmpty) formatarQuantidades(quantidades),
        if (metros > 0) formatarExtensao(metros),
        '$registros registro(s)',
      ].join(' · ');
}
