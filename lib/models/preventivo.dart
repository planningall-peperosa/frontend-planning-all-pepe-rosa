// lib/models/preventivo.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// Questo "modello" rappresenta un preventivo letto da Firestore.
// Ora è in un file separato e può essere importato da qualsiasi
// parte dell'applicazione (screen, provider, ecc.).
class Preventivo {
  final String id;
  final String nomeCliente;
  final String nomeEvento;
  final DateTime dataEvento;
  final String status;

  Preventivo({
    required this.id,
    required this.nomeCliente,
    required this.nomeEvento,
    required this.dataEvento,
    required this.status,
  });

  // Factory constructor per creare un'istanza da un DocumentSnapshot di Firestore
  factory Preventivo.fromFirestore(DocumentSnapshot doc) {
    // Converte i dati del documento Firestore in un oggetto che possiamo usare facilmente
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Preventivo(
      id: doc.id,
      // NOTA: Per mostrare il nome del cliente nella lista, è necessario
      // che questo campo sia presente direttamente nel documento del preventivo.
      // È una pratica comune chiamata "denormalizzazione" per migliorare le performance.
      nomeCliente: data['nome_cliente'] ?? 'Cliente Sconosciuto',
      nomeEvento: data['nome_evento'] ?? 'Senza Nome',
      dataEvento: (data['data_evento'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'Sconosciuto',
    );
  }
}