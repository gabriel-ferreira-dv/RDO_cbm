class Usuario {
  final int? id;
  final String nome;
  final String email;
  final String senhaHash;

  // Matrícula do funcionário no sistema corporativo (ex.: "051395"), usada
  // para casar o usuário com o campo `encarregado` do apontamento — que vem
  // como "051395::NOME". Vazia nas contas criadas antes deste campo existir;
  // nesse caso a busca da equipe volta a comparar pelo nome.
  final String matricula;

  // 'supervisor' libera a aba de gestão de equipe; qualquer outro valor
  // (inclusive vazio) é encarregado comum. Definido no metadata do Supabase.
  final String perfil;

  final String criadoEm;

  bool get ehSupervisor => perfil == perfilSupervisor;

  Usuario({
    this.id,
    required this.nome,
    required this.email,
    required this.senhaHash,
    this.matricula = '',
    this.perfil = '',
    required this.criadoEm,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'email': email,
        'senha_hash': senhaHash,
        'matricula': matricula,
        'perfil': perfil,
        'criado_em': criadoEm,
      };

  factory Usuario.fromMap(Map<String, dynamic> m) => Usuario(
        id: m['id'] as int,
        nome: m['nome'] as String,
        email: m['email'] as String,
        senhaHash: m['senha_hash'] as String,
        matricula: (m['matricula'] as String?) ?? '',
        perfil: (m['perfil'] as String?) ?? '',
        criadoEm: m['criado_em'] as String,
      );
}

// Valor de [Usuario.perfil] que dá acesso à gestão de equipe.
const String perfilSupervisor = 'supervisor';
