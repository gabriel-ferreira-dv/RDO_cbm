import 'dart:async';
import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../../../auth/models/usuario.dart';
import '../../../camera/camera_service.dart';
import '../../../camera/presentation/pages/camera_page.dart';
import '../../../historico/presentation/pages/historico_page.dart';
import '../../../auth/auth_service.dart';
import '../../../mapa/mapas_config.dart';
import '../../../mapa/permissao_mapas_service.dart';
import '../../../mapa/presentation/pages/map_page.dart';
import '../../../paralisacao/paralisacao_service.dart';
import '../../../paralisacao/presentation/pages/paralisacoes_page.dart';
import '../../../supervisor/equipe_supervisor_service.dart';
import '../../../supervisor/presentation/pages/supervisor_page.dart';
import '../../../tutorial/presentation/pages/tutorial_page.dart';
import '../../../relatorio/presentation/pages/relatorio_page.dart';
import '../../../relatorio/turno_noturno.dart';
import '../../atividades_descricoes.dart';
import '../../csv_dados_datasource.dart';
import '../../estaqueamento.dart';
import '../../models/registro.dart';
import '../../registro_service.dart';
import '../../sugestao_gps_service.dart';
import '../../vias_estaqueamento.dart';
import '../../../notificacoes/lembretes_service.dart';
import '../../../notificacoes/mensagens_service.dart';
import '../../../notificacoes/presentation/pages/atualizacoes_page.dart';
import '../../../sincronizacao/atualizacao_app_service.dart';
import '../../../sincronizacao/atualizacao_dados_service.dart';
import '../../../sincronizacao/presentation/widgets/atualizacao_app_dialogo.dart';
import '../../../sincronizacao/sincronizacao_service.dart';
import '../controllers/speech_controller.dart';
import '../widgets/campo_pesquisa_unico.dart';
import 'importar_atividade_page.dart';

class HomePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Usuario usuario;
  final VoidCallback aoSair;

  const HomePage({
    super.key,
    required this.cameras,
    required this.usuario,
    required this.aoSair,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Abas, na ordem da barra.
  static const _abaInicio = 0;
  static const _abaRegistro = 1;
  static const _abaParadas = 2;
  static const _abaHistorico = 3;
  static const _abaMapa = 4;
  static const _abaRelatorio = 5;
  static const _abaEquipe = 6; // só supervisor

  var selectedIndex = _abaInicio;

  // Há paralisação aberta hoje: ponto vermelho na aba Paradas.
  bool _paradoAgora = false;

  Future<void> _atualizarParadoAgora() async {
    final parado = await ParalisacaoService.instancia.paradoAgora(
      widget.usuario.id!,
      noturno: TurnoNoturnoService.instancia.ehNoturno(
          AuthService.instancia.usuarioLogado?.matricula ?? widget.usuario.matricula),
    );
    if (mounted && parado != _paradoAgora) setState(() => _paradoAgora = parado);
  }
  // Revalidado no initState: o perfil pode mudar no Dashboard após o login.
  late bool _ehSupervisor = widget.usuario.ehSupervisor;
  // Equipe do supervisor (para lançar em nome de um encarregado).
  List<EncarregadoDaEquipe> _equipeSupervisionada = [];
  // null = em nome próprio.
  EncarregadoDaEquipe? _registrandoPara;
  String? selTrecho;
  String? selKm;
  String? selEstInicial;
  String? selEstFinal;
  String? viaSelecionada;
  String? selGupoAtividade;
  String? selServNotavel;
  String? selServNotavelDetalhe;
  String? unidadeSelecionada;

  // Unidades mais usadas primeiro.
  static const List<String> _unidades = [
    'm³', 'm²', 'm', 'un', 'kg', 't', 'vb',
  ];

  List<String> trecho  = [];
  List<String> kmtrecho = [];
  // Estacas do KM escolhido e dos vizinhos, filtradas pela via.
  List<EstacaDoProjeto> estacasDoIntervalo = [];
  List<String> grupoAtividade = [];
  List<String> servNotavel = [];
  List<String> servNotavelDetalhe = [];

  int _subStep = 0;
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _quantidadeController = TextEditingController();
  final SpeechController _speechController = SpeechController();
  bool _isListening = false;
  bool _buscandoGps = false;
  String _textoAntesDitar = '';
  StreamSubscription<List<ConnectivityResult>>? _conectividadeSub;

  @override
  void initState() {
    super.initState();
    carregarTrechos().then((valores) => setState(() => trecho = valores));
    aquecerProcessadorFoto();
    SincronizacaoService.instancia.sincronizar();
    _conectividadeSub = Connectivity().onConnectivityChanged.listen((resultados) {
      final online = resultados.any((r) => r != ConnectivityResult.none);
      if (online) SincronizacaoService.instancia.sincronizar();
    });
    // A permissão vem antes: ela decide quais mapas podem ser baixados.
    PermissaoMapasService.instancia
        .sincronizar()
        .then((_) => _verificarAtualizacoesDeDados());
    _verificarAtualizacaoDoApp();
    TurnoNoturnoService.instancia.sincronizar();
    // Lembrete diário (seg–sáb, 16:30).
    LembretesService.instancia.agendarLembretesDiarios(widget.usuario.nome);
    _mostrarMensagensDoGestor();
    _revalidarPerfil();
    _atualizarParadoAgora();
  }

  Future<void> _revalidarPerfil() async {
    final usuario = await AuthService.instancia.sincronizarPerfil();
    if (!mounted || usuario == null) return;

    // Sessão expirada no servidor: o perfil fica congelado até novo login,
    // então avisa (senão uma promoção a supervisor nunca apareceria).
    if (AuthService.instancia.sessaoPrecisaRenovar) {
      _avisarSessaoExpirada();
      return;
    }

    if (usuario.ehSupervisor != _ehSupervisor) {
      setState(() {
        _ehSupervisor = usuario.ehSupervisor;
        // Perfil revogado com a aba Equipe aberta: volta para a Home.
        if (!_ehSupervisor && selectedIndex == _abaEquipe) selectedIndex = _abaInicio;
        if (!_ehSupervisor) _registrandoPara = null;
      });
    }
    if (!usuario.ehSupervisor) return;

    final equipe =
        await EquipeSupervisorService.instancia.carregar(usuario.matricula);
    if (!mounted) return;
    setState(() => _equipeSupervisionada = equipe);
  }

  // Barra fixa, e não SnackBar: o problema só passa com novo login.
  void _avisarSessaoExpirada() {
    // Após o primeiro frame: no initState o Scaffold ainda não existe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mostrarBannerSessao();
    });
  }

  void _mostrarBannerSessao() {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text(
          'Sua sessão expirou. Entre novamente para atualizar seu perfil — '
          'sem isso, mudanças feitas pelo administrador não chegam neste '
          'aparelho.',
        ),
        leading: const Icon(Icons.gpp_maybe_outlined),
        actions: [
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Agora não'),
          ),
          FilledButton(
            // Mesmo caminho do "Sair" do menu (o main cuida do logout).
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              widget.aoSair();
            },
            child: const Text('Entrar de novo'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarMensagensDoGestor() async {
    final mensagens =
        await MensagensService.instancia.buscarNovas(widget.usuario.email);
    for (final mensagem in mensagens) {
      LembretesService.instancia.exibirMensagemDoGestor(
          mensagem.id, mensagem.titulo, mensagem.corpo);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.campaign),
          title: Text(mensagem.titulo),
          content: Text(mensagem.corpo),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _verificarAtualizacoesDeDados() async {
    final resultado =
        await AtualizacaoDadosService.instancia.verificarEAtualizarCsvs();
    if (!mounted) return;

    if (resultado.csvsAtualizados.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Dados do projeto atualizados: ${resultado.csvsAtualizados.join(', ')}',
        ),
      ));
    }
    if (resultado.overlaysNovos.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        // "Para baixar": o primeiro download de cada mapa também vem por aqui.
        content: Text(
          '${resultado.overlaysNovos.map(rotuloDoMapa).join(' e ')} para '
          'baixar — abra a tela de Atualizações, de preferência no Wi-Fi',
        ),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AtualizacoesPage()),
          ),
        ),
      ));
    }
  }

  // Versão nova do app no Supabase (ver supabase/versao_app.sql).
  Future<void> _verificarAtualizacaoDoApp() async {
    final atualizacao = await AtualizacaoAppService.instancia.verificar();
    if (atualizacao == null || !mounted) return;
    await oferecerAtualizacaoDoApp(context, atualizacao);
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _quantidadeController.dispose();
    _speechController.cancel();
    _conectividadeSub?.cancel();
    super.dispose();
  }

  // Aceita vírgula ou ponto decimal; null se vazio ou inválido.
  double? _quantidadeInformada() {
    final texto = _quantidadeController.text.trim().replaceAll(',', '.');
    if (texto.isEmpty) return null;
    return double.tryParse(texto);
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechController.stopListening();
      setState(() => _isListening = false);
      return;
    }

    final ok = await _speechController.initialize();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reconhecimento de voz não disponível neste dispositivo')),
        );
      }
      return;
    }

    _textoAntesDitar = _descricaoController.text;
    setState(() => _isListening = true);

    await _speechController.startListening(
      onResult: (text) {
        if (!mounted) return;
        final prefix = _textoAntesDitar.isEmpty ? '' : '$_textoAntesDitar ';
        setState(() {
          _descricaoController.text = '$prefix$text';
          _descricaoController.selection = TextSelection.fromPosition(
            TextPosition(offset: _descricaoController.text.length),
          );
        });
      },
      onDone: () {
        if (mounted) setState(() => _isListening = false);
      },
    );
  }
  // Se o trecho pede a via (os Contornos não pedem).
  bool get _pedeVia => trechoTemVia(selTrecho);

  // Se o trecho pede estaca (as áreas de apoio não pedem).
  bool get _pedeEstaca => trechoTemEstaca(selTrecho);

  // Recarrega as estacas do KM e dos vizinhos, filtradas pela via. Estaca
  // escolhida que ficou fora da lista nova sai.
  Future<void> _recarregarEstacas() async {
    final trecho = selTrecho;
    final km = selKm;
    if (trecho == null || km == null || !_pedeEstaca) return;
    // Só espera a via onde ela é perguntada.
    if (_pedeVia && viaSelecionada == null) return;
    final estacas = await EstaqueamentoService.instancia
        .doKmEVizinhos(trecho, km, via: viaSelecionada);
    if (!mounted) return;
    setState(() {
      estacasDoIntervalo = estacas;
      if (_estacaPorRotulo(selEstInicial) == null) selEstInicial = null;
      if (_estacaPorRotulo(selEstFinal) == null) selEstFinal = null;
    });
  }

  // Estaca do intervalo com o rótulo [rotulo] (sem o KM ao lado).
  EstacaDoProjeto? _estacaPorRotulo(String? rotulo) {
    if (rotulo == null) return null;
    for (final estaca in estacasDoIntervalo) {
      if (estaca.rotulo == rotulo) return estaca;
    }
    return null;
  }

  // Posição da estaca [rotulo] na lista; null se não está nela.
  int? _indiceDaEstaca(String? rotulo) {
    final i = estacasDoIntervalo.indexWhere((e) => e.rotulo == rotulo);
    return i < 0 ? null : i;
  }

  // Posição da primeira estaca do KM escolhido, onde a lista abre.
  int? get _indiceDoKm {
    final i = estacasDoIntervalo.indexWhere((e) => e.km == selKm);
    return i < 0 ? null : i;
  }

  // Itens das listas de estaca: com o KM ao lado nas de outro KM.
  List<String> get _rotulosDoIntervalo => [
        for (final estaca in estacasDoIntervalo) rotuloComKm(estaca, selKm ?? ''),
      ];

  // Como a estaca [rotulo] aparece no campo.
  String? _rotuloNoCampo(String? rotulo) {
    final estaca = _estacaPorRotulo(rotulo);
    return estaca == null ? rotulo : rotuloComKm(estaca, selKm ?? '');
  }

  // Rótulo da estaca escolhida na lista, sem o KM ao lado.
  String _rotuloEscolhido(String item) {
    for (final estaca in estacasDoIntervalo) {
      if (rotuloComKm(estaca, selKm ?? '') == item) return estaca.rotulo;
    }
    return item;
  }

  Future<void> _importarAtividadeAnterior() async {
    final registro = await Navigator.of(context).push<Registro>(
      MaterialPageRoute(
        builder: (_) => ImportarAtividadePage(usuario: widget.usuario),
      ),
    );
    if (registro == null || !mounted) return;

    // Via em branco vira null, que é o "sem via" do seletor e do filtro.
    final viaImportada = registro.via.trim().isEmpty ? null : registro.via;

    final resultados = await Future.wait([
      carregarKmEst(3, 0, registro.trecho),
      carregarAtividades(registro.trecho),
      carregarServicosNotaveis(registro.trecho, registro.atividade),
      carregarPassosDoServico(
          registro.trecho, registro.atividade, registro.servicoNotavel),
    ]);
    if (!mounted) return;

    // Registro antigo pode vir sem passo: o campo fica em branco.
    final detalheImportado = registro.servicoNotavelDetalhe;

    final estacasImportadas = await EstaqueamentoService.instancia
        .doKmEVizinhos(registro.trecho, registro.km, via: viaImportada);
    if (!mounted) return;

    setState(() {
      selTrecho = registro.trecho;
      selKm = registro.km;
      viaSelecionada = viaImportada;
      selGupoAtividade = registro.atividade;
      selEstInicial = registro.estacaInicial;
      selEstFinal = registro.estacaFinal;
      estacasDoIntervalo = estacasImportadas;
      selServNotavel = registro.servicoNotavel;
      selServNotavelDetalhe =
          detalheImportado.isEmpty ? null : detalheImportado;
      // A medição é do dia: não se copia.
      _quantidadeController.clear();
      unidadeSelecionada = null;
      _descricaoController.text = registro.descricao;
      kmtrecho = resultados[0];
      grupoAtividade = resultados[1];
      servNotavel = resultados[2];
      servNotavelDetalhe = resultados[3];
      _subStep = 0;
    });
  }

  Future<void> _preencherPelaLocalizacao() async {
    setState(() => _buscandoGps = true);
    final resultado = await SugestaoGpsService.instancia.sugerir();
    if (!mounted) return;
    setState(() => _buscandoGps = false);

    final sugestao = resultado.sugestao;
    if (sugestao == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultado.erro ?? 'Não foi possível usar a localização')),
      );
      return;
    }

    final resultados = await Future.wait([
      carregarKmEst(3, 0, sugestao.trecho),
      carregarAtividades(sugestao.trecho),
    ]);
    final estacas = await EstaqueamentoService.instancia
        .doKmEVizinhos(sugestao.trecho, sugestao.km, via: sugestao.via);
    if (!mounted) return;

    setState(() {
      selTrecho = sugestao.trecho;
      selKm = sugestao.km;
      selEstInicial = sugestao.estaca;
      // Em pista dupla a estaca já diz a via; senão o encarregado escolhe.
      viaSelecionada = sugestao.via ?? viaSelecionada;
      selGupoAtividade = null;
      selEstFinal = null;
      selServNotavel = null;
      selServNotavelDetalhe = null;
      kmtrecho = resultados[0];
      grupoAtividade = resultados[1];
      estacasDoIntervalo = estacas;
      servNotavel = [];
      servNotavelDetalhe = [];
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(
          trechoTemEstaca(sugestao.trecho)
              ? 'Você está a ${formatarDistanciaMetros(sugestao.distanciaMetros)} da Estaca '
                  '${sugestao.estaca} no Trecho ${sugestao.trecho}, KM ${sugestao.km}'
              : 'Você está a ${formatarDistanciaMetros(sugestao.distanciaMetros)} do '
                  '${sugestao.trecho}, KM ${sugestao.km}',
        ),     
      ),
    );
  }

  Widget _cabecalhoEtapa(int etapa, String titulo) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            children: [
              Row(
                children: [
                  for (var i = 1; i <= 2; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 4,
                        margin: EdgeInsets.only(left: i == 1 ? 0 : 6),
                        decoration: BoxDecoration(
                          color: i <= etapa
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Etapa $etapa de 2',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Supervisor lançando em nome de um encarregado. O aviso fica porque a foto
  // sai com o GPS de quem fotografou.
  Widget _seletorDeAutoria() {
    final theme = Theme.of(context);
    final para = _registrandoPara;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: para?.matricula,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Registrar em nome de',
              prefixIcon: Icon(Icons.assignment_ind_outlined),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Meu próprio')),
              for (final e in _equipeSupervisionada)
                DropdownMenuItem(value: e.matricula, child: Text(e.nome)),
            ],
            onChanged: (matricula) => setState(() {
              _registrandoPara = matricula == null
                  ? null
                  : _equipeSupervisionada
                      .firstWhere((e) => e.matricula == matricula);
            }),
          ),
          if (para != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'O registro entra no nome de ${para.nome}, marcado como '
                'lançado por você. A foto sai com a sua localização.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trechoKmEstacaVia() {
    return SingleChildScrollView(
      child: Column(
      children: [
        _cabecalhoEtapa(1, 'Selecione os campos para realizar o registro'),
        if (_ehSupervisor && _equipeSupervisionada.isNotEmpty)
          _seletorDeAutoria(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: _importarAtividadeAnterior,
            icon: const Icon(Icons.history),
            label: const Text('Importar de uma atividade anterior'),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: _buscandoGps ? null : _preencherPelaLocalizacao,
            icon: _buscandoGps
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(
              _buscandoGps
                  ? 'Obtendo localização…'
                  : 'Preencher pela minha localização',
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('ou preencha manualmente:', style: TextStyle(fontSize: 13)),
        ),
        CampoPesquisaUnico(
          key: const ValueKey('campo_trecho'),
          textoPesquisa: "Selecione o Trecho",
          initialValue: selTrecho,
          items: trecho,
          onSelected: (value) {
            setState(() {
              selTrecho = value;
              selKm = null;
              // A via é de cada trecho: zera ao trocar.
              viaSelecionada = null;
              selGupoAtividade = null;
              selEstInicial = null;
              selEstFinal = null;
              selServNotavel = null;
              selServNotavelDetalhe = null;
              grupoAtividade = [];
              estacasDoIntervalo = [];
              servNotavel = [];
              servNotavelDetalhe = [];
            });
            carregarKmEst(3,0 , value).then(
              (valores) => setState(() => kmtrecho = valores),
            );
          },
        ),
        CampoPesquisaUnico(
          key: const ValueKey('campo_km'),
          textoPesquisa:"Selecione o KM",
          initialValue: selKm,
          items: kmtrecho,
          enabled: selTrecho != null,
          onSelected: (value) {
            // Trocar o KM invalida atividade/estacas/serviço já escolhidos.
            setState(() {
              selKm = value;
              selGupoAtividade = null;
              selEstInicial = null;
              selEstFinal = null;
              selServNotavel = null;
              selServNotavelDetalhe = null;
              estacasDoIntervalo = [];
              servNotavel = [];
              servNotavelDetalhe = [];
            });
            carregarAtividades(selTrecho!).then(
              (valores) => setState(() => grupoAtividade = valores),
            );
            _recarregarEstacas();
          },
          ),
        // A via vem antes das estacas: no C1 cada sentido tem numeração
        // própria. Nos Contornos ela não aparece; no Canteiro Industrial e no
        // Pátio de Vigas, nem ela nem as estacas. Ver vias_estaqueamento.dart.
        if (_pedeVia)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: viaSul,
                    label: Text('Via 01 Sul'),
                    icon: Icon(Icons.south),
                  ),
                  ButtonSegment(
                    value: viaNorte,
                    label: Text('Via 02 Norte'),
                    icon: Icon(Icons.north),
                  ),
                ],
                selected: {if (viaSelecionada != null) viaSelecionada!},
                emptySelectionAllowed: true,
                onSelectionChanged: (selecao) {
                  // Outra pista, outra numeração: zera as estacas.
                  setState(() {
                    viaSelecionada = selecao.isEmpty ? null : selecao.first;
                    selEstInicial = null;
                    selEstFinal = null;
                    estacasDoIntervalo = [];
                  });
                  _recarregarEstacas();
                },
              ),
            ),
          ),
        if (_pedeEstaca)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CampoPesquisaUnico(
                  key: const ValueKey('campo_estacaInicial'),
                  textoPesquisa: "Estaca inicial",
                  initialValue: _rotuloNoCampo(selEstInicial),
                  items: _rotulosDoIntervalo,
                  itensSemBusca: 500,
                  // Abre no KM escolhido (ou na estaca já escolhida).
                  rolarParaIndice: _indiceDaEstaca(selEstInicial) ?? _indiceDoKm,
                  enabled:
                      selKm != null && (!_pedeVia || viaSelecionada != null),
                  onSelected: (value) =>
                      setState(() => selEstInicial = _rotuloEscolhido(value)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(' - ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: CampoPesquisaUnico(
                  key: const ValueKey('campo_estacaFinal'),
                  textoPesquisa: "Estaca final",
                  initialValue: _rotuloNoCampo(selEstFinal),
                  items: _rotulosDoIntervalo,
                  itensSemBusca: 500,
                  // Abre na estaca inicial: a final costuma vir logo depois.
                  rolarParaIndice: _indiceDaEstaca(selEstFinal) ??
                      _indiceDaEstaca(selEstInicial) ??
                      _indiceDoKm,
                  enabled: selEstInicial != null,
                  onSelected: (value) =>
                      setState(() => selEstFinal = _rotuloEscolhido(value)),
                ),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: () {
              if (selTrecho == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Selecione o Trecho que está atuando')),
                );
                return;
              }else if (selKm == null){
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor selecione o KM!')),
                );
                return;

              }else if (_pedeEstaca &&
                  (selEstInicial == null || selEstFinal == null)){
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Selecione a estaca inicial e final')),
                );
                return;

              }else if (_pedeVia && viaSelecionada == null){
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor selecione o sentido da via!')),
                );
                return;

              }
              setState(() => _subStep = 1);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Próximo'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  // Guia das atividades, aberto pelo link "O que é cada atividade?".
  void _mostrarGuiaAtividades() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('Guia das atividades', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'O que cada atividade abrange, para escolher a certa.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              for (final entrada in descricoesAtividades.entries) ...[
                Text(entrada.key,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(entrada.value, style: theme.textTheme.bodyMedium),
                const Divider(height: 24),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _atividadeServDesc(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecalhoEtapa(2, 'Complete os demais campos do registro'),
        CampoPesquisaUnico(
          key: const ValueKey('campo_atividade'),
          textoPesquisa: "Selecione o grupo de atividade",
          initialValue: selGupoAtividade,
          items: grupoAtividade,
          enabled: selTrecho != null,
          onSelected: (value) {
            // Trocar a atividade invalida o serviço e o passo já escolhidos.
            setState(() {
              selGupoAtividade = value;
              selServNotavel = null;
              selServNotavelDetalhe = null;
              servNotavelDetalhe = [];
            });
            carregarServicosNotaveis(selTrecho!, value).then(
              (valores) => setState(() => servNotavel = valores),
            );
          },
        ),
        // Link para o guia e resumo da atividade escolhida.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('O que é cada grupo de serviço?'),
            onPressed: _mostrarGuiaAtividades,
          ),
        ),
        if (descricaoDaAtividade(selGupoAtividade) != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              descricaoDaAtividade(selGupoAtividade)!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        CampoPesquisaUnico(
          key: const ValueKey('campo_servico'),
          textoPesquisa:"Selecione o tipo de serviço",
          initialValue: selServNotavel,
          items: servNotavel,
          enabled: selGupoAtividade != null,
          onSelected: (value) {
            // Trocar o serviço invalida o passo já escolhido.
            setState(() {
              selServNotavel = value;
              selServNotavelDetalhe = null;
              servNotavelDetalhe = [];
            });
            carregarPassosDoServico(selTrecho!, selGupoAtividade!, value).then(
              (valores) => setState(() => servNotavelDetalhe = valores),
            );
          },
        ),
        CampoPesquisaUnico(
          key: const ValueKey('campo_servico_detalhe'),
          textoPesquisa: "Selecione o passo do serviço",
          initialValue: selServNotavelDetalhe,
          items: servNotavelDetalhe,
          enabled: selServNotavel != null,
          onSelected: (value) => setState(() => selServNotavelDetalhe = value),
        ),
        // Medição (opcional): quantidade + unidade.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _quantidadeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Quantidade (opcional)',
                    hintText: 'ex.: 120,5',
                    prefixIcon: Icon(Icons.straighten),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: unidadeSelecionada,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Unidade'),
                  items: [
                    for (final u in _unidades)
                      DropdownMenuItem(value: u, child: Text(u)),
                  ],
                  onChanged: (v) => setState(() => unidadeSelecionada = v),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TextField(
            controller: _descricaoController,
            maxLength: 1000,
            // Sem Expanded: dentro do scroll não há altura para expandir.
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Descrição da atividade (Opcional)',
              alignLabelWithHint: true,
              suffixIcon: IconButton(
                tooltip: _isListening ? 'Parar gravação' : 'Gravar áudio',
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? Colors.red : null,
                ),
                onPressed: _toggleListening,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _subStep = 0),
                child: const Text('Voltar'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () async {
                  if (selGupoAtividade == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Selecione o Grupo de Atividade!')),
                    );
                    return;
                  }else if (selServNotavel == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Selecione o serviço!')),
                    );
                    return;
                  }else if (selServNotavelDetalhe == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Selecione o passo do serviço!')),
                    );
                    return;
                  }

                  // Quantidade e unidade vêm juntas ou nenhuma.
                  final quantidade = _quantidadeInformada();
                  final temTextoQtd = _quantidadeController.text.trim().isNotEmpty;
                  if (temTextoQtd && quantidade == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Quantidade inválida — use só números (ex.: 120,5)')),
                    );
                    return;
                  }
                  if (quantidade != null && unidadeSelecionada == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Escolha a unidade da quantidade')),
                    );
                    return;
                  }
                  if (quantidade == null && unidadeSelecionada != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Informe a quantidade da medição')),
                    );
                    return;
                  }

                  if (widget.cameras.isNotEmpty) {
                    // O KM de cada ponta sai da estaca escolhida.
                    final kmInicio =
                        _estacaPorRotulo(selEstInicial)?.km ?? selKm!;
                    final kmFim = _estacaPorRotulo(selEstFinal)?.km ?? kmInicio;
                    final registroId = await RegistroService.instancia.criarRegistro(
                      usuarioId: widget.usuario.id!,
                      trecho: selTrecho!,
                      km: kmInicio,
                      // Só quando o serviço atravessa o KM.
                      kmFinal: kmFim == kmInicio ? '' : kmFim,
                      // Vazia onde a via não é perguntada.
                      via: _pedeVia ? (viaSelecionada ?? '') : '',
                      atividade: selGupoAtividade!,
                      estacaInicial: _pedeEstaca ? selEstInicial! : '',
                      estacaFinal: _pedeEstaca ? selEstFinal! : '',
                      servicoNotavel: selServNotavel!,
                      servicoNotavelDetalhe: selServNotavelDetalhe!,
                      quantidade: quantidade,
                      unidade: unidadeSelecionada ?? '',
                      emNomeDeMatricula: _registrandoPara?.matricula ?? '',
                      emNomeDeNome: _registrandoPara?.nome ?? '',
                      descricao: _descricaoController.text,
                    );

                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => CameraPage(
                          cameras: widget.cameras,
                          registroId: registroId,
                          trecho : selTrecho!,
                          // "231" ou "231 a 232".
                          kmtrecho: faixaDeKm(kmInicio, kmFim),
                          estacaInicial: _pedeEstaca ? selEstInicial! : '',
                          estacaFinal: _pedeEstaca ? selEstFinal! : '',
                          via: _pedeVia ? (viaSelecionada ?? '') : '',
                          descricao: _descricaoController.text,
                          servNotavel: selServNotavel!,
                          servNotavelDetalhes: selServNotavelDetalhe!,
                        ),
                      ),
                    );
                    // Limpa a medição para o próximo registro.
                    _quantidadeController.clear();
                    if (mounted) setState(() => unidadeSelecionada = null);
                    if (mounted) setState(() => _subStep = 0);
                    // Envia já; sem rede, vai quando ela voltar.
                    SincronizacaoService.instancia.sincronizar();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nenhuma câmera disponível')),
                    );
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.camera_alt),
                    SizedBox(width: 8),
                    Text('Fazer registro'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  // Usuário no AppBar; o toque abre nome, e-mail e "Sair".
  Widget _usuarioAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final nome = widget.usuario.nome.trim();
    final primeiroNome = nome.isEmpty ? 'Usuário' : nome.split(' ').first;
    final inicial = nome.isEmpty ? '?' : nome[0].toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Conta',
      onSelected: (opcao) {
        if (opcao == 'sair') widget.aoSair();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nome.isEmpty ? 'Usuário' : nome,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(widget.usuario.email, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'sair',
          child: Row(
            children: [
              Icon(Icons.logout, size: 20),
              SizedBox(width: 10),
              Text('Sair'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                inicial,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(primeiroNome, style: theme.textTheme.labelLarge),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A aba Mapa fica no Offstage abaixo, para não recriar o mapa.
    Widget? page;
    switch (selectedIndex) {
      case _abaInicio:
        page = TutorialPage(
          nomeUsuario: widget.usuario.nome,
          ehSupervisor: _ehSupervisor,
        );
        break;
      case _abaRegistro:
        page = AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(_subStep),
            child: _subStep == 0 ? _trechoKmEstacaVia() : _atividadeServDesc(context),
          ),
        );
        break;
      case _abaParadas:
        page = ParalisacoesPage(
          usuario: widget.usuario,
          aoMudar: _atualizarParadoAgora,
        );
        break;
      case _abaHistorico:
        page = HistoricoPage(usuario: widget.usuario);
        break;
      case _abaMapa:
        page = null;
        break;
      case _abaRelatorio:
        page = RelatorioPage(usuario: widget.usuario);
        break;
      // Só para supervisor.
      case _abaEquipe:
        page = SupervisorPage(usuario: widget.usuario);
        break;

      default:
        throw UnimplementedError('Paging not implemented for $selectedIndex');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('RDO cbm'),
            actions: [
              // A sincronização é automática: sem botão.
              IconButton(
                tooltip: 'Atualizações',
                icon: const Icon(Icons.system_update_alt),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AtualizacoesPage()),
                ),
              ),
              _usuarioAppBar(context),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            onDestinationSelected: (int index) {
              setState(() => selectedIndex = index);
              // A parada pode ter virado o dia ou sido encerrada no RDO.
              _atualizarParadoAgora();
            },
            selectedIndex: selectedIndex,
            // Com 7 abas (supervisor) "Histórico" e "Relatório" ficam no
            // limite num celular de 360 dp: letra 1 ponto menor para não
            // quebrar linha. As cores são as padrão da barra.
            labelTextStyle: _ehSupervisor
                ? WidgetStateProperty.resolveWith((estados) {
                    final tema = Theme.of(context);
                    return tema.textTheme.labelMedium?.copyWith(
                      fontSize: 11,
                      color: estados.contains(WidgetState.selected)
                          ? tema.colorScheme.onSurface
                          : tema.colorScheme.onSurfaceVariant,
                    );
                  })
                : null,
            destinations: <Widget>[
              const NavigationDestination(
                selectedIcon: Icon(Icons.home),
                icon: Icon(Icons.home_outlined),
                label: 'Início',
              ),
              const NavigationDestination(
                selectedIcon: Icon(Icons.edit_document),
                icon: Icon(Icons.edit_outlined),
                label: 'Registro',
              ),
              // Ponto vermelho: serviço parado agora.
              NavigationDestination(
                selectedIcon: Badge(
                  isLabelVisible: _paradoAgora,
                  child: const Icon(Icons.pause_circle),
                ),
                icon: Badge(
                  isLabelVisible: _paradoAgora,
                  child: const Icon(Icons.pause_circle_outline),
                ),
                label: 'Paradas',
              ),
              const NavigationDestination(
                selectedIcon: Icon(Icons.history),
                icon: Icon(Icons.history_outlined),
                label: 'Histórico',
              ),
              const NavigationDestination(
                selectedIcon: Icon(Icons.map),
                icon: Icon(Icons.map_outlined),
                label: 'Mapa',
              ),
              const NavigationDestination(
                selectedIcon: Icon(Icons.picture_as_pdf),
                icon: Icon(Icons.picture_as_pdf_outlined),
                label: 'Relatório',
              ),
              // Por último: some quando o perfil é revogado.
              if (_ehSupervisor)
                const NavigationDestination(
                  selectedIcon: Icon(Icons.groups),
                  icon: Icon(Icons.groups_outlined),
                  label: 'Equipe',
                ),
            ],
          ),

          body: Stack(
            children: [
              // Minimapa fora da tela: pré-carrega os tiles para a câmera.
              Positioned(
                left: -300,
                top: -300,
                child: SizedBox(
                  width: 256,
                  height: 256,
                  child: criarWidgetMiniMapa(locAtual),
                ),
              ),
              // Mapa sempre montado: a aba abre sem recarregar.
              Offstage(
                offstage: selectedIndex != _abaMapa,
                child: const MapPage(),
              ),
              if (page != null) page,
            ],
          ),
        );
      },
    );
  }
}
