// Previews do Flutter Widget Preview: cada função marcada com @Preview vira um
// quadro no painel "Flutter Widget Preview" do Android Studio (ou no Chrome,
// com `flutter widget-preview start`). Não entram no app: só o painel as chama.
//
// Regras para uma função de preview:
//   - fora de classe (ou static), pública (sem _ no nome);
//   - sem parâmetros obrigatórios;
//   - retorna um Widget.
// O preview roda como web: widget que usa SQLite, GPS, câmera, arquivo ou
// Supabase não aparece aqui. Passe os dados prontos por parâmetro.

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../theme/app_theme.dart';
import 'filtro_dia_dropdown.dart';
import 'info_chip.dart';

// Tema do app nos previews; sem ele o widget aparece com o tema padrão do
// Flutter, sem as cores da CBM. Claro ou escuro conforme o `brightness` do
// preview e o botão de sol/lua do painel. A API de tema do preview ainda
// muda entre versões do Flutter (esta é a da 3.47).
final class TemaDoApp extends PreviewThemeData {
  const TemaDoApp();

  @override
  Widget apply(BuildContext context, Widget child) => Theme(
        data: buildAppTheme(MediaQuery.platformBrightnessOf(context)),
        child: child,
      );
}

PreviewThemeData temaDoApp() => const TemaDoApp();

// 1. O mais simples: um widget com dados de exemplo.
@Preview(name: 'Estaca', group: 'InfoChip', theme: temaDoApp)
Widget infoChipEstaca() =>
    const InfoChip(icone: Icons.place, texto: 'EST. 1245 · KM 52');

// 2. O mesmo widget no modo escuro e num quadro de tamanho fixo.
@Preview(
  name: 'Escuro',
  group: 'InfoChip',
  theme: temaDoApp,
  brightness: Brightness.dark,
  size: Size(240, 60),
)
Widget infoChipEscuro() =>
    const InfoChip(icone: Icons.swap_horiz, texto: 'Via norte');

// 3. Texto longo, para ver se corta com "..." em vez de estourar.
@Preview(name: 'Texto longo', group: 'InfoChip', theme: temaDoApp, size: Size(220, 60))
Widget infoChipTextoLongo() => const InfoChip(
      icone: Icons.handyman_outlined,
      texto: 'Drenagem superficial – sarjeta de concreto moldada in loco',
    );

// 4. Vários widgets juntos, como aparecem no card do registro.
@Preview(name: 'Chips do registro', group: 'InfoChip', theme: temaDoApp, size: Size(380, 120))
Widget chipsDoRegistro() => const Padding(
      padding: EdgeInsets.all(12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          InfoChip(icone: Icons.swap_horiz, texto: 'Norte'),
          InfoChip(icone: Icons.straighten, texto: 'Estaca 1245 – 1250'),
          InfoChip(icone: Icons.handyman_outlined, texto: 'Terraplenagem'),
          InfoChip(icone: Icons.checklist_rtl, texto: 'Escavação'),
        ],
      ),
    );

// 5. Widget que recebe uma função: no preview ela não precisa fazer nada.
@Preview(name: 'Filtro por dia', group: 'Filtros', theme: temaDoApp, size: Size(360, 80))
Widget filtroDia() => FiltroDiaDropdown(
      dias: [DateTime(2026, 10, 5), DateTime(2026, 10, 4), DateTime(2026, 10, 3)],
      selecionado: DateTime(2026, 10, 5),
      onSelected: (_) {},
    );
