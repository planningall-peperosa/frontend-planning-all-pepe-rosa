// lib/models/tipo_turno.dart

import 'package:cloud_firestore/cloud_firestore.dart'; // Importa Firestore

class TipoTurno {
  final String idTurno;
  String nomeTurno;
  String orarioInizio;
  String orarioFine;

  TipoTurno({
    required this.idTurno,
    required this.nomeTurno,
    required this.orarioInizio,
    required this.orarioFine,
  });

  // Questo metodo crea un oggetto TipoTurno dai dati JSON ricevuti dal server
  factory TipoTurno.fromJson(Map<String, dynamic> json) {
    return TipoTurno(
      idTurno: json['id_turno'] ?? '',
      nomeTurno: json['nome_turno'] ?? '',
      orarioInizio: json['orario_inizio'] ?? '',
      orarioFine: json['orario_fine'] ?? '',
    );
  }
  
  // 🚨 NUOVA FACTORY: Traduttore da Firestore
  factory TipoTurno.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Mappiamo l'ID del documento Firestore su idTurno
    data['id_turno'] = doc.id;
    return TipoTurno.fromJson(data);
  }
}