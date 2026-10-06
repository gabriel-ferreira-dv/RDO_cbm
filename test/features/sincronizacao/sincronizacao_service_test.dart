import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, StorageException;
import 'package:namer_app/features/sincronizacao/sincronizacao_service.dart';

class _ClientException implements Exception {}

void main() {
  // Sem rede, a rodada para (a próxima continua dali). Recusa do servidor é
  // só daquele item: antes, uma foto recusada travava a fila do aparelho.
  group('ehFalhaDeRede', () {
    test('sem internet ou internet travada para a rodada', () {
      expect(ehFalhaDeRede(const SocketException('sem rota')), isTrue);
      expect(ehFalhaDeRede(TimeoutException('lento')), isTrue);
      expect(ehFalhaDeRede(_ClientException()), isTrue);
      // O Storage põe o nome da exceção no lugar do código HTTP.
      expect(ehFalhaDeRede(const StorageException('x', statusCode: 'SocketException')),
          isTrue);
    });

    test('recusa do servidor fica só com aquele item', () {
      expect(ehFalhaDeRede(const StorageException('negado', statusCode: '403')), isFalse);
      expect(ehFalhaDeRede(const PostgrestException(message: 'RLS', code: '42501')),
          isFalse);
    });
  });

  // O bug que travou os aparelhos com a versão nova: o servidor sem a coluna
  // km_final, e o app tirando a coluna km no lugar dela.
  group('colunaDesconhecida', () {
    const erro = PostgrestException(
      code: 'PGRST204',
      message: "Could not find the 'km_final' column of 'registros_app' in the schema cache",
    );
    final campos = ['dispositivo_id', 'trecho', 'km', 'km_final', 'via'];

    test('tira a coluna que o servidor não tem, não a que contém o nome', () {
      expect(colunaDesconhecida(erro, campos), 'km_final');
    });

    test('outro erro não tira coluna nenhuma', () {
      expect(
        colunaDesconhecida(
            const PostgrestException(code: '23502', message: "null value in column 'km'"),
            campos),
        isNull,
      );
    });

    test('coluna que não está entre os campos enviados não é tirada', () {
      expect(colunaDesconhecida(erro, ['trecho', 'km']), isNull);
    });
  });

  group('foto para o servidor', () {
    late Directory pasta;
    setUp(() => pasta = Directory.systemTemp.createTempSync('foto_upload'));
    tearDown(() => pasta.deleteSync(recursive: true));

    String salvar(int largura, int altura) {
      final foto = img.Image(width: largura, height: altura);
      img.fill(foto, color: img.ColorRgb8(90, 140, 60));
      final arquivo = File('${pasta.path}/foto_$largura.jpg')
        ..writeAsBytesSync(img.encodeJpg(foto, quality: 75));
      return arquivo.path;
    }

    // Comprimir de novo a foto do app só perdia qualidade.
    test('a foto da câmera (720p) sobe byte a byte como está no celular', () {
      final caminho = salvar(1280, 720);
      expect(prepararFotoParaUploadParaTeste(caminho), File(caminho).readAsBytesSync());
    });

    test('foto maior que o limite é reduzida para a largura máxima', () {
      final enviada = prepararFotoParaUploadParaTeste(salvar(4000, 3000))!;
      expect(img.decodeJpg(enviada)!.width, larguraMaximaNoServidor);
    });

    test('arquivo que sumiu não trava a fila', () {
      expect(prepararFotoParaUploadParaTeste('${pasta.path}/nao_existe.jpg'), isNull);
    });
  });

  test('slugParaArquivo converte para minúsculas sem acentos nem espaços', () {
    expect(slugParaArquivo('REMOÇÃO DE CERCA'), 'remocao_de_cerca');
    expect(slugParaArquivo('SERVIÇOS PRELIMINARES'), 'servicos_preliminares');
    expect(slugParaArquivo('Gabriel Souza'), 'gabriel_souza');
    expect(slugParaArquivo('SUBLEITO PISTA PRINCIPAL'), 'subleito_pista_principal');
  });

  test('slugParaArquivo trata caracteres especiais e bordas', () {
    // Barra e pontuação não podem virar subpasta/nome inválido no Storage.
    expect(slugParaArquivo('CORTE/ATERRO (1ª CAT.)'), 'corte_aterro_1a_cat');
    expect(slugParaArquivo('  espaços  nas  bordas  '), 'espacos_nas_bordas');
    expect(slugParaArquivo('***'), 'sem_nome');
    expect(slugParaArquivo(''), 'sem_nome');
  });
}
