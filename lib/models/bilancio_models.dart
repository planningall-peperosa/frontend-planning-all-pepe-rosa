// lib/models/bilancio_models.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// --- 1. Modello Categoria di Spesa ---
class SpesaCategoria {
  final String id;
  final String nome;
  final Timestamp timestamp;

  SpesaCategoria({
    required this.id,
    required this.nome,
    required this.timestamp,
  });

  factory SpesaCategoria.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SpesaCategoria(
      id: doc.id,
      nome: data['nome'] as String,
      timestamp: data['timestamp'] as Timestamp,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nome': nome,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

// --- 2. Modello Spesa Registrata ---
class SpesaRegistrata {
  final String id;
  final Timestamp data;
  final double importo;
  final String descrizione;
  final String categoria;

  SpesaRegistrata({
    required this.id,
    required this.data,
    required this.importo,
    required this.descrizione,
    required this.categoria,
  });

  factory SpesaRegistrata.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SpesaRegistrata(
      id: doc.id,
      data: data['data'] as Timestamp,
      importo: (data['importo'] as num).toDouble(),
      descrizione: data['descrizione'] as String,
      categoria: data['categoria'] as String,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'data': data,
      'importo': importo,
      'descrizione': descrizione,
      'categoria': categoria,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
