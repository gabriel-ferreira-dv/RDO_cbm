import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/sincronizacao/atualizacao_app_service.dart';
import 'package:namer_app/features/sincronizacao/atualizacao_dados_service.dart';

VersaoPublicada _publicada({int codigo = 3, int minima = 0, String nome = '1.0.1'}) =>
    VersaoPublicada(
      codigo: codigo,
      nome: nome,
      arquivo: 'RDO-cbm-$codigo.apk',
      minima: minima,
      novidades: '',
    );

void main() {
  group('compararVersoes', () {
    test('versão publicada maior oferece atualização opcional', () {
      final atualizacao = compararVersoes(2, _publicada(codigo: 3));
      expect(atualizacao, isNotNull);
      expect(atualizacao!.obrigatoria, isFalse);
    });

    test('na mesma versão ou acima não oferece nada', () {
      expect(compararVersoes(3, _publicada(codigo: 3)), isNull);
      expect(compararVersoes(4, _publicada(codigo: 3)), isNull);
    });

    test('abaixo da mínima a atualização é obrigatória', () {
      expect(compararVersoes(2, _publicada(codigo: 4, minima: 3))!.obrigatoria,
          isTrue);
      expect(compararVersoes(3, _publicada(codigo: 4, minima: 3))!.obrigatoria,
          isFalse);
    });

    // Mínima digitada acima da publicada: sem este cuidado, quem instalasse a
    // versão publicada continuaria "abaixo da mínima" e seria mandado instalar
    // a mesma versão para sempre.
    test('mínima maior que a publicada não prende quem já está nela', () {
      expect(compararVersoes(3, _publicada(codigo: 3, minima: 5)), isNull);
    });

    test('sem nome na tabela, o aviso mostra o código', () {
      expect(_publicada(codigo: 7, nome: ' ').rotulo, '7');
      expect(_publicada(nome: '1.0.1').rotulo, '1.0.1');
    });
  });

  group('versaoInstaladaDoMapa', () {
    // Os mapas saíram do APK. Se a ausência ainda valesse 1 ("a embutida"), a
    // linha versão 1 do servidor nunca seria oferecida e o mapa ficaria em
    // branco depois da atualização.
    test('mapa nunca baixado vale 0, para até a versão 1 ser oferecida', () {
      expect(versaoInstaladaDoMapa(baixado: false), 0);
    });

    test('pasta apagada volta a oferecer o download, mesmo com versão salva', () {
      expect(versaoInstaladaDoMapa(baixado: false, salva: 3), 0);
    });

    test('mapa baixado usa a versão salva', () {
      expect(versaoInstaladaDoMapa(baixado: true, salva: 3), 3);
      expect(versaoInstaladaDoMapa(baixado: true), 1);
    });
  });
}
