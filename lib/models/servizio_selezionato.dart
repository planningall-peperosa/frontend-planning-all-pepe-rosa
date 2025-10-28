// lib/models/servizio_selezionato.dart

// 🚨 CORREZIONE: Importa Firestore per riconoscere Timestamp
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'fornitore_servizio.dart';

class ServizioSelezionato {
  final String ruolo; // es: "allestimento"
  FornitoreServizio? fornitore;
  String? note;
  double? prezzo;
  
  final bool isContattato; 
  final DateTime? dataUltimoContatto;

  ServizioSelezionato({
    required this.ruolo,
    this.fornitore,
    this.note,
    this.prezzo,
    this.isContattato = false,
    this.dataUltimoContatto,
  });


  factory ServizioSelezionato.fromJson(Map<String, dynamic> json) {
    final p = json['prezzo'];
    double? parsedPrezzo;
    if (p is num) parsedPrezzo = p.toDouble();
    else if (p is String && p.trim().isNotEmpty) {
      parsedPrezzo = double.tryParse(p.replaceAll(',', '.'));
    }
    
    DateTime? parsedDataContatto;
    final rawDate = json['data_ultimo_contatto'];
    if (rawDate is Timestamp) {
      parsedDataContatto = rawDate.toDate();
    } else if (rawDate is String) {
      parsedDataContatto = DateTime.tryParse(rawDate);
    }
    
    final Map<String, dynamic>? fornitoreJson = 
        (json['fornitore'] is Map<String, dynamic>) 
        ? json['fornitore'] as Map<String, dynamic> 
        : null;

    FornitoreServizio? fornitoreServizio;
    if (fornitoreJson != null) {
        // 🚨 CORREZIONE CHIRURGICA: Usiamo la factory corretta per ricostruire il Fornitore
        fornitoreServizio = FornitoreServizio.fromJson(fornitoreJson);
    }
    
    return ServizioSelezionato(
      ruolo: json['ruolo'] ?? '',
      fornitore: fornitoreServizio, // Ora l'oggetto contiene i contatti
      note: json['note'],
      prezzo: parsedPrezzo,
      isContattato: json['is_contattato'] as bool? ?? false, 
      dataUltimoContatto: parsedDataContatto,
    );
  }


  Map<String, dynamic>? _fornitoreToJson() {
    if (fornitore == null) return null;
    
    // Inizializza la mappa con i dati di FornitoreServizio.toJson()
    final Map<String, dynamic> json = fornitore!.toJson();
    
    // Aggiungi l'idContatto (chiave necessaria per la relazione)
    json['id_contatto'] = fornitore!.idContatto;
    
    return json;
  }

  Map<String, dynamic> toJson() => {
      'ruolo': ruolo,
      // 🚨 CORREZIONE: Chiama la funzione helper corretta
      'fornitore': _fornitoreToJson(), 
      'note': note,
      'prezzo': prezzo,
      'is_contattato': isContattato,
      'data_ultimo_contatto': dataUltimoContatto?.toIso8601String(), 
    };
  
  ServizioSelezionato copyWith({
    String? ruolo,
    FornitoreServizio? fornitore,
    String? note,
    double? prezzo,
    bool? isContattato,
    DateTime? dataUltimoContatto,
  }) {
    return ServizioSelezionato(
      ruolo: ruolo ?? this.ruolo,
      fornitore: fornitore ?? this.fornitore,
      note: note ?? this.note,
      prezzo: prezzo ?? this.prezzo,
      isContattato: isContattato ?? this.isContattato,
      dataUltimoContatto: dataUltimoContatto ?? this.dataUltimoContatto,
    );
  }
}