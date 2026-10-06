// Executa UMA VEZ no PC de desenvolvimento para gerar os pedaços de cada mapa:
//   dart run tool/split_overlay.dart
//
// Para adicionar um novo mapa: copie um bloco _Config na lista _configs,
// aponte para o PNG de origem e defina a pasta de saída.
//
// Requer ~2 GB de RAM livre por mapa grande.

import 'dart:io';
import 'package:image/image.dart' as img;

class _Config {
  final String source;
  final String output;
  final int cols;
  final int rows;
  const _Config({required this.source, required this.output, required this.cols, required this.rows});
}

const _configs = [
  // _Config(source: 'assets/Contorno_Fundão.png',  output: 'assets/overlays/Contorno_Fundão',  cols: 15, rows: 30),
  _Config(source: 'C:/Users/064925/Downloads/tTRECHO D2.png', output: "C:\\Users\\064925\\Teste_dart\\meuApp\\flutter_application_1\\assets\\d2M", cols: 25, rows: 90),
];

void main() async {
  for (final cfg in _configs) {
    await _process(cfg);
  }
  print('\nTodos os mapas processados.');
}

Future<void> _process(_Config cfg) async {
  print('\n── ${cfg.source} → ${cfg.output} ──');

  final file = File(cfg.source);
  if (!await file.exists()) {
    print('AVISO: ${cfg.source} não encontrado, pulando.');
    return;
  }

  print('Lendo ${cfg.source} (aguarde)...');
  final bytes = await file.readAsBytes();

  print('Decodificando PNG...');
  final src = img.decodePng(bytes);
  if (src == null) {
    print('Erro: não foi possível decodificar ${cfg.source}');
    return;
  }
  print('Tamanho: ${src.width}×${src.height}px');

  await Directory(cfg.output).create(recursive: true);

  final pw = (src.width  / cfg.cols).ceil();
  final ph = (src.height / cfg.rows).ceil();
  print('Grade ${cfg.cols}×${cfg.rows} — pedaços de ~$pw×${ph}px cada');
  print('Gerando ${cfg.cols * cfg.rows} arquivos em ${cfg.output}/ ...');

  var count = 0;
  for (var r = 0; r < cfg.rows; r++) {
    for (var c = 0; c < cfg.cols; c++) {
      final x = c * pw;
      final y = r * ph;
      final w = x + pw > src.width  ? src.width  - x : pw;
      final h = y + ph > src.height ? src.height - y : ph;

      final piece = img.copyCrop(src, x: x, y: y, width: w, height: h);
      final name  = '${r.toString().padLeft(2, '0')}_$c.png';
      await File('${cfg.output}/$name').writeAsBytes(img.encodePng(piece));
      count++;
      stdout.write('\r  $count/${cfg.cols * cfg.rows}');
    }
  }

  print('\nConcluído! Pedaços salvos em ${cfg.output}/');
}
