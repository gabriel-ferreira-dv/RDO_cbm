// Equivalentes ASCII para o que a fonte do PDF não desenha.
const Map<int, String> _equivalentes = {
  // Traços de todo tipo.
  0x2010: '-', 0x2011: '-', 0x2012: '-', 0x2013: '-', 0x2014: '-', 0x2015: '-',
  0x2212: '-',
  // Aspas e apóstrofos curvos.
  0x2018: "'", 0x2019: "'", 0x201A: ',', 0x201B: "'",
  0x201C: '"', 0x201D: '"', 0x201E: '"', 0x201F: '"',
  0x2032: "'", 0x2033: '"',
  0x2039: '<', 0x203A: '>',
  // Marcadores de lista.
  0x2022: '-', 0x2023: '-', 0x25AA: '-', 0x25CF: '-', 0x25E6: '-',
  // Reticências.
  0x2026: '...',
  // Setas e comparadores, comuns em observação de campo.
  0x2190: '<-', 0x2192: '->', 0x21D2: '=>',
  0x2260: '!=', 0x2264: '<=', 0x2265: '>=', 0x2248: '~',
  // Espaços especiais viram espaço comum.
  0x2007: ' ', 0x2008: ' ', 0x2009: ' ', 0x200A: ' ', 0x202F: ' ', 0x205F: ' ',
  0x3000: ' ',
  // Invisíveis: somem sem deixar rastro.
  0x200B: '', 0x200C: '', 0x200D: '', 0x2060: '', 0xFEFF: '',
  // Símbolos avulsos.
  0x20AC: 'EUR', 0x2122: '(TM)', 0x2117: '(P)',
};

// Deixa [texto] no que a fonte do PDF desenha. A Helvetica embutida só tem
// Latin-1: acento passa, mas travessão e aspas curvas (que o teclado do
// celular insere sozinho) viravam quadradinho.
String textoParaPdf(String texto) {
  // Quase tudo já é Latin-1: sai cedo.
  if (!texto.runes.any((r) => r > 0xFF)) return texto;

  final buffer = StringBuffer();
  for (final rune in texto.runes) {
    if (rune <= 0xFF) {
      buffer.writeCharCode(rune);
      continue;
    }
    final equivalente = _equivalentes[rune];
    if (equivalente != null) {
      buffer.write(equivalente);
      continue;
    }
    // Sem equivalente (emoji, outro alfabeto): some.
  }
  return buffer.toString();
}

// Aplica [textoParaPdf] em cada item da lista, descartando o que sobrar vazio.
List<String> linhasParaPdf(Iterable<String> linhas) => [
      for (final linha in linhas)
        if (textoParaPdf(linha).trim().isNotEmpty) textoParaPdf(linha),
    ];
