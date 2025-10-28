// lib/providers/dipendenti_provider.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import cruciale per Firestore
import '../models/cliente.dart'; // Usiamo il modello unificato Cliente
// Rimuoviamo l'import di '../services/dipendenti_service.dart';
// Rimuoviamo l'import di '../models/dipendente.dart';

class DipendentiProvider with ChangeNotifier {
  // 1. Istanza di Firestore e nome della collection
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'dipendenti'; 
  
  List<Cliente> _dipendenti = []; // Ora gestisce oggetti Cliente
  bool _isLoading = false;
  String? _error;

  List<Cliente> get dipendenti => _dipendenti;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ----------------------------------------------------
  // LOGICA READ (fetchDipendenti)
  // ----------------------------------------------------

  Future<void> fetchDipendenti() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await _firestore.collection(_collectionName).get();
      // Mappiamo i documenti usando la factory Cliente.fromFirestore
      _dipendenti = snapshot.docs.map((doc) => Cliente.fromFirestore(doc)).toList();
    } catch (e) {
      _error = "Errore nel caricamento dei dipendenti: ${e.toString()}";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------
  // LOGICA CREATE (addDipendente)
  // ----------------------------------------------------

  Future<bool> addDipendente(Map<String, dynamic> data) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // 1. Filtriamo i dati in input per evitare di salvare campi obsoleti/inutili
      final payload = {
          'tipo': 'dipendente', // Imposta il tipo fisso
          'ragione_sociale': data['nome_dipendente'],
          'ruolo': data['ruolo'],
          'email': data['email'],
          'telefono_01': data['telefono'],
          'colore': data['colore'],
          // PIN e Campi Extra sono omessi
      };

      // 2. Aggiungi a Firestore
      await _firestore.collection(_collectionName).add(payload);
      
      // 3. Ricarica la lista per aggiornare l'UI
      await fetchDipendenti(); 
      return true;
    } catch (e) {
      _error = "Errore nell'aggiunta del dipendente: ${e.toString()}";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------
  // LOGICA UPDATE (updateDipendente)
  // ----------------------------------------------------

  Future<bool> updateDipendente(String id, Map<String, dynamic> data) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // 1. Filtriamo i dati in input per evitare di aggiornare campi obsoleti
      final payload = {
          'ragione_sociale': data['nome_dipendente'],
          'ruolo': data['ruolo'],
          'email': data['email'],
          'telefono_01': data['telefono'],
          'colore': data['colore'],
          // Gli aggiornamenti dei campi extra e del PIN sono ignorati
      };
      
      // 2. Aggiorna Firestore
      await _firestore.collection(_collectionName).doc(id).update(payload);
      
      // 3. Ricarica la lista per aggiornare l'UI
      await fetchDipendenti();
      return true;
    } catch (e) {
      _error = "Errore nell'aggiornamento del dipendente: ${e.toString()}";
      print("[DipendentiProvider] Aggiornamento fallito. Errore: $_error");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------
  // LOGICA DELETE (deleteDipendente)
  // ----------------------------------------------------

  Future<bool> deleteDipendente(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _firestore.collection(_collectionName).doc(id).delete();
      
      // Ricarica la lista per aggiornare l'UI
      await fetchDipendenti();
      return true;
    } catch (e) {
      _error = "Errore nell'eliminazione del dipendente: ${e.toString()}";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}