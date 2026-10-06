import 'package:flutter/material.dart';
import '../../../../core/dados_remotos.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../mapa/mapas_config.dart';
import '../../../sincronizacao/atualizacao_app_service.dart';
import '../../../sincronizacao/atualizacao_dados_service.dart';
import '../../../sincronizacao/presentation/widgets/atualizacao_app_dialogo.dart';
import '../../../sincronizacao/presentation/widgets/estado_do_envio.dart';
import '../../avisos_service.dart';

// Atualizações: o envio para o servidor, novidades, mapas e o histórico.
class AtualizacoesPage extends StatefulWidget {
  const AtualizacoesPage({super.key});

  @override
  State<AtualizacoesPage> createState() => _AtualizacoesPageState();
}

class _AtualizacoesPageState extends State<AtualizacoesPage> {
  late Future<List<Aviso>> _avisosFuture;
  List<String> _mapasDisponiveis = [];
  AtualizacaoDisponivel? _atualizacaoApp;
  // Mostrada no rodapé, para o suporte.
  String? _versaoInstalada;
  bool _buscando = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _avisosFuture = AvisosService.instancia.listar();
    // Busca automática ao abrir a tela — o botão fica para re-verificar.
    _buscar();
  }

  Future<void> _buscar() async {
    setState(() {
      _buscando = true;
      _status = null;
    });
    final resultado =
        await AtualizacaoDadosService.instancia.verificarEAtualizarCsvs();
    final atualizacaoApp = await AtualizacaoAppService.instancia.verificar();
    final versaoInstalada =
        await AtualizacaoAppService.instancia.versaoInstalada();
    if (!mounted) return;
    setState(() {
      _buscando = false;
      _mapasDisponiveis = List.of(resultado.overlaysNovos);
      _atualizacaoApp = atualizacaoApp;
      _versaoInstalada = versaoInstalada;
      if (resultado.erro != null) {
        _status = resultado.erro;
      } else if (resultado.csvsAtualizados.isNotEmpty) {
        _status =
            'Dados atualizados: ${resultado.csvsAtualizados.join(', ')}';
      } else if (resultado.overlaysNovos.isEmpty && atualizacaoApp == null) {
        _status = 'Tudo atualizado — nada novo no servidor';
      } else {
        _status = 'Há atualização disponível para baixar';
      }
      _avisosFuture = AvisosService.instancia.listar();
    });
  }

  Future<void> _baixarMapa(String nome) async {
    final rotulo = rotuloDoMapa(nome);
    final progresso = ValueNotifier<double>(0);
    // Diálogo de progresso não-fechável enquanto baixa/instala.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Baixando $rotulo…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progresso,
          builder: (context, valor, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: valor > 0 ? valor : null),
              const SizedBox(height: 12),
              Text(valor >= 1
                  ? 'Instalando…'
                  : '${(valor * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );

    final erro = await AtualizacaoDadosService.instancia
        .baixarOverlay(nome: nome, aoProgredir: (p) => progresso.value = p);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() {
      if (erro == null) _mapasDisponiveis.remove(nome);
      _avisosFuture = AvisosService.instancia.listar();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        erro ?? '$rotulo atualizado! Feche e abra o app para aplicar.',
      ),
    ));
  }

  IconData _iconePara(Aviso aviso) =>
      aviso.titulo.toLowerCase().contains('mapa')
          ? Icons.map_outlined
          : Icons.table_chart_outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Atualizações')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── Buscar ────────────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _status ?? 'Verifique se há mapas e dados novos no servidor',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _buscando ? null : _buscar,
                    icon: _buscando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Buscar'),
                  ),
                ],
              ),
            ),
          ),

          // ── Envio para o servidor (o que falta subir e por quê) ──────────
          const EstadoDoEnvioCard(),

          // ── Versão nova do app ────────────────────────────────────────────
          if (_atualizacaoApp != null)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.system_update,
                        color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nova versão do app: '
                            '${_atualizacaoApp!.versao.rotulo}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          if (_versaoInstalada != null)
                            Text(
                              'Instalada: $_versaoInstalada',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          oferecerAtualizacaoDoApp(context, _atualizacaoApp!),
                      child: const Text('Atualizar'),
                    ),
                  ],
                ),
              ),
            ),

          // ── Mapas disponíveis para baixar ─────────────────────────────────
          for (final nome in _mapasDisponiveis)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.map_outlined,
                        color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rotuloDoMapa(nome)} — '
                            '${mapaBaixado(nome) ? 'nova versão' : 'ainda não baixado'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            'Download grande use Wi-Fi',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _baixarMapa(nome),
                      child: const Text('Baixar'),
                    ),
                  ],
                ),
              ),
            ),

          // ── Histórico ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              'Histórico de atualizações',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          FutureBuilder<List<Aviso>>(
            future: _avisosFuture,
            builder: (context, snapshot) {
              final avisos = snapshot.data ?? [];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (avisos.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Nenhuma atualização recebida ainda',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final aviso in avisos)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _iconePara(aviso),
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          aviso.titulo,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(aviso.corpo),
                            const SizedBox(height: 2),
                            Text(
                              formatarDataHora(aviso.criadoEm),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_versaoInstalada != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Text(
                  'Versão do app: $_versaoInstalada',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
