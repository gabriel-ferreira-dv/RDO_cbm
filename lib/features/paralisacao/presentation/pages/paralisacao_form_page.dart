import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/galeria_imagens_page.dart';
import '../../../auth/models/usuario.dart';
import '../../../camera/presentation/pages/camera_page.dart';
import '../../../registro/csv_dados_datasource.dart';
import '../../../relatorio/turno_noturno.dart';
import '../../models/paralisacao.dart';
import '../../paralisacao_service.dart';

// Nova paralisação no dia de trabalho [dia], ou edição de [paralisacao].
class ParalisacaoFormPage extends StatefulWidget {
  final Usuario usuario;
  final DateTime dia;
  final bool noturno;
  final Paralisacao? paralisacao;

  const ParalisacaoFormPage({
    super.key,
    required this.usuario,
    required this.dia,
    this.noturno = false,
    this.paralisacao,
  });

  @override
  State<ParalisacaoFormPage> createState() => _ParalisacaoFormPageState();
}

class _ParalisacaoFormPageState extends State<ParalisacaoFormPage> {
  final _observacao = TextEditingController();
  int? _id;
  late final String _criadoEm = widget.paralisacao?.criadoEm ??
      DateTime.now().toUtc().toIso8601String();
  String? _motivo;
  late DateTime _inicio; // local
  DateTime? _fim; // local; null = ainda parado
  String? _trecho;
  String? _km;
  List<String> _trechos = [];
  List<String> _kms = [];
  List<FotoParalisacao> _fotos = [];
  bool _salvando = false;

  bool get _ehHoje =>
      DateTime(widget.dia.year, widget.dia.month, widget.dia.day) ==
      diaDoTurno(DateTime.now(), noturno: widget.noturno);

  @override
  void initState() {
    super.initState();
    final p = widget.paralisacao;
    if (p != null) {
      _id = p.id;
      _motivo = p.motivo;
      _inicio = p.inicio.toLocal();
      _fim = p.fim?.toLocal();
      _trecho = p.trecho.isEmpty ? null : p.trecho;
      _km = p.km.isEmpty ? null : p.km;
      _observacao.text = p.observacao;
      _carregarFotos();
    } else if (_ehHoje) {
      // Parou agora: começa agora e segue sem término.
      _inicio = DateTime.now();
      _sugerirLocal();
    } else {
      // Lançamento de outro dia: um horário qualquer para ajustar.
      _inicio = DateTime(widget.dia.year, widget.dia.month, widget.dia.day, 13);
      _fim = _inicio.add(const Duration(hours: 1));
    }
    carregarTrechos().then((v) {
      if (mounted) setState(() => _trechos = v);
    });
    if (_trecho != null) _carregarKms(_trecho!);
  }

  @override
  void dispose() {
    _observacao.dispose();
    super.dispose();
  }

  Future<void> _sugerirLocal() async {
    final local = await ParalisacaoService.instancia.ultimoLocalDoDia(widget.usuario.id!);
    if (!mounted || local == null || _trecho != null) return;
    setState(() {
      _trecho = local.trecho.isEmpty ? null : local.trecho;
      _km = local.km.isEmpty ? null : local.km;
    });
    if (_trecho != null) _carregarKms(_trecho!);
  }

  Future<void> _carregarKms(String trecho) async {
    final kms = await carregarKmEst(3, 0, trecho);
    if (mounted) setState(() => _kms = kms);
  }

  Future<void> _carregarFotos() async {
    final id = _id;
    if (id == null) return;
    final fotos = await ParalisacaoService.instancia.fotosDe(id);
    if (mounted) setState(() => _fotos = fotos);
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _ddmm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  // Hora escolhida levada para o dia de trabalho: no turno da noite, a
  // madrugada é do dia seguinte.
  DateTime _noDia(TimeOfDay hora) {
    final d = widget.dia;
    final madrugada = widget.noturno && hora.hour < horaViradaTurnoNoturno;
    return DateTime(d.year, d.month, d.day + (madrugada ? 1 : 0), hora.hour, hora.minute);
  }

  Future<void> _escolherInicio() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_inicio),
      helpText: 'Parou às',
    );
    if (hora == null) return;
    setState(() => _inicio = _noDia(hora));
  }

  Future<void> _escolherFim() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fim ?? DateTime.now()),
      helpText: 'Voltou às',
    );
    if (hora == null) return;
    var fim = DateTime(_inicio.year, _inicio.month, _inicio.day, hora.hour, hora.minute);
    // Antes do início: passou da meia-noite.
    if (!fim.isAfter(_inicio)) fim = fim.add(const Duration(days: 1));
    setState(() => _fim = fim);
  }

  // Salva e devolve o id; null se faltar algo.
  Future<int?> _salvar() async {
    final motivo = _motivo;
    if (motivo == null) {
      _avisar('Escolha o motivo da paralisação');
      return null;
    }
    final fim = _fim;
    if (fim != null && !fim.isAfter(_inicio)) {
      _avisar('O término tem que ser depois do início');
      return null;
    }
    setState(() => _salvando = true);
    try {
      final id = await ParalisacaoService.instancia.salvar(Paralisacao(
        id: _id,
        usuarioId: widget.usuario.id!,
        motivo: motivo,
        observacao: _observacao.text.trim(),
        trecho: _trecho ?? '',
        km: _km ?? '',
        inicio: _inicio.toUtc(),
        fim: fim?.toUtc(),
        criadoEm: _criadoEm,
      ));
      _id = id;
      return id;
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _salvarEFechar() async {
    if (await _salvar() != null && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _salvarEFotografar() async {
    final id = await _salvar();
    if (id == null || !mounted) return;
    List<CameraDescription> cameras = [];
    try {
      cameras = await availableCameras();
    } catch (e) {
      debugPrint('Paralisação: câmera indisponível: $e');
    }
    if (!mounted) return;
    if (cameras.isEmpty) {
      _avisar('Câmera indisponível neste aparelho');
      return;
    }
    final fim = _fim;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CameraPage(
        cameras: cameras,
        aoSalvarFoto: (caminho, posicao) => ParalisacaoService.instancia.adicionarFoto(
          paralisacaoId: id,
          caminhoArquivo: caminho,
          latitude: posicao.latitude,
          longitude: posicao.longitude,
        ),
        trecho: _trecho ?? '',
        kmtrecho: _km ?? '',
        estacaInicial: '',
        estacaFinal: '',
        via: '',
        descricao: _observacao.text.trim(),
        servNotavel: 'PARALISAÇÃO - ${_motivo!}',
        servNotavelDetalhes: fim == null
            ? 'Parado desde ${_hhmm(_inicio)}'
            : 'Parado das ${_hhmm(_inicio)} às ${_hhmm(fim)}',
      ),
    ));
    await _carregarFotos();
  }

  Future<void> _excluir() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir paralisação?'),
        content: const Text('Ela sai do relatório. As fotos ficam no aparelho.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmado != true || _id == null) return;
    await ParalisacaoService.instancia.excluir(_id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _avisar(String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fim = _fim;
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? 'Registrar paralisação' : 'Paralisação'),
        actions: [
          if (_id != null)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: _salvando ? null : _excluir,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Motivo', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final motivo in motivosParalisacao)
                ChoiceChip(
                  label: Text(motivo),
                  selected: _motivo == motivo,
                  onSelected: (_) => setState(() => _motivo = motivo),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _escolherInicio,
                  icon: const Icon(Icons.pause_circle_outline),
                  label: Text('Parou: ${_hhmm(_inicio)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: fim == null ? null : _escolherFim,
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(fim == null ? 'Voltou: --:--' : 'Voltou: ${_hhmm(fim)}'),
                ),
              ),
            ],
          ),
          if (fim != null && fim.day != _inicio.day)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Voltou no dia ${_ddmm(fim)}',
                  style: theme.textTheme.bodySmall),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ainda parado'),
            subtitle: const Text('Toque em "Retomar serviço" quando voltar'),
            value: fim == null,
            onChanged: (parado) => setState(() {
              _fim = parado ? null : _padraoDeTermino();
            }),
          ),
          const SizedBox(height: 8),
          Text('Onde (opcional)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            // Recria quando a sugestão do último registro chega.
            key: ValueKey('trecho_${_trecho}_${_trechos.length}'),
            initialValue: _trecho,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Trecho', isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('Não informar')),
              for (final t in {..._trechos, if (_trecho != null) _trecho!})
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (t) {
              setState(() {
                _trecho = t;
                _km = null;
                _kms = [];
              });
              if (t != null) _carregarKms(t);
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            // Recria ao trocar o trecho, para o KM antigo sair.
            key: ValueKey('km_${_trecho}_${_kms.length}'),
            initialValue: _km,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'KM', isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('Não informar')),
              for (final k in {..._kms, if (_km != null) _km!})
                DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: _trecho == null ? null : (k) => setState(() => _km = k),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _observacao,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observação (opcional)',
              hintText: 'Ex.: chuva forte, pista alagada no KM 225',
              border: OutlineInputBorder(),
            ),
          ),
          if (_fotos.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Fotos (${_fotos.length})', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final foto in _fotos)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => GaleriaImagensPage(
                            fotos: [for (final f in _fotos) f.caminhoArquivo],
                            descricao: _observacao.text.trim(),
                          ),
                        )),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(File(foto.caminhoArquivo),
                              width: 96, height: 72, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _salvando ? null : _salvarEFotografar,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_fotos.isEmpty ? 'Salvar e tirar foto' : 'Salvar e tirar mais fotos'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _salvando ? null : _salvarEFechar,
            icon: const Icon(Icons.check),
            label: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // Término sugerido ao desligar "Ainda parado".
  DateTime _padraoDeTermino() {
    final agora = DateTime.now();
    return agora.isAfter(_inicio) && agora.difference(_inicio).inHours < 24
        ? agora
        : _inicio.add(const Duration(hours: 1));
  }
}
