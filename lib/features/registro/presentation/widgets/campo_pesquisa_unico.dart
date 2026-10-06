import 'package:flutter/material.dart';

class CampoPesquisaUnico extends StatefulWidget {
  final List<String> items;
  final ValueChanged<String>? onSelected;
  final bool enabled;
  final String textoPesquisa;
  final String? initialValue;

  // Quantos itens a lista mostra antes de a pessoa digitar.
  final int itensSemBusca;

  // Item em que a lista abre rolada. Os itens passam a ter altura fixa, então
  // só serve para listas de uma linha por item.
  final int? rolarParaIndice;
  const CampoPesquisaUnico({super.key, required this.items, this.onSelected, this.enabled = true, required this.textoPesquisa, this.initialValue, this.itensSemBusca = 50, this.rolarParaIndice});

  @override
  State<CampoPesquisaUnico> createState() => _CampoPesquisaUnicoState();
}

class _CampoPesquisaUnicoState extends State<CampoPesquisaUnico> {


  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _rolagem = ScrollController();
  static const double _alturaItem = 56;
  List<String> _filtered = [];
  bool _showList = false;
  int get _previewCount => widget.itensSemBusca;

  @override
  void initState() {
    super.initState();
    _filtered = [];
    if (widget.initialValue != null) _controller.text = widget.initialValue!;
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {

          _filtered = widget.items.take(_previewCount).toList();
          _showList = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _rolarAteOIndice());
      } else {

        setState(() => _showList = false);
      }
    });

    _controller.addListener(() {
      final text = _controller.text;
      setState(() {
        if (text.isEmpty) {

          _filtered = _focusNode.hasFocus ? widget.items.take(_previewCount).toList() : [];
          _showList = _focusNode.hasFocus;
        } else {
          _filtered = widget.items
              .where((p) => p.toLowerCase().contains(text.toLowerCase()))
              .toList();
          // Só com foco: o texto também muda por código e a lista ficava presa.
          _showList = _focusNode.hasFocus;
        }
      });
    });
  }

  @override
  void didUpdateWidget(CampoPesquisaUnico oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items && _focusNode.hasFocus) {
      final text = _controller.text;
      setState(() {
        _filtered = text.isEmpty
            ? widget.items.take(_previewCount).toList()
            : widget.items
                .where((p) => p.toLowerCase().contains(text.toLowerCase()))
                .toList();
      });
    }
    if (oldWidget.enabled && !widget.enabled) {
      _controller.clear();
      _focusNode.unfocus();
      setState(() => _showList = false);
    }
    // Acompanha o valor quando ele muda por fora (reset, importação).
    final novoValor = widget.initialValue ?? '';
    if (widget.initialValue != oldWidget.initialValue && novoValor != _controller.text) {
      _controller.text = novoValor;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  void _rolarAteOIndice() {
    final indice = widget.rolarParaIndice;
    if (indice == null || !_rolagem.hasClients) return;
    _rolagem.jumpTo(
        (indice * _alturaItem).clamp(0.0, _rolagem.position.maxScrollExtent));
  }

  void _select(String value) {
    _controller.text = value;
    _focusNode.unfocus();
    setState(() => _showList = false);
    debugPrint('Selecionado: $value');
    widget.onSelected?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: widget.textoPesquisa,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          if (_showList)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Card(
                child: SizedBox(
                  height: 200,
                  child: ListView.builder(
                    controller: _rolagem,
                    itemExtent:
                        widget.rolarParaIndice == null ? null : _alturaItem,
                    padding: EdgeInsets.zero,
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final item = _filtered[index];
                      return ListTile(
                        title: Text(item),
                        onTap: () => _select(item),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
