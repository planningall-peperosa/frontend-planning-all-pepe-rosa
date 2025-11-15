// lib/models/pacchetto_evento.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class PacchettoEvento {
  final String id;
  final String nome;
  final double prezzoFisso;
  final String _descrizione1; // 🌟 NUOVO CAMPO PRIVATO
  final String _descrizione2; // 🌟 NUOVO CAMPO PRIVATO
  final String _descrizione3; // 🌟 NUOVO CAMPO PRIVATO
  final String propostaGastronomica; 

  const PacchettoEvento({
    required this.id,
    required this.nome,
    required this.prezzoFisso,
    required String descrizione1, // Rinomino in costruttore
    required String descrizione2, // Rinomino in costruttore
    required String descrizione3, // Rinomino in costruttore
    required this.propostaGastronomica,
  }) : _descrizione1 = descrizione1, 
       _descrizione2 = descrizione2,
       _descrizione3 = descrizione3;

  // 🟢 GETTER PUBBLICI PER LA UI (che cercavi nel log)
  String get descrizione_1 => _descrizione1;
  String get descrizione_2 => _descrizione2;
  String get descrizione_3 => _descrizione3;
  
  // Vecchio getter unito (potrebbe non servire più, ma lo lasciamo per sicurezza)
  String get descrizione => [descrizione_1, descrizione_2, descrizione_3].where((s) => s.isNotEmpty).join('\n');

  // Metodo factory per creare l'oggetto dal DocumentSnapshot di Firestore
  factory PacchettoEvento.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    // Estrazione esplicita dei tre campi
    final d1 = data['descrizione_1'] as String? ?? '';
    final d2 = data['descrizione_2'] as String? ?? '';
    final d3 = data['descrizione_3'] as String? ?? '';

    final String proposta = data['proposta_gastronomica'] as String? ?? 'Menù fisso non specificato.';

    return PacchettoEvento(
      id: doc.id,
      nome: data['nome_evento'] as String? ?? 'Pacchetto Sconosciuto',
      prezzoFisso: (data['prezzo'] as num?)?.toDouble() ?? 0.0,
      descrizione1: d1,
      descrizione2: d2,
      descrizione3: d3,
      propostaGastronomica: proposta,
    );
  }

  // 👉 Serve al Provider per create/update su Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'nome_evento': nome,
      'prezzo': prezzoFisso,
      'descrizione_1': _descrizione1,
      'descrizione_2': _descrizione2,
      'descrizione_3': _descrizione3,
      'proposta_gastronomica': propostaGastronomica,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // 👉 Utile per modifiche locali prima del salvataggio
  PacchettoEvento copyWith({
    String? id,
    String? nome,
    double? prezzoFisso,
    String? descrizione1,
    String? descrizione2,
    String? descrizione3,
    String? propostaGastronomica,
  }) {
    return PacchettoEvento(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      prezzoFisso: prezzoFisso ?? this.prezzoFisso,
      descrizione1: descrizione1 ?? _descrizione1,
      descrizione2: descrizione2 ?? _descrizione2,
      descrizione3: descrizione3 ?? _descrizione3,
      propostaGastronomica: propostaGastronomica ?? this.propostaGastronomica,
    );
  }

  // Metodo per combinare proposta e descrizioni per la UI (come usato prima)
  String get descrizioneCompletaPerUI {
    final buffer = StringBuffer();
    buffer.writeln(propostaGastronomica);
    final descList = [descrizione_1, descrizione_2, descrizione_3].where((s) => s.isNotEmpty).join('\n');
    if (descList.isNotEmpty) {
      buffer.writeln('\n--- Condizioni ---\n$descList');
    }
    return buffer.toString();
  }
}
