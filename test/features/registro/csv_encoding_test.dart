import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/registro/csv_dados_datasource.dart';

// O Excel pt-BR salva CSV em Windows-1252 (Latin-1). Um único acento nesse
// formato quebrava a leitura UTF-8 e sumia com TODAS as estacas (o bug do
// "Ç" de IBIRAÇU no estacas_coords.csv). O loader tem que tolerar isso.
void main() {
  test('lê CSV em UTF-8 normalmente', () {
    final bytes = utf8.encode('Trecho;Estaca\nCONTORNO DE IBIRAÇU;0');
    expect(decodificarCsv(bytes), contains('IBIRAÇU'));
  });

  test('lê CSV salvo em Latin-1/Windows-1252 sem quebrar', () {
    // "IBIRAÇU" com o Ç no byte 0xC7 do Latin-1 — o caso real do arquivo.
    final bytes = latin1.encode('Trecho;Estaca\nCONTORNO DE IBIRAÇU;0');
    expect(bytes, contains(0xC7)); // garante que não é UTF-8 válido
    final texto = decodificarCsv(bytes);
    expect(texto, contains('IBIRAÇU'));
  });

  test('CSV puro ASCII é idêntico nos dois caminhos', () {
    const conteudo = 'Trecho;Estaca\nD2;57';
    expect(decodificarCsv(utf8.encode(conteudo)), conteudo);
    expect(decodificarCsv(latin1.encode(conteudo)), conteudo);
  });
}
