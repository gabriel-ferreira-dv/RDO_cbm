import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../auth/auth_service.dart';
import '../../../auth/models/usuario.dart';
import '../../models/relatorio_diario_info.dart';
import '../../relatorio_service.dart';
import '../../turno_noturno.dart';

// Pré-visualização do relatório em PDF, com botões nativos de imprimir,
// compartilhar e salvar fornecidos pelo próprio PdfPreview.
class RelatorioPdfPreviewPage extends StatelessWidget {
  final Usuario usuario;
  final DateTime dia;
  final RelatorioDiarioInfo? info;

  const RelatorioPdfPreviewPage({super.key, required this.usuario, required this.dia, this.info});

  @override
  Widget build(BuildContext context) {
    final dataFormatada = '${dia.day.toString().padLeft(2, '0')}/'
        '${dia.month.toString().padLeft(2, '0')}/${dia.year}';
    return Scaffold(
      appBar: AppBar(title: Text('Relatório — $dataFormatada')),
      body: PdfPreview(
        build: (format) async {
          final bytes = await RelatorioService.instancia.gerarRelatorioDoDia(
            usuarioId: usuario.id!,
            dia: dia,
            nomeUsuario: usuario.nome,
            info: info,
            noturno: TurnoNoturnoService.instancia.ehNoturno(
                AuthService.instancia.usuarioLogado?.matricula ??
                    usuario.matricula),
          );
          // Não deveria ocorrer: RelatorioPage já garante que há fotos ou
          // paralisação no dia. PDF vazio como fallback defensivo.
          return bytes ?? Uint8List(0);
        },
        allowSharing: true,
        allowPrinting: true,
        canChangePageFormat: false,
        pdfFileName:
            'relatorio_${dia.year}${dia.month.toString().padLeft(2, '0')}${dia.day.toString().padLeft(2, '0')}.pdf',
      ),
    );
  }
}
