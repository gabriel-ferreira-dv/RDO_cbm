import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:namer_app/features/camera/camera_service.dart';

// Garante que a linha de serviço do carimbo nunca ultrapassa a largura útil
// da foto (o espaço entre o minimapa e a margem direita) — foi o que fez o
// texto vazar por cima do minimapa e sair da imagem.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late img.BitmapFont fonte;

  setUpAll(() async {
    final data = await rootBundle.load('assets/fonts/custom_pt_24.zip');
    fonte = img.readFontZip(data.buffer.asUint8List());
  });

  // Caso real da foto que estourou: serviço + passo somam ~80 caracteres.
  const servicoLongo = 'TRANSPORTE DE MATERIAIS ESCAVADOS OU SOLOS - '
      'Carga do material com carregadeira';

  test('texto longo é quebrado e nenhuma linha passa da largura', () {
    const larguraMax = 600;
    final linhas = quebrarEmLinhasParaTeste(fonte, servicoLongo, larguraMax);

    expect(linhas.length, greaterThan(1));
    for (final linha in linhas) {
      expect(larguraTextoParaTeste(fonte, linha), lessThanOrEqualTo(larguraMax));
    }
  });

  test('nenhuma palavra é perdida na quebra', () {
    final linhas = quebrarEmLinhasParaTeste(fonte, servicoLongo, 600);
    expect(linhas.join(' ').split(RegExp(r'\s+')),
        equals(servicoLongo.split(RegExp(r'\s+'))));
  });

  test('texto curto continua em uma linha só', () {
    final linhas = quebrarEmLinhasParaTeste(fonte, 'KM 225 - Via 02 Norte', 600);
    expect(linhas, hasLength(1));
  });

  test('palavra única gigante é cortada em vez de vazar', () {
    // Sem espaços não há onde quebrar: tem que cortar no meio da palavra.
    final linhas = quebrarEmLinhasParaTeste(fonte, 'A' * 200, 300);
    expect(linhas.length, greaterThan(1));
    for (final linha in linhas) {
      expect(larguraTextoParaTeste(fonte, linha), lessThanOrEqualTo(300));
    }
  });

  test('largura útil menor ainda gera linhas dentro do limite', () {
    for (final largura in [200, 350, 500, 900]) {
      final linhas = quebrarEmLinhasParaTeste(fonte, servicoLongo, largura);
      for (final linha in linhas) {
        expect(larguraTextoParaTeste(fonte, linha), lessThanOrEqualTo(largura),
            reason: 'estourou com larguraMax=$largura na linha "$linha"');
      }
    }
  });
}
