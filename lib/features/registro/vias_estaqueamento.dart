// Regras de estaqueamento por via. No C1 a Via 02 Norte é a série 1000 e a
// Via 01 Sul a 2000 (a 2115 fica ao lado da 1115); no D2 há uma série só e a
// via é escolhida pelo usuário. Sem imports, para evitar import circular.

const String viaSul = 'Via 01 Sul';
const String viaNorte = 'Via 02 Norte';

// Só os dígitos ("EST. 57" → "57"): os CSVs escrevem a estaca diferente.
String numeroDaEstaca(String texto) => texto.replaceAll(RegExp(r'[^0-9]'), '');

// Primeira estaca da série sul.
const int inicioSerieSul = 2000;

// Distância entre as duas numerações: a estaca 1115 vira 2115 na outra pista.
const int deslocamentoEntreSeries = 1000;

bool estacaDaSerieSul(int numero) => numero >= inicioSerieSul;

// Estaca equivalente na via sul (1115 → 2115).
int gemeaNaSerieSul(int numero) => numero + deslocamentoEntreSeries;

// Estaca equivalente na via norte (2115 → 1115), ou null se já é do norte.
int? gemeaNaSerieNorte(int numero) =>
    estacaDaSerieSul(numero) ? numero - deslocamentoEntreSeries : null;

// Via pela numeração; null em pista simples.
String? viaDaEstaca(int numero, {required bool pistaDupla}) {
  if (!pistaDupla) return null;
  return estacaDaSerieSul(numero) ? viaSul : viaNorte;
}

// KM para exibir: "231", ou "231 a 232" quando o serviço atravessa o KM.
String faixaDeKm(String km, String kmFinal) {
  final fim = kmFinal.trim();
  return fim.isEmpty || fim == km.trim() ? km : '$km a $fim';
}

// Trechos sem via (pista simples e áreas de apoio): o formulário não
// pergunta. Lista manual, porque o dado não distingue (o D2 tem uma série só
// e tem via). Nomes já normalizados por [chaveDoTrecho].
const Set<String> trechosSemVia = {
  'CONTORNO DE FUNDAO',
  'CONTORNO DE IBIRACU',
  'CANTEIRO INDUSTRIAL',
  'PATIO DE VIGAS',
};

// Áreas de apoio sem estaqueamento de projeto: o formulário não pede estaca
// (no KMxEst elas só têm a estaca 0, de marcador). Nomes já normalizados por
// [chaveDoTrecho].
const Set<String> trechosSemEstaca = {
  'CANTEIRO INDUSTRIAL',
  'PATIO DE VIGAS',
};

// Nome do trecho comparável: caixa alta, sem acento nem espaço repetido.
String chaveDoTrecho(String trecho) {
  const comAcento = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const semAcento = 'AAAAAEEEEIIIIOOOOOUUUUC';
  final texto = trecho
      .toUpperCase()
      // Acentos que vieram decompostos (o "Ç" como C + cedilha).
      .replaceAll(RegExp('[\u0300-\u036F]'), '');
  final buffer = StringBuffer();
  for (final rune in texto.runes) {
    final caractere = String.fromCharCode(rune);
    final i = comAcento.indexOf(caractere);
    buffer.write(i >= 0 ? semAcento[i] : caractere);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

// Se o trecho pede a via. Trecho não escolhido conta como pedindo.
bool trechoTemVia(String? trecho) =>
    trecho == null || !trechosSemVia.contains(chaveDoTrecho(trecho));

// Se o trecho pede estaca. Trecho não escolhido conta como pedindo.
bool trechoTemEstaca(String? trecho) =>
    trecho == null || !trechosSemEstaca.contains(chaveDoTrecho(trecho));
