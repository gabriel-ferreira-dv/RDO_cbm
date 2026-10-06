// Explicação de cada atividade (resumo no campo e guia completo). As chaves
// precisam bater com a coluna Atividade do SevNotaveis.csv (há teste).
const Map<String, String> descricoesAtividades = {
  'Terraplanagem':
      'Preparação e movimentação de terra: limpeza da área, remoções e '
          'demolições, escavações, cargas e transportes, aterros e '
          'compactação — o que conforma o terreno ao greide do projeto.',
  'Drenagem':
      'Dispositivos de captação, condução e disposição das águas pluviais: '
          'bueiros, sarjetas, valetas, meios-fios, caixas coletoras e drenos, '
          'protegendo a via contra erosão e acúmulo de água.',
  'Pavimentação':
      'Camadas do pavimento, do subleito ao revestimento asfáltico: '
          'fresagem, bases e sub-bases, pinturas betuminosas e aplicação de '
          'misturas asfálticas (CBUQ, PMQ), formando a estrutura de rolamento.',
  'Civil':
      'Obras de concreto e estrutura: fundações, estacas, armação, fôrmas, '
          'concretagem, protensão e pré-moldados, além de contenções, '
          'andaimes e os serviços de apoio e acabamento da obra.',
  'Sinalização':
      'Elementos de segurança viária e sinalização: barreiras tipo New '
          'Jersey, defensas, placas e marcações que protegem e orientam o '
          'tráfego.',
};

// Descrição da atividade, ou null se ainda não houver texto para ela.
String? descricaoDaAtividade(String? atividade) =>
    atividade == null ? null : descricoesAtividades[atividade];
