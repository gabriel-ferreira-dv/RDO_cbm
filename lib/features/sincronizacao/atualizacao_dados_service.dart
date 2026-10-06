import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/dados_remotos.dart';
import '../../core/supabase_config.dart';
import '../mapa/mapas_config.dart';
import '../mapa/permissao_mapas_service.dart';
import '../mapa/navegacao_estacas_service.dart';
import '../notificacoes/avisos_service.dart';
import '../registro/sugestao_gps_service.dart';

// Resultado da checagem de versões no boot.
class ResultadoVerificacao {
  final List<String> csvsAtualizados;

  // Mapas para baixar (o usuário confirma, porque são grandes).
  final List<String> overlaysNovos;
  final String? erro;

  const ResultadoVerificacao({
    required this.csvsAtualizados,
    this.overlaysNovos = const [],
    this.erro,
  });
}

// Versão do mapa no aparelho. Sem a pasta baixada é 0 (o APK não traz
// mapas), para até a versão 1 do servidor ser oferecida.
int versaoInstaladaDoMapa({required bool baixado, int? salva}) =>
    baixado ? (salva ?? 1) : 0;

// Compara versoes_dados do Supabase com as versões do aparelho e baixa do
// bucket "dados" o que mudou. CSVs baixam sozinhos; mapas, com confirmação.
class AtualizacaoDadosService {
  AtualizacaoDadosService._interno();
  static final AtualizacaoDadosService instancia = AtualizacaoDadosService._interno();

  static const _prefixoVersao = 'versao_dados_';

  String _urlPublica(String arquivo) =>
      '$supabaseUrl/storage/v1/object/public/dados/$arquivo';

  Future<ResultadoVerificacao> verificarEAtualizarCsvs() async {
    try {
      final destinoBase = dirDadosRemotos;
      if (destinoBase == null) {
        return const ResultadoVerificacao(
            csvsAtualizados: [], erro: 'Pasta de dados não inicializada');
      }

      final linhas = await Supabase.instance.client.from('versoes_dados').select();
      final prefs = await SharedPreferences.getInstance();
      final atualizados = <String>[];
      final overlaysNovos = <String>[];

      for (final linha in linhas) {
        final nome = linha['nome'] as String;
        final versao = linha['versao'] as int;
        final arquivo = linha['arquivo'] as String;
        final salva = prefs.getInt('$_prefixoVersao$nome');
        final instalada = ehNomeDeMapa(nome)
            ? versaoInstaladaDoMapa(baixado: mapaBaixado(nome), salva: salva)
            // CSV: a versão 1 vem no APK.
            : salva ?? 1;
        if (versao <= instalada) continue;

        // Mapa não baixa sozinho: o usuário confirma.
        if (ehNomeDeMapa(nome)) {
          // Só oferece mapa dos grupos do usuário.
          if (PermissaoMapasService.instancia.podeVerMapa(nome)) {
            overlaysNovos.add(nome);
          }
          continue;
        }

        await baixarParaArquivo(_urlPublica(arquivo), File('${destinoBase.path}/$nome'));
        await prefs.setInt('$_prefixoVersao$nome', versao);
        atualizados.add(nome);
      }

      if (atualizados.isNotEmpty) {
        // Limpa os caches que guardam o CSV antigo.
        SugestaoGpsService.instancia.limparCache();
        NavegacaoEstacasService.instancia.limparCache();
        // Histórico da tela de Atualizações.
        await AvisosService.instancia.registrar(
          'Dados do projeto atualizados',
          'Arquivos baixados: ${atualizados.join(', ')}.',
        );
      }

      return ResultadoVerificacao(
        csvsAtualizados: atualizados,
        overlaysNovos: overlaysNovos,
      );
    } catch (e) {
      debugPrint('Verificação de atualizações falhou: $e');
      return const ResultadoVerificacao(
          csvsAtualizados: [], erro: 'Sem conexão ou servidor indisponível');
    }
  }

  // Baixa e instala o mapa [nome]. null = sucesso; senão, o erro.
  // [aoProgredir] vai de 0 a 1 durante o download.
  Future<String?> baixarOverlay({
    required String nome,
    void Function(double progresso)? aoProgredir,
  }) async {
    try {
      final destinoBase = dirDadosRemotos;
      if (destinoBase == null) return 'Pasta de dados não inicializada';

      final linha = await Supabase.instance.client
          .from('versoes_dados')
          .select()
          .eq('nome', nome)
          .single();
      final versao = linha['versao'] as int;
      final arquivo = linha['arquivo'] as String;

      // 1) Baixa direto para o disco (não cabe na memória).
      final zip = File('${destinoBase.path}/${nome}_download.zip');
      await baixarParaArquivo(_urlPublica(arquivo), zip, aoProgredir: aoProgredir);

      // 2) Extrai num isolate (é CPU-pesado) para uma pasta temporária.
      final pastaTemporaria = Directory('${destinoBase.path}/${nome}_novo');
      if (pastaTemporaria.existsSync()) pastaTemporaria.deleteSync(recursive: true);
      await compute(_extrairZip, {'zip': zip.path, 'destino': pastaTemporaria.path});
      zip.deleteSync();

      // 3) O mapa antigo só sai com o novo completo.
      final origem = _pastaComTiles(pastaTemporaria);

      // Poucos tiles = extração incompleta: falha em vez de instalar pela metade.
      final tiles = origem
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.webp'))
          .length;
      if (tiles < 10) {
        throw FormatException(
            'Extração incompleta: só $tiles tile(s) foram gravados');
      }

      final destino = Directory('${destinoBase.path}/$nome');
      if (destino.existsSync()) destino.deleteSync(recursive: true);
      origem.renameSync(destino.path);
      if (pastaTemporaria.existsSync()) pastaTemporaria.deleteSync(recursive: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_prefixoVersao$nome', versao);
      // Histórico da tela de Atualizações.
      await AvisosService.instancia.registrar(
        '${rotuloDoMapa(nome)} atualizado',
        'A nova versão do desenho foi baixada e instalada.',
      );
      return null;
    } catch (e) {
      debugPrint('Download do overlay "$nome" falhou: $e');
      // 404 = "arquivo" em versoes_dados não bate com o bucket (falta o .zip?).
      if (e is HttpException && e.message.contains('HTTP 404')) {
        return 'Arquivo do mapa não encontrado no servidor — confira a coluna '
            '"arquivo" em versoes_dados';
      }
      return 'Falha ao baixar o mapa — verifique a conexão e tente de novo';
    }
  }

  // Pasta com os tiles: a raiz do zip ou a única pasta dentro dele.
  Directory _pastaComTiles(Directory extraida) {
    final temTileNaRaiz = extraida.listSync().any((e) =>
        e is File &&
        (e.path.toLowerCase().endsWith('.webp') ||
            e.path.toLowerCase().endsWith('.png')));
    if (temTileNaRaiz) return extraida;

    final subpastas = extraida.listSync().whereType<Directory>().toList();
    if (subpastas.length == 1) return subpastas.first;
    throw const FormatException('overlay.zip sem tiles na raiz nem pasta única');
  }

  // Baixa [url] para [destino] direto no disco (também usado pelo APK).
  Future<void> baixarParaArquivo(
    String url,
    File destino, {
    void Function(double progresso)? aoProgredir,
  }) async {
    final cliente = HttpClient();
    try {
      final requisicao = await cliente.getUrl(Uri.parse(url));
      final resposta = await requisicao.close();
      if (resposta.statusCode != 200) {
        throw HttpException('HTTP ${resposta.statusCode} em $url');
      }

      // .tmp renomeado no fim: queda de rede não deixa arquivo pela metade.
      final temporario = File('${destino.path}.tmp');
      final total = resposta.contentLength;
      var recebido = 0;
      final escrita = temporario.openWrite();
      try {
        await for (final pedaco in resposta) {
          escrita.add(pedaco);
          recebido += pedaco.length;
          if (aoProgredir != null && total > 0) aoProgredir(recebido / total);
        }
      } finally {
        await escrita.close();
      }
      if (destino.existsSync()) destino.deleteSync();
      temporario.renameSync(destino.path);
    } finally {
      cliente.close();
    }
  }
}

// Entrada do compute. O `await` é essencial: sem ele o isolate morria no
// meio da extração.
Future<void> _extrairZip(Map<String, String> args) async {
  await extractFileToDisk(args['zip']!, args['destino']!);
}
