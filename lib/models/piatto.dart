// lib/models/piatto.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Piatto {
  final String idUnico;
  final String genere;
  final String nome;
  final String? descrizione;
  final String? stagione;
  final String? linkFoto;
  final String tipologia;

  Piatto({
    required this.idUnico,
    required this.genere,
    required this.nome,
    this.descrizione,
    this.stagione,
    this.linkFoto,
    required this.tipologia,
  });

  static String? _asString(dynamic v) {
    if (v == null) return null;
    return v.toString();
  }

  // --- MODIFICA: fromJson ora legge SOLO i campi standard di Firestore ---
  factory Piatto.fromJson(Map<String, dynamic> json) {
    return Piatto(
      idUnico: _asString(json['id_unico']) ?? '',
      genere:  _asString(json['genere']) ?? '',
      nome:    _asString(json['nome']) ?? 'Nome non disponibile',
      descrizione: _asString(json['descrizione']),
      stagione:   _asString(json['stagione']),
      linkFoto:    _asString(json['link_foto_piatto']), // <-- LEGGE SOLO DA 'link_foto_piatto'
      tipologia:   _asString(json['tipologia']) ?? '',
    );
  }
  
  factory Piatto.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id_unico'] = doc.id; 
    return Piatto.fromJson(data);
  }

  Piatto copyWith({
    String? idUnico,
    String? genere,
    String? nome,
    String? descrizione,
    String? stagione,
    String? linkFoto,
    String? tipologia,
  }) {
    return Piatto(
      idUnico: idUnico ?? this.idUnico,
      genere: genere ?? this.genere,
      nome: nome ?? this.nome,
      descrizione: descrizione ?? this.descrizione,
      stagione: stagione ?? this.stagione,
      linkFoto: linkFoto ?? this.linkFoto,
      tipologia: tipologia ?? this.tipologia,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
    'genere': genere,
    'nome': nome,
    'descrizione': descrizione,
    'stagione': stagione,
    'link_foto_piatto': linkFoto, // <-- SCRIVE SOLO SU 'link_foto_piatto'
    'tipologia': tipologia,
  };
}