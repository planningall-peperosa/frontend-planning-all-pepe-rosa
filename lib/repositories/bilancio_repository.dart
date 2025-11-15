// lib/repositories/bilancio_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/bilancio_models.dart';

// Variabili di contesto (ottenute dalla configurazione globale)
const String APP_ID = 'peperosa-planning-v2';

// ====================================================================
// MAPPER LOGIC (omissis, rimane invariata)
// ====================================================================

class PreventivoCostiMapper {
  final Map<String, dynamic> data;

  PreventivoCostiMapper(this.data);

  int get _numeroAdulti {
    final ospiti = (data['numero_ospiti'] as num?)?.toInt() ?? 0;
    final b = (data['numero_bambini'] as num?)?.toInt() ?? 0;
    final bb = b < 0 ? 0 : (b > ospiti ? ospiti : b);
    return ospiti - bb;
  }

  double get costoMenuAdulti {
    final prezzo = (data['prezzo_menu_persona'] as num?)?.toDouble() ?? 
                   (data['prezzo_menu_adulto'] as num?)?.toDouble() ?? 0.0;
    return prezzo * _numeroAdulti;
  }

  double get costoMenuBambini {
    final prezzo = (data['prezzo_menu_bambino'] as num?)?.toDouble() ?? 0.0;
    return prezzo * ((data['numero_bambini'] as num?)?.toInt() ?? 0);
  }

  double get costoServizi {
    final List<dynamic> servizi = data['servizi'] ?? data['servizi_extra'] ?? [];
    return servizi.fold<double>(0.0, (sum, s) {
      final prezzo = (s['prezzo'] as num?)?.toDouble() ?? 0.0;
      return sum + prezzo;
    });
  }

  double get costoPacchettoWelcomeDolci {
    final n = (data['numero_ospiti'] as num?)?.toInt() ?? 0;
    final aperitivo = (data['aperitivo_benvenuto'] as bool?) ?? false;
    final dolci = (data['buffet_dolci'] as bool?) ?? false;
    
    if (aperitivo && dolci) return n * 10.0;
    if (aperitivo && !dolci) return n * 8.0;
    if (!aperitivo && dolci) return n * 5.0;
    return 0.0;
  }
  
  double get subtotale {
    final isPacchettoFisso = (data['is_pacchetto_fisso'] as bool?) ?? false;
    final prezzoPacchettoFisso = (data['prezzo_pacchetto_fisso'] as num?)?.toDouble() ?? 0.0;

    final double costoBase;
    
    if (isPacchettoFisso) {
      costoBase = prezzoPacchettoFisso;
    } else {
      costoBase = costoMenuAdulti + costoMenuBambini + costoPacchettoWelcomeDolci;
    }

    return costoBase + costoServizi;
  }

  double get totaleFinale {
    final sconto = (data['sconto'] as num?)?.toDouble() ?? 0.0;
    return subtotale - sconto;
  }
}

// ====================================================================
// REPOSITORY IMPLEMENTATION
// ====================================================================


class BilancioRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _appId = APP_ID;
  
  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  // Riferimenti Collezioni
  CollectionReference<Map<String, dynamic>> _speseCategorieCollection() {
    return _db.collection('spese_categorie');
  }

  CollectionReference<Map<String, dynamic>> _speseRegistrateCollection() {
    final userId = _userId;
    if (userId == null) {
      throw Exception('User not authenticated for private expenses.');
    }
    return _db.collection('users').doc(userId).collection('spese_registrate');
  }

  CollectionReference<Map<String, dynamic>> get _preventiviCollection {
    return _db.collection('preventivi');
  }

  // Operazioni Spese

  /// Ottiene lo stream di tutte le categorie di spesa.
  Stream<List<SpesaCategoria>> getCategorieStream() {
    return _speseCategorieCollection()
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SpesaCategoria.fromFirestore(doc))
            .toList());
  }

  /// Aggiunge una nuova categoria di spesa.
  Future<void> addCategoria(String nomeCategoria) async {
    final data = SpesaCategoria(id: '', nome: nomeCategoria, timestamp: Timestamp.now());
    await _speseCategorieCollection().add(data.toFirestore());
  }

  // 🔑 NUOVO: Aggiorna una categoria esistente
  Future<void> updateCategoria(String id, String nuovoNome) async {
    await _speseCategorieCollection().doc(id).update({
      'nome': nuovoNome,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // 🔑 NUOVO: Cancella una categoria
  Future<void> deleteCategoria(String id) async {
    // Nota: Non c'è un check di sicurezza per le spese associate in questo layer
    await _speseCategorieCollection().doc(id).delete();
  }

  Future<void> addSpesa({required DateTime data, required double importo, required String descrizione, required String categoria}) async {
    final nuovaSpesa = SpesaRegistrata(id: '', data: Timestamp.fromDate(data), importo: importo, descrizione: descrizione, categoria: categoria);
    await _speseRegistrateCollection().add(nuovaSpesa.toFirestore());
  }

  /// 🔑 NUOVO: Elimina una spesa registrata per id documento.
  Future<void> deleteSpesa(String id) async {
    await _speseRegistrateCollection().doc(id).delete();
  }
  
  Stream<List<SpesaRegistrata>> getSpeseByPeriod({required DateTime start, required DateTime end}) {
    final startTimestamp = Timestamp.fromDate(start);
    final endOfEndDay = end.add(const Duration(days: 1)); 
    final endTimestamp = Timestamp.fromDate(endOfEndDay);

    return _speseRegistrateCollection()
        .where('data', isGreaterThanOrEqualTo: startTimestamp)
        .where('data', isLessThan: endTimestamp)
        .orderBy('data', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SpesaRegistrata.fromFirestore(doc))
            .toList());
  }

  // Logica Calcolo Entrate (Ricalcolo Totale)

  Future<Map<String, dynamic>> calculateEntrateWithDetails({
    required DateTime start,
    required DateTime end,
  }) async {
    // ... (Logica omessa per brevità)
    if (kDebugMode) print('--- DEBUG ENTRATE FIREBASE (Inizio) ---');
    if (kDebugMode) print('Periodo richiesto: ${start.toIso8601String()} a ${end.toIso8601String()}');
    
    final startTimestamp = Timestamp.fromDate(start);
    final endOfEndDay = end.add(const Duration(days: 1));
    final endTimestamp = Timestamp.fromDate(endOfEndDay);

    try {
      final query = _preventiviCollection
          .where('data_evento', isGreaterThanOrEqualTo: startTimestamp)
          .where('data_evento', isLessThan: endTimestamp)
          .where('status', isEqualTo: 'confermato'); 
          
      final snapshot = await query.get(); 

      double totalEntrate = 0.0;
      final List<Map<String, dynamic>> details = [];
      
      if (kDebugMode) print('Preventivi trovati: ${snapshot.docs.length}');
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        final mapper = PreventivoCostiMapper(data);
        final totaleCalcolato = mapper.totaleFinale;

        if (totaleCalcolato > 0) {
           totalEntrate += totaleCalcolato;
           
           details.add({
             'id': doc.id,
             'nome_evento': data['nome_evento'] ?? 'N/D',
             'data_evento': (data['data_evento'] as Timestamp?)?.toDate() ?? DateTime.now(), 
             'totale_conteggiato': totaleCalcolato,
             'cliente_nome': data['cliente']?['ragione_sociale'] ?? 'Cliente Sconosciuto',
             'costo_menu_adulti': mapper.costoMenuAdulti,
             'costo_servizi': mapper.costoServizi,
             'sconto': (data['sconto'] as num?)?.toDouble() ?? 0.0,
           });
        }
      }
      
      if (kDebugMode) print('Totale Entrate FINALE calcolato: €${totalEntrate.toStringAsFixed(2)}');
      if (kDebugMode) print('--- DEBUG ENTRATE FIREBASE (Fine) ---');
      
      return {'total': totalEntrate, 'details': details};
    } catch (e) {
      if (kDebugMode) print("FATAL ERRORE nel calcolo delle entrate da Firestore: $e");
      return {'total': 0.0, 'details': []};
    }
  }
}
