import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/share_util.dart';
import 'editar_imagem_page.dart';

// Exibe uma única foto em tela cheia, com ações de compartilhar e editar.
// Reaproveitada tanto pela câmera (foto recém-tirada) quanto pelo histórico
// (fotos já salvas).
class MostrarImagemPage extends StatelessWidget {
  final String imagePath;
  final String descricao;

  const MostrarImagemPage({super.key, required this.imagePath, this.descricao = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Compartilhar',
            onPressed: () => compartilharImagem(imagePath, texto: descricao),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => EditarImagemPage(imagePath: imagePath),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(child: Image.file(File(imagePath))),
    );
  }
}
