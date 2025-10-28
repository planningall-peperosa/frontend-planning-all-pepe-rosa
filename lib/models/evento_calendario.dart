// lib/models/evento_calendario.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class EventoCalendario {
  final String id;
  final String nomeEvento;
  final DateTime dataEvento; // Data normalizzata (solo giorno/mese/anno)
  final String tipoPasto; // Pranzo o Cena
  final int numeroOspiti;
  final String clienteNome;
  
  final String stato; 

  EventoCalendario({
    required this.id,
    required this.nomeEvento,
    required this.dataEvento,
    required this.tipoPasto,
    required this.numeroOspiti,
    required this.clienteNome,
    required this.stato,
  });

  // Factory per mappare da un documento Preventivo di Firestore
  factory EventoCalendario.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // 1. Parsing Data (supporta Timestamp e Stringa ISO YYYY-MM-DD)
    DateTime? dtEvento;
    final rawDate = data['data_evento'];
    if (rawDate is Timestamp) {
      dtEvento = rawDate.toDate();
    } else if (rawDate is String) {
      dtEvento = DateTime.tryParse(rawDate);
    }
    
    if (dtEvento == null) {
       // Possibile che questo errore sia causato da documenti incompleti
       throw Exception("Data evento non valida per il calendario: ${doc.id}");
    }
    
    final normalizedDate = DateTime.utc(dtEvento.year, dtEvento.month, dtEvento.day);

    // 2. Estrazione Campo Stato e Tipo Pasto
    // 🔑 CORREZIONE CHIAVE: Uso 'status' anziché 'stato'. Fallback a 'bozza' se assente.
    final String extractedStato = (data['status'] as String?)?.trim() ?? 'bozza'; 
    final String extractedTipoPasto = (data['tipo_pasto'] as String?) ?? 'N/A';
    
    return EventoCalendario(
      id: doc.id,
      nomeEvento: data['nome_evento'] as String? ?? 'Evento Sconosciuto',
      dataEvento: normalizedDate,
      tipoPasto: extractedTipoPasto,
      numeroOspiti: (data['numero_ospiti'] as num?)?.toInt() ?? 0,
      clienteNome: data['nome_cliente'] as String? ?? 'N/A',
      stato: extractedStato, // Il valore è la stringa originale (es. "Confermato")
    );
  }

  // Rende comparabili gli eventi (richiesto da table_calendar)
  @override
  bool operator ==(Object other) => other is EventoCalendario && id == other.id;

  @override
  int get hashCode => id.hashCode;
}