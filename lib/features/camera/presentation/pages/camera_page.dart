import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../../core/localizacao_service.dart';
import '../../../../core/widgets/galeria_imagens_page.dart';
import '../../../mapa/presentation/pages/map_page.dart' show criarWidgetMiniMapa, locAtual;
import '../../../registro/registro_service.dart';
import '../../camera_service.dart';

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  // Registro dono das fotos. Sem ele, [aoSalvarFoto] decide onde guardar.
  final int? registroId;

  // Destino da foto já carimbada, no lugar do registro (ex.: paralisação).
  final Future<void> Function(String caminho, PosicaoGps posicao)? aoSalvarFoto;

  final String trecho;
  final String kmtrecho;
  final String estacaInicial;
  final String estacaFinal;
  final String via;
  final String descricao;
  final String servNotavel;
  final String servNotavelDetalhes;

  const CameraPage({
    super.key,
    required this.cameras,
    this.registroId,
    this.aoSalvarFoto,
    required this.trecho,
    required this.kmtrecho,
    required this.estacaInicial,
    required this.estacaFinal,
    required this.via,
    required this.descricao,
    required this.servNotavel,
    required this.servNotavelDetalhes,
  }) : assert(registroId != null || aoSalvarFoto != null);

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late CameraController _controller;
  late Future<void> _initFuture;
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;
  String? _ultimaFoto;
  final List<String> _fotos = [];
  bool _processando = false;
  final GlobalKey _minimapKey = GlobalKey();

  // Rotação dos ícones detectada pelo acelerômetro (0.25 = 90°, -0.25 = -90°).
  double _iconTurns = 0.0;
  StreamSubscription<AccelerometerEvent>? _orientacaoSub;

  @override
  void initState() {
    super.initState();
    // Trava o layout em portrait; os ícones giram individualmente pelo sensor.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _inicializarCamera(_cameraIndex);
    _orientacaoSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_atualizarOrientacao);
  }

  // Orientação física pelo acelerômetro (a tela fica travada).
  void _atualizarOrientacao(AccelerometerEvent e) {
    double turns;
    if (e.x.abs() > e.y.abs() + 2) {
      // Deitado: X > 0 gira o ícone 90° horário; X < 0, anti-horário.
      turns = e.x > 0 ? 0.25 : -0.25;
    } else if (e.y.abs() > e.x.abs() + 2) {
      // Em pé: Y > 0 normal; Y < 0, de cabeça para baixo.
      turns = e.y > 0 ? 0.0 : 0.5;
    } else {
      return; // Diagonal: mantém orientação atual.
    }
    if (turns != _iconTurns && mounted) {
      setState(() => _iconTurns = turns);
      // Sincroniza já, e não no disparo: evita o preview piscar na foto.
      if (_controller.value.isInitialized) {
        _controller.lockCaptureOrientation(_turnsParaOrientacao(turns));
      }
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _orientacaoSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _inicializarCamera(int index) async {
    final controller = CameraController(widget.cameras[index], ResolutionPreset.high);
    _controller = controller;
    _initFuture = controller.initialize();
    await _initFuture;
    _minZoom = await controller.getMinZoomLevel();
    _maxZoom = await controller.getMaxZoomLevel();
    await controller.setFlashMode(_flashMode);
    await controller.lockCaptureOrientation(_turnsParaOrientacao(_iconTurns));
    if (mounted) setState(() {});
  }

  Future<void> _trocarCamera() async {
    if (widget.cameras.length < 2) return;
    final novoIndex = (_cameraIndex + 1) % widget.cameras.length;
    await _controller.dispose();
    setState(() {
      _cameraIndex = novoIndex;
      _zoom = 1.0;
    });
    await _inicializarCamera(novoIndex);
  }

  Future<void> _toggleFlash() async {
    final modos = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final proximo = modos[(modos.indexOf(_flashMode) + 1) % modos.length];
    await _controller.setFlashMode(proximo);
    setState(() => _flashMode = proximo);
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      default:
        return Icons.flash_off;
    }
  }

  // Só fotografa com o celular na horizontal (pelo acelerômetro).
  bool get _emPaisagem => _iconTurns == 0.25 || _iconTurns == -0.25;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                // Minimapa fora da tela: é capturado, mas nunca aparece.
                Positioned(
                  left: -300,
                  top: -300,
                  child: SizedBox(
                    width: 256,
                    height: 256,
                    child: RepaintBoundary(
                      key: _minimapKey,
                      child: criarWidgetMiniMapa(locAtual),
                    ),
                  ),
                ),
                _buildPreview(),
                _buildControles(context),
                if (_fotosProcessandoEmFundo > 0) _buildIndicadorFundo(),
                // Bloqueia os controles enquanto a foto é capturada.
                if (_processando) _buildOverlayProcessando(),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  // Selo no topo enquanto há fotos sendo carimbadas em segundo plano.
  Widget _buildIndicadorFundo() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fotosProcessandoEmFundo == 1
                        ? 'Processando 1 foto…'
                        : 'Processando $_fotosProcessandoEmFundo fotos…',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayProcessando() {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: const ui.Color.fromARGB(110, 0, 0, 0),
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final size = _controller.value.previewSize!;
    // buildPreview(), e não CameraPreview: este gira o visor ao inclinar o
    // celular. A orientação travada vale só para a foto salva.
    return GestureDetector(
      onScaleStart: (_) => _baseZoom = _zoom,
      onScaleUpdate: (details) async {
        final novoZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
        await _controller.setZoomLevel(novoZoom);
        setState(() => _zoom = novoZoom);
      },
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: _controller.buildPreview(),
          ),
        ),
      ),
    );
  }

  Widget _buildControles(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _botaoIcone(_flashIcon, _toggleFlash),
                if (widget.cameras.length > 1)
                  _botaoIcone(Icons.cameraswitch, _trocarCamera),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (!_emPaisagem) _avisoGirarCelular(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMiniatura(context),
                _buildBotaoCaptura(),
                const SizedBox(width: 88),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _avisoGirarCelular() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.screen_rotation, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Gire o celular na horizontal para fotografar',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _botaoIcone(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: AnimatedRotation(
          turns: _iconTurns,
          duration: const Duration(milliseconds: 300),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildBotaoCaptura() {
    final habilitado = !_processando && _emPaisagem;
    return GestureDetector(
      onTap: habilitado ? _tirarFoto : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color: Colors.white.withValues(alpha: _emPaisagem ? 0.15 : 0.05),
        ),
        child: _processando
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : Icon(Icons.circle, color: Colors.white.withValues(alpha: _emPaisagem ? 1 : 0.3), size: 52),
      ),
    );
  }

  Widget _buildMiniatura(BuildContext context) {
    if (_ultimaFoto == null) return const SizedBox(width: 88);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GaleriaImagensPage(fotos: _fotos, descricao: widget.descricao)),
      ),
      child: Container(
        width: 56,
        height: 56,
        margin: const EdgeInsets.only(right: 32),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: FileImage(File(_ultimaFoto!)),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  // Rotação do ícone → DeviceOrientation, para o EXIF da foto sair certo.
  DeviceOrientation _turnsParaOrientacao(double turns) {
    if (turns == 0.25)  return DeviceOrientation.landscapeLeft;
    if (turns == -0.25) return DeviceOrientation.landscapeRight;
    if (turns == 0.5)   return DeviceOrientation.portraitDown;
    return DeviceOrientation.portraitUp;
  }

  // Depois da 1ª foto os tiles já estão carregados: não espera de novo.
  bool _minimapJaCarregouUmaVez = false;

  // pixelRatio mínimo para o minimapa não sair borrado na foto (25% de folga).
  double _pixelRatioMinimapaPara(List<int> dims) {
    final menor = dims[0] < dims[1] ? dims[0] : dims[1];
    // 0.36 = mesma fração usada pro mapaSize em camera_service.dart.
    final targetPx = menor * 0.36;
    return ((targetPx / 256) * 1.25).clamp(3.0, 10.0);
  }

  Future<Uint8List?> _capturarMiniMapa(Future<List<int>> dimsFuture) async {
    final sw = Stopwatch()..start();
    try {
      // Tiles já no cache: espera só alguns frames para desenhar.
      final espera = _minimapJaCarregouUmaVez
          ? const Duration(milliseconds: 50)
          : const Duration(milliseconds: 250);
      // Em paralelo com a espera dos tiles.
      final esperaResultados = await Future.wait([
        Future.delayed(espera),
        dimsFuture,
      ]);
      final dims = esperaResultados[1] as List<int>;
      _minimapJaCarregouUmaVez = true;
      debugPrint('[timing] minimap: espera tiles+dims = ${sw.elapsedMilliseconds}ms');
      sw.reset();
      final boundary = _minimapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final pixelRatio = _pixelRatioMinimapaPara(dims);
      final ui.Image img = await boundary.toImage(pixelRatio: pixelRatio);
      debugPrint('[timing] minimap: toImage (pixelRatio=${pixelRatio.toStringAsFixed(1)}) = ${sw.elapsedMilliseconds}ms');
      sw.reset();
      final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      debugPrint('[timing] minimap: toByteData(png) = ${sw.elapsedMilliseconds}ms');
      return bytes?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[minimap] captura falhou: $e');
      return null;
    }
  }

  // Tira a foto do cache (que o Android limpa) antes de gravar o caminho.
  Future<String> _moverParaPastaPermanente(String caminhoTemporario) async {
    final docs = await getApplicationDocumentsDirectory();
    final pastaFotos = Directory(p.join(docs.path, 'fotos'));
    if (!await pastaFotos.exists()) {
      await pastaFotos.create(recursive: true);
    }
    final destino = p.join(pastaFotos.path, p.basename(caminhoTemporario));
    final arquivoFinal = await File(caminhoTemporario).copy(destino);
    await File(caminhoTemporario).delete();
    return arquivoFinal.path;
  }

  // Fotos cujo carimbo/gravação ainda estão rodando na fila do isolate.
  int _fotosProcessandoEmFundo = 0;

  Future<void> _tirarFoto() async {
    if (!_emPaisagem) return;
    final sw = Stopwatch()..start();
    try {
      setState(() => _processando = true);
      await _initFuture;
      final image = await _controller.takePicture();
      debugPrint('[timing] takePicture = ${sw.elapsedMilliseconds}ms');
      sw.reset();
      // Lida uma vez só: serve ao minimapa e ao processarFoto.
      final dimsFuture = dimensoesImagem(image.path);
      // Prepara logo e fonte no isolate, em paralelo com GPS e minimapa.
      unawaited(dimsFuture.then(aquecerCachesParaFoto));
      // GPS e minimapa em paralelo.
      final resultados = await Future.wait([
        pegarLocalizacao(),
        _capturarMiniMapa(dimsFuture),
      ]);
      final posicao = resultados[0] as PosicaoGps;
      final minimap = resultados[1] as Uint8List?;
      final dims = await dimsFuture;
      debugPrint('[timing] localizacao+minimap (paralelo) = ${sw.elapsedMilliseconds}ms');

      // O resto roda em segundo plano, na ordem; a câmera já libera para a
      // próxima foto.
      setState(() => _fotosProcessandoEmFundo++);
      unawaited(_finalizarFotoEmFundo(image.path, posicao, minimap, dims));
    } catch (e) {
      debugPrint('Erro ao tirar foto: $e');
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _finalizarFotoEmFundo(
    String caminhoTemporario,
    PosicaoGps posicao,
    Uint8List? minimap,
    List<int> dims,
  ) async {
    final sw = Stopwatch()..start();
    try {
      await processarFoto(
        caminhoTemporario,
        posicao.latitude,
        posicao.longitude,
        widget.trecho,
        widget.kmtrecho,
        widget.estacaInicial,
        widget.estacaFinal,
        widget.via,
        widget.descricao,
        widget.servNotavel,
        widget.servNotavelDetalhes,

        minimapBytes: minimap,
        dimsConhecidas: dims,
      );
      final caminhoFinal = await _moverParaPastaPermanente(caminhoTemporario);
      // Só grava no banco com o carimbo pronto: nada vê foto pela metade.
      final salvar = widget.aoSalvarFoto;
      if (salvar != null) {
        await salvar(caminhoFinal, posicao);
      } else {
        await RegistroService.instancia.adicionarFoto(
          registroId: widget.registroId!,
          caminhoArquivo: caminhoFinal,
          latitude: posicao.latitude,
          longitude: posicao.longitude,
        );
      }
      debugPrint('[timing] foto finalizada em fundo = ${sw.elapsedMilliseconds}ms');
      _fotos.add(caminhoFinal);
      if (mounted) setState(() => _ultimaFoto = caminhoFinal);
    } catch (e) {
      debugPrint('Falha ao finalizar foto em segundo plano: $e');
    } finally {
      _fotosProcessandoEmFundo--;
      if (mounted) setState(() {});
    }
  }
}
