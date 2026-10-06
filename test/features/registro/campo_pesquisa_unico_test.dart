import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/presentation/widgets/campo_pesquisa_unico.dart';

Widget _app({String? initialValue, ValueChanged<String>? onSelected}) {
  return MaterialApp(
    home: Scaffold(
      body: CampoPesquisaUnico(
        textoPesquisa: 'Estaca inicial',
        items: const ['57', '58', '59'],
        initialValue: initialValue,
        onSelected: onSelected,
      ),
    ),
  );
}

void main() {
  testWidgets('abre a lista ao focar e fecha ao selecionar um item',
      (tester) async {
    String? selecionado;
    await tester.pumpWidget(_app(onSelected: (v) => selecionado = v));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(3));

    await tester.tap(find.widgetWithText(ListTile, '58'));
    await tester.pumpAndSettle();

    expect(selecionado, '58');
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('não abre a lista quando o valor é definido por fora',
      (tester) async {
    // Simula o preenchimento programático (GPS/importar): o initialValue muda
    // sem o campo ter foco — a lista deve continuar fechada.
    await tester.pumpWidget(_app());
    await tester.pumpWidget(_app(initialValue: '57'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(TextField), matching: find.text('57')),
        findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}
