import 'package:flutter/material.dart';

import '../../../relatorio/equipe_simova_service.dart';
import '../../equipe_supervisor_service.dart';

// Escolha dos encarregados que formam a equipe do supervisor.
//
// A lista vem do apontamento (quem teve lançamento nos últimos dias), então o
// supervisor marca nomes reais em vez de digitar matrícula.
class MontarEquipePage extends StatefulWidget {
  final String supervisorMatricula;
  final List<EncarregadoDaEquipe> equipeAtual;

  const MontarEquipePage({
    super.key,
    required this.supervisorMatricula,
    required this.equipeAtual,
  });

  @override
  State<MontarEquipePage> createState() => _MontarEquipePageState();
}

class _MontarEquipePageState extends State<MontarEquipePage> {
  List<({String matricula, String nome})> _disponiveis = [];
  late Set<String> _marcados;
  final _filtroController = TextEditingController();
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _marcados = {for (final e in widget.equipeAtual) e.matricula};
    _carregar();
  }

  @override
  void dispose() {
    _filtroController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final lista = await EquipeSimovaService.instancia.listarEncarregados();
    if (!mounted) return;
    setState(() {
      _disponiveis = lista;
      _carregando = false;
    });
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    final equipe = [
      for (final e in _disponiveis)
        if (_marcados.contains(e.matricula))
          EncarregadoDaEquipe(matricula: e.matricula, nome: e.nome),
      // Mantém quem já estava na equipe mas não apareceu no apontamento
      // recente — férias ou afastamento não podem apagar o cadastro.
      for (final e in widget.equipeAtual)
        if (_marcados.contains(e.matricula) &&
            !_disponiveis.any((d) => d.matricula == e.matricula))
          e,
    ];
    final erro = await EquipeSupervisorService.instancia
        .salvar(widget.supervisorMatricula, equipe);
    if (!mounted) return;
    setState(() => _salvando = false);
    if (erro != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(erro)));
      return;
    }
    Navigator.of(context).pop(equipe);
  }

  @override
  Widget build(BuildContext context) {
    final filtro = _filtroController.text.trim().toLowerCase();
    final visiveis = filtro.isEmpty
        ? _disponiveis
        : _disponiveis
            .where((e) =>
                e.nome.toLowerCase().contains(filtro) ||
                e.matricula.contains(filtro))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha equipe'),
        actions: [
          TextButton(
            onPressed: _salvando ? null : _salvar,
            child: Text(_salvando ? 'Salvando…' : 'Salvar'),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _filtroController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Buscar por nome ou matrícula',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_marcados.length} selecionado(s)',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                if (_disponiveis.isEmpty)
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Nenhum encarregado encontrado no apontamento dos '
                          'últimos dias. Verifique a conexão e se o '
                          'apontamento foi importado.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: visiveis.length,
                      itemBuilder: (_, i) {
                        final e = visiveis[i];
                        return CheckboxListTile(
                          dense: true,
                          value: _marcados.contains(e.matricula),
                          title: Text(e.nome,
                              style: const TextStyle(fontSize: 14)),
                          subtitle: Text('Matrícula ${e.matricula}',
                              style: const TextStyle(fontSize: 12)),
                          onChanged: (marcado) => setState(() {
                            if (marcado == true) {
                              _marcados.add(e.matricula);
                            } else {
                              _marcados.remove(e.matricula);
                            }
                          }),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
