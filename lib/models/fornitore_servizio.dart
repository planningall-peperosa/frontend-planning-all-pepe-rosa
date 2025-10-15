// lib/models/fornitore_servizio.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FornitoreServizio {
  final String idContatto;
  final String ragioneSociale;
  final String? ruolo;
  final double? prezzo;
  final String? telefono01;
  final String? telefono02;
  final String? mail;
  final int? conteggioPreventivi;

  FornitoreServizio({
    required this.idContatto,
    required this.ragioneSociale,
    this.ruolo,
    this.prezzo,
    this.telefono01,
    this.telefono02,
    this.mail,
    this.conteggioPreventivi,
  });

  // --- NUOVA AGGIUNTA: TRADUTTORE DA JSON ---
  // Questo metodo risolve l'errore "Member not found: 'FornitoreServizio.fromJson'".
  factory FornitoreServizio.fromJson(Map<String, dynamic> json) {
    return FornitoreServizio(
      idContatto: json['id_contatto'] ?? '',
      ragioneSociale: json['ragione_sociale'] ?? 'Senza Nome',
      ruolo: json['ruolo'] as String?,
      prezzo: (json['prezzo'] as num?)?.toDouble(),
      telefono01: json['telefono_01'] as String?,
      telefono02: json['telefono_02'] as String?,
      mail: json['mail'] as String?,
      conteggioPreventivi: (json['conteggio_preventivi'] as num?)?.toInt(),
    );
  }

  // Traduttore da un documento Firebase a un oggetto FornitoreServizio
  factory FornitoreServizio.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    // Riutilizziamo la logica fromJson per coerenza
    data['id_contatto'] = doc.id;
    return FornitoreServizio.fromJson(data);
  }

  // Metodo per convertire l'oggetto in una mappa, utile per futuri salvataggi
  Map<String, dynamic> toJson() {
    return {
      'ragione_sociale': ragioneSociale,
      'ruolo': ruolo,
      'prezzo': prezzo,
      'telefono_01': telefono01,
      'telefono_02': telefono02,
      'mail': mail,
      'conteggio_preventivi': conteggioPreventivi,
    };
  }
}