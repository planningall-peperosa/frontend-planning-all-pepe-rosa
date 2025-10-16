// lib/providers/piatti_provider.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <-- MODIFICA: Import per Firestore
import '../models/piatto.dart';
// import '../services/piatti_service.dart'; // <-- MODIFICA: Non ci serve più il vecchio service

class PiattiProvider with ChangeNotifier {
  // --- MODIFICA: Rimuoviamo il PiattiService e usiamo un'istanza diretta di Firestore ---
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'piatti'; // Nome della nostra collezione su Firestore

  List<Piatto> _piatti = [];
  bool _loading = false;
  String? _error;

  List<Piatto> get piatti => _piatti;
  bool get isLoading => _loading;
  String? get error => _error;

  // --- MODIFICA: Legge tutti i piatti da FIRESTORE ---
  Future<void> fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await _firestore.collection(_collectionName).get();
      // Usiamo il costruttore fromFirestore che abbiamo già nel modello Piatto
      _piatti = snapshot.docs.map((doc) => Piatto.fromFirestore(doc)).toList();
    } catch (e) {
      _error = "Errore nel caricamento dei piatti: ${e.toString()}";
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // --- MODIFICA: Aggiunge un nuovo piatto su FIRESTORE ---
  Future<bool> add(Map<String, dynamic> payload) async {
    _loading = true;
    notifyListeners();
    try {
      // Il metodo .add() crea un nuovo documento con un ID generato automaticamente
      await _firestore.collection(_collectionName).add(payload);
      // Dopo aver aggiunto, ricarichiamo la lista per avere i dati aggiornati
      await fetch(); 
      return true;
    } catch (e) {
      _error = "Errore nell'aggiunta del piatto: ${e.toString()}";
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // --- MODIFICA: Aggiorna un piatto esistente su FIRESTORE ---
  Future<bool> update(String idUnico, Map<String, dynamic> payload) async {
    _loading = true;
    notifyListeners();
    try {
      // Usiamo .doc(idUnico) per puntare al documento specifico e .update() per modificarlo
      await _firestore.collection(_collectionName).doc(idUnico).update(payload);
      await fetch(); // Ricarichiamo per semplicità, in futuro si può ottimizzare
      return true;
    } catch (e) {
      _error = "Errore nell'aggiornamento del piatto: ${e.toString()}";
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // --- MODIFICA: Elimina un piatto da FIRESTORE ---
  Future<bool> remove(String idUnico) async {
    _loading = true;
    notifyListeners();
    try {
      // Usiamo .doc(idUnico) per puntare al documento specifico e .delete() per rimuoverlo
      await _firestore.collection(_collectionName).doc(idUnico).delete();
      await fetch(); // Ricarichiamo per avere la lista aggiornata
      return true;
    } catch (e) {
      _error = "Errore nell'eliminazione del piatto: ${e.toString()}";
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}