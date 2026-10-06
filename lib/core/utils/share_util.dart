import 'package:share_plus/share_plus.dart';

// Compartilha uma ou mais imagens processadas via share sheet do sistema.
// O usuário escolhe o destino (WhatsApp, e-mail, Drive, etc.).
Future<void> compartilharImagens(
  List<String> paths, {
  String texto = '',
}) async {
  if (paths.isEmpty) return;

  final arquivos = paths
      .map((p) => XFile(p, mimeType: 'image/jpeg'))
      .toList();

  await Share.shareXFiles(arquivos, text: texto);
}

// Atalho para compartilhar uma única imagem.
Future<void> compartilharImagem(String path, {String texto = ''}) =>
    compartilharImagens([path], texto: texto);
