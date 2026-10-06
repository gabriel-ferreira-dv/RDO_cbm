import 'package:flutter/material.dart';

import '../../sincronizacao_service.dart';

// O que está esperando para subir, quando foi o último envio e o último
// erro. Serve para descobrir, no próprio celular, por que uma foto não chegou.
class EstadoDoEnvioCard extends StatefulWidget {
  const EstadoDoEnvioCard({super.key});

  @override
  State<EstadoDoEnvioCard> createState() => _EstadoDoEnvioCardState();
}

class _EstadoDoEnvioCardState extends State<EstadoDoEnvioCard> {
  final _servico = SincronizacaoService.instancia;
  String _aparelho = '';

  @override
  void initState() {
    super.initState();
    _servico.idDoAparelho().then((id) {
      if (mounted) setState(() => _aparelho = id);
    });
    // Antes da primeira rodada o estado não tem as contagens.
    if (_servico.estado.value.pendentes == null) _atualizarPendentes();
  }

  Future<void> _atualizarPendentes() async {
    final pendentes = await _servico.contarPendentes();
    if (!mounted) return;
    final atual = _servico.estado.value;
    _servico.estado.value = EstadoDoEnvio(
      enviando: atual.enviando,
      pendentes: pendentes,
      ultimaRodadaCompleta: atual.ultimaRodadaCompleta,
      ultimoErro: atual.ultimoErro,
      quandoErro: atual.quandoErro,
    );
  }

  Future<void> _enviarAgora() async {
    final resultado = await _servico.sincronizar();
    if (!mounted) return;
    final enviados = resultado.registrosEnviados + resultado.fotosEnviadas;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(resultado.erro ??
          (enviados == 0
              ? 'Nada pendente: tudo já está no servidor'
              : 'Enviados: ${resultado.registrosEnviados} registro(s) e '
                  '${resultado.fotosEnviadas} foto(s)')),
    ));
  }

  String _hora(DateTime d) {
    String dois(int n) => n.toString().padLeft(2, '0');
    final hoje = DateTime.now();
    final mesmoDia = d.year == hoje.year && d.month == hoje.month && d.day == hoje.day;
    return mesmoDia
        ? 'hoje às ${dois(d.hour)}:${dois(d.minute)}'
        : '${dois(d.day)}/${dois(d.month)} às ${dois(d.hour)}:${dois(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<EstadoDoEnvio>(
      valueListenable: _servico.estado,
      builder: (context, estado, _) {
        final p = estado.pendentes;
        final total = p == null ? 0 : p.registros + p.fotos + p.paralisacoes;
        final comErro = estado.ultimoErro != null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      comErro
                          ? Icons.cloud_off
                          : total == 0
                              ? Icons.cloud_done
                              : Icons.cloud_upload_outlined,
                      color: comErro ? theme.colorScheme.error : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Envio para o servidor',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: estado.enviando ? null : _enviarAgora,
                      icon: estado.enviando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload),
                      label: Text(estado.enviando ? 'Enviando…' : 'Enviar agora'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  p == null
                      ? 'Contando o que falta enviar…'
                      : total == 0
                          ? 'Tudo enviado: nada esperando no aparelho.'
                          : 'Esperando envio: ${p.registros} registro(s), '
                              '${p.fotos} foto(s)'
                              '${p.paralisacoes > 0 ? ', ${p.paralisacoes} paralisação(ões)' : ''}.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (estado.ultimaRodadaCompleta != null)
                  Text('Último envio completo: ${_hora(estado.ultimaRodadaCompleta!)}',
                      style: theme.textTheme.bodySmall),
                if (comErro) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Último erro (${_hora(estado.quandoErro!)}): ${estado.ultimoErro}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                if (_aparelho.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  // O suporte acha as linhas deste celular no Supabase por aqui.
                  SelectableText('Aparelho: $_aparelho',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
