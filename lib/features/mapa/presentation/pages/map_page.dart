import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/dados_remotos.dart';
import '../../../../core/localizacao_service.dart';
import '../../../../core/utils/utm.dart';
import '../../mapa_estatico.dart' show PecaDoProjeto;
import '../../mapas_config.dart';
import '../../navegacao_estacas_service.dart';
import '../../permissao_mapas_service.dart';

// Conversão UTM em core/utils/utm.dart.

double _distanciaMedicao(List<LatLng> pontos) {
  if (pontos.length < 2) return 0;
  final utm = pontos.map(latLngParaUtm).toList();
  var total = 0.0;
  for (var i = 0; i < utm.length - 1; i++) {
    final dx = utm[i + 1].x - utm[i].x;
    final dy = utm[i + 1].y - utm[i].y;
    total += sqrt(dx * dx + dy * dy);
  }
  return total;
}

double _areaMedicao(List<LatLng> pontos) {
  if (pontos.length < 3) return 0;
  final utm = pontos.map(latLngParaUtm).toList();
  var soma = 0.0;
  for (var i = 0; i < utm.length; i++) {
    final p1 = utm[i];
    final p2 = utm[(i + 1) % utm.length];
    soma += p1.x * p2.y - p2.x * p1.y;
  }
  return soma.abs() / 2;
}

String _formatDistancia(double metros) {
  if (metros >= 1000) return '${(metros / 1000).toStringAsFixed(2)} km';
  return '${metros.toStringAsFixed(1)} m';
}


String _formatArea(double m2) => '${m2.toStringAsFixed(1)} m²';

bool _overlaps(LatLngBounds a, LatLngBounds b) =>
    a.south <= b.north &&
    a.north >= b.south &&
    a.west  <= b.east  &&
    a.east  >= b.west;

class _MapDef {
  final int rows;
  final int cols;
  final String tileDir;
  final List<List<LatLng>> _grid;

  _MapDef({
    required double swE,
    required double swN,
    required double neE,
    required double neN,
    required this.rows,
    required this.cols,
    required this.tileDir,
    String zoneName = zonaUtmNomePadrao,
    String zoneDef = zonaUtmDefPadrao,
  }) : _grid = List.generate(
          rows + 1,
          (r) => List.generate(
            cols + 1,
            (c) => utmParaLatLng(
              swE + (neE - swE) * c / cols,
              neN - (neN - swN) * r / rows,
              zoneName: zoneName,
              zoneDef: zoneDef,
            ),
          ),
        );


  LatLng corner(int row, int col) => _grid[row][col];

  LatLng get sw => _grid[rows][0];
  LatLng get ne => _grid[0][cols];


  LatLngBounds pieceEnvelope(int row, int col) => LatLngBounds.fromPoints([
        corner(row, col),
        corner(row, col + 1),
        corner(row + 1, col),
        corner(row + 1, col + 1),
      ]);
}

final _mapa1 = _MapDef(
  swE: 351849.7584, swN: 7784342.6030,
  neE: 354010.7511, neN: 7794250.1072,
  cols: 25,
  rows: 90,
  tileDir: mapasConfig[0].assetDir, // D2
);

final _mapa2 = _MapDef(
  swE: 351473.537, swN: 7796577.542,
  neE: 355442.406, neN: 7803295.129,
  cols: 30,
  rows: 60,
  tileDir: mapasConfig[1].assetDir, // C1
);

final _mapa3 = _MapDef(
  swE: 352423.387 , swN: 7793005.057, 
  neE: 354770.603, neN: 7797645.351, 
  cols: 15,
  rows: 30,
  tileDir: mapasConfig[2].assetDir, // Contorno_Fundão
);

final _mapa4 = _MapDef(
  swE: 354902.080, swN: 7806251.889, 
  neE: 357104.019, neN: 7808991.788, 
  cols: 20,
  rows: 30,
  tileDir: mapasConfig[3].assetDir, // Contorno_Ibiraçu
);
final _mapa5 = _MapDef(
  swE: 356373.777, swN: 7807923.567, 
  neE: 356763.392, neN: 7808298.461, 
  cols: 10,
  rows: 10,
  tileDir: mapasConfig[4].assetDir, // GEO_dreno
);

// Coordenadas de cada mapa de mapasConfig; sem entrada aqui, não é desenhado.
final Map<String, _MapDef> _defsPorNome = {
  'D2': _mapa1,
  'C1': _mapa2,
  'Contorno_Fundão': _mapa3,
  'Contorno_Ibiraçu': _mapa4,
  'GEO_dreno': _mapa5,
};

// Mapas dos grupos do usuário (ver PermissaoMapasService).
List<_MapDef> _mapasVisiveis() => [
      for (final info
          in mapasDosGrupos(PermissaoMapasService.instancia.grupos.value))
        if (_defsPorNome[info.nome] != null) _defsPorNome[info.nome]!,
    ];

// Camadas do mapa do projeto para outro FlutterMap (mapa de avanço). Só
// aparecem a partir de [zoomMinimo]: de longe seriam centenas de tiles.
List<Widget> camadasDoProjeto({double zoomMinimo = 14}) => [
      for (final mapa in _mapasVisiveis())
        _OverlayLayer(mapa, zoomMinimo: zoomMinimo),
    ];

// Tiles já baixados dos mapas do usuário que cruzam [area], com os cantos
// no mapa (para o mapa do relatório).
List<PecaDoProjeto> pecasDoProjetoEm(LatLngBounds area) {
  final dir = dirDadosRemotos;
  if (dir == null) return const [];
  final pecas = <PecaDoProjeto>[];
  for (final def in _mapasVisiveis()) {
    if (!_overlaps(area, LatLngBounds(def.sw, def.ne))) continue;
    final pasta = def.tileDir.split('/').last;
    for (var r = 0; r < def.rows; r++) {
      for (var c = 0; c < def.cols; c++) {
        if (!_overlaps(area, def.pieceEnvelope(r, c))) continue;
        final arquivo = '${dir.path}/$pasta/${r.toString().padLeft(2, '0')}_$c.webp';
        if (!File(arquivo).existsSync()) continue;
        pecas.add(PecaDoProjeto(
          arquivo: arquivo,
          topoEsquerda: def.corner(r, c),
          baseEsquerda: def.corner(r + 1, c),
          baseDireita: def.corner(r + 1, c + 1),
        ));
      }
    }
  }
  return pecas;
}

// Centro do D2, até o GPS dar a primeira posição.
final LatLng _centroInicial = LatLng(
  (_mapa1.sw.latitude + _mapa1.ne.latitude) / 2,
  (_mapa1.sw.longitude + _mapa1.ne.longitude) / 2,
);

// Última posição filtrada (a mesma do carimbo).
LatLng get locAtual =>
    LocalizacaoService.instancia.posicao.value?.ponto ?? _centroInicial;

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  LatLng? _userLocation;
  double _precisaoMetros = 0;
  bool _seguindoUsuario = true;
  EstacaNavegavel? _destino;

  Future<void> _abrirNavegacao() async {
    final escolhida = await showModalBottomSheet<EstacaNavegavel>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FolhaNavegacao(destinoAtual: _destino),
    );
    if (escolhida == null || !mounted) return;
    setState(() {
      _destino = escolhida;
      _seguindoUsuario = false;
    });
    _mapController.move(escolhida.ponto, 20);
  }

  void _limparDestino() => setState(() => _destino = null);

  void _voltarParaMinhaLocalizacao() {
    setState(() => _seguindoUsuario = true);
    final loc = _userLocation;
    if (loc != null) _mapController.move(loc, _mapController.camera.zoom);
  }

  bool _medindo = false;
  final List<LatLng> _pontosMedicao = [];

  void _alternarMedicao() {
    setState(() => _medindo = !_medindo);
  }

  void _adicionarPontoMedicao(LatLng ponto) {
    if (!_medindo) return;
    setState(() => _pontosMedicao.add(ponto));
  }

  void _desfazerPontoMedicao() {
    if (_pontosMedicao.isEmpty) return;
    setState(() => _pontosMedicao.removeLast());
  }

  void _limparMedicao() {
    setState(() => _pontosMedicao.clear());
  }

  static final _center = LatLng(
    (_mapa1.sw.latitude  + _mapa1.ne.latitude)  / 2,
    (_mapa1.sw.longitude + _mapa1.ne.longitude) / 2,
  );

  @override
  void initState() {
    super.initState();
    LocalizacaoService.instancia.posicao.addListener(_aoMoverGps);
    LocalizacaoService.instancia.iniciar();
    // A permissão pode chegar com a tela já aberta.
    PermissaoMapasService.instancia.grupos.addListener(_aoMudarPermissao);
  }

  void _aoMudarPermissao() {
    if (mounted) setState(() {});
  }

  // Nova posição filtrada do GPS (ver LocalizacaoService).
  void _aoMoverGps() {
    final posicao = LocalizacaoService.instancia.posicao.value;
    if (posicao == null || !mounted) return;
    setState(() {
      _userLocation = posicao.ponto;
      _precisaoMetros = posicao.precisaoMetros;
    });
    if (_seguindoUsuario) {
      _mapController.move(posicao.ponto, _mapController.camera.zoom);
    }
  }

  @override
  void dispose() {
    LocalizacaoService.instancia.posicao.removeListener(_aoMoverGps);
    PermissaoMapasService.instancia.grupos.removeListener(_aoMudarPermissao);
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 20,
            minZoom: 18,
            maxZoom: 22,
            onTap: (_, ponto) => _adicionarPontoMedicao(ponto),
            onPositionChanged: (_, porGesto) {
              if (porGesto && _seguindoUsuario) {
                setState(() => _seguindoUsuario = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.example.namer_app',
              maxNativeZoom: 18,
            ),
            for (final mapa in _mapasVisiveis()) _OverlayLayer(mapa),
            // Círculo de precisão.
            if (_userLocation != null && _precisaoMetros > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _userLocation!,
                    radius: _precisaoMetros,
                    useRadiusInMeter: true,
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderColor: Colors.blue.withValues(alpha: 0.5),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            if (_userLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _userLocation!,
                    width: 6,
                    height: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 243, 33, 33),
                        shape: BoxShape.rectangle,
                        border: Border.all(color: Colors.red, width: 3),
                        boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black38)],
                      ),
                    ),
                  ),
                ],
              ),
            if (_pontosMedicao.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _pontosMedicao,
                    color: Colors.amber.withValues(alpha: 0.25),
                    borderColor: Colors.amber,
                    borderStrokeWidth: 3,
                  ),
                ],
              ),
            if (_pontosMedicao.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _pontosMedicao,
                    color: Colors.amber,
                    strokeWidth: 3,
                  ),
                ],
              ),
            // Linha até a estaca escolhida (mostra a direção).
            if (_destino != null && _userLocation != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [_userLocation!, _destino!.ponto],
                    color: Colors.lightBlueAccent,
                    strokeWidth: 3,
                    pattern: StrokePattern.dashed(segments: const [12, 8]),
                  ),
                ],
              ),
            if (_destino != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _destino!.ponto,
                    width: 34,
                    height: 34,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(blurRadius: 4, color: Colors.black38),
                        ],
                      ),
                      child: const Icon(Icons.place, size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            if (_pontosMedicao.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final p in _pontosMedicao)
                    Marker(
                      point: p,
                      width: 14,
                      height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (_medindo)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _PainelMedicao(
              pontos: _pontosMedicao,
              onDesfazer: _desfazerPontoMedicao,
              onLimpar: _limparMedicao,
            ),
          ),
        if (!_medindo && _destino != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _PainelDestino(
              destino: _destino!,
              usuario: _userLocation,
              onTrocar: _abrirNavegacao,
              onLimpar: _limparDestino,
            ),
          ),
        Positioned(
          right: 12,
          bottom: _medindo
              ? 180
              : _destino != null
                  ? 140
                  : 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_medindo) ...[
                FloatingActionButton.small(
                  heroTag: 'btnNavegar',
                  tooltip: 'Ir para uma estaca',
                  backgroundColor: _destino != null ? Colors.lightBlueAccent : null,
                  onPressed: _abrirNavegacao,
                  child: const Icon(Icons.signpost_outlined),
                ),
                const SizedBox(height: 10),
                // Volta ao GPS; destacado enquanto o mapa segue o usuário.
                FloatingActionButton.small(
                  heroTag: 'btnMinhaLocalizacao',
                  tooltip: _seguindoUsuario
                      ? 'Seguindo sua localização'
                      : 'Voltar para minha localização',
                  backgroundColor: _seguindoUsuario ? Colors.lightBlue : null,
                  foregroundColor: _seguindoUsuario ? Colors.white : null,
                  onPressed: _voltarParaMinhaLocalizacao,
                  child: Icon(_seguindoUsuario
                      ? Icons.my_location
                      : Icons.location_searching),
                ),
                const SizedBox(height: 10),
              ],
              FloatingActionButton(
                heroTag: 'btnMedicao',
                backgroundColor: _medindo ? Colors.amber : null,
                onPressed: _alternarMedicao,
                child: Icon(_medindo ? Icons.close : Icons.straighten),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

//  Estaca destino
class _PainelDestino extends StatelessWidget {
  final EstacaNavegavel destino;
  final LatLng? usuario;
  final VoidCallback onTrocar;
  final VoidCallback onLimpar;

  const _PainelDestino({
    required this.destino,
    required this.usuario,
    required this.onTrocar,
    required this.onLimpar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distancia =
        usuario == null ? null : _distanciaMedicao([usuario!, destino.ponto]);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.place, color: Colors.lightBlueAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${destino.descricao} • ${destino.trecho} • KM ${destino.km}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (distancia != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 32),
                child: Text('Você está a ${_formatDistancia(distancia)} daqui'),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onTrocar,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Trocar'),
                ),
                TextButton.icon(
                  onPressed: onLimpar,
                  icon: const Icon(Icons.close),
                  label: const Text('Encerrar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Folha de seleção: trecho → KM → estaca ────────────────────────────────────
class _FolhaNavegacao extends StatefulWidget {
  final EstacaNavegavel? destinoAtual;
  const _FolhaNavegacao({this.destinoAtual});

  @override
  State<_FolhaNavegacao> createState() => _FolhaNavegacaoState();
}

class _FolhaNavegacaoState extends State<_FolhaNavegacao> {
  final _servico = NavegacaoEstacasService.instancia;

  List<String> _trechos = [];
  List<String> _kms = [];
  List<EstacaNavegavel> _estacas = [];

  String? _trecho;
  String? _km;

  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarInicial();
  }

  Future<void> _carregarInicial() async {
    final trechos = await _servico.trechos();
    if (!mounted) return;
    // Reabre no trecho/KM atual: o comum é ir para a estaca vizinha.
    final atual = widget.destinoAtual;
    setState(() {
      _trechos = trechos;
      _carregando = false;
    });
    if (atual != null && trechos.contains(atual.trecho)) {
      await _selecionarTrecho(atual.trecho);
      if (mounted) await _selecionarKm(atual.km);
    }
  }

  Future<void> _selecionarTrecho(String trecho) async {
    setState(() {
      _trecho = trecho;
      _km = null;
      _kms = [];
      _estacas = [];
    });
    final kms = await _servico.kms(trecho);
    if (!mounted) return;
    setState(() => _kms = kms);
  }

  Future<void> _selecionarKm(String km) async {
    setState(() {
      _km = km;
      _estacas = [];
    });
    final estacas = await _servico.estacas(_trecho!, km);
    if (!mounted) return;
    setState(() => _estacas = estacas);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ir para uma estaca', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_trechos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nenhuma estaca com coordenada e KM cadastrados — '
                  'verifique os arquivos do projeto na tela de Atualizações.',
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _trecho,
                decoration: const InputDecoration(
                  labelText: 'Trecho',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in _trechos)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => v == null ? null : _selecionarTrecho(v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _km,
                decoration: const InputDecoration(
                  labelText: 'KM',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final km in _kms)
                    DropdownMenuItem(value: km, child: Text('KM $km')),
                ],
                onChanged:
                    _trecho == null ? null : (v) => v == null ? null : _selecionarKm(v),
              ),
              const SizedBox(height: 12),
              if (_km != null)
                Text('Estaca', style: theme.textTheme.labelLarge),
              if (_km != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: _estacas.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _estacas.length,
                          itemBuilder: (_, i) {
                            final estaca = _estacas[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined),
                              title: Text(estaca.descricao),
                              onTap: () => Navigator.of(context).pop(estaca),
                            );
                          },
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Painel de resultados da medição ───────────────────────────────────────────
class _PainelMedicao extends StatelessWidget {
  final List<LatLng> pontos;
  final VoidCallback onDesfazer;
  final VoidCallback onLimpar;

  const _PainelMedicao({
    required this.pontos,
    required this.onDesfazer,
    required this.onLimpar,
  });

  @override
  Widget build(BuildContext context) {
    final distancia = _distanciaMedicao(pontos);
    final area = _areaMedicao(pontos);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pontos.isEmpty
                  ? 'Toque no mapa para marcar pontos'
                  : 'Distância: ${_formatDistancia(distancia)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (pontos.length >= 3)
              Text('Área: ${_formatArea(area)}'),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: pontos.isEmpty ? null : onDesfazer,
                  icon: const Icon(Icons.undo),
                  label: const Text('Desfazer'),
                ),
                TextButton.icon(
                  onPressed: pontos.isEmpty ? null : onLimpar,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Limpar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Layer de overlay com cache acumulativo ────────────────────────────────────
// Guarda os tiles vistos para não recarregar a cada movimento.
class _OverlayLayer extends StatefulWidget {
  final _MapDef def;

  // Abaixo deste zoom não carrega nada.
  final double zoomMinimo;

  const _OverlayLayer(this.def, {this.zoomMinimo = 14});

  @override
  State<_OverlayLayer> createState() => _OverlayLayerState();
}

class _OverlayLayerState extends State<_OverlayLayer> {
  // chave "RR_C" — mesmo formato do nome do arquivo sem extensão
  final Set<String> _loaded = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTiles();
  }

  void _syncTiles() {
    final camera    = MapCamera.of(context);
    final def       = widget.def;
    final visible   = camera.visibleBounds;
    final mapBounds = LatLngBounds(def.sw, def.ne);

    // Mapa inteiro fora da tela → libera tudo
    if (camera.zoom < widget.zoomMinimo || !_overlaps(visible, mapBounds)) {
      if (_loaded.isNotEmpty) setState(() => _loaded.clear());
      return;
    }

    // Mantém os tiles até 2× a área visível; o resto sai da memória.
    final latM = (visible.north - visible.south) * 2;
    final lonM = (visible.east  - visible.west)  * 2;
    final keep = LatLngBounds(
      LatLng(visible.south - latM, visible.west  - lonM),
      LatLng(visible.north + latM, visible.east  + lonM),
    );

    // Descarta tiles fora da zona de retenção
    final before = _loaded.length;
    _loaded.removeWhere((key) {
      final sep = key.indexOf('_');
      final r   = int.parse(key.substring(0, sep));
      final c   = int.parse(key.substring(sep + 1));
      return !_overlaps(keep, def.pieceEnvelope(r, c));
    });
    var changed = _loaded.length != before;

    // Adiciona tiles visíveis ao cache
    for (var r = 0; r < def.rows; r++) {
      for (var c = 0; c < def.cols; c++) {
        if (_overlaps(visible, def.pieceEnvelope(r, c))) {
          if (_loaded.add('${r.toString().padLeft(2, '0')}_$c')) changed = true;
        }
      }
    }
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded.isEmpty) return const SizedBox.shrink();

    final def    = widget.def;
    final pieces = <BaseOverlayImage>[];

    for (final key in _loaded) {
      final sep = key.indexOf('_');
      final r   = int.parse(key.substring(0, sep));
      final c   = int.parse(key.substring(sep + 1));
      pieces.add(RotatedOverlayImage(
        topLeftCorner: def.corner(r, c),
        bottomLeftCorner: def.corner(r + 1, c),
        bottomRightCorner: def.corner(r + 1, c + 1),
        // Tile baixado do servidor (.webp, bem menor que PNG).
        imageProvider: imagemOverlay(def.tileDir, '$key.webp'),
        gaplessPlayback: true,
        opacity: 0.8,
      ));
    }

    return OverlayImageLayer(overlayImages: pieces);
  }
}

// ── Minimap para foto ─────────────────────────────────────────────────────────
// Zoom 19 mostra uns 72 m: dá para ler as marcações do mapa da obra.
const double _zoomMiniMapa = 19;

// Minimapa do carimbo: satélite, mapa da obra e ponto, capturado fora da tela.
Widget criarWidgetMiniMapa(LatLng centro) => _MiniMapa(centro: centro);

class _MiniMapa extends StatefulWidget {
  final LatLng centro;

  const _MiniMapa({required this.centro});

  @override
  State<_MiniMapa> createState() => _MiniMapaState();
}

class _MiniMapaState extends State<_MiniMapa> {
  final MapController _controlador = MapController();
  late LatLng _centro = widget.centro;

  // `move` só vale com o mapa montado; antes, vale o `initialCenter`.
  bool _mapaPronto = false;

  @override
  void initState() {
    super.initState();
    // Acompanha o GPS sozinho, para o ponto ficar sempre no centro.
    LocalizacaoService.instancia.posicao.addListener(_acompanharPosicao);
    PermissaoMapasService.instancia.grupos.addListener(_aoMudarPermissao);
  }

  void _aoMudarPermissao() {
    if (mounted) setState(() {});
  }

  void _acompanharPosicao() {
    final posicao = LocalizacaoService.instancia.posicao.value;
    if (posicao == null || !mounted) return;
    setState(() => _centro = posicao.ponto);
    if (_mapaPronto) _controlador.move(_centro, _zoomMiniMapa);
  }

  @override
  void didUpdateWidget(covariant _MiniMapa anterior) {
    super.didUpdateWidget(anterior);
    if (widget.centro != anterior.centro) {
      _centro = widget.centro;
      if (_mapaPronto) _controlador.move(_centro, _zoomMiniMapa);
    }
  }

  @override
  void dispose() {
    LocalizacaoService.instancia.posicao.removeListener(_acompanharPosicao);
    PermissaoMapasService.instancia.grupos.removeListener(_aoMudarPermissao);
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _controlador,
      options: MapOptions(
        initialCenter: _centro,
        initialZoom: _zoomMiniMapa,
        onMapReady: () => _mapaPronto = true,
        interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.example.namer_app',
          maxNativeZoom: 18,
        ),
        for (final mapa in _mapasVisiveis()) _OverlayLayer(mapa),
        MarkerLayer(
          markers: [
            Marker(
              point: _centro,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
