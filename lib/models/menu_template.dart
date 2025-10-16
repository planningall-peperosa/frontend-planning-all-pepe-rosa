// lib/models/menu_template.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MenuTemplate {
  final String idMenu;
  final String nomeMenu;
  final String tipologia;
  final double prezzo;
  final double prezzoBambino;
  final Map<String, List<String>> composizioneDefault;

  MenuTemplate({
    required this.idMenu,
    required this.nomeMenu,
    required this.tipologia,
    required this.prezzo,
    this.prezzoBambino = 0.0,
    required this.composizioneDefault,
  });

  factory MenuTemplate.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final Map<String, List<String>> parsedComposizione = {};
    if (data['composizione_default'] is Map) {
      (data['composizione_default'] as Map).forEach((key, value) {
        if (value is List) {
          parsedComposizione[key.toString()] = value.map((e) => e.toString()).toList();
        }
      });
    }

    return MenuTemplate(
      idMenu: doc.id,
      nomeMenu: data['nome_menu'] ?? 'Nome non trovato',
      tipologia: data['tipologia'] ?? '',
      prezzo: (data['prezzo'] as num?)?.toDouble() ?? 0.0,
      prezzoBambino: (data['prezzo_bambino'] as num?)?.toDouble() ?? 0.0,
      composizioneDefault: parsedComposizione,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'nome_menu': nomeMenu,
        'tipologia': tipologia,
        'prezzo': prezzo,
        'prezzo_bambino': prezzoBambino,
        'composizione_default': composizioneDefault,
      };
}