import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

Directory? _dirDadosRemotos;

// Chamado no boot.
Future<void> inicializarDadosRemotos() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/dados_remotos');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  _dirDadosRemotos = dir;
}

Directory? get dirDadosRemotos => _dirDadosRemotos;

// Cópia baixada do arquivo, ou null se ainda não há.
File? arquivoRemotoOuNull(String nomeBase) {
  final dir = _dirDadosRemotos;
  if (dir == null) return null;
  final arquivo = File('${dir.path}/$nomeBase');
  return arquivo.existsSync() ? arquivo : null;
}

// true se o mapa já foi baixado.
bool mapaBaixado(String nome) {
  final dir = _dirDadosRemotos;
  return dir != null && Directory('${dir.path}/$nome').existsSync();
}

// Tile do mapa baixado; transparente se o arquivo não existe.
ImageProvider imagemOverlay(String assetDir, String nomeArquivo) {
  final dir = _dirDadosRemotos;
  if (dir != null) {
    final pasta = assetDir.split('/').last;
    final arquivo = File('${dir.path}/$pasta/$nomeArquivo');
    if (arquivo.existsSync()) return FileImage(arquivo);
  }
  return _tileTransparente;
}

final MemoryImage _tileTransparente =
    MemoryImage(img.encodePng(img.Image(width: 1, height: 1, numChannels: 4)));
