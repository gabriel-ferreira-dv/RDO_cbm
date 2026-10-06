// Smoke test do bootstrap do app: sem sessão ativa, MyApp deve abrir na
// LoginPage. Substitui o teste padrão do template do Flutter (contador),
// que não correspondia a nenhuma tela real deste app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/main.dart';

void main() {
  testWidgets('App sem sessão ativa mostra a tela de login', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(cameras: []));
    await tester.pumpAndSettle();

    expect(find.text('RDO cbm'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Entrar'), findsOneWidget);
  });
}
