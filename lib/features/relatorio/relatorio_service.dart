import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../../core/database/db_helper.dart';
import '../../core/utils/date_formatter.dart';
import '../registro/models/grupo_atividade.dart';
import '../registro/vias_estaqueamento.dart' show faixaDeKm;
import '../registro/registro_service.dart';
import '../paralisacao/models/paralisacao.dart';
import '../paralisacao/paralisacao_service.dart';
import 'foto_no_pdf.dart';
import 'mapa_do_relatorio.dart';
import 'texto_pdf.dart';
import 'turno_noturno.dart';
import 'models/relatorio_diario_info.dart';

// RDO do dia em PDF, com as fotos agrupadas como no Histórico.
class RelatorioService {
  RelatorioService._interno();
  static final RelatorioService instancia = RelatorioService._interno();

  // Fotos do dia de trabalho, agrupadas por atividade. No turno da noite o dia
  // vai até o meio-dia seguinte (ver diaDoTurno).
  Future<List<GrupoAtividade>> buscarGruposDoDia(int usuarioId, DateTime dia,
      {bool noturno = false}) async {
    final todasFotos = await RegistroService.instancia.listarFotosComContexto(usuarioId);
    final alvo = DateTime(dia.year, dia.month, dia.day);
    final fotosDoDia = todasFotos.where((f) {
      final local = DateTime.tryParse(f.fotoCriadoEm)?.toLocal();
      return local != null && diaDoTurno(local, noturno: noturno) == alvo;
    }).toList();
    final grupos = agruparPorAtividade(fotosDoDia);
    // A lista vem do mais recente; o relatório segue a ordem do dia.
    for (final grupo in grupos) {
      grupo.registros.sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
      for (final registro in grupo.registros) {
        registro.fotos.sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
      }
    }
    return grupos;
  }

  // Centro das fotos do dia: onde buscar o tempo. Null sem foto com GPS.
  Future<({double latitude, double longitude})?> posicaoDoDia(
      int usuarioId, DateTime dia,
      {bool noturno = false}) async {
    final grupos = await buscarGruposDoDia(usuarioId, dia, noturno: noturno);
    final pontos = [
      for (final g in grupos)
        for (final r in g.registros)
          for (final f in r.fotos)
            if (f.latitude != null && f.longitude != null)
              (f.latitude!, f.longitude!),
    ];
    if (pontos.isEmpty) return null;
    return (
      latitude: pontos.fold(0.0, (s, p) => s + p.$1) / pontos.length,
      longitude: pontos.fold(0.0, (s, p) => s + p.$2) / pontos.length,
    );
  }

  String _chaveDia(DateTime dia) =>
      '${dia.year.toString().padLeft(4, '0')}-${dia.month.toString().padLeft(2, '0')}-'
      '${dia.day.toString().padLeft(2, '0')}';

  // Infos do RDO já salvas para o dia (pré-preenchem o formulário).
  Future<RelatorioDiarioInfo?> buscarInfoDoDia(int usuarioId, DateTime dia) async {
    final db = await DbHelper.instancia.database;
    final resultado = await db.query(
      'relatorio_diario_info',
      where: 'usuario_id = ? AND data = ?',
      whereArgs: [usuarioId, _chaveDia(dia)],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return RelatorioDiarioInfo.fromMap(resultado.first);
  }

  // Salva ou substitui as infos do dia (UNIQUE usuario_id + data).
  Future<void> salvarInfoDoDia(RelatorioDiarioInfo info) async {
    final db = await DbHelper.instancia.database;
    await db.insert(
      'relatorio_diario_info',
      info.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // PDF do dia, ou null se não há fotos nem paralisação. Monta num isolate:
  // processar as fotos na thread principal congelava a tela.
  Future<Uint8List?> gerarRelatorioDoDia({
    required int usuarioId,
    required DateTime dia,
    required String nomeUsuario,
    RelatorioDiarioInfo? info,
    bool noturno = false,
  }) async {
    // Banco e assets só existem no isolate principal: busca tudo aqui.
    final grupos = await buscarGruposDoDia(usuarioId, dia, noturno: noturno);
    final paradas = await ParalisacaoService.instancia
        .listarDoDia(usuarioId, dia, noturno: noturno);
    // Dia só de chuva: sem foto de serviço, mas com paralisação, sai assim mesmo.
    if (grupos.isEmpty && paradas.isEmpty) return null;
    final paralisacoes = [
      for (final p in paradas)
        _ParalisacaoNoPdf(
          linha: textoParaPdf(p.descricao),
          legenda: textoParaPdf('Paralisação - ${p.motivo}'),
          fotos: [
            for (final f in await ParalisacaoService.instancia.fotosDe(p.id!))
              (caminho: f.caminhoArquivo, criadoEm: f.criadoEm),
          ],
        ),
    ];
    final parado = tempoParado([for (final p in paradas) (inicio: p.inicio, fim: p.fim)]);
    // Onde o serviço do dia foi feito. Sem estaca com coordenada, fica sem mapa.
    final mapa = await montarMapaDasAtividades([
      for (final g in grupos)
        for (final r in g.registros)
          (
            trecho: g.trecho,
            estacaInicial: r.estacaInicial,
            estacaFinal: r.estacaFinal,
            servico: g.servicoNotavel,
          ),
    ]);

    final dataFormatada = '${dia.day.toString().padLeft(2, '0')}/'
        '${dia.month.toString().padLeft(2, '0')}/${dia.year}';
    final logoBytes = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();

    return compute(
      _montarPdfEmIsolate,
      _ParametrosPdf(
        grupos: grupos,
        paralisacoes: paralisacoes,
        tempoParado: parado,
        mapa: mapa,
        info: info,
        nomeUsuario: nomeUsuario,
        dataFormatada: dataFormatada,
        logoBytes: logoBytes,
      ),
    );
  }

  // Roda no isolate (via _montarPdfEmIsolate), nunca na thread principal.
  Future<Uint8List> _montarPdf(_ParametrosPdf p) async {
    final grupos = p.grupos;
    final info = p.info;
    final nomeUsuario = textoParaPdf(p.nomeUsuario);
    final dataFormatada = p.dataFormatada;

    final doc = pw.Document();
    final logo = pw.MemoryImage(p.logoBytes);

    // Margem mínima que as impressoras ainda aceitam.
    const margemPagina = pw.EdgeInsets.all(12);
    final larguraConteudo = PdfPageFormat.a4.width - margemPagina.left - margemPagina.right;

    // 2 fotos por linha; 1pt de folga para o Wrap não quebrar a 2ª coluna.
    const espacamentoColunas = 12.0;
    final larguraFoto = (larguraConteudo - espacamentoColunas) / 2 - 1;

    // Numeração contínua no relatório inteiro.
    var numeroFoto = 0;

    // null quando não há o que mostrar, para não sobrar bloco vazio.
    final blocoInfo = _construirBlocoInfo(info);
    final resumoAtividades = _construirAtividadesResumo(grupos);
    final resumoParalisacoes = _construirParalisacoes(p.paralisacoes, p.tempoParado);
    final fotosParalisacao = [
      for (final parada in p.paralisacoes)
        for (final foto in parada.fotos) (foto: foto, legenda: parada.legenda),
    ];

    // Um MultiPage só: os grupos seguem em sequência, sem página por grupo.
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: margemPagina,
        maxPages: 1000,
        header: (context) => context.pageNumber == 1
            ? pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 14),
                child: _construirCabecalho(logo, nomeUsuario, dataFormatada),
              )
            : pw.SizedBox(),
        build: (context) => [
          if (blocoInfo != null) ...[blocoInfo, pw.SizedBox(height: 14)],
          if (resumoAtividades != null) ...[resumoAtividades, pw.SizedBox(height: 20)],
          if (resumoParalisacoes != null) ...[resumoParalisacoes, pw.SizedBox(height: 20)],
          if (p.mapa != null) ...[
            mapaNoPdf(p.mapa!,
                titulo: _construirBarraTitulo('Mapa das atividades'),
                largura: larguraConteudo),
            pw.SizedBox(height: 20),
          ],
          for (final grupo in grupos) ...[
            _construirCabecalhoGrupo(grupo),
            // Todas as fotos do grupo juntas, 2 por linha.
            pw.Wrap(
              spacing: espacamentoColunas,
              runSpacing: 10,
              children: [
                for (final registro in grupo.registros)
                  for (final foto in registro.fotos)
                    _construirFoto(foto, registro, ++numeroFoto, larguraFoto),
              ],
            ),
            pw.SizedBox(height: 20),
          ],
          if (fotosParalisacao.isNotEmpty) ...[
            _construirBarraTitulo('Fotos das paralisações'),
            pw.SizedBox(height: 8),
            // Solto no MultiPage, como as outras: o Wrap quebra página.
            pw.Wrap(
              spacing: espacamentoColunas,
              runSpacing: 10,
              children: [
                for (final f in fotosParalisacao)
                  _fotoComLegenda(f.foto.caminho, f.foto.criadoEm, f.legenda,
                      ++numeroFoto, larguraFoto),
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  // Infos do RDO preenchidas no formulário; null se nada foi preenchido.
  pw.Widget? _construirBlocoInfo(RelatorioDiarioInfo? info) {
    if (info == null) return null;
    // Texto digitado no celular: limpa o que a fonte do PDF não desenha.
    final linhasEquipe = linhasParaPdf(_linhasNaoVazias(info.equipe));
    final linhasMaquinas = linhasParaPdf(_linhasNaoVazias(info.maquinasEquipamentos));
    final encarregado = textoParaPdf(info.encarregado.trim());
    final ddsTema = textoParaPdf(info.ddsTema.trim());
    final horario = info.horarioInicio.trim().isEmpty && info.horarioFim.trim().isEmpty
        ? ''
        : textoParaPdf('${info.horarioInicio} às ${info.horarioFim}');
    final clima = textoParaPdf(info.climaPorPeriodo
        .map((c) => '${c.periodo}: ${c.condicao}')
        .join('   '));

    if (encarregado.isEmpty &&
        linhasEquipe.isEmpty &&
        ddsTema.isEmpty &&
        horario.isEmpty &&
        clima.isEmpty &&
        linhasMaquinas.isEmpty) {
      return null;
    }

    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (encarregado.isNotEmpty || horario.isNotEmpty)
            pw.Row(
              children: [
                if (encarregado.isNotEmpty)
                  pw.Expanded(
                    child: pw.Text('Encarregado: $encarregado', style:  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ),
                if (horario.isNotEmpty)
                  pw.Text('Horário: $horario', style:  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          // Equipe e Máquinas lado a lado.
          if (linhasEquipe.isNotEmpty || linhasMaquinas.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (linhasEquipe.isNotEmpty)
                  pw.Expanded(child: _construirColunaLista('Equipe', linhasEquipe)),
                if (linhasEquipe.isNotEmpty && linhasMaquinas.isNotEmpty) pw.SizedBox(width: 16),
                if (linhasMaquinas.isNotEmpty)
                  pw.Expanded(child: _construirColunaLista('Máquinas', linhasMaquinas)),
              ],
            ),
          ],
          if (clima.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Condições climáticas: $clima',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
          if (ddsTema.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('DDS/Ordem Unida - Tema: $ddsTema', style:  pw.TextStyle(fontSize: 11,fontWeight: pw.FontWeight.bold))
          ],
        ],
      ),
    );
  }

  // Lista "Atividades", montada dos registros; null se não há grupos.
  pw.Widget? _construirAtividadesResumo(List<GrupoAtividade> grupos) {
    final itens = <String>[];
    // Junta só registros com todos os campos do texto iguais.
    final chavesVistas = <String>{};
    for (final grupo in grupos) {
      for (final registro in grupo.registros) {
        final estaca = registro.estacaInicial == registro.estacaFinal
            ? registro.estacaInicial
            : '${registro.estacaInicial} a ${registro.estacaFinal}';
        final via = registro.via.trim();
        final passo = grupo.servicoNotavelDetalhe.trim();
        final medicao =
            registro.quantidade != null && registro.unidade.isNotEmpty
                ? '${formatarQuantidade(registro.quantidade!)} ${registro.unidade}'
                : '';
        final chave = '${grupo.km}|${grupo.kmFinal}|${grupo.atividade}'
            '|${grupo.servicoNotavel}'
            '|$passo|$via|$estaca|$medicao'
            '|${registro.emNomeDeNome}|${registro.registradoPorNome}';
        if (!chavesVistas.add(chave)) continue;
        // Marca o que foi lançado pela supervisão.
        final emNome = registro.emNomeDeNome.trim();
        final porOutro = registro.registradoPorNome.trim();
        final autoria = emNome.isNotEmpty
            ? ' (em nome de $emNome)'
            : porOutro.isNotEmpty
                ? ' (lançado por $porOutro)'
                : '';
        var item = '${grupo.servicoNotavel}'
            '${passo.isNotEmpty ? ' ($passo)' : ''}'
            ', KM ${faixaDeKm(grupo.km, grupo.kmFinal)}'
            '${estaca.isNotEmpty ? ', estaca $estaca' : ''}'
            '${via.isNotEmpty ? ', via $via' : ''}'
            // Hífen, não travessão: a fonte do PDF só tem Latin-1.
            '${medicao.isNotEmpty ? ' - $medicao' : ''}'
            '$autoria.';
        itens.add(textoParaPdf(item));
      }
    }
    if (itens.isEmpty) return null;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _construirBarraTitulo('Atividades'),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final item in itens) pw.Text('-  $item', style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  // Lista "Paralisações" com o total parado; null se não houve.
  pw.Widget? _construirParalisacoes(List<_ParalisacaoNoPdf> paradas, Duration total) {
    if (paradas.isEmpty) return null;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _construirBarraTitulo('Paralisações'),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final p in paradas)
                pw.Text('-  ${p.linha}', style: const pw.TextStyle(fontSize: 11)),
              if (total > Duration.zero) ...[
                pw.SizedBox(height: 4),
                pw.Text('Total parado: ${formatarDuracao(total)}',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Linhas não vazias de um campo multi-linha.
  List<String> _linhasNaoVazias(String texto) =>
      texto.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  // Coluna de título + itens (Equipe e Máquinas).
  pw.Widget _construirColunaLista(String titulo, List<String> itens) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(titulo, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        for (final item in itens) pw.Text('-  $item', style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  // Título e dados do grupo num widget só, para não quebrar página no meio.
  pw.Widget _construirCabecalhoGrupo(GrupoAtividade grupo) {
    final vias = grupo.registros.map((r) => r.via.trim()).where((v) => v.isNotEmpty).toSet();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _construirBarraTitulo('${grupo.atividade} - ${grupo.trecho} / '
            'KM ${faixaDeKm(grupo.km, grupo.kmFinal)}'),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Serviço: ${grupo.servicoNotavel}', style: const pw.TextStyle(fontSize: 11)),
              if (grupo.servicoNotavelDetalhe.trim().isNotEmpty)
                pw.Text('Passo: ${grupo.servicoNotavelDetalhe}',
                    style: const pw.TextStyle(fontSize: 11)),
              if (vias.isNotEmpty)
                pw.Text('Via: ${vias.join(", ")}', style: const pw.TextStyle(fontSize: 11)),
              if (grupo.quantidadeTotal != null)
                pw.Text(
                  'Quantidade medida: '
                  '${formatarQuantidade(grupo.quantidadeTotal!.total)} '
                  '${grupo.quantidadeTotal!.unidade}',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Cabeçalho da 1ª página. O logo é branco, por isso o fundo preto.
  pw.Widget _construirCabecalho(pw.MemoryImage logo, String nomeUsuario, String dataFormatada) {
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Row(
              children: [
                pw.Container(
                  color: PdfColors.black,
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Image(logo, height: 30),
                ),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text('Relatório de Atividades',
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  ),
                ),
                // Espaço do tamanho do logo, para centralizar o título.
                pw.SizedBox(width: 54),
              ],
            ),
          ),
          pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.black))),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(right: pw.BorderSide(color: PdfColors.black)),
                    ),
                    child: pw.Text('Usuário: $nomeUsuario', style: const pw.TextStyle(fontSize: 11)),
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: pw.Text('Data: $dataFormatada',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Barra preta com título branco (nome de cada grupo).
  pw.Widget _construirBarraTitulo(String texto) {
    return pw.Container(
      color: PdfColors.black,
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Text(
        texto,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  // Foto com legenda: número, descrição e estaca.
  pw.Widget _construirFoto(FotoAgrupada foto, RegistroAgrupado registro, int numero, double largura) {
    final descricao = registro.descricao.trim();
    // Texto livre: limpa antes de desenhar.
    // Área de apoio não tem estaca.
    final estacas = registro.estacaInicial.isEmpty
        ? ''
        : 'Estaca ${registro.estacaInicial} a ${registro.estacaFinal}.';
    final legenda = textoParaPdf([
      if (descricao.isNotEmpty) descricao,
      if (estacas.isNotEmpty) estacas,
    ].join(' - '));
    return _fotoComLegenda(foto.caminhoArquivo, foto.criadoEm, legenda, numero, largura);
  }

  pw.Widget _fotoComLegenda(
      String caminho, String criadoEm, String legenda, int numero, double largura) {
    final bytes = _lerEDownscalear(caminho);
    final hora = formatarHora(criadoEm);

    if (bytes == null) {
      return pw.Container(
        width: largura,
        height: largura * proporcaoPadraoDaFoto,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(border: pw.Border.all()),
        child: pw.Text('Foto indisponível\n$hora',
            style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
      );
    }
    // Caixa na proporção da foto, para não cortar o carimbo (foto_no_pdf.dart).
    final imagem = pw.MemoryImage(bytes);
    return pw.Container(
      width: largura,
      child: pw.Column(
        children: [
          pw.Image(imagem,
              width: largura,
              height: alturaDaFotoNoPdf(imagem, largura),
              fit: pw.BoxFit.contain),
          pw.SizedBox(height: 3),
          pw.RichText(
            textAlign: pw.TextAlign.center,
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 9),
              children: [
                pw.TextSpan(
                  text: 'Foto $numero. ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: legenda, style: pw.TextStyle(fontStyle: pw.FontStyle.italic)),
              ],
            ),
          ),
          pw.Text(hora, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  // Lê e reduz a foto para o PDF não ficar enorme; null se o arquivo sumiu.
  // Síncrono: só roda no isolate.
  Uint8List? _lerEDownscalear(String caminho) {
    final arquivo = File(caminho);
    if (!arquivo.existsSync()) return null;
    try {
      final original = img.decodeImage(arquivo.readAsBytesSync());
      if (original == null) return null;
      final redimensionada = original.width > 1200
          ? img.copyResize(original, width: 1200, interpolation: img.Interpolation.average)
          : original;
      return Uint8List.fromList(img.encodeJpg(redimensionada, quality: 85));
    } catch (_) {
      return null;
    }
  }
}

// Paralisação já em texto de PDF, com as fotos dela.
class _ParalisacaoNoPdf {
  final String linha;
  final String legenda;
  final List<({String caminho, String criadoEm})> fotos;

  const _ParalisacaoNoPdf({
    required this.linha,
    required this.legenda,
    required this.fotos,
  });
}

// Dados puros que o isolate precisa para montar o PDF.
class _ParametrosPdf {
  final List<GrupoAtividade> grupos;
  final List<_ParalisacaoNoPdf> paralisacoes;
  final Duration tempoParado;
  final MapaNoPdf? mapa;
  final RelatorioDiarioInfo? info;
  final String nomeUsuario;
  final String dataFormatada;
  final Uint8List logoBytes;

  _ParametrosPdf({
    required this.grupos,
    this.paralisacoes = const [],
    this.tempoParado = Duration.zero,
    this.mapa,
    required this.info,
    required this.nomeUsuario,
    required this.dataFormatada,
    required this.logoBytes,
  });
}

// Entrada do compute (precisa ser função de nível superior).
Future<Uint8List> _montarPdfEmIsolate(_ParametrosPdf parametros) =>
    RelatorioService.instancia._montarPdf(parametros);
