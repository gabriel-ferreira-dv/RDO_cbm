import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/features/mapa/mapas_config.dart';

// A atualização remota depende de três nomes idênticos: a pasta de assets, a
// pasta baixada (dados_remotos) e a coluna `nome` do Supabase. Estes testes
// travam as duas pontas que vivem no repositório — a terceira (Supabase) é
// responsabilidade do administrador, e o app confia nela.
void main() {
  // Os tiles não são mais versionados (ver .gitignore): num clone novo a pasta
  // nem existe, e o mapa vem do Supabase. Onde ela existe — a máquina de quem
  // gera os .zip — a conferência continua valendo.
  test('todo mapa do config tem a pasta de tiles correspondente', () {
    for (final mapa in mapasConfig) {
      final dir = Directory(mapa.assetDir);
      if (!dir.existsSync()) continue;
      final webps =
          dir.listSync().where((f) => f.path.endsWith('.webp')).length;
      expect(webps, greaterThan(0),
          reason: '${mapa.assetDir} não tem tiles .webp');
    }
  });

  test('ehNomeDeMapa reconhece os mapas e recusa CSVs', () {
    for (final mapa in mapasConfig) {
      expect(ehNomeDeMapa(mapa.nome), isTrue);
    }
    // Nomes de CSV não podem ser confundidos com mapa — senão a atualização
    // trataria um mapa de 100+ MB como um download automático de CSV.
    expect(ehNomeDeMapa('KMxEst.csv'), isFalse);
    expect(ehNomeDeMapa('SevNotaveis.csv'), isFalse);
    // O esquema antigo não deve mais casar.
    expect(ehNomeDeMapa('overlay'), isFalse);
    expect(ehNomeDeMapa('overlay2'), isFalse);
  });

  // Os mapas são divididos em grupos e cada usuário recebe um ou os dois (ver
  // supabase/mapas_por_usuario.sql). O que a subcontratada enxerga da obra da
  // CBM, e vice-versa, sai daqui.
  group('grupos de mapa', () {
    test('quem só tem CBM não vê o mapa da subcontratada', () {
      final nomes = mapasDosGrupos({grupoCbm}).map((m) => m.nome);
      expect(nomes, contains('D2'));
      expect(nomes, isNot(contains('GEO_dreno')));
    });

    test('quem só tem SUB CONTRATADA vê apenas o mapa dela', () {
      final nomes = mapasDosGrupos({grupoSubContratada}).map((m) => m.nome);
      expect(nomes, ['GEO_dreno']);
    });

    test('nos dois grupos vê todos os mapas', () {
      expect(mapasDosGrupos({grupoCbm, grupoSubContratada}).length,
          mapasConfig.length);
    });

    test('sem grupo nenhum não sobra mapa solto', () {
      expect(mapasDosGrupos({}), isEmpty);
    });

    test('grupoDoMapa responde pelo nome, com padrão seguro', () {
      expect(grupoDoMapa('D2'), grupoCbm);
      expect(grupoDoMapa('GEO_dreno'), grupoSubContratada);
      // Nome desconhecido cai no grupo de todo mundo, nunca no restrito.
      expect(grupoDoMapa('inexistente'), grupoCbm);
    });
  });

  test('nomes de mapa são únicos', () {
    final nomes = mapasConfig.map((m) => m.nome).toList();
    expect(nomes.toSet().length, nomes.length);
  });

  test('rótulo tem fallback para nome desconhecido', () {
    expect(rotuloDoMapa('C1'), 'Mapa do trecho C1');
    expect(rotuloDoMapa('inexistente'), 'Mapa (inexistente)');
  });
}
