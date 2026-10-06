import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Arquivos que desenham rótulo fixo no PDF.
//
// Só estes dois: são os que chamam `pw.Text` com texto escrito à mão. O texto
// que vem de fora (descrição digitada, nome do apontamento, legenda de foto)
// não dá para cobrir com um teste de código-fonte — quem digita é o
// encarregado no celular — e por isso passa por `textoParaPdf` em tempo de
// execução. Este teste cuida do outro lado: o rótulo que está no código.
//
// Arquivo de tela fica de fora de propósito. O travessão de um `AppBar` é
// legítimo: o Flutter desenha Unicode inteiro, quem não desenha é o PDF.
const _fontes = [
  'lib/features/relatorio/relatorio_service.dart',
  'lib/features/supervisor/relatorio_consolidado_service.dart',
];

// Remove o comentário de fim de linha.
//
// Os comentários deste projeto são em português e usam travessão à vontade —
// e não vão para o PDF. Cortar no `//` deixa passar um caractere que esteja
// depois de um `//` dentro de uma string (uma URL), o que só faria o teste
// deixar de acusar algo, nunca acusar à toa.
String _semComentario(String linha) {
  final i = linha.indexOf('//');
  return i < 0 ? linha : linha.substring(0, i);
}

void main() {
  // O PDF usa a Helvetica embutida, que é Type1: o dart_pdf codifica o texto
  // em Latin-1 e trata como não suportado tudo que passa de U+00FF. O
  // caractere não é desenhado — vira um quadradinho no relatório, sem erro
  // nenhum na geração. Já aconteceu com o travessão "—" antes da medição.
  //
  // Acento não é problema: "ção", "m³" e "º" cabem no Latin-1. O que não cabe
  // é o travessão, o "•", as reticências "…" e as aspas curvas — exatamente o
  // que um editor de texto insere sozinho ao colar de outro lugar.
  test('nenhum texto do PDF usa caractere fora do Latin-1', () {
    final problemas = <String>[];

    for (final caminho in _fontes) {
      final arquivo = File(caminho);
      expect(arquivo.existsSync(), isTrue, reason: '$caminho não existe mais');

      final linhas = arquivo.readAsLinesSync();
      for (var n = 0; n < linhas.length; n++) {
        final codigo = _semComentario(linhas[n]);
        // Identificador em Dart é ASCII, então qualquer caractere alto que
        // sobre aqui está necessariamente dentro de uma string literal.
        final fora = codigo.runes.where((r) => r > 0xFF).toSet();
        if (fora.isEmpty) continue;
        final vistos = fora
            .map((r) => '"${String.fromCharCode(r)}" (U+'
                '${r.toRadixString(16).toUpperCase().padLeft(4, '0')})')
            .join(', ');
        problemas.add('$caminho:${n + 1}  $vistos\n    ${codigo.trim()}');
      }
    }

    expect(problemas, isEmpty,
        reason: 'estes caracteres viram quadradinho no PDF; troque por um '
            'equivalente ASCII:\n${problemas.join('\n')}');
  });
}
