// lib/models/preventivo.dart
import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory Preventivo.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Preventivo(
      id: doc.id,
      nomeCliente: data['nome_cliente'] ?? 'Cliente Sconosciuto',
      nomeEvento: data['nome_evento'] ?? 'Senza Nome',
      dataEvento: (data['data_evento'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'Sconosciuto',
    );
  }
}