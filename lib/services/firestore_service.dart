// lib/services/firestore_service.dart (MODIFICATO)

import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Riferimento esistente
  CollectionReference<Map<String, dynamic>> get preventiviCollection {
    return _db.collection('preventivi');
  }

  // Aggiungi qui eventuali collezioni che servono per i Pacchetti Fissi.

  // ====================================================================
  // 🟢 NUOVE COLLEZIONI PER BILANCIO
  // ====================================================================

  /// Raccolta pubblica per la lista delle categorie di spesa (condivise per app).
  /// Path: artifacts/{appId}/public/data/spese_categorie
  CollectionReference<Map<String, dynamic>> speseCategorieCollection({
    required String appId,
  }) {
    // Usiamo l'appId come sottocollezione per isolare i dati del tenant
    return _db
        .collection('artifacts')
        .doc(appId)
        .collection('public')
        .doc('data')
        .collection('spese_categorie');
  }

  /// Raccolta privata per le singole spese registrate dall'utente.
  /// Path: artifacts/{appId}/users/{userId}/spese_registrate
  CollectionReference<Map<String, dynamic>> speseRegistrateCollection({
    required String appId,
    required String userId,
  }) {
    // Isoliamo per app e per utente (sicurezza e isolamento)
    return _db
        .collection('artifacts')
        .doc(appId)
        .collection('users')
        .doc(userId)
        .collection('spese_registrate');
  }
}