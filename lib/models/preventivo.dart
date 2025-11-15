// lib/models/preventivo.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Questo "modello" rappresenta un preventivo letto da Firestore.
/// È usato per le liste o anteprime di preventivi.
class Preventivo {
  final String id;
  final String nomeCliente;
  final String nomeEvento;
  final DateTime dataEvento;
  final String status;
  final String? noteIntegrative; // ✅ nuovo campo opzionale

  Preventivo({
    required this.id,
    required this.nomeCliente,
    required this.nomeEvento,
    required this.dataEvento,
    required this.status,
    this.noteIntegrative,
  });

  /// Factory constructor per creare un'istanza da un DocumentSnapshot di Firestore
  factory Preventivo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Preventivo(
      id: doc.id,
      nomeCliente: data['nome_cliente'] ?? 'Cliente Sconosciuto',
      nomeEvento: data['nome_evento'] ?? 'Senza Nome',
      dataEvento: (data['data_evento'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'Sconosciuto',
      noteIntegrative: data['note_integrative'], // ✅ aggiunto per coerenza
    );
  }
}
