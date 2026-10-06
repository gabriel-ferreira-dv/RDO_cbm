import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import 'atualizacao_dados_service.dart';

// Versão do app publicada no Supabase (ver supabase/versao_app.sql).
class VersaoPublicada {
  // O número depois do "+" no pubspec: é ele que decide a atualização.
  final int codigo;
  final String nome;

  // Nome do APK no bucket "dados".
  final String arquivo;

  // Quem tiver código menor que este é obrigado a atualizar.
  final int minima;
  final String novidades;

  const VersaoPublicada({
    required this.codigo,
    required this.nome,
    required this.arquivo,
    required this.minima,
    required this.novidades,
  });

  factory VersaoPublicada.fromMap(Map<String, dynamic> m) => VersaoPublicada(
        codigo: (m['versao_codigo'] as num).toInt(),
        nome: (m['versao_nome'] as String?) ?? '',
        arquivo: m['arquivo'] as String,
        minima: (m['versao_minima'] as num?)?.toInt() ?? 0,
        novidades: (m['novidades'] as String?) ?? '',
      );

  // "1.0.1", ou o código se o nome estiver em branco.
  String get rotulo => nome.trim().isEmpty ? '$codigo' : nome.trim();
}

// Uma versão publicada que este aparelho ainda não tem.
class AtualizacaoDisponivel {
  final VersaoPublicada versao;
  final bool obrigatoria;

  const AtualizacaoDisponivel(this.versao, {required this.obrigatoria});
}

// Compara instalado com publicado; null se está em dia. Quem já tem a versão
// publicada nunca é obrigado, mesmo com a mínima digitada acima dela.
AtualizacaoDisponivel? compararVersoes(int instalado, VersaoPublicada publicada) {
  if (instalado >= publicada.codigo) return null;
  return AtualizacaoDisponivel(publicada,
      obrigatoria: instalado < publicada.minima);
}

// Atualização do app pelo Supabase. Só Android (no iPhone, só App Store/TestFlight).
class AtualizacaoAppService {
  AtualizacaoAppService._interno();
  static final AtualizacaoAppService instancia = AtualizacaoAppService._interno();

  static const String tabela = 'versao_app';
  static const String _tipoApk = 'application/vnd.android.package-archive';

  // Versão instalada no formato do pubspec ("1.0.0+2"), para mostrar.
  Future<String> versaoInstalada() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  // Atualização pendente; null se em dia, sem rede ou fora do Android.
  Future<AtualizacaoDisponivel?> verificar() async {
    if (!Platform.isAndroid) return null;
    try {
      final linha = await Supabase.instance.client
          .from(tabela)
          .select()
          .eq('plataforma', 'android')
          .maybeSingle();
      if (linha == null) return null;
      final info = await PackageInfo.fromPlatform();
      final instalado = int.tryParse(info.buildNumber) ?? 0;
      return compararVersoes(instalado, VersaoPublicada.fromMap(linha));
    } catch (e) {
      debugPrint('Verificação de versão do app falhou: $e');
      return null;
    }
  }

  // Baixa o APK e abre o instalador. null = abriu; senão, o erro.
  Future<String?> baixarEInstalar(
    VersaoPublicada versao, {
    void Function(double progresso)? aoProgredir,
  }) async {
    try {
      // Cache do app: dispensa permissão de armazenamento. Apaga APKs antigos.
      final cache = await getTemporaryDirectory();
      for (final antigo in cache.listSync().whereType<File>()) {
        if (antigo.path.endsWith('.apk')) antigo.deleteSync();
      }
      final apk = File('${cache.path}/rdo-cbm-${versao.codigo}.apk');
      await AtualizacaoDadosService.instancia.baixarParaArquivo(
        '$supabaseUrl/storage/v1/object/public/dados/${versao.arquivo}',
        apk,
        aoProgredir: aoProgredir,
      );

      final resultado = await OpenFilex.open(apk.path, type: _tipoApk);
      if (resultado.type != ResultType.done) {
        debugPrint('Instalador não abriu: ${resultado.message}');
        return 'Não foi possível abrir o instalador: ${resultado.message}';
      }
      return null;
    } catch (e) {
      debugPrint('Download da atualização do app falhou: $e');
      // 404 = "arquivo" não bate com o nome do APK no bucket.
      if (e is HttpException && e.message.contains('HTTP 404')) {
        return 'Atualização não encontrada no servidor — confira a coluna '
            '"arquivo" em versao_app';
      }
      return 'Falha ao baixar a atualização — verifique a conexão e tente de novo';
    }
  }
}
