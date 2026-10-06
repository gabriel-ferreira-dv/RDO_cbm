import 'dart:io';
import 'package:flutter/material.dart';
import 'mostrar_imagem_page.dart';

// Grade de miniaturas das fotos de uma sessão; toque abre [MostrarImagemPage]
// em tela cheia. Reaproveitada pela câmera e pelo histórico.
class GaleriaImagensPage extends StatelessWidget {
  final List<String> fotos;
  final String descricao;

  const GaleriaImagensPage({super.key, required this.fotos, this.descricao = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Fotos (${fotos.length})')),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: fotos.length,
        itemBuilder: (context, index) {
          final path = fotos[fotos.length - 1 - index];
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => MostrarImagemPage(imagePath: path, descricao: descricao),
                ),
              );
            },
            child: Image.file(File(path), fit: BoxFit.cover),
          );
        },
      ),
    );
  }
}
