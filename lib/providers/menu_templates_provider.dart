// lib/providers/menu_templates_provider.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/menu_template.dart';

class MenuTemplatesProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'menu_templates';

  List<MenuTemplate> _templates = [];
  bool _loading = false;
  String? _error;

  List<MenuTemplate> get templates => List.unmodifiable(_templates);
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await _firestore.collection(_collectionName).get();
      _templates = snapshot.docs.map((doc) => MenuTemplate.fromFirestore(doc)).toList();
    } catch (e) {
      _error = "Errore caricamento menu: ${e.toString()}";
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> add(Map<String, dynamic> payload) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _firestore.collection(_collectionName).add(payload);
      await fetch();
      return true;
    } catch (e) {
      _error = "Errore aggiunta menu: ${e.toString()}";
      notifyListeners(); // Notifica l'errore
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> update(String idMenu, Map<String, dynamic> payload) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _firestore.collection(_collectionName).doc(idMenu).update(payload);
      await fetch();
      return true;
    } catch (e) {
      _error = "Errore aggiornamento menu: ${e.toString()}";
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> remove(String idMenu) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _firestore.collection(_collectionName).doc(idMenu).delete();
      await fetch();
      return true;
    } catch (e) {
      _error = "Errore eliminazione menu: ${e.toString()}";
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}