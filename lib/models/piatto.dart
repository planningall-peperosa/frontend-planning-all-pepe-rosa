// lib/models/piatto.dart
class Piatto {
  final String idUnico;
  final String genere;
  final String nome;
  final String? descrizione;
  final String? allergeni;
  final String? linkFoto;
  final String tipologia;

  Piatto({
    required this.idUnico,
    required this.genere,
    required this.nome,
    this.descrizione,
    this.allergeni,
    this.linkFoto,
    required this.tipologia,
  });

  static String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is List) {
      return v.map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .join(', ');
    }
    return v.toString();
  }

  factory Piatto.fromJson(Map<String, dynamic> json) {
    return Piatto(
      idUnico: _asString(json['id_unico']) ?? '',
      genere:  _asString(json['genere']) ?? '',
      // alcuni endpoint usano "piatto", altri "nome"
      nome:    _asString(json['piatto'] ?? json['nome']) ?? 'Nome non disponibile',
      descrizione: _asString(json['descrizione']),
      allergeni:   _asString(json['allergeni']),
      // alcuni fogli hanno "link_foto_piatto", altri "link_foto"
      linkFoto:    _asString(json['link_foto_piatto'] ?? json['link_foto']),
      tipologia:   _asString(json['tipologia']) ?? '',
    );
  }

  Piatto copyWith({
    String? idUnico,
    String? genere,
    String? nome,
    String? descrizione,
    String? allergeni,
    String? linkFoto,
    String? tipologia,
  }) {
    return Piatto(
      idUnico: idUnico ?? this.idUnico,
      genere: genere ?? this.genere,
      nome: nome ?? this.nome,
      descrizione: descrizione ?? this.descrizione,
      allergeni: allergeni ?? this.allergeni,
      linkFoto: linkFoto ?? this.linkFoto,
      tipologia: tipologia ?? this.tipologia,
    );
  }

  Map<String, dynamic> toJson() => {
    'id_unico': idUnico,
    'genere': genere,
    'piatto': nome,
    'descrizione': descrizione,
    'allergeni': allergeni,
    'link_foto_piatto': linkFoto,
    'tipologia': tipologia,
  };
}
