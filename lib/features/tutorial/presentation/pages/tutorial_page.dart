import 'package:flutter/material.dart';

// Um passo do fluxo de uso do app.
class _Passo {
  final IconData icone;
  final String titulo;
  final String resumo;
  final List<String> detalhes;

  const _Passo({
    required this.icone,
    required this.titulo,
    required this.resumo,
    required this.detalhes,
  });
}

// Passos na ordem de uso, com os mesmos ícones das telas.
const _passos = [
  _Passo(
    icone: Icons.login,
    titulo: 'Entre no app',
    resumo: 'Login com e-mail e senha, uma vez só.',
    detalhes: [
      'A sessão fica salva: nas próximas vezes o app abre direto.',
      'Sem internet você continua entrando, desde que já tenha entrado '
          'uma vez neste aparelho.',
    ],
  ),
  _Passo(
    icone: Icons.my_location,
    titulo: 'Preencha pela sua localização',
    resumo: 'Um toque traz trecho, KM e estaca.',
    detalhes: [
      'Na aba Registro, toque em "Preencher pela minha localização".',
      'O app acha a estaca do projeto mais perto de você e preenche '
          'trecho, KM e estaca sozinho.',
      'Confira a estaca final e o sentido da via — em pista dupla, a via '
          'define quais estacas aparecem.',
      'Serviço repetido? Use "Importar de uma atividade anterior" e só '
          'ajuste o que mudou.',
    ],
  ),
  _Passo(
    icone: Icons.construction,
    titulo: 'Escolha a atividade e o serviço',
    resumo: 'Atividade, serviço notável e o passo executado.',
    detalhes: [
      'Os campos vêm em cascata: escolher a atividade filtra os serviços, '
          'e o serviço filtra os passos.',
      'Em dúvida sobre qual atividade é qual, toque em "O que é cada '
          'atividade?" — abre o guia com a explicação de todas.',
      'Se mediu o serviço, informe a quantidade e a unidade (m³, m², m…). '
          'É o que soma a produção no relatório. lembrando essa e uma opção de preenchimento, caso não tenha medido, pode deixar em branco.',
    ],
  ),
  _Passo(
    icone: Icons.photo_camera,
    titulo: 'Fotografe a frente de serviço',
    resumo: 'A foto já sai carimbada e georreferenciada.',
    detalhes: [
      'Gire o celular na horizontal antes de fotografar.',
      'A foto sai com data, hora, trecho, KM, estaca, coordenadas e um '
          'minimapa da sua posição — tudo gravado na imagem.',
      'Pode tirar várias fotos do mesmo registro.',
      'Se abrir a imagem na galeria do app que fica no quanto infeiror esquerdo',
      ' da camera, dá para ver a foto com o carimbo e o minimapa, além de poder '
          'compartilhar por WhatsApp ou e-mail.',
    ],
  ),
  _Passo(
    icone: Icons.pause_circle_outline,
    titulo: 'Registre as paralisações',
    resumo: 'Parou por chuva ou falta de material? Dois toques.',
    detalhes: [
      'Na aba Paradas, toque em "Registrar paralisação", escolha o motivo e '
          'salve. O horário de início já vem preenchido.',
      'Enquanto o serviço estiver parado, a aba fica com um ponto vermelho. '
          'Quando voltar, toque em "Retomar serviço": o app fecha o horário '
          'sozinho.',
      'Tire uma foto: ela sai carimbada com data, hora e local — é a prova '
          'de que a parada não foi culpa da obra.',
      'Esqueceu na hora? Na aba Paradas, volte para o dia com as setas e '
          'lance com o horário certo. O formulário do relatório também mostra '
          'as paradas do dia, para conferir antes de gerar.',
    ],
  ),
  _Passo(
    icone: Icons.picture_as_pdf,
    titulo: 'Gere o RDO do dia',
    resumo: 'O relatório sai pronto, com as fotos.',
    detalhes: [
      'Na aba Relatório, escolha o dia e toque em gerar.',
      'O clima de cada período vem sugerido pelo tempo da região. Confira, '
          'ajuste se precisar e marque "Impraticável" quando não deu para '
          'trabalhar — é o que justifica paralisação por chuva.',
      'As paralisações do dia entram no relatório com horário, motivo e '
          'fotos. Em dia só de chuva, o RDO sai mesmo sem foto de serviço.',
      'A equipe pode vir do apontamento do simova (já contada por função) ou ser '
          'preenchida à mão quando estiver sem internet.',
      'No fim, dá para imprimir ou compartilhar por WhatsApp e e-mail.',
    ],
  ),
  _Passo(
    icone: Icons.cloud_done,
    titulo: 'Upload automático',
    resumo: 'Upload automático na nuvem assim que houver rede.',
    detalhes: [
      'Registros e fotos sobem sozinhos assim que houver rede.',
      'Sem sinal na frente de serviço, o app guarda tudo e envia depois.',
      'Trocou de celular? Ao entrar com a mesma conta, seu histórico '
          'recente volta sozinho.',
    ],
  ),
];

// Passos só de supervisor (escondidos para os demais).
const _passosSupervisor = [
  _Passo(
    icone: Icons.group_add,
    titulo: 'Monte a sua equipe',
    resumo: 'Primeira coisa a fazer — sem isso a aba fica vazia.',
    detalhes: [
      'Na aba Equipe, toque em "Equipe" e marque os encarregados que você '
          'supervisiona. A lista vem do apontamento.',
      'A equipe fica salva no servidor: se você trocar de celular, ela '
          'continua lá.',
      'Pode mudar quando quiser — entrou gente nova na frente, é só marcar.',
    ],
  ),
  _Passo(
    icone: Icons.groups,
    titulo: 'Acompanhe o dia da equipe',
    resumo: 'O que cada encarregado produziu, sem pedir a ninguém.',
    detalhes: [
      'Escolha o dia e veja, por encarregado, o efetivo apontado e as '
          'atividades que ele registrou no app.',
      'Encarregado que não apontou nada aparece na lista mesmo assim — '
          '"não registrou" também é informação.',
      'Puxe a tela para baixo para atualizar.',
    ],
  ),
  _Passo(
    icone: Icons.picture_as_pdf,
    titulo: 'Gere o relatório da equipe',
    resumo: 'Todos os encarregados num PDF só.',
    detalhes: [
      'Sai em modo resumo: efetivo, atividades e medição de cada um.',
      'A chave "Incluir fotos" traz também as imagens — o PDF fica bem '
          'maior e demora mais, porque baixa todas as fotos do dia.',
      'Dá para imprimir ou compartilhar como qualquer outro relatório.',
    ],
  ),
  _Passo(
    icone: Icons.map_outlined,
    titulo: 'Veja o avanço no mapa',
    resumo: 'Onde cada serviço já foi feito, e quanto.',
    detalhes: [
      'Na aba Equipe, toque em "Mapa de avanço da equipe".',
      'Cada serviço ganha uma cor, pintada sobre as estacas registradas. A '
          'linha mais forte é dos últimos 7 dias.',
      'Filtre por período, serviço ou encarregado. Toque numa linha para ver '
          'quem registrou, quando e quanto mediu.',
      'Embaixo fica o acumulado por serviço e KM: quantidade medida, '
          'extensão e número de registros. Toque num KM para ir até ele.',
    ],
  ),
  _Passo(
    icone: Icons.assignment_ind_outlined,
    titulo: 'Registre em nome de um encarregado',
    resumo: 'Para quando ele não pôde apontar.',
    detalhes: [
      'Na aba Registro aparece o campo "Registrar em nome de". O padrão é '
          '"Mim mesmo".',
      'Serve para celular quebrado, afastamento ou uma vistoria sua.',
      'O registro entra no nome do encarregado — vale na medição e no RDO '
          'dele —, mas fica marcado como lançado por você.',
      'Atenção: a foto sai com a SUA localização, não com a da frente dele. '
          'Só registre o que você viu.',
    ],
  ),
];

// O que o perfil de supervisor permite e o que não permite.
const _limitesSupervisor = [
  (true, 'Ver os registros e as fotos de quem está na sua equipe'),
  (true, 'Gerar o consolidado do dia de todos de uma vez'),
  (true, 'Lançar um apontamento em nome de alguém da equipe'),
  (false, 'Ver quem não está na sua equipe — o servidor bloqueia, '
      'não é só a tela que esconde'),
  (false, 'Editar ou apagar registro de outra pessoa'),
  (false, 'Lançar sem deixar rastro — todo registro seu guarda seu nome'),
];

// Uma tela simplificada, para a demonstração.
class _Demo {
  final String titulo;
  final String legenda;
  final List<_LinhaDemo> linhas;

  const _Demo({
    required this.titulo,
    required this.legenda,
    required this.linhas,
  });
}

class _LinhaDemo {
  final String rotulo;
  final String valor;
  final bool destaque;

  const _LinhaDemo(this.rotulo, this.valor, {this.destaque = false});
}

// Esquemas das telas (campos e ordem), não cópias fiéis.
const _demos = [
  _Demo(
    titulo: 'Registro · etapa 1',
    legenda: 'Onde o serviço foi executado',
    linhas: [
      _LinhaDemo('Trecho', 'C1', destaque: true),
      _LinhaDemo('KM', '225'),
      _LinhaDemo('Via', 'Via 02 Norte'),
      _LinhaDemo('Estacas', 'EST. 1115 – EST. 1120'),
    ],
  ),
  _Demo(
    titulo: 'Registro · etapa 2',
    legenda: 'O que foi executado',
    linhas: [
      _LinhaDemo('Atividade', 'TERRAPLENAGEM', destaque: true),
      _LinhaDemo('Serviço', 'Compactação de aterro'),
      _LinhaDemo('Passo', 'Compactação (rolo)'),
      _LinhaDemo('Medição', '120,5 m³'),
    ],
  ),
  _Demo(
    titulo: 'Foto carimbada',
    legenda: 'Cada foto vira prova de execução',
    linhas: [
      _LinhaDemo('Carimbo', 'C1 · KM 225 · EST. 1115'),
      _LinhaDemo('Data e hora', '31/07/2026 13:15'),
      _LinhaDemo('Coordenadas', 'Lat -19.8935  Lon -40.4122'),
      _LinhaDemo('Minimapa', 'sua posição sobre o projeto', destaque: true),
    ],
  ),
  _Demo(
    titulo: 'RDO do dia',
    legenda: 'Gerado em segundos',
    linhas: [
      _LinhaDemo('Clima', 'Manhã: Bom · Tarde: Chuvoso'),
      _LinhaDemo('Equipe', '12 do apontamento', destaque: true),
      _LinhaDemo('Atividades', 'lista do dia, com medição'),
      _LinhaDemo('Fotos', 'numeradas e legendadas'),
    ],
  ),
];

// Tela inicial: passo a passo e demonstração das telas.
class TutorialPage extends StatefulWidget {
  final String nomeUsuario;

  // Mostra a seção de supervisor.
  final bool ehSupervisor;

  const TutorialPage({
    super.key,
    required this.nomeUsuario,
    this.ehSupervisor = false,
  });

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final _paginas = PageController();
  int _demoAtual = 0;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primeiroNome = widget.nomeUsuario.trim().split(' ').first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          primeiroNome.isEmpty ? 'Bem-vindo' : 'Olá, $primeiroNome',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Uma abordagem rapida de como utilizar o app, '
          'fazendo o registro de serviços, tirando fotos e gerando o RDO.'
          ' O app é simples e intuitivo.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Text('Uma aba que pode ser bastante útil é a do\'Mapa\', que pode ser utilizada para se localizar melhor na obra e saber seu local exato no trecho.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),      
        ),
        const SizedBox(height: 20),

        _titulo(theme, 'Demonstração'),
        const SizedBox(height: 8),
        _carrossel(theme),
        const SizedBox(height: 24),

        _titulo(theme, 'Passo a passo'),
        const SizedBox(height: 4),
        Text(
          'Toque em cada passo para ver os detalhes.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        for (final (i, passo) in _passos.indexed) _cartaoPasso(theme, i, passo),

        if (widget.ehSupervisor) ...[
          const SizedBox(height: 24),
          _secaoSupervisor(theme),
        ],

        const SizedBox(height: 24),
        _titulo(theme, 'Também no app'),
        const SizedBox(height: 8),
        _recurso(theme, Icons.map_outlined, 'Mapa do projeto',
            'O desenho do CAD sobre o satélite, com sua posição em tempo real. '
                'Funciona offline e mede distâncias e áreas na tela.'),
        _recurso(theme, Icons.signpost_outlined, 'Ir para uma estaca',
            'No mapa, escolha trecho, KM e estaca: o app traça a direção e '
                'mostra a distância até lá.'),
        _recurso(theme, Icons.history, 'Histórico',
            'Tudo que você registrou, agrupado por trecho e atividade, com as '
                'miniaturas das fotos.'),
        _recurso(theme, Icons.system_update_alt, 'Atualizações',
            'Quando o projeto muda, o app baixa os mapas e as tabelas novas '
                'sem precisar reinstalar.'),
      ],
    );
  }

  Widget _titulo(ThemeData theme, String texto) => Text(
        texto,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      );

  Widget _secaoSupervisor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.supervisor_account,
                      color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    'Você é supervisor',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Além de registrar a atividade para o encarregado de sua equipe, você acompanha a '
                'produção da sua equipe e fecha o relatório de todos de uma vez '
                '— sem precisar pedir o RDO de cada um.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final (i, passo) in _passosSupervisor.indexed)
          _cartaoPasso(theme, i, passo),
        const SizedBox(height: 8),
        Text('O que o perfil permite',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        for (final (permitido, texto) in _limitesSupervisor)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  permitido ? Icons.check_circle_outline : Icons.block,
                  size: 18,
                  color: permitido
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(texto, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _carrossel(ThemeData theme) {
    return Column(
      children: [
        SizedBox(
          height: 250,
          child: PageView.builder(
            controller: _paginas,
            itemCount: _demos.length,
            onPageChanged: (i) => setState(() => _demoAtual = i),
            itemBuilder: (_, i) => _telaDemo(theme, _demos[i]),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _demos.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _demoAtual ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _demoAtual
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _telaDemo(ThemeData theme, _Demo demo) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(demo.titulo,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(demo.legenda,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const Divider(height: 18),
            for (final linha in demo.linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(linha.rotulo,
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    Expanded(
                      child: Text(
                        linha.valor,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              linha.destaque ? FontWeight.bold : FontWeight.normal,
                          color: linha.destaque ? theme.colorScheme.primary : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoPasso(ThemeData theme, int indice, _Passo passo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(passo.icone,
              size: 20, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text('${indice + 1}. ${passo.titulo}',
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(passo.resumo, style: theme.textTheme.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(60, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final detalhe in passo.detalhes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(
                      child: Text(detalhe, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _recurso(
      ThemeData theme, IconData icone, String titulo, String descricao) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(descricao,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
