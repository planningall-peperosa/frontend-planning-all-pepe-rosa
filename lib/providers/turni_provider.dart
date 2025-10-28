// lib/providers/turni_provider.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import cruciale
import '../models/tipo_turno.dart';
// Rimuoviamo l'import di '../services/turni_service.dart';

class TurniProvider with ChangeNotifier {
  // 1. Istanza di Firestore e nome della collection
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'tipi_turno'; 

  List<TipoTurno> _tipiTurno = [];
  bool _isLoading = false;
  String? _error;

  List<TipoTurno> get tipiTurno => _tipiTurno;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ----------------------------------------------------
  // LOGICA READ (fetchTipiTurno)
  // ----------------------------------------------------

  Future<void> fetchTipiTurno() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await _firestore.collection(_collectionName).get();
      // Mappiamo i documenti usando la factory TipoTurno.fromFirestore (che aggiungeremo)
      _tipiTurno = snapshot.docs.map((doc) => TipoTurno.fromFirestore(doc)).toList();
    } catch (e) {
      _error = "Errore nel caricamento dei tipi turno: ${e.toString()}";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------
  // LOGICA CREATE (addTipoTurno)
  // ----------------------------------------------------

  Future<bool> addTipoTurno(Map<String, dynamic> data) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // 1. Aggiungi a Firestore
      await _firestore.collection(_collectionName).add(data);
      
      // 2. Ricarica la lista per aggiornare l'UI
      await fetchTipiTurno();
      return true;
    } catch (e) {
      _error = "Errore nell'aggiunta del tipo turno: ${e.toString()}";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------
  // LOGICA UPDATE (updateTipoTurno)
  // ----------------------------------------------------

  Future<bool> updateTipoTurno(String id, Map<String, dynamic> data) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // 1. Aggiorna Firestore
      await _firestore.collection(_collectionName).doc(id).update(data);
      
      // 2. Ricarica la lista per aggiornare l'UI
      await fetchTipiTurno();
      return true;
    } catch (e) {
      _error = "Errore nell'aggiornamento del tipo turno: ${e.toString()}";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------
  // LOGICA DELETE (deleteTipoTurno)
  // ----------------------------------------------------

  Future<bool> deleteTipoTurno(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // 1. Elimina da Firestore
      await _firestore.collection(_collectionName).doc(id).delete();
      
      // 2. Ricarica la lista per aggiornare l'UI
      await fetchTipiTurno();
      return true;
    } catch (e) {
      _error = "Errore nell'eliminazione del tipo turno: ${e.toString()}";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}