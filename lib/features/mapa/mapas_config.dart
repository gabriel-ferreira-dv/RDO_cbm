// Mapas do projeto. O `nome` precisa bater em três lugares: a pasta
// assets/overlays/<nome> (origem do .zip), a pasta baixada dados_remotos/<nome>
// e a coluna `nome` de versoes_dados. Mapa novo: entrada aqui e coordenadas
// em map_page.dart. O .zip no bucket deve ter nome sem acento.

// Grupos de mapa; cada usuário tem um ou os dois (ver PermissaoMapasService).
const String grupoCbm = 'CBM';
const String grupoSubContratada = 'SUB CONTRATADA';

class MapaInfo {
  // Identificador e nome da pasta (assets e dados_remotos).
  final String nome;

  // Rótulo amigável para diálogos e avisos.
  final String rotulo;

  // Grupo que dá acesso a este mapa.
  final String grupo;

  const MapaInfo(this.nome, this.rotulo, {this.grupo = grupoCbm});

  String get assetDir => 'assets/overlays/$nome';
}

const List<MapaInfo> mapasConfig = [
  MapaInfo('D2', 'Mapa do trecho D2'),
  MapaInfo('C1', 'Mapa do trecho C1'),
  MapaInfo('Contorno_Fundão', 'Mapa do Contorno de Fundão'),
  MapaInfo('Contorno_Ibiraçu', 'Mapa do Contorno de Ibiraçu'),
  MapaInfo('GEO_dreno', 'Mapa do GEO dreno', grupo: grupoSubContratada),
];

// Mapas visíveis para estes [grupos].
List<MapaInfo> mapasDosGrupos(Set<String> grupos) =>
    [for (final mapa in mapasConfig) if (grupos.contains(mapa.grupo)) mapa];

// true se [nome] (vindo da tabela versoes_dados) é um mapa — e não um CSV.
bool ehNomeDeMapa(String nome) => mapasConfig.any((m) => m.nome == nome);

// Grupo do mapa [nome]; [grupoCbm] se desconhecido.
String grupoDoMapa(String nome) {
  for (final m in mapasConfig) {
    if (m.nome == nome) return m.grupo;
  }
  return grupoCbm;
}

// Nome amigável de um mapa; cai para um genérico se não estiver cadastrado.
String rotuloDoMapa(String nome) {
  for (final m in mapasConfig) {
    if (m.nome == nome) return m.rotulo;
  }
  return 'Mapa ($nome)';
}
