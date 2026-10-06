import 'package:flutter/material.dart';

// Placeholder da tela de edição manual de foto — funcionalidade ainda não
// implementada, aberta a partir de [MostrarImagemPage].
class EditarImagemPage extends StatelessWidget {
  final String imagePath;

  const EditarImagemPage({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar Foto')),
      body: const Center(child: Text('Funcionalidade de edição em desenvolvimento')),
    );
  }
}
