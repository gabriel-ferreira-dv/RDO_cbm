import 'package:flutter/material.dart';

import '../../atualizacao_app_service.dart';

// Oferece a atualização do app: aviso com as novidades e, se o usuário
// aceitar, download com progresso e o instalador do Android.
//
// Obrigatória: sem "Depois" e sem fechar pelo voltar. Se o usuário cancelar o
// instalador ou o download falhar, o aviso volta; só some quando a versão nova
// é instalada, porque o Android fecha o app nessa hora.
Future<void> oferecerAtualizacaoDoApp(
  BuildContext context,
  AtualizacaoDisponivel atualizacao,
) async {
  final versao = atualizacao.versao;
  while (context.mounted) {
    final aceitou = await showDialog<bool>(
      context: context,
      barrierDismissible: !atualizacao.obrigatoria,
      builder: (context) => PopScope(
        canPop: !atualizacao.obrigatoria,
        child: AlertDialog(
          icon: const Icon(Icons.system_update),
          title: const Text('Nova versão do app'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A versão ${versao.rotulo} do RDO cbm está disponível.'),
              if (versao.novidades.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(versao.novidades.trim()),
              ],
              const SizedBox(height: 12),
              Text(
                atualizacao.obrigatoria
                    ? 'Esta atualização é obrigatória para continuar usando o '
                        'app. Seus registros e fotos continuam no celular.'
                    : 'Seus registros e fotos continuam no celular.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            if (!atualizacao.obrigatoria)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Depois'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
    if (aceitou != true || !context.mounted) return;

    final erro = await _baixarComProgresso(context, versao);
    if (!context.mounted) return;
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
    }
    if (!atualizacao.obrigatoria) return;
  }
}

Future<String?> _baixarComProgresso(
  BuildContext context,
  VersaoPublicada versao,
) async {
  final progresso = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Baixando atualização…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progresso,
          builder: (context, valor, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: valor > 0 ? valor : null),
              const SizedBox(height: 12),
              Text('${(valor * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    ),
  );

  final erro = await AtualizacaoAppService.instancia
      .baixarEInstalar(versao, aoProgredir: (p) => progresso.value = p);
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progresso.dispose();
  return erro;
}
