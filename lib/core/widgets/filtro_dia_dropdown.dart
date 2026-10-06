import 'package:flutter/material.dart';

// Dropdown "Filtrar por dia" usado no Histórico e na importação de
// atividade anterior. [dias] em ordem decrescente (mais recente primeiro);
// selecionar "Todos os dias" devolve null no [onSelected].
class FiltroDiaDropdown extends StatelessWidget {
  final List<DateTime> dias;
  final DateTime? selecionado;
  final ValueChanged<DateTime?> onSelected;

  const FiltroDiaDropdown({
    super.key,
    required this.dias,
    required this.selecionado,
    required this.onSelected,
  });

  String _rotulo(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<DateTime?>(
      initialSelection: selecionado,
      label: const Text('Filtrar por dia'),
      leadingIcon: const Icon(Icons.calendar_today_outlined),
      // Ocupa a largura disponível, alinhado com os cards das listas.
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: [
        const DropdownMenuEntry<DateTime?>(value: null, label: 'Todos os dias'),
        for (final dia in dias)
          DropdownMenuEntry<DateTime?>(value: dia, label: _rotulo(dia)),
      ],
      onSelected: onSelected,
    );
  }
}
